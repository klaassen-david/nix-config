{
  config,
  lib,
  pkgs,
  secretsPath,
  ...
}:

# Hot-swapped apps: services whose binary is not in the nix store
# ===============================================================
# decisions/hot-swap.md. For apps that change faster than a switch is worth
# (orchestrator, coordinator on hestia; control on olympus, ./apps.nix), nix-config owns the
# unit, the port, the firewall hole, the vhost (./vhosts.nix, on olympus) and the
# swap/rollback logic; the binary is whatever
#   /home/dk/deploy/<app>/current/bin/<app>
# resolves to. Releases are static (musl) binaries built with cargo on hestia,
# so nothing they link against has to be in the store. A release is never
# modified after upload.
#
# /home/dk/deploy/<app>/ (dk-owned; tmpfiles creates the dirs):
#   releases/<version>/bin/<app>   one dir per upload
#   current -> releases/<v>        what <app>.service runs; only <app>-swap moves it
#   want                           the version to switch to, written by the deployer
#   good                           the last version that passed the health check
#   state/                         the app's data ($STATE_DIR), kept across swaps
#
# Upgrade and downgrade are the same move, no sudo (both units are in
# host.userManagedUnits, common/modules/polkit-units):
#   echo <version> > ~/deploy/<app>/want && systemctl start <app>-swap
# <app>-swap flips `current`, restarts <app>.service and polls
#   http://127.0.0.1:<port>/healthz
# until it answers 200 with exactly <version> as the body (so a restart that
# kept the old binary does not count). After 30 s it points `current` back,
# restarts again and fails, so `systemctl start` exits non-zero. It is a unit of
# its own so an app can replace itself (`systemctl start --no-block <app>-swap`)
# without its own restart killing the swap; systemd runs one start job per unit,
# which serialises concurrent swaps.
#
# The app unit runs as dk with dk's home and PATH unless the app's serviceConfig
# sandboxes it, as ../control does (an agent harness is no more
# confined than a login shell) and is skipped (ConditionPathExists) until a
# first release exists. It gets dk's XDG_RUNTIME_DIR, so `systemd-run --user`
# and `systemctl --user` reach dk's (lingering) manager: work started that way
# lives in user@1000.service, outside this unit, and survives every swap.
# Pruning releases/ is the deployer's job.
#
# Network: a mesh app binds 0.0.0.0:<port> (a mesh restart cannot leave it unbound;
# an app on olympus itself binds loopback and brings its own vhost)
# and the firewall accepts the port only on the mesh interface from `sources`,
# by default the hub alone: olympus's nginx is the only door (ACL, optional
# SSO). Phones (10.100.1.0/24) and the other hosts are refused.
#
# Proxy key (hotSwap.proxyKey, ./proxy-key.nix): the apps trust the hub only
# when it also sends the shared key. agenix writes it per app as a real file
# (the apps refuse a symlink) next to the admin token, where agents cannot read
# it, and the unit gets TRUSTED_PROXY_KEY_FILE. A new key restarts the apps.

let
  inherit (lib) mkOption types;
  apps = config.hotSwap.apps;
  user = config.users.users.dk;
  root = "${user.home}/deploy";
  registry = import ./apps.nix;
  # dk is the first normal user, so 1000 when NixOS allocates the uid
  runtimeDir = "/run/user/${toString (lib.defaultTo 1000 user.uid)}";
  hub = lib.findFirst (n: n.hub) null (lib.attrValues config.vpn.nodes);
  keyAge = "${secretsPath}/orch-proxy-key.age";
  keyPath = name: "${root}/${name}/state/secrets/proxy-key";

  swap = pkgs.writeShellApplication {
    name = "hot-swap";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.curl
      config.systemd.package
    ];
    text = ''
      app=$1 port=$2
      dir=${root}/$app
      want=$(tr -d '[:space:]' < "$dir/want")
      if ! [[ $want =~ ^[A-Za-z0-9._+-]+$ ]]; then
        echo "$app: bad version '$want' in $dir/want" >&2
        exit 1
      fi
      if ! [ -x "$dir/releases/$want/bin/$app" ]; then
        echo "$app: $dir/releases/$want/bin/$app is missing or not executable" >&2
        exit 1
      fi
      prev=$(readlink "$dir/current" || true)

      point() { ln -sfn "$1" "$dir/.current.tmp" && mv -Tf "$dir/.current.tmp" "$dir/current"; }
      healthy() {
        for _ in $(seq 60); do
          [ "$(curl -fsS --max-time 2 "http://127.0.0.1:$port/healthz" 2>/dev/null)" = "$1" ] && return 0
          sleep 0.5
        done
        return 1
      }

      point "releases/$want"
      systemctl restart "$app.service"
      if healthy "$want"; then
        echo "$want" > "$dir/good"
        echo "$app: now at $want"
        exit 0
      fi

      echo "$app: $want failed its health check; back to ''${prev:-nothing}" >&2
      if [ -n "$prev" ]; then
        point "$prev"
        systemctl restart "$app.service"
        healthy "''${prev#releases/}" || echo "$app: ''${prev#releases/} is unhealthy too" >&2
      else
        rm -f "$dir/current"
        systemctl stop "$app.service"
      fi
      exit 1
    '';
  };
