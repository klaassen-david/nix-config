{
  config,
  lib,
  secretsPath,
  ...
}:

# -----------------------------------------------------------------------------
# ACME — automatic renewal of the shared wildcard cert
# -----------------------------------------------------------------------------
# Replaces the hand-rolled pair in ssl-fullchain.age / ssl-key.age, which has no
# renewal path and simply stops working on its notAfter date. Gated by
# host.tls.acme; ../nginx switches sslVhost and tlsCert on the same flag.
#
# The CA is IONOS fronting Sectigo, not Let's Encrypt: the directory advertises
# `"externalAccountRequired": true` and caaIdentities sectigo.com /
# trust-provider.com / usertrust.com. Registration therefore needs the *external
# account binding* pair — a key id and an HMAC — that IONOS issues with the
# certificate. lego takes them as --eab/--kid/--hmac, but flags are
# world-readable in the store, so they go through the environment file as
# $LEGO_EAB/$LEGO_EAB_KID/$LEGO_EAB_HMAC. Many CAs mint an EAB pair valid for a
# single registration; a failed first run may need fresh credentials, not a retry.
#
# HTTP-01, and therefore **no wildcard**: RFC 8555 lets a wildcard identifier be
# validated only by dns-01, which would need write access to the zone — an IONOS
# DNS API key we do not have. So the cert carries an explicit SAN list instead,
# which is also what IONOS' own certbot tutorial does. The names are derived
# from the nginx vhosts rather than restated here, so a new subdomain lands in
# the next renewal by itself; forgetting one is otherwise a silent TLS error on
# exactly the host nobody visits often.
#
# The challenge location is not configured here: for a `useACMEHost` vhost the
# nixpkgs nginx module adds `^~ /.well-known/acme-challenge/` to the port-80
# redirect block, rooted at acmeRoot and with `auth_request off` — which is what
# keeps validation working through the Nextcloud SSO gate. `webroot` below has
# to agree with that acmeRoot default.
#
# acme-env.age is three lines:
#   LEGO_EAB=true
#   LEGO_EAB_KID=<key id>
#   LEGO_EAB_HMAC=<hmac — already base64url without padding, do not re-encode>
# systemd reads EnvironmentFile as root before the unit drops to the acme user,
# so the default 0400 root mode is correct.
#
# Switching over is a soft failure, not an outage: nixpkgs always writes a
# self-signed placeholder into /var/lib/acme/${domain}, so nginx and stalwart
# start regardless and serve an untrusted cert until issuance succeeds. lego runs
# in acme-order-renew-${domain}.service (acme-${domain}.service only prepares the
# placeholder), so that is the unit to read after the first switch; setting
# host.tls.acme back to false restores the agenix pair.

let
  domain = "dklaassen.de";

  # every nginx vhost under the domain except the apex itself, which is the CN.
  # Drops the "_" catch-all by construction.
  extraNames = lib.filter (n: n != domain && lib.hasSuffix ".${domain}" n) (
    lib.attrNames config.services.nginx.virtualHosts
  );
in
{
  config = lib.mkIf config.host.tls.acme {
    age.secrets.acme-env.file = "${secretsPath}/acme-env.age";

    security.acme = {
      acceptTerms = true;
      defaults.email = "postmaster@${domain}";

      certs.${domain} = {
        # the attr name is the directory under /var/lib/acme, and `domain` is the
        # CN; every other vhost rides along as a SAN.
        inherit domain;
        extraDomainNames = extraNames;

        server = "https://acme.ionos.com/directory";
        environmentFile = config.age.secrets.acme-env.path;

        # must match services.nginx.virtualHosts.<n>.acmeRoot, which is where the
        # generated challenge location looks.
        webroot = "/var/lib/acme/acme-challenge";

        # rsa2048 over lego's ec256 default: this cert also terminates SMTP/IMAP
        # for arbitrary remote MTAs, and it is what the current cert uses.
        keyType = "rsa2048";

        # nginx reads the PEMs as the ssl-cert group and is added to
        # reloadServices by the nixpkgs nginx module (useACMEHost). Stalwart
        # inlines them with %{file:..}% at startup, so it needs restarting too.
        group = "ssl-cert";
        reloadServices = lib.optional config.services.stalwart.enable "stalwart.service";
      };
    };
  };
}
