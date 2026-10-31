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
  spool = "${pushHome}/spool";
  work = "${pushHome}/work";
in
{
  # Pull from the cache. These merge with the cachix substituters/keys in
  # common/common.nix (the module system concatenates list options).
  nix.settings.extra-substituters = [ "https://${cacheHost}/${cacheName}" ];
  nix.settings.extra-trusted-public-keys = [
    "${cacheName}:i+2mRKAyTgO2dXVt2bnJV6TuUdIn1sLK+vUL07dnAJY="
  ];

  # A dead or unreachable attic must not brick every host's builds. Nix treats a
  # substituter error (nginx 502, TCP timeout) as FATAL unless `fallback` is set:
  # substitution-goal.cc stashes the exception, and once the substituter list is
  # exhausted it rethrows — so a path that exists only in OUR cache fails the whole
  # build instead of being built locally. With fallback it is merely logged, and
  # http-binary-cache-store's auto-disable (gated on the same setting) sidelines the
  # cache for 60s instead of re-timing-out on every single path.
  nix.settings.fallback = true;

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
  # (root), synchronously. It only drops $OUT_PATHS into ${spool} (written as a
  # dotfile, renamed when complete — path units ignore dotfiles) and returns.
  # attic-push.path starts the one attic-push.service whenever the spool is
  # non-empty, and starts it again after each run while it still is, so at most
  # one upload runs at a time. A push per hook (the old design) put hundreds of
  # concurrent uploads on olympus after a flake update: atticd's sqlite pool and
  # nginx's worker_connections ran out, and failed paths never re-pushed.
  nix.settings.post-build-hook = lib.mkIf config.host.capabilities.binaryCachePush (
    pkgs.writeShellScript "attic-enqueue" ''
      tmp=$(${pkgs.coreutils}/bin/mktemp ${spool}/.XXXXXXXX) \
        && echo "$OUT_PATHS" > "$tmp" \
        && ${pkgs.coreutils}/bin/mv "$tmp" "${spool}/q''${tmp##*/.}" \
        || true
    ''
  );

  systemd.tmpfiles.rules = lib.mkIf config.host.capabilities.binaryCachePush [
    "d ${pushHome} 0700 root root -"
    "d ${spool} 0700 root root -"
    "d ${work} 0700 root root -"
  ];

  systemd.paths.attic-push = lib.mkIf config.host.capabilities.binaryCachePush {
    wantedBy = [ "paths.target" ];
    pathConfig.DirectoryNotEmpty = spool;
  };

  # Each run claims the whole spool into ${work}, expands the full closure and
  # drops never-share fragments BEFORE pushing (filtering only $OUT_PATHS would
  # miss nvidia/initrd riding in as deps of the system toplevel), then pushes
  # with --no-closure. On failure the batch goes back to the spool; the sleep
  # keeps the path unit from re-triggering in a tight loop. TimeoutStartSec caps
  # a wedged uploader (seen pinning >1G per stuck -j8 job); the next run requeues
  # what it left in ${work}, and paths already uploaded are skipped.
  systemd.services.attic-push = lib.mkIf config.host.capabilities.binaryCachePush {
    description = "Push queued build outputs to the attic cache";
    wants = [ "network-online.target" ];
    after = [
      "network-online.target"
      "attic-push-config.service"
    ];
    environment.HOME = pushHome;
    path = [
      config.nix.package
      pkgs.attic-client
      pkgs.coreutils
      pkgs.findutils
      pkgs.gnugrep
    ];
    serviceConfig = {
      Type = "oneshot";
      TimeoutStartSec = "1h";
      Nice = 10;
      IOSchedulingClass = "idle";
    };
    script = ''
      set -o pipefail
      shopt -s nullglob
      left=(${work}/*)
      [ ''${#left[@]} -eq 0 ] || mv -t ${spool} "''${left[@]}"
      batch=(${spool}/*)
      [ ''${#batch[@]} -gt 0 ] || exit 0
      mv -t ${work} "''${batch[@]}"

      roots=()
      for p in $(cat ${work}/* | tr ' ' '\n' | sort -u); do
        if [ -e "$p" ]; then roots+=("$p"); fi
      done

      if [ ''${#roots[@]} -gt 0 ] && ! nix-store -qR "''${roots[@]}" \
          | { grep -vE -- '-(nvidia|initrd|modules-shrunk)' || true; } \
          | xargs -r attic push --no-closure -j8 ${cacheName}; then
        mv -t ${spool} ${work}/*
        sleep 300
        exit 1
      fi
      rm -f ${work}/*
    '';
  };
}