in
{
  imports = [ ./proxy-key.nix ];

  # Internal: each app module registers itself here.
  options.hotSwap.apps = mkOption {
    internal = true;
    default = { };
    description = "Apps run from /home/dk/deploy/<name>/current, keyed by name (= binary name).";
    type = types.attrsOf (
      types.submodule {
        options = {
          port = mkOption {
            type = types.port;
            description = "TCP port the app listens on; GET /healthz answers on 127.0.0.1.";
          };
          sources = mkOption {
            type = types.listOf types.str;
            default = [ "10.100.0.${toString hub.octet}" ];
            defaultText = "the hub's mesh address";
            description = "Source addresses accepted on the mesh interface for this port.";
          };
          proxyKey = mkOption {
            type = types.bool;
            default = config.hotSwap.proxyKey;
            defaultText = "config.hotSwap.proxyKey";
            description = "Hand this app the shared proxy key (TRUSTED_PROXY_KEY_FILE).";
          };
          environment = mkOption {
            type = types.attrsOf types.str;
            default = { };
            description = "Environment of the app unit.";
          };
          serviceConfig = mkOption {
            type = types.attrsOf types.anything;
            default = { };
            description = "Merged into the app unit's serviceConfig.";
          };
        };
      }
    );
  };

  config = lib.mkIf (apps != { }) {
    assertions = lib.mapAttrsToList (name: _: {
      assertion = registry ? ${name} && registry.${name}.node == config.host.hostName;
      message = "hot-swap app ${name} is imported on ${config.host.hostName}, but common/modules/hot-swap/apps.nix places it on ${
        registry.${name}.node or "no host"
      }";
    }) apps;

    systemd.tmpfiles.rules = [
      "d ${root} 0755 dk ${user.group} -"
    ]
    ++ lib.concatLists (
      lib.mapAttrsToList (name: app: [
        "d ${root}/${name} 0755 dk ${user.group} -"
        "d ${root}/${name}/releases 0755 dk ${user.group} -"
        "d ${root}/${name}/state 0700 dk ${user.group} -"
      ]
      ++ lib.optional app.proxyKey "d ${root}/${name}/state/secrets 0700 dk ${user.group} -"
      ) apps
    );

    age.secrets = lib.mapAttrs' (
      name: _:
      lib.nameValuePair "orch-proxy-key-${name}" {
        file = keyAge;
        path = keyPath name;
        symlink = false;
        owner = "dk";
        inherit (user) group;
        mode = "0400";
      }
    ) (lib.filterAttrs (_: app: app.proxyKey) apps);

    systemd.services = lib.mkMerge (
      lib.mapAttrsToList (name: app: {
        ${name} = {
          description = "${name} (hot-swapped, ${root}/${name}/current)";
          wantedBy = [ "multi-user.target" ];
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
          unitConfig.ConditionPathExists = "${root}/${name}/current/bin/${name}";
          # dk's profile first: the harness calls git, nix, claude like a shell would
          path = [
            "/etc/profiles/per-user/dk"
            "/run/current-system/sw"
          ];
          environment =
            app.environment
            // {
              STATE_DIR = "${root}/${name}/state";
              XDG_RUNTIME_DIR = runtimeDir;
            }
            // lib.optionalAttrs app.proxyKey { TRUSTED_PROXY_KEY_FILE = keyPath name; };
          # the key is read at start
          restartTriggers = lib.optional app.proxyKey keyAge;
          serviceConfig = {
            User = "dk";
            ExecStart = "${root}/${name}/current/bin/${name}";
            WorkingDirectory = "${root}/${name}/state";
            Restart = "on-failure";
            RestartSec = 2;
            # optional, dk-owned settings file (KEY=VALUE lines): app settings change with a restart, without a
            # nix switch (hot-swap's goal). Its values override `environment`. Agents may not write ~/deploy (D63).
            EnvironmentFile = "-${root}/${name}/env";
          }
          // app.serviceConfig;
        };

        "${name}-swap" = {
          description = "Point ${name} at ${root}/${name}/want; roll back if unhealthy";
          serviceConfig = {
            Type = "oneshot";
            User = "dk";
            ExecStart = "${lib.getExe swap} ${name} ${toString app.port}";
          };
        };
      }) apps
    );

    networking.firewall.extraCommands = lib.concatStrings (
      lib.mapAttrsToList (
        _: app:
        lib.concatMapStrings (
          src:
          "iptables -A nixos-fw -i olympus -s ${src} -p tcp --dport ${toString app.port} -j nixos-fw-accept\n"
        ) app.sources
      ) apps
    );

    host.userManagedUnits = lib.concatMap (name: [
      "${name}.service"
      "${name}-swap.service"
    ]) (lib.attrNames apps);
  };
}
