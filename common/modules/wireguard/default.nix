{
  config,
  lib,
  pkgs,
  secretsPath,
  ...
}:

# ---------------------------------------------------------------------------
# WireGuard mesh, egress and phone plane (+ the `tukl` university VPN)
# ---------------------------------------------------------------------------
# Rulings: decisions/vpn.md. This header holds the mechanics.
#
# Roles come from the `vpn.nodes` registry: `hub` (olympus: server, NAT, keeps
# its own traffic on its uplink), `exit` (hermes, hestia: may carry other hosts'
# full-tunnel traffic), `lan` (hestia's home prefix), `tukl` (own RPTU config).
# Hosts keep an always-on split tunnel to the hub on the `olympus` interface
# (UDP 51820); only the mesh supernet goes through it. Full-tunnel egress is a
# runtime choice (`vpn egress ...`, see cli.nix), never a nix setting.
#
# Addressing (o = node octet, x = exit's octet):
#   mesh              10.100.0.o            fdaa:e184:83f::o       supernet /16, /48
#   o's source via x  10.100.(10+x).o       fdaa:e184:83f:(10+x)::o  range of x: /24, /64
#   phones (wg-easy)  10.100.1.0/24 on wg0  fdcc:ad94:bacf:61a4::cafe:0/112
# The hub's peer for o allows its mesh /32+/128, its sources for every other
# exit, and its `lan`; so the source address alone tells the hub which exit a
# packet wants.
#
# Routing (both families unless noted; lower pref wins):
#   where  pref   rule                                   table
#   hub    2000   main, suppress_prefixlength 0          mesh routes beat the rest
#   hub    3000+x from <x's range>                       2000+x: default dev vpn-<x>
#   hub    3500   from <phone> (vpn-phone, per phone)    2000+x, or prohibit
#   exit   4900   fwmark 0x2000/0x2000                   2300: default dev vpn-exit
#   exit   4950   iif vpn-exit                           main
#   host   5000   fwmark 0x1000/0x1000                   main (mesh socket: never tunnelled)
#   host   5100   to <lan> (v4; vpn-home)                2200: <lan> dev olympus
#   host   5200   main, suppress_prefixlength 0          (egress unit: local routes first)
#   host   5300   all                                    2100: default dev olympus
#
# GRE relays host exits: a WireGuard interface lets only one peer hold
# 0.0.0.0/0, so the hub cannot give each exit its own default route. Instead
# `vpn-<x>` (hub) and `vpn-exit` (exit) are a GRE pair over the mesh addresses
# (mtu 1396); table 2000+x sends x's source range into it. The exit
# masquerades out its uplink and returns replies via 4900 (connection mark
# 0x2000, set in prerouting). GRE is accepted on `olympus` by extraCommands.
#
# The exit tables 2000+x also hold a blackhole default (metric 4294967295),
# installed with `vpn-hub-nft` and never removed: a vanished vpn-<x> link drops
# its sources instead of letting them fall through to the hub's uplink.
#
# nft: `vpn-hub` (hub) gates phones on wg0: phones reach phones and the
# internet (not private, CGNAT or link-local ranges behind the uplink); mesh
# hosts and the home lan only for addresses in the vpn-phone sets. New
# connections from the uplink into the mesh, wg0 or the GRE links are dropped.
# It also rejects the hub's own traffic to the lan unless vpn-home is on. `vpn-exit`
# (exits) forwards with policy drop: relayed traffic (from `vpn-exit`) to
# anywhere but the mesh, tukl, private ranges and the exit's own lan
# (`vpn-languard` refills it, `vpn-languard-watch` on route and address
# changes, v6 widened to /56), plus mesh/phone sources to the lan on its owner;
# only those are masqueraded, and the exit's own services are shut to relayed
# traffic. Both tables reload atomically and have no stop. Their gate units
# (`vpn-hub-nft`, `vpn-exit-nft`) run before network-pre.target and
# `wireguard-olympus` (hub: also `podman-wg-easy`) requires them. Apply changes
# with `systemctl reload`: a restart would take the mesh down with it.
#
# Units (hosts; wheel starts/stops them without sudo, host.userManagedUnits):
#   wireguard-olympus      the mesh; the units below are bound to it
#   vpn-egress-<olympus|x> one active at most, conflict with each other and tukl;
#                          vpn-egress-watch@ announces a dead exit (traffic is dropped)
#   wg-quick-tukl          tukl, dialled by the host itself
#   vpn-home               host: route the lan over the mesh; hub: lift its reject
# Hub: vpn-hub-nft, vpn-phones (re-applies on wg-easy db writes), vpn-home.
# `vpn status|egress|home|mesh` wraps the host side; phones are managed on the
# hub with `sudo vpn-phone list | <phone> egress|hosts|home ... | apply`.
#
# Key material: private keys are agenix (secrets/wg-<host>.age, tukl's per its
# registry entry), referenced by path only; public keys live in the registry.
# DNS records: vpn.dklaassen.de A (+ AAAA if dialled over v6) -> olympus; it
# serves the mesh (:51820) and wg-easy (:51821, see ../wg-easy).
#
# Known limits:
#   - In a full tunnel DNS is whatever resolver the local network handed out
#     (tukl pushes its own); it is not forced through the exit.
#   - Phones get v6 only via an exit: olympus has no global v6 (see networking.nat).

