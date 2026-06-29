{
  config,
  secretsPath,
  sslVhost,
  ...
}:

# Self-hosted Nix binary cache (atticd) on olympus, fronted by nginx at
# attic.dklaassen.de. Every host pulls it as a substituter and non-vps hosts push
# each freshly built path to it (both wired in common/common.nix, gated by
# host.capabilities.binaryCachePush). Replaces the public klaassen-david.cachix.org
# once verified.
#
# NOT behind Nextcloud SSO: oauth2-proxy is an interactive browser redirect, but
# the nix-daemon and the `attic` CLI authenticate with a bearer JWT and cannot
# follow an OAuth flow. So this vhost is plain TLS (sslVhost) and attic's own
# token layer guards writes; reads are open because the cache is `--public`.
#
# ---------------------------------------------------------------------------
# One-time bootstrap (run once, by hand, AFTER the first deploy of this module)
# ---------------------------------------------------------------------------
# The cache signing keypair and every token are minted by the running server, so
# none of them can be committed up front. atticd refuses to start until step 1
# provides its JWT secret, so the first `nixos-rebuild switch` on olympus will
# leave atticd failing — that is expected; finish the steps below and redeploy.
#
#   1. Generate the server's RS256 JWT secret and store it as the agenix secret
#      `atticd-env.age` (an EnvironmentFile in KEY=VALUE form). From `secrets/`
#      with the flake devshell (`nix develop`) so `agenix` is on PATH:
#        openssl genrsa -traditional 4096 | base64 -w0   # copy the output
#        agenix -e atticd-env.age                        # opens $EDITOR; add line:
#          ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64=<paste the base64 from above>
#      Deploy olympus so atticd comes up with the secret.
#
#   2. On olympus, mint a short-lived bootstrap token allowed to create/manage
#      the cache (this module installs the `atticd-atticadm` wrapper):
#        atticd-atticadm make-token --sub bootstrap --validity '1h' \
#          --create-cache 'dklaassencache' --configure-cache 'dklaassencache' \
#          --push 'dklaassencache' --pull 'dklaassencache'
#
#   3. With the `attic` client (e.g. from a desktop: `nix run nixpkgs#attic-client`),
#      log in and create the cache PUBLIC (public read, token-gated write):
#        attic login olympus https://attic.dklaassen.de/ <bootstrap-token>
#        attic cache create --public dklaassencache
#
#   4. Read the cache's `public-key` and wire it into the substituter config:
#        attic cache info dklaassencache
#      Paste the key into common/common.nix — uncomment the attic substituter and
#      trusted-public-key lines there.
#
#   5. Mint the long-lived push/pull token the fleet uses and store it as the
#      agenix secret `attic-token.age` (the RAW token, no KEY= prefix):
#        atticd-atticadm make-token --sub fleet --validity '100y' --push 'dklaassencache' --pull 'dklaassencache'
#        agenix -e attic-token.age   # opens $EDITOR; paste the token, nothing else
#
#   6. Deploy all hosts. Confirm a desktop build lands in the cache (the path
#      count rises after a fresh build):
#        attic cache info dklaassencache
#      Then drop the klaassen-david.cachix.org substituter from common/common.nix.

let
  port = 8081; # 8080 is the off-repo control panel (see common/headless.nix)
  cacheHost = "attic.dklaassen.de";
in
{
  age.secrets.atticd-env = {
    # read by systemd (root) via EnvironmentFile before the service drops privs,
    # so the root-owned 0400 defaults are correct.
    file = "${secretsPath}/atticd-env.age";
  };

  services.atticd = {
    enable = true;
    environmentFile = config.age.secrets.atticd-env.path;
    settings = {
      listen = "127.0.0.1:${toString port}";
      # required for production: only serve our own Host, and hand clients the
      # canonical https endpoint in cache-config responses (must end in a slash).
      allowed-hosts = [ cacheHost ];
      api-endpoint = "https://${cacheHost}/";

      # database (sqlite), storage (local, /var/lib/atticd), chunking and zstd
      # compression all keep the module defaults — fine at single-user scale, and
      # content-defined chunking dedups identical NAR chunks across uploads.
      garbage-collection = {
        interval = "12 hours";
        # bound VPS disk growth: drop paths untouched for 30d. Per-cache retention
        # can override this via `attic cache configure --retention-period`.
        default-retention-period = "30 days";
      };
    };
  };

  # Plain TLS, no nextcloudSSO (see header). Large, streamed NAR uploads need the
  # body-size cap lifted and request buffering off.
  services.nginx.virtualHosts.${cacheHost} = sslVhost { } // {
    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString port}";
      extraConfig = ''
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        client_max_body_size 0;
        proxy_request_buffering off;
        proxy_read_timeout  3600s;
        proxy_send_timeout  3600s;
      '';
    };
  };
}
