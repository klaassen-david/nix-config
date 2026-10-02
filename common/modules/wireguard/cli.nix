{
  config,
  lib,
  pkgs,
  ...
}:

# `vpn` — one command over the mesh, egress and home units on the hosts (not the hub).
# A thin front-end: switching is `systemctl start|stop` (no sudo, see polkit-units;
# Conflicts= does the exclusivity), and status is read from unit state *and* kernel
# state, so a tunnel brought up behind systemd's back shows as `inconsistent`.
#
#   vpn status [--short|--json]     --short feeds the bar (exit 1 only on `inconsistent`)
#   vpn egress <direct|olympus|<exit>|tukl>
#   vpn home on|off                 needs vpn-home.service
#   vpn mesh on|off
#
# `egress`, `home` and `mesh` are serialised on a lock (overlapping calls would
# interleave a stop and a start). `egress` switches without a direct window (see
# egressScripts in default.nix); `egress direct` and `mesh off` go direct.
#
# --short is `direct|olympus|<host>|tukl`, plus ` +home` and ` !down` (the exit
# watchdog's /run/vpn-egress-watch/<unit>.down marker), or exactly `blocked` (the
# egress slot is installed but no unit holds it: a stopped or failed exit drops
# traffic; `vpn egress direct` or starting an exit clears it) or `inconsistent`.
# --json is the same as an i3status-rust custom block (always exit 0, so the bar
# can render the Critical state).
let
  selfName = config.host.hostName;
  nodes = config.vpn.nodes;
  isHub = nodes.${selfName}.hub;
  hasTukl = nodes.${selfName}.tukl != null;

  otherExits = lib.sort (a: b: a < b) (
    lib.attrNames (lib.filterAttrs (n: x: x.exit && n != selfName) nodes)
  );
  targets = [ "olympus" ] ++ otherExits ++ lib.optional hasTukl "tukl";
  # tukl's endpoint host, resolved before the current exit is dropped
  tuklHost = lib.optionalString hasTukl (
    lib.head (lib.splitString ":" nodes.${selfName}.tukl.endpoint)
  );

  vpn = pkgs.writeShellApplication {
    name = "vpn";
    runtimeInputs = [
      pkgs.iproute2
      pkgs.coreutils
      pkgs.util-linux
      pkgs.getent
      config.systemd.package
    ];
    text = ''
      targets=(${lib.escapeShellArgs targets})
      owner=/run/vpn-egress
      lock=/run/lock/vpn.lock
      watch=/run/vpn-egress-watch

      usage() {
        cat >&2 <<'USAGE'
      usage: vpn status [--short|--json]
             vpn egress <direct|${lib.concatStringsSep "|" targets}>
             vpn home on|off
             vpn mesh on|off
      USAGE
        exit 2
      }

      unit_of() { if [ "$1" = tukl ]; then echo wg-quick-tukl; else echo "vpn-egress-$1"; fi; }
      active() { systemctl is-active --quiet "$1.service"; }
      rules() { ip "$1" rule show pref 5300 | wc -l; }

      # Sets exit_name, home, down and problems from unit and kernel state.
      gather() {
        local on=() t r4 r6 own link
        for t in "''${targets[@]}"; do
          if active "$(unit_of "$t")"; then on+=("$t"); fi
        done
        r4=$(rules -4)
        r6=$(rules -6)
        own=$(cat "$owner" 2>/dev/null || true)
        link=0
        if ip link show dev tukl >/dev/null 2>&1; then link=1; fi
        problems=()
        exit_name=direct
        down=0
        home=0
        if active vpn-home; then home=1; fi

        if [ "''${#on[@]}" -gt 1 ]; then
          problems+=("several exits are active: ''${on[*]}")
        else
          if [ "''${#on[@]}" = 1 ]; then exit_name=''${on[0]}; fi
          case $exit_name in
            direct)
              if [ -n "$own" ]; then problems+=("no exit is active but $owner names $own"); fi
              if [ "$link" = 1 ]; then problems+=("no exit is active but a tukl link exists"); fi
              ;;
            tukl)
              if [ "$link" = 0 ]; then problems+=("wg-quick-tukl is active but there is no tukl link"); fi
              if [ "$r4" != 1 ] || [ "$r6" != 1 ]; then problems+=("tukl should have one pref 5300 rule per family (v4: $r4, v6: $r6)"); fi
              if [ "$own" != wg-quick-tukl ]; then problems+=("$owner names '$own', not wg-quick-tukl"); fi
              ;;
            *)
              if [ "$r4" != 1 ] || [ "$r6" != 1 ]; then problems+=("$exit_name should have one pref 5300 rule per family (v4: $r4, v6: $r6)"); fi
              if [ "$own" != "vpn-egress-$exit_name" ]; then problems+=("$owner names '$own', not vpn-egress-$exit_name"); fi
              if [ "$link" = 1 ]; then problems+=("$exit_name is active but a tukl link exists"); fi
              ;;
          esac
          if [ "$exit_name" != direct ] && [ -e "$watch/$(unit_of "$exit_name").down" ]; then down=1; fi
        fi
        if [ "''${#problems[@]}" -gt 0 ]; then
          exit_name=inconsistent
        elif [ "$exit_name" = direct ] && { [ "$r4" != 0 ] || [ "$r6" != 0 ]; }; then
          exit_name=blocked
        fi
      }

      short() {
        if [ "$exit_name" = inconsistent ] || [ "$exit_name" = blocked ]; then echo "$exit_name"; return; fi
        local line=$exit_name
        if [ "$home" = 1 ]; then line+=" +home"; fi
        if [ "$down" = 1 ]; then line+=" !down"; fi
        echo "$line"
      }

      status() {
        gather
        case ''${1:-} in
          --short)
            short
            [ "$exit_name" != inconsistent ] && [ "$exit_name" != blocked ]
            ;;
          --json)
            local state=Info
            if [ "$exit_name" = direct ]; then state=Idle; fi
            if [ "$exit_name" = inconsistent ] || [ "$exit_name" = blocked ] || [ "$down" = 1 ]; then state=Critical; fi
            printf '{"text":"%s","state":"%s"}\n' "$(short)" "$state"
            ;;
          "")
            echo "exit: $exit_name"
            if [ "$home" = 1 ]; then echo "home: on"; else echo "home: off"; fi
            if active wireguard-olympus; then echo "mesh: up"; else echo "mesh: down"; fi
            if [ "$down" = 1 ]; then echo "warning: the exit is not forwarding, traffic is dropped"; fi
            if [ "$exit_name" = blocked ]; then echo "blocked: no exit holds the egress slot, traffic is dropped; 'vpn egress direct' goes direct"; fi
            for p in "''${problems[@]}"; do echo "inconsistent: $p"; done
            [ "$exit_name" != inconsistent ] && [ "$exit_name" != blocked ]
            ;;
          *) usage ;;
        esac
      }

      # stop every unit, then clear what a failed or half-finished switch left behind
      direct() {
        local units=() t
        for t in "''${targets[@]}"; do units+=("$(unit_of "$t").service"); done
        systemctl stop "''${units[@]}"
        systemctl start vpn-egress-reset.service
      }

      switch() { # <on|off> <unit>
        case $1 in
          on) systemctl start "$2.service" ;;
          off) systemctl stop "$2.service" ;;
          *) usage ;;
        esac
      }

      # one mutating call at a time (the lock is a read-only fd: no write access needed)
      serialise() {
        if ! exec 9< "$lock"; then
          echo "vpn: cannot open $lock" >&2
          exit 1
        fi
        flock -w 120 9 || { echo "vpn: another vpn command holds the lock" >&2; exit 1; }
      }

      [ $# -ge 1 ] || usage
      cmd=$1
      shift
      case $cmd in
        status)
          [ $# -le 1 ] || usage
          # the --json block must stay renderable when the state is Critical
          rc=0
          status "$@" || rc=$?
          if [ "''${1:-}" = --json ]; then exit 0; fi
          exit "$rc"
          ;;
        egress)
          [ $# -eq 1 ] || usage
          serialise
          if [ "$1" = direct ]; then
            direct
          else
            found=0
            for t in "''${targets[@]}"; do if [ "$t" = "$1" ]; then found=1; fi; done
            [ "$found" = 1 ] || usage
            # the old unit's stop leaves the slot blackholed, so a switch never passes
            # through a direct moment
            ${lib.optionalString hasTukl ''
              # warm resolved's cache while the old exit still routes, so wg-quick can
              # resolve the endpoint with the slot closed
              if [ "$1" = tukl ]; then getent ahosts ${tuklHost} > /dev/null || true; fi
            ''}
            rc=0
            systemctl start "$(unit_of "$1").service" || rc=$?
            if [ "$rc" != 0 ]; then
              echo "vpn: switching failed, traffic stays dropped; 'vpn egress direct' goes direct" >&2
              exit "$rc"
            fi
          fi
          status --short
          ;;
        home)
          [ $# -eq 1 ] || usage
          serialise
          if ! systemctl cat vpn-home.service >/dev/null 2>&1; then
            echo "vpn: vpn-home.service does not exist on this host" >&2
            exit 1
          fi
          switch "$1" vpn-home
          ;;
        mesh)
          [ $# -eq 1 ] || usage
          serialise
          # mesh off means direct: a selected egress cannot outlive its tunnel
          if [ "$1" = off ]; then direct; fi
          switch "$1" wireguard-olympus
          ;;
        *) usage ;;
      esac
    '';
  };
in
{
  config.environment.systemPackages = lib.mkIf (!isHub) [ vpn ];
}