let
  base4 = "10.100";
  subnet = "${base4}.0";
  # ULA (RFC 4193, randomly generated). The tunnel is dual-stack so a client with
  # native IPv6 does not silently blackhole AAAA traffic into a v4-only tunnel.
  # Egress caveat on networking.nat below.
  base6 = "fdaa:e184:83f";
  subnet6 = "${base6}::";
  port = 51820;
  cfg = config.vpn;

  # Registry entries plus the addresses derived from `octet`.
  nodes = lib.mapAttrs (
    name: node:
    node
    // {
      inherit name;
      ip = "${subnet}.${toString node.octet}";
      ip6 = "${subnet6}${toString node.octet}";
    }
  ) cfg.nodes;
  # Spokes in octet order, so the hub's peer list is stable.
  spokes = lib.sort (a: b: a.octet < b.octet) (lib.filter (n: !n.hub) (lib.attrValues nodes));

  ip = "${pkgs.iproute2}/bin/ip";
  # fwmark on the mesh socket; rule 5000 sends marked packets via main
  mark = "0x1000";
  underlayRules =
    action:
    lib.concatMapStringsSep "\n"
      (
        f:
        lib.optionalString (
          action == "add"
        ) "${ip} ${f} rule del fwmark ${mark}/${mark} lookup main pref 5000 || true\n"
        + "${ip} ${f} rule ${action} fwmark ${mark}/${mark} lookup main pref 5000${
          lib.optionalString (action == "del") " || true"
        }"
      )
      [
        "-4"
        "-6"
      ];

  selfName = config.host.hostName;
  self = nodes.${selfName};
  isServer = self.hub;
  hub = lib.findFirst (n: n.hub) null (lib.attrValues nodes);

  # Exits in octet order; `x` below is an exit, `n` any node.
  exits = lib.sort (a: b: a.octet < b.octet) (lib.filter (n: n.exit) (lib.attrValues nodes));
  otherExits = lib.filter (x: x.name != selfName) exits;
  # Source addresses node `n` uses when it egresses through exit `x`, and the
  # range the hub maps to `x` (x.octet + 10 in the third v4 octet / fourth v6 group).
  exitNet = x: toString (10 + x.octet);
  src4 = x: n: "${base4}.${exitNet x}.${toString n.octet}";
  src6 = x: n: "${base6}:${exitNet x}::${toString n.octet}";
  range4 = x: "${base4}.${exitNet x}.0/24";
  range6 = x: "${base6}:${exitNet x}::/64";

  # Egress units on this host; each conflicts with all the others and with tukl.
  egressUnits = [ "vpn-egress-olympus" ] ++ map (x: "vpn-egress-${x.name}") otherExits;

  # GRE mtu: mesh mtu 1420 minus 24 bytes of GRE
  greMtu = "1396";
  # Idempotent rule add/delete; `ruleAdd` applies one spec to both families.
  ruleAddIn = f: spec: ''
    ${ip} ${f} rule del ${spec} || true
    ${ip} ${f} rule add ${spec}
  '';
  ruleAdd = spec: ruleAddIn "-4" spec + ruleAddIn "-6" spec;
  ruleDel =
    spec:
    lib.concatMapStringsSep "\n" (f: "${ip} ${f} rule del ${spec} || true") [
      "-4"
      "-6"
    ];
  routeDefault =
    dev: table:
    lib.concatMapStringsSep "\n"
      (f: "${ip} ${f} route replace default dev ${dev} table ${toString table}")
      [
        "-4"
        "-6"
      ];
  greAdd = dev: local: remote: ''
    ${ip} link del ${dev} 2>/dev/null || true
    ${ip} link add ${dev} type gre local ${local} remote ${remote} ttl 64
    ${ip} link set ${dev} mtu ${greMtu} up
  '';

  # Hub: one GRE link per exit, its own table, and a rule sending the exit's
  # source range into it. Rule 2000 lets the mesh routes (prefix > 0) win first.
  hubSetup = ''
    ${ruleAdd "pref 2000 lookup main suppress_prefixlength 0"}
    ${lib.concatMapStringsSep "\n" (x: ''
      ${greAdd "vpn-${x.name}" self.ip x.ip}
      ${routeDefault "vpn-${x.name}" (2000 + x.octet)}
      ${ruleAddIn "-4" "pref ${toString (3000 + x.octet)} from ${range4 x} lookup ${toString (2000 + x.octet)}"}
      ${ruleAddIn "-6" "pref ${toString (3000 + x.octet)} from ${range6 x} lookup ${toString (2000 + x.octet)}"}
    '') exits}
  '';
  # Fallback in every exit table, installed with the gate and never removed:
  # while a vpn-<x> link is gone, its sources are dropped, not sent out of olympus.
  hubBlackholes = pkgs.writeShellScript "vpn-hub-blackholes" (
    lib.concatMapStringsSep "\n" (
      x:
      lib.concatMapStringsSep "\n" (
        f: "${ip} ${f} route replace blackhole default metric 4294967295 table ${toString (2000 + x.octet)}"
      ) [ "-4" "-6" ]
    ) exits
  );
  hubShutdown = ''
    ${ruleDel "pref 2000"}
    ${lib.concatMapStringsSep "\n" (x: ''
      ${ruleDel "pref ${toString (3000 + x.octet)}"}
      ${ip} link del vpn-${x.name} || true
    '') exits}
  '';

  # Exit: GRE back to the hub; connection-marked replies return through it (4900),
  # and forwarded exit traffic bypasses the host's own egress (4950).
  exitSetup = ''
    ${greAdd "vpn-exit" self.ip hub.ip}
    ${routeDefault "vpn-exit" 2300}
    ${ruleAdd "pref 4900 fwmark 0x2000/0x2000 lookup 2300"}
    ${ruleAdd "pref 4950 iif vpn-exit lookup main"}
  '';
  exitShutdown = ''
    ${ruleDel "pref 4900"}
    ${ruleDel "pref 4950"}
    ${ip} link del vpn-exit || true
  '';

  nft = "${pkgs.nftables}/bin/nft";
  # Atomic (re)load: empty declaration, delete, real table — the gate is never open.
  nftReload =
    table: ruleset:
    pkgs.writeText "${table}.nft" ''
      table inet ${table} {}
      delete table inet ${table}
      ${ruleset}
    '';
  # A gate loads before the network exists (before network-pre.target) and
  # wireguard-olympus requires it, so no packet is forwarded ungated. Changes
  # are applied by reload: restarting the gate would bounce the mesh too.
  nftUnit =
    file: after: {
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-pre.target" ];
      before = [ "network-pre.target" ];
      reloadIfChanged = true;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = [ "${nft} -f ${file}" ] ++ after;
        ExecReload = [ "${nft} -f ${file}" ] ++ after;
      };
    };

  # Phone gate (see the phone plane section): wg-easy clients may go out to the
  # internet and between phones; the mesh hosts and the home LAN only when
  # `vpn-phone` put them in the matching set.
  phoneIf = cfg.phones.interface;
  hostSpokes = lib.filter (n: !n.hub) (lib.attrValues nodes);
  lanNodes = lib.filter (n: n.lan != null) (lib.attrValues nodes);
  # Home LANs reached over the mesh rather than attached locally (vpn-home).
  remoteLans = lib.filter (n: n.name != selfName) lanNodes;
  addrList = lib.concatMapStringsSep ", " toString;
  hubRuleset = nftReload "vpn-hub" ''
    table inet vpn-hub {
      set phone_hosts { type ipv4_addr; }
      set phone_hosts6 { type ipv6_addr; }
      set phone_home { type ipv4_addr; }
      set local_home { type ipv4_addr; flags interval; }

      chain forward {
        type filter hook forward priority filter; policy accept;
        oifname "vpn-*" tcp flags syn tcp option maxseg size set rt mtu

        # nothing from the internet opens connections into the mesh or the phones
        iifname "${cfg.uplink}" oifname { "olympus", "${phoneIf}" } ct state new counter drop
        iifname "${cfg.uplink}" oifname "vpn-*" ct state new counter drop

        iifname "${phoneIf}" ct state established,related accept
        # phones get the internet, not the provider's private side or metadata service
        iifname "${phoneIf}" oifname "${cfg.uplink}" ip daddr { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 100.64.0.0/10, 169.254.0.0/16 } counter drop
        iifname "${phoneIf}" oifname "${cfg.uplink}" ip6 daddr { fc00::/7, fe80::/10 } counter drop
        iifname "${phoneIf}" oifname { "${cfg.uplink}", "${phoneIf}" } accept
        iifname "${phoneIf}" oifname "vpn-*" accept
        ${lib.optionalString (hostSpokes != [ ]) ''
          iifname "${phoneIf}" ip daddr { ${addrList (map (n: n.ip) hostSpokes)} } ip saddr @phone_hosts accept
          iifname "${phoneIf}" ip6 daddr { ${addrList (map (n: n.ip6) hostSpokes)} } ip6 saddr @phone_hosts6 accept
        ''}
        ${lib.concatMapStringsSep "\n" (
          n: ''iifname "${phoneIf}" ip daddr ${n.lan} ip saddr @phone_home accept''
        ) lanNodes}
        iifname "${phoneIf}" drop
      }

      # the hub's own home switch (vpn-home fills local_home)
      chain output {
        type filter hook output priority filter; policy accept;
        ${lib.concatMapStringsSep "\n" (n: "ip daddr ${n.lan} ip daddr != @local_home reject") lanNodes}
      }
    }
  '';

  meshIfaces = ''{ "olympus", "vpn-exit" }'';
  exitRuleset = nftReload "vpn-exit" ''
    table inet vpn-exit {
      set lan4 { type ipv4_addr; flags interval; auto-merge; }
      set lan6 { type ipv6_addr; flags interval; auto-merge; }

      chain prerouting {
        type filter hook prerouting priority mangle; policy accept;
        iifname "vpn-exit" ct mark set ct mark or 0x2000
        iifname != "vpn-exit" ct mark & 0x2000 == 0x2000 meta mark set meta mark or 0x2000
      }

      chain input {
        type filter hook input priority filter; policy accept;
        iifname "vpn-exit" drop
      }

      # Default drop: forwarding is on host-wide, so LAN neighbours or spoofed
      # mesh sources must not find a router here; only relay and home access pass.
      chain forward {
        type filter hook forward priority filter; policy drop;
        oifname "vpn-exit" tcp flags syn tcp option maxseg size set rt mtu
        ct state invalid drop
        ct state established,related accept
        iifname "vpn-exit" oifname ${meshIfaces} drop
        iifname "vpn-exit" oifname "tukl" counter drop
        iifname "vpn-exit" ip daddr { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 100.64.0.0/10, 169.254.0.0/16 } drop
        iifname "vpn-exit" ip daddr @lan4 drop
        iifname "vpn-exit" ip6 daddr { fc00::/7, fe80::/10 } drop
        iifname "vpn-exit" ip6 daddr @lan6 drop
        iifname "vpn-exit" accept
        ${lib.optionalString (self.lan != null)
          # the hub's lan route also catches exit-range sources (rule 2000): only mesh and phone sources may enter
          ''iifname "olympus" ip saddr { ${base4}.0.0/24,${cfg.phones.subnet} } ip daddr ${self.lan} accept''
        }
      }

      # NAT only relayed flows (connection mark from prerouting) and home access
      chain postrouting {
        type nat hook postrouting priority srcnat; policy accept;
        oifname != { "olympus", "vpn-exit", "lo", "tukl" } ct mark & 0x2000 == 0x2000 masquerade
        ${lib.optionalString (self.lan != null) ''iifname "olympus" ip daddr ${self.lan} masquerade''}
      }
    }
  '';

  # Global v6 prefixes are widened to their /56: a delegated prefix hands out
  # neighbouring /64s (and rotates them), the exit must refuse the whole site.
  widen6 = pkgs.writeText "vpn-widen6.py" ''
    import ipaddress
    import sys

    global_unicast = ipaddress.ip_network("2000::/3")
    for line in sys.stdin:
        if not line.strip():
            continue
        net = ipaddress.ip_network(line.strip(), strict=False)
        if net.subnet_of(global_unicast) and net.prefixlen > 56:
            net = net.supernet(new_prefix=56)
        print(net)
  '';

  # Refills lan4/lan6 with every routed prefix behind a real link, so the exit can
  # refuse its own LAN whatever network it is on.
  languard = pkgs.writeShellApplication {
    name = "vpn-languard";
    runtimeInputs = [
      pkgs.iproute2
      pkgs.nftables
      pkgs.jq
      pkgs.coreutils
      pkgs.python3
    ];
    text = ''
      fill() {
        local set=$1 elems
        elems=$(sort -u | paste -sd, -)
        echo "flush set inet vpn-exit $set"
        if [ -n "$elems" ]; then echo "add element inet vpn-exit $set { $elems }"; fi
      }
      routes='.[] | select(.dst != "default" and .dev != null and (.dev | test("^(lo|olympus|vpn-.*)$") | not))'
      {
        ip -j route show table main | jq -r "$routes | .dst" | fill lan4
        ip -j -6 route show table main \
          | jq -r "$routes | select(.dst | test(\"^(fe[89ab][0-9a-f]:|ff)\"; \"i\") | not) | .dst" \
          | python3 ${widen6} | fill lan6
      } | nft -f -
    '';
  };

  # Keeps the sets current: joining another network must not leave its lan open
  # to relayed traffic. The first event refills at once; a burst is coalesced
  # and followed by one more refill.
  languardWatch = pkgs.writeShellApplication {
    name = "vpn-languard-watch";
    runtimeInputs = [
      pkgs.iproute2
      pkgs.coreutils
      languard
    ];
    text = ''
      vpn-languard || true
      ip -o monitor route address | while read -r _; do
        vpn-languard || true
        if read -r -t 1 _; then
          while read -r -t 1 _; do :; done
          vpn-languard || true
        fi
      done
    '';
  };

  # Per-phone policy for the wg-easy clients (hub only): which exit they leave
  # through and whether they may reach the mesh hosts / home LAN. Clients come
  # from wg-easy's sqlite db; the choices live in state.json, keyed by public key.
  phoneStateDir = "/var/lib/vpn-phones";
  phoneCli = pkgs.writeShellApplication {
    name = "vpn-phone";
    runtimeInputs = [
      pkgs.jq
      pkgs.iproute2
      pkgs.nftables
      pkgs.coreutils
      pkgs.sqlite
      pkgs.gawk
      pkgs.gnugrep
      pkgs.util-linux
    ];
    text = ''
      db=${cfg.phones.db}
      state=${phoneStateDir}/state.json
      # exit name -> routing table on the hub
      declare -A tables=(${lib.concatMapStrings (x: " [${x.name}]=${toString (2000 + x.octet)}") exits} )

      usage() {
        cat >&2 <<'USAGE'
      usage: vpn-phone list
             vpn-phone <phone> egress <olympus|${lib.concatMapStringsSep "|" (x: x.name) exits}>
             vpn-phone <phone> hosts on|off
             vpn-phone <phone> home on|off
             vpn-phone apply
      <phone> is the wg-easy client name or its IPv4 address.
      USAGE
        exit 2
      }

      if [ "$(id -u)" != 0 ]; then
        echo "vpn-phone: must run as root (sudo vpn-phone ...)" >&2
        exit 1
      fi

      # public_key, v4, v6, name, enabled (tab separated); nothing while wg-easy has no db yet
      clients() {
        if [ -e "$db" ]; then
          sqlite3 -readonly -separator $'\t' "$db" \
            "SELECT public_key, ipv4_address, ipv6_address, name, enabled FROM clients_table WHERE interface_id = '${cfg.phones.interface}';"
        fi
      }

      get() { # <pk> <key> <default>
        if [ -s "$state" ]; then
          jq -r --arg pk "$1" --arg k "$2" --arg d "$3" '.[$pk][$k] // $d | tostring' "$state"
        else
          echo "$3"
        fi
      }

      set_state() { # <pk> <key> <json value>
        local tmp
        tmp=$(mktemp "$state.XXXXXX")
        if [ -s "$state" ]; then cat "$state"; else echo '{}'; fi \
          | jq --arg pk "$1" --arg k "$2" --argjson v "$3" '.[$pk][$k] = $v' > "$tmp"
        mv "$tmp" "$state"
      }

      # Rules are diffed, not reset: adds precede deletes, so a phone never
      # passes through a moment without its rule (which would leak it to olympus).
      apply() {
        local rows sets="" want have spec
        rows=$(clients)
        want=$(mktemp)
        have=$(mktemp)
        while IFS=$'\t' read -r pk a4 a6 name enabled; do
          [ -n "$pk" ] && [ "$enabled" != 0 ] || continue
          egress=$(get "$pk" egress olympus)
          if [ "$egress" != olympus ]; then
            target=''${tables[$egress]:-}
            if [ -z "$target" ]; then
              echo "vpn-phone: $name: unknown exit '$egress', its traffic is dropped" >&2
              target=prohibit
            fi
            [ -z "$a4" ] || echo "4 $a4/32 $target" >> "$want"
            [ -z "$a6" ] || echo "6 $a6/128 $target" >> "$want"
          fi
          if [ "$(get "$pk" hosts false)" = true ]; then
            [ -z "$a4" ] || sets+="add element inet vpn-hub phone_hosts { $a4 }"$'\n'
            [ -z "$a6" ] || sets+="add element inet vpn-hub phone_hosts6 { $a6 }"$'\n'
          fi
          if [ "$(get "$pk" home false)" = true ] && [ -n "$a4" ]; then
            sets+="add element inet vpn-hub phone_home { $a4 }"$'\n'
          fi
        done <<< "$rows"
        for f in 4 6; do
          ip -j -"$f" rule show pref 3500 \
            | jq -r --arg f "$f" '.[] | "\($f) \(.src)/\(.srclen // (if $f == "4" then 32 else 128 end)) \(.table // .action)"' >> "$have"
        done
        sort -o "$want" "$want"
        sort -o "$have" "$have"
        rule() { # <add|del> <family> <src> <target>
          if [[ $4 =~ ^[0-9]+$ ]]; then spec=(lookup "$4"); else spec=("$4"); fi
          ip -"$2" rule "$1" from "$3" "''${spec[@]}" pref 3500
        }
        comm -13 "$have" "$want" | while read -r f src target; do rule add "$f" "$src" "$target"; done
        comm -23 "$have" "$want" | while read -r f src target; do rule del "$f" "$src" "$target"; done
        rm -f "$want" "$have"
        nft -f - <<NFT
      flush set inet vpn-hub phone_hosts
      flush set inet vpn-hub phone_hosts6
      flush set inet vpn-hub phone_home
      $sets
      NFT
      }

      # resolve <phone> to a public key
      resolve() {
        local hits
        hits=$(clients | awk -F'\t' -v p="$1" '$4 == p || $2 == p { print $1 }')
        case $(printf '%s' "$hits" | grep -c . || true) in
          1) echo "$hits" ;;
          0) echo "vpn-phone: no such phone: $1" >&2; return 1 ;;
          *) echo "vpn-phone: '$1' is ambiguous, use its IPv4 address" >&2; return 1 ;;
        esac
      }

      [ $# -ge 1 ] || usage
      mkdir -p ${phoneStateDir}
      # the CLI, vpn-phones.service and the hub reload may overlap
      exec 9> ${phoneStateDir}/lock
      flock 9
      case $1 in
        list)
          [ $# -eq 1 ] || usage
          {
            echo -e "NAME\tIPV4\tIPV6\tENABLED\tEGRESS\tHOSTS\tHOME"
            clients | while IFS=$'\t' read -r pk a4 a6 name enabled; do
              echo -e "$name\t$a4\t$a6\t$enabled\t$(get "$pk" egress olympus)\t$(get "$pk" hosts false)\t$(get "$pk" home false)"
            done
          } | column -t -s $'\t'
          ;;
        apply)
          [ $# -eq 1 ] || usage
          apply
          ;;
        *)
          [ $# -ge 3 ] || usage
          pk=$(resolve "$1")
          case $2 in
            egress)
              [ $# -eq 3 ] || usage
              if [ "$3" != olympus ] && [ -z "''${tables[$3]:-}" ]; then usage; fi
              set_state "$pk" egress "\"$3\""
              ;;
            hosts | home)
              [ $# -eq 3 ] || usage
              case $3 in
                on) set_state "$pk" "$2" true ;;
                off) set_state "$pk" "$2" false ;;
                *) usage ;;
              esac
              ;;
            *) usage ;;
          esac
          apply
          ;;
      esac
    '';
  };

  # Re-applies whenever wg-easy writes its db. A systemd .path unit cannot do
  # this: it also fires on IN_CLOSE_WRITE, which every sqlite reader (apply
  # itself) causes by opening the -wal/-shm files read-write, so it re-triggers
  # forever until the start limit kills it. IN_MODIFY is writers only, bar the
  # -shm file, which a reader rewrites when no writer holds the db open.
  phonesWatch = pkgs.writeShellApplication {
    name = "vpn-phones-watch";
    runtimeInputs = [
      pkgs.inotify-tools
      pkgs.coreutils
      phoneCli
    ];
    text = ''
      vpn-phone apply
      inotifywait -m -q -e modify -e moved_to --exclude '-shm$' --format x ${dirOf cfg.phones.db} | while read -r _; do
        # let a burst of writes settle
        while read -r -t 1 _; do :; done
        echo "wg-easy db changed, applying"
        vpn-phone apply
      done
    '';
  };

  owner = "/run/vpn-egress";

  # Egress table 2100 is consulted by rules 5200/5300 while the unit is active.
  # `extra` are addresses added to `olympus` for the unit's lifetime.
  egressScripts =
    {
      name,
      src4,
      src6,
      extra ? [ ],
    }:
    let
      each =
        f:
        lib.concatMapStringsSep "\n" f [
          "-4"
          "-6"
        ];
      addrFlags = a: lib.optionalString (lib.hasInfix ":" a) "-6 ";
      nodad = a: lib.optionalString (lib.hasInfix ":" a) " nodad";
    in
    {
      start = pkgs.writeShellScript "vpn-egress-start" ''
        echo ${name} > ${owner}
        ${lib.concatMapStringsSep "\n" (
          a: "${ip} ${addrFlags a}addr replace ${a} dev olympus${nodad a}"
        ) extra}
        ${ip} route replace default dev olympus src ${src4} table 2100
        ${ip} -6 route replace default dev olympus src ${src6} table 2100
        ${each (f: ''
          ${ip} ${f} rule del pref 5200 || true
          ${ip} ${f} rule add pref 5200 lookup main suppress_prefixlength 0
          ${ip} ${f} rule del pref 5300 || true
          ${ip} ${f} rule add pref 5300 lookup 2100
        '')}
      '';
      # Switching units starts the new one before this stop may run; only the
      # current owner of the shared rules and table tears them down.
      stop = pkgs.writeShellScript "vpn-egress-stop" ''
        if [ "$(cat ${owner} 2>/dev/null)" = ${name} ]; then
          ${each (f: ''
            ${ip} ${f} rule del pref 5200 || true
            ${ip} ${f} rule del pref 5300 || true
            ${ip} ${f} route flush table 2100 || true
          '')}
          rm -f ${owner}
        fi
        ${lib.concatMapStringsSep "\n" (a: "${ip} ${addrFlags a}addr del ${a} dev olympus || true") extra}
      '';
    };

  # Bypass guards: tukl and the egress rules (pref 5300) must never be up together,
  # whatever brought one of them up.
  egressGuard = pkgs.writeShellScript "vpn-egress-guard" ''
    if ${ip} link show dev tukl >/dev/null 2>&1 \
      && ! ${config.systemd.package}/bin/systemctl is-active --quiet wg-quick-tukl.service; then
      echo "a tukl link exists outside wg-quick-tukl.service; run 'wg-quick down tukl' first" >&2
      exit 1
    fi
  '';
  tuklGuard = pkgs.writeShellScript "wg-quick-tukl-guard" ''
    for f in -4 -6; do
      if [ -n "$(${ip} $f rule show pref 5300)" ]; then
        echo "an egress rule (pref 5300) is active; stop the vpn-egress unit first" >&2
        exit 1
      fi
    done
  '';

  egressUnit =
    name: args:
    let
      scripts = egressScripts (args // { inherit name; });
    in
    {
      bindsTo = [ "wireguard-olympus.service" ];
      # Conflicts= alone does not order the stop before the start; any ordering edge
      # does, so the egress units and tukl form a one-directional chain in list order.
      after = [
        "wireguard-olympus.service"
      ]
      ++ map (n: "${n}.service") (lib.take (lib.lists.findFirstIndex (n: n == name) null egressUnits) egressUnits);
      partOf = [ "wireguard-olympus.service" ];
      conflicts =
        map (n: "${n}.service") (lib.filter (n: n != name) egressUnits)
        ++ lib.optional (self.tukl != null) "wg-quick-tukl.service";
      wants = [ "vpn-egress-watch@${name}.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStartPre = egressGuard;
        ExecStart = scripts.start;
        ExecStop = scripts.stop;
      };
    };

  # Pings through the egress table (the unit's rules are active) and shouts when
  # the exit stops forwarding; the tunnel then drops traffic instead of leaking it.
  egressWatch = pkgs.writeShellApplication {
    name = "vpn-egress-watch";
    runtimeInputs = [
      pkgs.iputils
      pkgs.util-linux
      pkgs.coreutils
    ];
    text = ''
      unit=$1
      fails=0
      down=0
      # the `vpn` CLI and the bar read this marker while the exit is down
      marker=/run/vpn-egress-watch/$unit.down
      mkdir -p /run/vpn-egress-watch
      trap 'rm -f "$marker"' EXIT
      trap 'exit 0' TERM INT

      notify() {
        bus="/run/user/$(id -u dk)/bus"
        if [ -S "$bus" ]; then
          runuser -u dk -- env "DBUS_SESSION_BUS_ADDRESS=unix:path=$bus" \
            ${pkgs.libnotify}/bin/notify-send -u "$1" -a vpn "$2" "$3" || true
        fi
      }

      while true; do
        if ping -c1 -W5 -n ${cfg.probe} >/dev/null 2>&1; then
          fails=0
          if [ "$down" = 1 ]; then
            down=0
            rm -f "$marker"
            echo "$unit: reachable again"
            notify normal "VPN exit back" "$unit: internet reachable again"
          fi
        else
          fails=$((fails + 1))
          if [ "$fails" -ge 2 ] && [ "$down" = 0 ]; then
            down=1
            touch "$marker"
            echo "$unit: no internet through the exit — traffic is dropped"
            notify critical "VPN exit down" "$unit: no internet, traffic is dropped — systemctl stop $unit to go direct"
          fi
        fi
        sleep 15 &
        wait $!
      done
    '';
  };

  # ssh over the tunnel. While `olympus` is up, `ssh hestia` must resolve to the
  # peer's tunnel address — its LAN name is unreachable from anywhere else, and
  # a full tunnel (tukl, egress) puts the client "anywhere else" even at home. Every node in the
  # registry gets an entry, self included, so the file is the same everywhere.
  # The `.local` aliases are deliberately left alone as the LAN fast path for
  # bulk transfers: via the tunnel every byte detours through olympus at ~45 ms
  # RTT. Identity/auth still come from the home-manager block in ~/.ssh/config —
  # ssh takes the first value it obtains and Include is first, so that block has
  # to name all three hosts (see home-manager/modules/ssh).
  sshTunnelConfig = pkgs.writeText "ssh-config-olympus" (
    lib.concatStrings (
      lib.mapAttrsToList (name: node: ''
        Host ${name}
          HostName ${node.ip}
      '') nodes
    )
  );
  # `programs.ssh.includes` in home-manager/modules/ssh pulls this path in; a
  # missing include is a debug message to ssh, not an error, so the tunnel-down
  # state is simply the file's absence.
  sshUser = config.users.users.dk;
  sshLocalConfig = "${sshUser.home}/.ssh/config.local";
in
{
  imports = [ ./cli.nix ];

  # Internal: the registry and its constants. tests/vpn.nix overrides them.
  options.vpn = {
    nodes = lib.mkOption {
      internal = true;
      description = "Mesh node registry, keyed by host name.";
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            octet = lib.mkOption {
              type = lib.types.ints.between 1 254;
              description = "Last address octet in the v4 and v6 mesh subnets.";
            };
            publicKey = lib.mkOption {
              type = lib.types.str;
              description = "WireGuard public key of the node.";
            };
            hub = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Whether the node is the mesh hub (server).";
            };
            exit = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Whether the node can serve as an exit for the others.";
            };
            lan = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "LAN prefix behind the node, if it has one.";
            };
            tukl = lib.mkOption {
              type = lib.types.nullOr (
                lib.types.submodule {
                  options = {
                    secret = lib.mkOption {
                      type = lib.types.str;
                      description = "Agenix secret filename (without .age) for the WireGuard private key.";
                    };
                    address = lib.mkOption {
                      type = lib.types.listOf lib.types.str;
                      description = "List of addresses for the tukl interface.";
                    };
                    dns = lib.mkOption {
                      type = lib.types.listOf lib.types.str;
                      description = "List of DNS servers for the tukl interface.";
                    };
                    mtu = lib.mkOption {
                      type = lib.types.int;
                      description = "MTU for the tukl interface.";
                    };
                    publicKey = lib.mkOption {
                      type = lib.types.str;
                      description = "RPTU peer's WireGuard public key.";
                    };
                    endpoint = lib.mkOption {
                      type = lib.types.str;
                      description = "RPTU peer's endpoint (host:port).";
                    };
                  };
                }
              );
              default = null;
              description = "RPTU VPN configuration for this node (null if not using tukl).";
            };
          };
        }
      );
      default =
        let
          # RPTU's peer is the same for every config; each host has its own key/address.
          rptu = secret: address: {
            inherit secret address;
            dns = [
              "2001:638:208:9::116"
              "2001:638:208:1::116"
              "131.246.9.116"
              "131.246.1.116"
            ];
            mtu = 1280;
            publicKey = "j77guFVKQ4sxwJCgqt/vFvHxkvX4Bwqh7B3Za6oOOk4=";
            endpoint = "vpnwg.uni-kl.de:51820";
          };
        in
        {
          olympus = {
            octet = 1;
            publicKey = "8ujDiLPMOK3X0BdAWVTDWPMUOxPSnGNdFKtYD1MgxRk=";
            hub = true;
          };
          hestia = {
            octet = 2;
            publicKey = "4YGKRQjZN2l4OmoxOfvL9zAa5hVFBb3IoE6+uUGz4kk=";
            exit = true;
            lan = "192.168.178.0/24";
            tukl = rptu "wg-tukl-hestia" [
              "172.27.242.67/32"
              "2001:638:208:fd49:f:5fff:fe21:49a7/128"
            ];
          };
          hermes = {
            octet = 3;
            publicKey = "bAad0LzXDbsnk4NISns3VOfWiOlmgVMc3dkWd4Z2KTM=";
            exit = true;
            tukl = rptu "wg-tukl-hermes" [
              "172.27.248.53/32"
              "2001:638:208:fd49:37:9bff:fe2e:ef6a/128"
            ];
          };
        };
    };
    endpoint = lib.mkOption {
      internal = true;
      type = lib.types.str;
      default = "vpn.dklaassen.de:${toString port}";
      description = "Hub endpoint the spokes dial.";
    };
    uplink = lib.mkOption {
      internal = true;
      type = lib.types.str;
      default = "ens6";
      description = "Hub WAN interface (NAT external interface).";
    };
    probe = lib.mkOption {
      internal = true;
      type = lib.types.str;
      default = "1.1.1.1";
      description = "Address the egress watchdog pings through the exit.";
    };
    phones.interface = lib.mkOption {
      internal = true;
      type = lib.types.str;
      default = "wg0";
      description = "wg-easy interface on the hub.";
    };
    phones.subnet = lib.mkOption {
      internal = true;
      type = lib.types.str;
      default = "10.100.1.0/24";
      description = "wg-easy phone v4 subnet.";
    };
    phones.db = lib.mkOption {
      internal = true;
      type = lib.types.str;
      default = "/var/lib/wg-easy/wg-easy.db";
      description = "wg-easy's sqlite database, read by vpn-phone.";
    };
    phones.subnet6 = lib.mkOption {
      internal = true;
      type = lib.types.str;
      default = "fdcc:ad94:bacf:61a4::cafe:0/112";
      description = "wg-easy phone v6 subnet; exits masquerade it like the mesh.";
    };
    privateKeyFile = lib.mkOption {
      internal = true;
      type = lib.types.str;
      default = config.age.secrets."wg-${selfName}".path;
      defaultText = lib.literalExpression ''config.age.secrets."wg-''${host.hostName}".path'';
      description = "Path of this host's mesh private key.";
    };
  };

  config = {
    age.secrets."wg-${selfName}" = {
      file = "${secretsPath}/wg-${selfName}.age";
      mode = "0400";
    };

    # ---------------------------------------------------------------------------
    # HUB (olympus) — mesh server, NAT, GRE links to the exits
    # ---------------------------------------------------------------------------
    networking.wireguard.interfaces.olympus = lib.mkMerge [
      (lib.mkIf isServer {
        ips = [
          "${self.ip}/24"
          "${self.ip6}/64"
        ];
        listenPort = port;
        inherit (cfg) privateKeyFile;
        peers = map (node: {
          inherit (node) publicKey;
          allowedIPs = [
            "${node.ip}/32"
            "${node.ip6}/128"
          ]
          ++ lib.concatMap (x: [
            "${src4 x node}/32"
            "${src6 x node}/128"
          ]) (lib.filter (x: x.name != node.name) exits)
          ++ lib.optional (node.lan != null) node.lan;
        }) spokes;
        postSetup = hubSetup;
        postShutdown = hubShutdown;
      })
      (lib.mkIf (!isServer) {
        ips = [
          "${self.ip}/24"
          "${self.ip6}/64"
        ];
        inherit (cfg) privateKeyFile;
        fwMark = mark;
        allowedIPsAsRoutes = false;
        peers = [
          {
            name = "olympus";
            inherit (nodes.olympus) publicKey;
            allowedIPs = [
              "0.0.0.0/0"
              "::/0"
            ];
            inherit (cfg) endpoint;
            persistentKeepalive = 25;
            # retries DNS forever, so booting offline is fine
            dynamicEndpointRefreshSeconds = 300;
          }
        ];
        # rules are deleted first so a re-run after a crashed stop stays idempotent
        postSetup = ''
          ${ip} route replace ${subnet}.0/16 dev olympus src ${self.ip}
          ${ip} -6 route replace ${subnet6}/48 dev olympus src ${self.ip6}
          ${underlayRules "add"}
          ${lib.optionalString self.exit exitSetup}
          ${pkgs.coreutils}/bin/install -m 0600 -o ${sshUser.name} -g ${sshUser.group} ${sshTunnelConfig} ${sshLocalConfig}
        '';
        postShutdown = ''
          ${underlayRules "del"}
          ${lib.optionalString self.exit exitShutdown}
          ${pkgs.coreutils}/bin/rm -f ${sshLocalConfig}
        '';
      })
    ];

    # networking.nat enables forwarding and installs the masquerade/forward rules
    # so client traffic (0.0.0.0/0, ::/0) can egress via olympus's WAN interface.
    # enableIPv6 adds the ip6tables half plus net.ipv6.conf.*.forwarding.
    #
    # CAVEAT: olympus currently has NO global IPv6 on ens6 (link-local only, no v6
    # default route) — the VPS provider has not assigned a prefix. Until it does,
    # the v6 masquerade rule matches nothing routable and traffic to the v6
    # internet dies at olympus with an ICMPv6 "no route", which the client sees
    # immediately and Happy Eyeballs turns into a fast fallback to IPv4. That is
    # the point of giving the tunnel v6 addresses at all: a v4-only tunnel that
    # still carries ::/0 blackholes AAAA traffic silently instead. Once the
    # provider hands olympus a prefix, full v6 egress works with no config change.
    networking.nat = lib.mkIf isServer {
      enable = true;
      enableIPv6 = true;
      externalInterface = cfg.uplink;
      internalInterfaces = [ "olympus" ];
    };

    networking.firewall.allowedUDPPorts = lib.mkIf isServer [ port ];
    # GRE between the hub and the exits rides inside the mesh
    networking.firewall.extraCommands = "iptables -A nixos-fw -i olympus -p gre -j nixos-fw-accept";

    # ---------------------------------------------------------------------------
    # HOSTS (hermes / hestia) — always-on split mesh
    # ---------------------------------------------------------------------------
    # The peer carries 0.0.0.0/0 + ::/0 only so the hub may source any address;
    # allowedIPsAsRoutes = false keeps the default route off the interface, and
    # postSetup routes just the mesh supernet through it. fwMark + rule 5000 keep
    # the encrypted socket on the underlay, out of any full tunnel (tukl included).
    # Toggle with `systemctl stop|start wireguard-olympus` (no sudo: userManagedUnits).

    # the mesh is flipped by hand, so let wheel do it without sudo
    host.userManagedUnits = lib.optionals (!isServer) (
      [
        "wireguard-olympus.service"
      ]
      ++ map (n: "${n}.service") egressUnits
      ++ lib.optional (remoteLans != [ ]) "vpn-home.service"
      ++ lib.optional (self.tukl != null) "wg-quick-tukl.service"
    );

    # ---------------------------------------------------------------------------
    # Egress — opt-in full tunnel
    # ---------------------------------------------------------------------------
    # "Direct" means no egress unit is active; `vpn egress` wraps start/stop.
    # The watcher makes a dead exit loud: traffic is dropped, never sent direct.
    systemd.services = lib.mkMerge [
      (lib.mkIf (!isServer) (
        {
          vpn-egress-olympus = egressUnit "vpn-egress-olympus" {
            src4 = self.ip;
            src6 = self.ip6;
          };
          "vpn-egress-watch@" = {
            bindsTo = [ "%i.service" ];
            after = [ "%i.service" ];
            serviceConfig = {
              Type = "simple";
              ExecStart = "${egressWatch}/bin/vpn-egress-watch %i";
            };
          };
          wg-quick-tukl = lib.mkIf (self.tukl != null) {
            wants = [ "vpn-egress-watch@wg-quick-tukl.service" ];
            after = map (n: "${n}.service") egressUnits;
          };
        }
        // lib.listToAttrs (
          map (x: {
            name = "vpn-egress-${x.name}";
            value = egressUnit "vpn-egress-${x.name}" {
              src4 = src4 x self;
              src6 = src6 x self;
              extra = [
                "${src4 x self}/32"
                "${src6 x self}/128"
              ];
            };
          }) otherExits
        )
      ))
      (lib.mkIf isServer {
        # a reload empties local_home: restart vpn-home (partOf) to refill it
        vpn-hub-nft = lib.recursiveUpdate (nftUnit hubRuleset [
          "${phoneCli}/bin/vpn-phone apply"
          "-${config.systemd.package}/bin/systemctl --no-block try-restart vpn-home.service"
        ]) { serviceConfig.ExecStartPre = hubBlackholes; };
        wireguard-olympus = {
          requires = [ "vpn-hub-nft.service" ];
          after = [ "vpn-hub-nft.service" ];
        };
        # olympus's own access to the home LAN
        vpn-home = lib.mkIf (lanNodes != [ ]) {
          after = [ "vpn-hub-nft.service" ];
          requires = [ "vpn-hub-nft.service" ];
          partOf = [ "vpn-hub-nft.service" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = "${nft} add element inet vpn-hub local_home { ${addrList (map (n: n.lan) lanNodes)} }";
            ExecStop = "${nft} flush set inet vpn-hub local_home";
          };
        };
        vpn-phones = {
          wantedBy = [ "multi-user.target" ];
          after = [ "vpn-hub-nft.service" ];
          requires = [ "vpn-hub-nft.service" ];
          serviceConfig = {
            Type = "simple";
            ExecStart = "${phonesWatch}/bin/vpn-phones-watch";
            Restart = "on-failure";
          };
        };
      })
      # home LAN through the mesh: table 2200, rule 5100 (v4 only)
      (lib.mkIf (!isServer && remoteLans != [ ]) {
        vpn-home = {
          bindsTo = [ "wireguard-olympus.service" ];
          after = [ "wireguard-olympus.service" ];
          partOf = [ "wireguard-olympus.service" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = pkgs.writeShellScript "vpn-home-start" (
              lib.concatMapStringsSep "\n" (n: ''
                ${ip} route replace ${n.lan} dev olympus src ${self.ip} table 2200
                ${ip} rule del to ${n.lan} lookup 2200 pref 5100 || true
                ${ip} rule add to ${n.lan} lookup 2200 pref 5100
              '') remoteLans
            );
            ExecStop = pkgs.writeShellScript "vpn-home-stop" (
              lib.concatMapStringsSep "\n" (n: ''
                ${ip} rule del to ${n.lan} lookup 2200 pref 5100 || true
                ${ip} route del ${n.lan} table 2200 || true
              '') remoteLans
            );
          };
        };
      })
      # wg-easy's interface must not come up before the phone gate
      (lib.mkIf (isServer && config.virtualisation.oci-containers.containers ? wg-easy) {
        podman-wg-easy = {
          requires = [ "vpn-hub-nft.service" ];
          after = [ "vpn-hub-nft.service" ];
        };
      })
      (lib.mkIf self.exit {
        vpn-exit-nft = nftUnit exitRuleset [ "${languard}/bin/vpn-languard" ];
        wireguard-olympus = {
          requires = [ "vpn-exit-nft.service" ];
          after = [ "vpn-exit-nft.service" ];
        };
        vpn-languard-watch = {
          wantedBy = [ "multi-user.target" ];
          requires = [ "vpn-exit-nft.service" ];
          after = [ "vpn-exit-nft.service" ];
          partOf = [ "vpn-exit-nft.service" ];
          serviceConfig = {
            ExecStart = "${languardWatch}/bin/vpn-languard-watch";
            Restart = "always";
          };
        };
      })
    ];

    # ---------------------------------------------------------------------------
    # Phone plane (hub) — per-phone egress and access
    # ---------------------------------------------------------------------------
    # Defaults: exit through olympus, no mesh hosts, no home LAN. Choices live in
    # ${phoneStateDir}/state.json keyed by public key. A phone whose exit is
    # unknown is blocked (prohibit), one whose exit is down loses its traffic;
    # neither falls back to olympus.
    systemd.tmpfiles.rules = lib.mkIf isServer [ "d ${phoneStateDir} 0700 root root -" ];
    environment.systemPackages = lib.mkIf isServer [ phoneCli ];

    # ---------------------------------------------------------------------------
    # Exits — hosts that carry other hosts' full-tunnel traffic
    # ---------------------------------------------------------------------------
    # Exit side of the GRE relay (see header): forwarding, rpfilter, vpn-exit nft.
    boot.kernel.sysctl = lib.mkIf self.exit {
      # NetworkManager handles RAs in userspace here (accept_ra = 0 on the links),
      # so forwarding does not cost the host its v6 default route.
      "net.ipv4.conf.all.forwarding" = 1;
      "net.ipv6.conf.all.forwarding" = 1;
      # systemd applies its loose rp_filter default to each new link; that still
      # drops the decapsulated packets (reverse lookups ignore the iif rules)
      "net.ipv4.conf.vpn-exit.rp_filter" = 0;
    };
    assertions = lib.optional self.exit {
      assertion = config.networking.firewall.checkReversePath != true;
      message = "vpn exits need networking.firewall.checkReversePath = false or \"loose\": strict rpfilter drops the GRE-decapsulated exit traffic.";
    };

    # keep NetworkManager off the mesh and the GRE links on the desktops
    networking.networkmanager.unmanaged = lib.mkIf (!isServer) [
      "interface-name:olympus"
      "interface-name:vpn-*"
    ];

    # ---------------------------------------------------------------------------
    # tukl — TU Kaiserslautern university VPN, per-node config from registry
    # ---------------------------------------------------------------------------
    # Modeled declaratively from the upstream wg-quick config. Only the private
    # key is secret: it lives in agenix and is referenced via privateKeyFile so
    # it never lands in the Nix store. Not autostarted: `vpn egress tukl` (or
    # `systemctl start wg-quick-tukl`) dials it, conflicting with the egress units.
    age.secrets.wg-tukl = lib.mkIf (self.tukl != null) {
      file = "${secretsPath}/${self.tukl.secret}.age";
      mode = "0400";
    };

    networking.wg-quick.interfaces.tukl = lib.mkIf (self.tukl != null) {
      autostart = false;
      privateKeyFile = config.age.secrets.wg-tukl.path;
      preUp = "${tuklGuard}";
      inherit (self.tukl) address dns mtu;
      peers = [
        {
          inherit (self.tukl) publicKey endpoint;
          allowedIPs = [
            "0.0.0.0/0"
            "::/0"
          ];
          persistentKeepalive = 25;
        }
      ];
    };
  };
}
