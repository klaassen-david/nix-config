{
  config,
  lib,
  pkgs,
  secretsPath,
  ...
}:

# Consumer side of the self-hosted attic binary cache (dklaassencache on
# olympus). Imported by common/common.nix, so EVERY host pulls from the cache
# (substituter + trusted key) and authenticates to it (pull-only netrc). Hosts
# with host.capabilities.binaryCachePush (default: non-vps) additionally push
# every freshly built path. The atticd SERVER and its one-time bootstrap live in
# the sibling ../attic module (olympus only).

let
  cacheHost = "attic.dklaassen.de";
  cacheName = "dklaassencache";
  pushHome = "/var/lib/attic-push";
in
{
  # Pull from the cache. These merge with the cachix substituters/keys in
  # common/common.nix (the module system concatenates list options).
  nix.settings.extra-substituters = [ "https://${cacheHost}/${cacheName}" ];
  nix.settings.extra-trusted-public-keys = [
    "${cacheName}:i+2mRKAyTgO2dXVt2bnJV6TuUdIn1sLK+vUL07dnAJY="
  ];

  # Pull auth for the PRIVATE cache. Nix authenticates to the substituter above
  # by sending the netrc password as the token (attic accepts it as the
  # Basic-auth password; the username is ignored). Deployed to EVERY host — pulls
  # are fleet-wide — unlike the push token, which stays gated to binaryCachePush
  # hosts. The token here is PULL-ONLY; mint it on olympus and store it in
  # attic-netrc.age as a single line. From secrets/ (devshell):
  #   sudo atticd-atticadm make-token --sub fleet-pull --validity '1y' \
  #     --pull '${cacheName}' </dev/null
  #   agenix -e attic-netrc.age   # $EDITOR; the file must contain exactly:
  #     machine ${cacheHost} password <pull-only-token>
  age.secrets.attic-netrc.file = "${secretsPath}/attic-netrc.age";
  nix.settings.netrc-file = config.age.secrets.attic-netrc.path;

  # ---------------------------------------------------------------------------
  # Push (only on host.capabilities.binaryCachePush hosts)
  # ---------------------------------------------------------------------------
  # The nix-daemon runs post-build-hook as root and `attic` reads its token from
  # $HOME/.config/attic/config.toml, so an agenix-fed oneshot renders that file
  # before any push.
  age.secrets.attic-token = lib.mkIf config.host.capabilities.binaryCachePush {
    file = "${secretsPath}/attic-token.age";
  };

  systemd.services.attic-push-config = lib.mkIf config.host.capabilities.binaryCachePush {
    description = "Render attic client config for the nix-daemon push hook";
    after = [ "agenix.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig.Type = "oneshot";
    script = ''
      install -d -m 700 ${pushHome}/.config/attic
      umask 077
      printf 'default-server = "olympus"\n[servers.olympus]\nendpoint = "https://${cacheHost}/"\ntoken = "%s"\n' \
        "$(cat ${config.age.secrets.attic-token.path})" \
        > ${pushHome}/.config/attic/config.toml
    '';
  };

  # post-build-hook fires once per locally-built derivation as the nix-daemon
  # (root). Nix runs hooks SYNCHRONOUSLY, so to keep builds from blocking on the
  # upload we hand the push to a detached transient unit via `systemd-run
  # --no-block` and return immediately. That unit expands the built path's full
  # closure and drops never-share fragments BEFORE pushing, then pushes the
  # survivors with --no-closure (filtering only $OUT_PATHS would miss nvidia/
  # initrd when they ride in as transitive deps of the system toplevel). HOME
  # points at the config rendered above; `|| true` keeps a failed upload silent.
  nix.settings.post-build-hook = lib.mkIf config.host.capabilities.binaryCachePush (
    pkgs.writeShellScript "attic-push" ''
      set -eu
      exec ${config.systemd.package}/bin/systemd-run \
        --collect --no-block --quiet \
        --setenv=HOME=${pushHome} \
        --setenv=OUT_PATHS="$OUT_PATHS" \
        -- ${pkgs.writeShellScript "attic-push-upload" ''
          set -euf
          paths=$(${config.nix.package}/bin/nix-store -qR $OUT_PATHS \
            | ${pkgs.gnugrep}/bin/grep -vE -- '-(nvidia|initrd|modules-shrunk)') || true
          [ -z "$paths" ] || ${pkgs.attic-client}/bin/attic push --no-closure -j8 ${cacheName} $paths || true
        ''}
    ''
  );
}
