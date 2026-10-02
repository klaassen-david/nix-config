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
#   hub    2000   to <mesh, phones, lans>: main, suppress_prefixlength 0
#                                                        their routes beat the exit tables
#   hub    3000+x from <x's range>                       2000+x: default dev vpn-<x>
#   hub    3500   from <phone> (vpn-phone, per phone)    2000+x, or prohibit
#   exit   4900   fwmark 0x2000/0x2000                   2300: default dev vpn-exit
#   exit   4950   iif vpn-exit                           main
#   host   4960   to <mesh /16, /48, phones /112>        2050: those prefixes dev olympus, + blackholes
#   host   5000   fwmark 0x1000/0x1000                   main (mesh socket: never tunnelled)
#   host   5100   to <lan> (v4; vpn-home)                2200: <lan> dev olympus
#   host   5200   all (egress or tukl selected)          2150: networks attached to the local links
#                                                        (>= /16, /48) + routes over the mesh
#   host   5300   all (egress or tukl selected)          2100: default dev olympus|tukl, else blackhole;
#                                                        prohibit <home lan>
#
# Mesh prefixes (4960) are always resolved in table 2050, whatever main holds: a
# route a local network pushes cannot divert them, and with the mesh down the
# blackholes (kept by `vpn-underlay`, like rule 5000, independent of the mesh unit)
# make them unreachable rather than sending them out of the local link.
#
# The egress slot (5200/5300, table 2100) is shared by the egress units and tukl
# (wg-quick `Table = off`, its scripts fill the slot). It outlives its holder: a
# unit's stop (plain stop, restart, shutdown) removes only its default routes and
# extra addresses, so the blackhole in 2100 drops traffic until a unit takes the
# slot again or `vpn egress direct` / `vpn mesh off` (`vpn-egress-reset`) removes
# it; `vpn status` calls that `blocked`. Table 2150 holds the prefixes of the
# networks the host sits on (from the interface addresses, not from main) and the
# mesh routes, kept by `vpn-onlink` while a slot is taken: a route pushed into
# main by the local network (DHCP option 121, TunnelVision) cannot steer traffic
# around the tunnel. A mesh restart re-attaches the selected unit's routes only if
# that unit is still active; the units do not restart on deploys.
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
# hosts and the home lan only for addresses in the vpn-phone sets. From the
# uplink into the mesh, wg0 or the GRE links only replies pass (established,
# related; the rest, invalid included, is dropped). Hosts may open connections
# to phones (only wg0 ingress is gated). It also rejects the hub's own traffic
# to the lan unless vpn-home is on. `vpn-exit` (exits) forwards with policy
# drop: relayed traffic (from `vpn-exit`) to anywhere but the mesh, tukl,
# private ranges and the exit's own lan (`vpn-languard` supplies the sets, v6
# widened to /56; `vpn-exit-load` loads them in the gate's own transaction and
# `vpn-languard-watch` follows route and address changes), plus mesh/phone
# sources to the lan on its owner; only those are masqueraded. The exit's own
# services are shut to relayed traffic, and on the lan owner to phones (mesh
# hosts only) at its lan address. Both tables reload atomically and have no
# stop. Their gate units (`vpn-hub-nft`, `vpn-exit-nft`) run before
# network-pre.target and `wireguard-olympus` (hub: also `podman-wg-easy`)
# requires them. Apply changes with `systemctl reload`: a restart would take
# the mesh down with it.
#
# Units (hosts; wheel starts/stops them without sudo, host.userManagedUnits):
#   wireguard-olympus      the mesh; vpn-home is bound to it, the egress units only
#                          want it (a restart re-attaches the selected egress)
#   vpn-underlay           always on, before the network: rule 5000, rule 4960 + blackholes
#   vpn-onlink             keeps table 2150 current while the slot is taken
#   vpn-egress-<olympus|x> one active at most, conflict with each other and tukl;
#                          vpn-egress-watch@ announces a dead exit (traffic is dropped)
#   wg-quick-tukl          tukl, dialled by the host itself, in the same slot
#   vpn-egress-reset       tears the slot down (`vpn egress direct`)
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
#   - Table 2150 trusts the host's own interface addresses: a network that hands
#     out a /16-or-longer address (or a rogue DHCP lease) keeps that prefix
#     direct, as it must for the network to be reachable at all. The watchdog
#     checks the probe's path, not every destination.
#   - The selection does not survive a reboot; hosts boot direct.
#   - After the hub's mesh restarts, spokes re-handshake on their next keepalive:
#     up to 1-2 minutes of dropped traffic.
#   - Relayed traffic is refused the exit's LAN, not the home router's WAN
#     address: services the router exposes there (hairpin/port forwards) stay
#     reachable through hestia. TODO.md tracks adding the WAN address.
#   - An exit carries its own network position: a phone relayed through hermes
#     on campus reaches what the RPTU network lets that host reach.
#   - The egress selection lives in /run: every boot starts direct.

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
  # Add if missing, never delete first: for rules that must not blink on a re-run.
  ruleKeep =
    spec:
    lib.concatMapStringsSep "\n" (f: "${ip} ${f} rule add ${spec} 2>/dev/null || true") [
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

  # Delete every rule at a pref (a pref can hold several rules).
  ruleFlush =
    pref:
    lib.concatMapStringsSep "\n" (f: "while ${ip} ${f} rule del pref ${pref} 2>/dev/null; do :; done") [
      "-4"
      "-6"
    ];
  # Prefixes the hub reaches through main: the mesh, the phones, the home lans.
  hubMain4 = lib.unique ([ "${base4}.0.0/16" cfg.phones.subnet ] ++ map (n: n.lan) lanNodes);
  hubMain6 = lib.unique [
    "${base6}::/48"
    cfg.phones.subnet6
  ];

  # Hub: one GRE link per exit, its own table, and a rule sending the exit's
  # source range into it. Rule 2000 lets main's routes (prefix > 0) win first,
  # but only towards the mesh, phones and lans: any other main route (an
  # on-link prefix at the provider, say) must not catch an exit's traffic.
  hubSetup = ''
    ${ruleFlush "2000"}
    ${lib.concatMapStringsSep "\n" (
      p: ruleAddIn "-4" "pref 2000 to ${p} lookup main suppress_prefixlength 0"
    ) hubMain4}
    ${lib.concatMapStringsSep "\n" (
      p: ruleAddIn "-6" "pref 2000 to ${p} lookup main suppress_prefixlength 0"
    ) hubMain6}
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
    ${ruleFlush "2000"}
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

  # Mesh prefixes (hosts): routed by table 2050, consulted by rule 4960 ahead of the
  # egress slot and main. The mesh's postSetup adds the real routes; the blackholes
  # stay, so a downed mesh makes the mesh unreachable instead of sending it to the
  # local network (a route pushed into main cannot take it either).
  meshTable = "2050";
  meshPrefixes = [
    {
      f = "-4";
      dst = "${subnet}.0/16";
    }
    {
      f = "-6";
      dst = "${subnet6}/48";
    }
    {
      f = "-6";
      dst = cfg.phones.subnet6;
    }
  ];
  meshRoutes = lib.concatMapStringsSep "\n" (
    p:
    "${ip} ${p.f} route replace ${p.dst} dev olympus src ${
      if p.f == "-4" then self.ip else self.ip6
    } table ${meshTable}"
  ) meshPrefixes;
  # Independent of the mesh unit and never removed: the underlay rule (the mesh
  # socket stays out of any tunnel) and the mesh blackholes must outlive a mesh
  # restart. Idempotent, so a restart of this unit never opens a gap.
  underlay = pkgs.writeShellScript "vpn-underlay" ''
    set -euo pipefail
    ${ruleKeep "pref 5000 fwmark ${mark}/${mark} lookup main"}
    ${lib.concatMapStringsSep "\n" (p: ''
      ${ip} ${p.f} route replace blackhole ${p.dst} metric 4294967295 table ${meshTable}
      ${ip} ${p.f} rule add pref 4960 to ${p.dst} lookup ${meshTable} 2>/dev/null || true
    '') meshPrefixes}
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
    load: after: {
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-pre.target" ];
      before = [ "network-pre.target" ];
      reloadIfChanged = true;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = [ load ] ++ after;
        ExecReload = [ load ] ++ after;
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

        # from the internet only replies enter the mesh, the phones and the GRE links
        iifname "${cfg.uplink}" oifname { "olympus", "${phoneIf}" } ct state { established, related } accept
        iifname "${cfg.uplink}" oifname { "olympus", "${phoneIf}" } counter drop
        iifname "${cfg.uplink}" oifname "vpn-*" ct state { established, related } accept
        iifname "${cfg.uplink}" oifname "vpn-*" counter drop

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
        ${lib.optionalString (self.lan != null)
          # home-lan access is for passing through: only mesh hosts may talk to this host's own lan address
          ''iifname "olympus" ip daddr ${self.lan} ip saddr != ${base4}.0.0/24 counter drop''
        }
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
  # refuse its own LAN whatever network it is on. `--print` emits the `add
  # element` lines instead of loading them (for vpn-exit-load).
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
      print=0
      if [ "''${1:-}" = --print ]; then print=1; fi
      fill() {
        local set=$1 elems
        elems=$(sort -u | paste -sd, -)
        if [ "$print" = 0 ]; then echo "flush set inet vpn-exit $set"; fi
        if [ -n "$elems" ]; then echo "add element inet vpn-exit $set { $elems }"; fi
      }
      routes='.[] | select(.dst != "default" and .dev != null and (.dev | test("^(lo|olympus|vpn-.*)$") | not))'
      {
        ip -j route show table main | jq -r "$routes | .dst" | fill lan4
        ip -j -6 route show table main \
          | jq -r "$routes | select(.dst | test(\"^(fe[89ab][0-9a-f]:|ff)\"; \"i\") | not) | .dst" \
          | python3 ${widen6} | fill lan6
      } | if [ "$print" = 1 ]; then cat; else nft -f -; fi
    '';
  };

  # Loads the exit gate with the current lan4/lan6 elements in the same nft
  # transaction, so the sets are never empty, not even during a reload.
  exitLoad = pkgs.writeShellApplication {
    name = "vpn-exit-load";
    runtimeInputs = [
      pkgs.nftables
      pkgs.coreutils
      languard
    ];
    text = ''
      elems=$(vpn-languard --print)
      { cat ${exitRuleset}; printf '%s\n' "$elems"; } | nft -f -
    '';
  };

  # Keeps the sets current: joining another network must not leave its lan open
  # to relayed traffic. The monitor starts before the first refill, so a change
  # in between is not missed; a burst of events is coalesced and followed by
  # one more refill.
  languardWatch = pkgs.writeShellApplication {
    name = "vpn-languard-watch";
    runtimeInputs = [
      pkgs.iproute2
      pkgs.coreutils
      languard
    ];
    text = ''
      ip -o monitor route address | {
        sleep 1 # the monitor has subscribed by now
        vpn-languard || true
        while read -r _; do
          vpn-languard || true
          if read -r -t 1 _; then
            while read -r -t 1 _; do :; done
            vpn-languard || true
          fi
        done
      }
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
      pkgs.conntrack-tools
      pkgs.python3
    ];
    text = ''
      db=${cfg.phones.db}
      state=${phoneStateDir}/state.json
      subnet4=${cfg.phones.subnet}
      subnet6=${cfg.phones.subnet6}
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

      # The db is written by wg-easy admins, so every field is validated before
      # it reaches ip or nft; malformed rows are skipped with a warning.
      us=$'\x1f'
      ip4int() {
        local IFS=. a b c d
        read -r a b c d <<< "$1"
        echo $(( (a << 24) | (b << 16) | (c << 8) | d ))
      }
      valid4() { # <addr> within ${cfg.phones.subnet}
        local o oct net=''${subnet4%/*} len=''${subnet4#*/} mask
        [[ $1 =~ ^(0|[1-9][0-9]{0,2})(\.(0|[1-9][0-9]{0,2})){3}$ ]] || return 1
        IFS=. read -ra oct <<< "$1"
        for o in "''${oct[@]}"; do [ "$o" -le 255 ] || return 1; done
        mask=$(( (0xFFFFFFFF << (32 - len)) & 0xFFFFFFFF ))
        [ $(( $(ip4int "$1") & mask )) -eq $(( $(ip4int "$net") & mask )) ]
      }
      groups6() { # <addr>: eight decimal 16-bit groups, or fail
        local a=$1 h=() t=() g=() n i
        [[ $a =~ ^[0-9a-fA-F:]+$ && $a != *:::* ]] || return 1
        if [[ $a == *::* ]]; then
          [[ ''${a#*::} != *::* ]] || return 1
          IFS=: read -ra h <<< "''${a%%::*}"
          IFS=: read -ra t <<< "''${a#*::}"
          n=$(( 8 - ''${#h[@]} - ''${#t[@]} ))
          [ "$n" -ge 1 ] || return 1
          g=("''${h[@]}")
          for ((i = 0; i < n; i++)); do g+=(0); done
          g+=("''${t[@]}")
        else
          IFS=: read -ra g <<< "$a"
        fi
        [ "''${#g[@]}" -eq 8 ] || return 1
        for i in "''${g[@]}"; do
          [[ $i =~ ^[0-9a-fA-F]{1,4}$ ]] || return 1
          printf '%d ' "$((16#$i))"
        done
      }
      valid6() { # <addr> within ${cfg.phones.subnet6}
        local net=''${subnet6%/*} len=''${subnet6#*/} a n i bits mask
        a=$(groups6 "$1") || return 1
        n=$(groups6 "$net") || return 1
        read -ra a <<< "$a"
        read -ra n <<< "$n"
        for i in 0 1 2 3 4 5 6 7; do
          bits=$(( len - 16 * i ))
          if [ "$bits" -gt 16 ]; then bits=16; elif [ "$bits" -lt 0 ]; then bits=0; fi
          mask=$(( (0xFFFF << (16 - bits)) & 0xFFFF ))
          [ $(( a[i] & mask )) -eq $(( n[i] & mask )) ] || return 1
        done
      }

      # The kernel and nft print addresses compressed and lowercase, so every
      # address is canonicalised before it is compared, stored or handed to them.
      canon6() { python3 -c 'import ipaddress, sys; print(ipaddress.IPv6Address(sys.argv[1]))' "$1"; }

      # public_key, v4, v6, name, enabled (US separated; empty fields stay
      # empty); nothing while wg-easy has no db yet. Rows sharing an address
      # are all skipped: which phone owns it is not decidable.
      clients() {
        local json pk a4 a6 name enabled rows
        [ -e "$db" ] || return 0
        json=$(sqlite3 -readonly -json -cmd '.timeout 5000' "$db" \
          "SELECT public_key, ipv4_address, ipv6_address, name, enabled FROM clients_table WHERE interface_id = '${cfg.phones.interface}';")
        [ -n "$json" ] || return 0
        rows=$(jq -r '.[] | (map_values(if . == null then "" else tostring | gsub("[[:cntrl:]]"; "?") end)
            | [.public_key, .ipv4_address, .ipv6_address, .name]) + [if .enabled == 1 then "1" else "0" end]
            | join("\u001f")' <<< "$json" \
          | while IFS=$us read -r pk a4 a6 name enabled; do
              if [[ $pk =~ ^[A-Za-z0-9+/]{43}=$ ]] && { [ -n "$a4" ] || [ -n "$a6" ]; } \
                && { [ -z "$a4" ] || valid4 "$a4"; } && { [ -z "$a6" ] || valid6 "$a6"; }; then
                [ -z "$a6" ] || a6=$(canon6 "$a6")
                printf '%s\n' "$pk$us$a4$us$a6$us$name$us$enabled"
              else
                echo "vpn-phone: skipping malformed client row '$name'" >&2
              fi
            done)
        [ -n "$rows" ] || return 0
        awk -F "$us" '
          NR == FNR { if ($2 != "") n[$2]++; if ($3 != "") n[$3]++; next }
          ($2 != "" && n[$2] > 1) || ($3 != "" && n[$3] > 1) {
            print "vpn-phone: skipping client row \x27" $4 "\x27: its address is used by another row" > "/dev/stderr"
            next
          }
          { print }' <(printf '%s\n' "$rows") <(printf '%s\n' "$rows")
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

      cut_flows() { # <addresses, one per line>
        local a fam
        for a in $(printf '%s\n' "$1" | sort -u); do
          fam=ipv4
          if [[ $a == *:* ]]; then fam=ipv6; fi
          conntrack -f "$fam" -D -s "$a" > /dev/null 2>&1 || true
          conntrack -f "$fam" -D -d "$a" > /dev/null 2>&1 || true
        done
      }

      # Order matters. First the nft sets and the conntrack entries of what a
      # phone lost: they neither wait on nor fail with the rule changes. Then
      # the rules, diffed rather than reset (adds precede deletes, so a phone
      # never has a moment without its rule, which would leak it to olympus)
      # and idempotent. Last the conntrack entries of phones whose rules
      # changed: a flow outlives the rule that admitted it (established flows
      # are accepted, NAT keeps its mapping), and cut earlier it would be
      # re-created on the old path.
      apply() {
        local rows sets="" want have spec newel changed revoked rc=0
        rows=$(clients)
        want=$(mktemp)
        have=$(mktemp)
        newel=$(mktemp)
        changed=$(mktemp)
        while IFS=$us read -r pk a4 a6 name enabled; do
          [ "$enabled" = 1 ] || continue
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
            [ -z "$a4" ] || { sets+="add element inet vpn-hub phone_hosts { $a4 }"$'\n'; echo "phone_hosts $a4" >> "$newel"; }
            [ -z "$a6" ] || { sets+="add element inet vpn-hub phone_hosts6 { $a6 }"$'\n'; echo "phone_hosts6 $a6" >> "$newel"; }
          fi
          if [ "$(get "$pk" home false)" = true ] && [ -n "$a4" ]; then
            sets+="add element inet vpn-hub phone_home { $a4 }"$'\n'
            echo "phone_home $a4" >> "$newel"
          fi
        done <<< "$rows"
        for f in 4 6; do
          ip -j -"$f" rule show pref 3500 \
            | jq -r --arg f "$f" '.[] | "\($f) \(.src)/\(.srclen // (if $f == "4" then 32 else 128 end)) \(.table // .action)"' >> "$have"
        done
        sort -o "$want" "$want"
        sort -o "$have" "$have"

        revoked=$(for a in phone_hosts phone_hosts6 phone_home; do
          nft -j list set inet vpn-hub "$a" \
            | jq -r --arg s "$a" '.nftables[] | select(.set) | .set.elem // [] | .[] | "\($s) \(.)"'
        done | { grep -vxFf "$newel" || true; } | cut -d' ' -f2) || revoked=""
        nft -f - <<NFT || { echo "vpn-phone: updating the nft sets failed" >&2; rc=1; }
      flush set inet vpn-hub phone_hosts
      flush set inet vpn-hub phone_hosts6
      flush set inet vpn-hub phone_home
      $sets
      NFT
        cut_flows "$revoked"

        rule() { # <add|del> <family> <src> <target>; adding what exists or deleting what is gone is fine
          local out
          if [[ $4 =~ ^[0-9]+$ ]]; then spec=(lookup "$4"); else spec=("$4"); fi
          out=$(ip -"$2" rule "$1" from "$3" "''${spec[@]}" pref 3500 2>&1) && return 0
          case $out in
            *"File exists"* | *"No such file"*) return 0 ;;
          esac
          echo "vpn-phone: ip rule $1 from $3 $4 failed: $out" >&2
          return 1
        }
        { comm -13 "$have" "$want"; comm -23 "$have" "$want"; } | awk '{ sub("/.*", "", $2); print $2 }' > "$changed"
        while read -r f src target; do rule add "$f" "$src" "$target" || rc=1; done < <(comm -13 "$have" "$want")
        while read -r f src target; do rule del "$f" "$src" "$target" || rc=1; done < <(comm -23 "$have" "$want")
        cut_flows "$(cat "$changed")"
        rm -f "$want" "$have" "$newel" "$changed"
        return "$rc"
      }

      # resolve <phone> to a public key
      resolve() {
        local hits
        hits=$(clients | awk -F "$us" -v p="$1" '$4 == p || $2 == p { print $1 }')
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
            printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' NAME IPV4 IPV6 ENABLED EGRESS HOSTS HOME
            clients | while IFS=$us read -r pk a4 a6 name enabled; do
              printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$name" "''${a4:--}" "''${a6:--}" "$enabled" \
                "$(get "$pk" egress olympus)" "$(get "$pk" hosts false)" "$(get "$pk" home false)"
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
      pkgs.sqlite
      pkgs.systemd
      phoneCli
    ];
    text = ''
      db=${cfg.phones.db}
      # Interface hooks run as root on the hub (wg-easy: host netns, NET_ADMIN),
      # so none may persist: clear them and restart wg-easy so no bring-up
      # outlives a hook an admin set.
      check_hooks() {
        local n
        [ -e "$db" ] || return 0
        n=$(sqlite3 -readonly -cmd '.timeout 5000' "$db" "SELECT count(*) FROM hooks_table WHERE coalesce(pre_up, ''') || coalesce(post_up, ''') || coalesce(pre_down, ''') || coalesce(post_down, ''') <> ''';") || return 0
        [ "$n" != 0 ] || return 0
        echo "<3>wg-easy interface hooks are set (root code on olympus), clearing them"
        sqlite3 -cmd '.timeout 5000' "$db" "${cfg.phones.clearHooksSql}"
        if systemctl cat podman-wg-easy.service > /dev/null 2>&1; then
          systemctl restart podman-wg-easy.service
        else
          echo "<4>podman-wg-easy.service does not exist, not restarting"
        fi
      }

      # Watch first, then apply: a write in between would go unseen until the
      # next one. Events queue in the pipe while apply runs.
      exec 3< <(inotifywait -m -e modify -e moved_to --exclude '-shm$' --format x ${dirOf cfg.phones.db} 2>&1)
      line=
      while read -r -u 3 line; do
        [ "$line" != "Watches established." ] || break
      done
      [ "$line" = "Watches established." ] || { echo "<3>inotifywait failed to start" >&2; exit 1; }

      check_hooks
      vpn-phone apply || echo "<3>vpn-phone apply failed"
      while read -r -u 3 line; do
        [ "$line" = x ] || continue
        # let a burst of writes settle
        while read -r -t 1 -u 3 _; do :; done
        echo "wg-easy db changed, applying"
        check_hooks
        vpn-phone apply || echo "<3>vpn-phone apply failed"
      done
      exit 1
    '';
  };

  owner = "/run/vpn-egress";
  systemctl = "${config.systemd.package}/bin/systemctl";

  # Table 2150 (rule 5200): what stays direct in a full tunnel — the prefixes
  # attached to the local links (from their addresses, at least /16 resp. /48) and
  # every route over the mesh (mesh, home). Routes in main are *not* copied: a
  # rogue DHCP server could push `198.51.100.0/24 dev eth1` (option 121) or
  # `0.0.0.0/1 via <it>` and pull traffic around the tunnel (TunnelVision).
  onlinkPy = pkgs.writeText "vpn-onlink.py" ''
    import ipaddress
    import json
    import re
    import subprocess
    import sys

    fam = sys.argv[1]
    minlen = 16 if fam == "-4" else 48
    vpn = re.compile(r"^(lo|olympus|tukl|vpn-.*)$")


    def ip(*args):
        out = subprocess.run(["ip", "-j", fam, *args], capture_output=True, text=True).stdout
        return json.loads(out) if out.strip() else []


    for link in ip("addr", "show"):
        if vpn.match(link["ifname"]):
            continue
        for a in link.get("addr_info", []):
            if a.get("scope") != "global":
                continue
            net = ipaddress.ip_interface(f"{a['local']}/{a['prefixlen']}").network
            if net.prefixlen >= minlen:
                print(f"{net} dev {link['ifname']} metric {0 if fam == '-4' else 1024}")

    for r in ip("route", "show", "dev", "olympus"):
        if r["dst"] == "default" or r["dst"].startswith("fe80:") or r.get("type", "unicast") != "unicast":
            continue
        src = f" src {r['prefsrc']}" if r.get("prefsrc") else ""
        print(f"{r['dst']} dev olympus{src} metric {r.get('metric', 0)}")
  '';
  onlink = pkgs.writeShellApplication {
    name = "vpn-onlink";
    runtimeInputs = [
      pkgs.iproute2
      pkgs.jq
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.gnused
      pkgs.gawk
      pkgs.python3
      config.systemd.package
    ];
    text = ''
      # replace first, delete stale after, so a refill never opens a gap
      fill() { # <-4|-6>
        local want have
        want=$(mktemp)
        have=$(mktemp)
        python3 ${onlinkPy} "$1" | sort -u > "$want"
        sed 's/^/route replace /; s/$/ table 2150/' "$want" | ip -force "$1" -batch - || true
        awk '{ print $1, $NF }' "$want" | sort -u > "$want.k"
        { ip -j "$1" route show table 2150 2>/dev/null || true; } | jq -r '.[]? | "\(.dst) \(.metric // 0)"' | sort -u > "$have"
        comm -13 "$want.k" "$have" | while read -r dst metric; do
          ip "$1" route del "$dst" metric "$metric" table 2150 || true
        done
        rm -f "$want" "$want.k" "$have"
      }
      fill_all() {
        fill -4
        fill -6
      }

      case $1 in
        clear)
          ip -4 route flush table 2150 2>/dev/null || true
          ip -6 route flush table 2150 2>/dev/null || true
          ;;
        watch)
          # The follower is subscribed before the first fill, so a change in between
          # is not lost; the unit is ready (Type=notify) once table 2150 is filled.
          # Events of other tables (incl. our own 2150 writes) print " table ".
          exec 8< <(ip -o monitor route address | grep --line-buffered -v ' table ')
          sleep 0.3
          fill_all
          systemd-notify --ready
          while read -r _ <&8; do
            while read -r -t 1 _ <&8; do :; done
            fill_all
          done
          ;;
      esac
    '';
  };

  # Egress table 2100 is consulted by rules 5200/5300 while the slot is taken. The
  # slot (rules, blackhole default at the worst metric, `prohibit` for every home
  # lan so a full tunnel never carries it unless vpn-home's rule 5100 picks it
  # first) is installed by a unit's start and outlives it: a unit's stop removes
  # only its own default routes, its extra addresses and the owner marker, so a
  # plain stop, restart, crash or shutdown fails closed (`vpn status`: blocked).
  # Only `vpn-egress-reset` (`vpn egress direct`, `vpn mesh off`) removes the slot.
  # A switch is the same thing: the old unit's stop leaves the blackhole, the new
  # start replaces it, with no direct window. The owner marker names the unit
  # holding the routes, so a late ExecStop of the old unit cannot strip the new one.
  # `extra` are addresses added to `olympus` for the unit's lifetime.
  egressScripts =
    {
      name,
      dev,
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
      srcOpt = a: lib.optionalString (a != null) " src ${a}";
    in
    rec {
      # (Re)creates what lives and dies with the tunnel link: source addresses and
      # the real default routes. Also run by the mesh's postSetup after a restart.
      attach = pkgs.writeShellScript "vpn-egress-attach" ''
        set -euo pipefail
        ${lib.concatMapStringsSep "\n" (
          a: "${ip} ${addrFlags a}addr replace ${a} dev olympus${nodad a}"
        ) extra}
        ${ip} -4 route replace default dev ${dev}${srcOpt src4} metric 100 table 2100
        ${ip} -6 route replace default dev ${dev}${srcOpt src6} metric 100 table 2100
      '';
      start = pkgs.writeShellScript "vpn-egress-start" ''
        set -euo pipefail
        ${systemctl} start vpn-onlink.service
        echo ${name} > ${owner}
        # fail closed first: whatever goes wrong below, nothing leaks
        ${each (f: "${ip} ${f} route replace blackhole default metric 4294967295 table 2100")}
        ${lib.concatMapStringsSep "\n" (n: "${ip} -4 route replace prohibit ${n.lan} table 2100") lanNodes}
        # rules already in place (switch, or left by a stop) are not touched: no gap
        ${each (f: ''
          ${ip} ${f} rule show pref 5200 | ${grep} -qw 'lookup 2150' || ${ip} ${f} rule add pref 5200 lookup 2150
          ${ip} ${f} rule show pref 5300 | ${grep} -qw 'lookup 2100' || ${ip} ${f} rule add pref 5300 lookup 2100
        '')}
        ${attach}
      '';
      # The slot (rules, blackhole, prohibits, onlink) stays; see above.
      stop = pkgs.writeShellScript "vpn-egress-stop" ''
        set -uo pipefail
        if [ "$(cat ${owner} 2>/dev/null || true)" = ${name} ]; then
          ${each (f: "${ip} ${f} route del default dev ${dev} metric 100 table 2100 || true")}
          rm -f ${owner}
        fi
        ${lib.concatMapStringsSep "\n" (a: "${ip} ${addrFlags a}addr del ${a} dev olympus || true") extra}
      '';
    };

  # The whole slot, whoever holds it.
  teardown = ''
    ${lib.concatMapStringsSep "\n" (f: ''
      ${ip} ${f} rule del pref 5200 || true
      ${ip} ${f} rule del pref 5300 || true
      ${ip} ${f} route flush table 2100 || true
    '') [ "-4" "-6" ]}
    rm -f ${owner}
    ${systemctl} stop --no-block vpn-onlink.service || true
  '';
  grep = "${pkgs.gnugrep}/bin/grep";

  # One definition per slot holder; units, the mesh re-attach and tukl share them.
  egressDefs = {
    vpn-egress-olympus = {
      dev = "olympus";
      src4 = self.ip;
      src6 = self.ip6;
    };
  }
  // lib.listToAttrs (
    map (x: {
      name = "vpn-egress-${x.name}";
      value = {
        dev = "olympus";
        src4 = src4 x self;
        src6 = src6 x self;
        extra = [
          "${src4 x self}/32"
          "${src6 x self}/128"
        ];
      };
    }) otherExits
  )
  // lib.optionalAttrs (self.tukl != null) {
    wg-quick-tukl =
      let
        addr =
          v6:
          let
            l = lib.filter (a: lib.hasInfix ":" a == v6) self.tukl.address;
          in
          if l == [ ] then null else lib.head (lib.splitString "/" (lib.head l));
      in
      {
        dev = "tukl";
        src4 = addr false;
        src6 = addr true;
      };
  };
  egressScriptsOf = lib.mapAttrs (name: args: egressScripts (args // { inherit name; })) egressDefs;

  # `systemctl start vpn-egress-reset` removes the slot (`vpn egress direct`).
  resetScript = pkgs.writeShellScript "vpn-egress-reset" ''
    set -euo pipefail
    ${teardown}
  '';

  # Bypass guards: tukl and an egress unit must never be up together, whatever
  # brought one of them up. (A slot left by a stopped unit is fine: it only blocks.)
  egressGuard = pkgs.writeShellScript "vpn-egress-guard" ''
    if ${ip} link show dev tukl >/dev/null 2>&1 \
      && ! ${systemctl} is-active --quiet wg-quick-tukl.service; then
      echo "a tukl link exists outside wg-quick-tukl.service; run 'wg-quick down tukl' first" >&2
      exit 1
    fi
  '';
  tuklGuard = pkgs.writeShellScript "wg-quick-tukl-guard" ''
    own=$(cat ${owner} 2>/dev/null || true)
    case $own in
      vpn-egress-*)
        if ${systemctl} is-active --quiet "$own.service"; then
          echo "$own is active; use 'vpn egress tukl' or stop it first" >&2
          exit 1
        fi
        ;;
    esac
  '';

  # wants+after the mesh, not bound to it: a mesh restart (deploy, `wg` hiccup)
  # leaves the selection in place, the blackhole drops meanwhile, and the mesh's
  # postSetup re-attaches the routes.
  egressUnit = name: {
    # Conflicts= alone does not order the stop before the start; any ordering edge
    # does, so the egress units and tukl form a one-directional chain in list order.
    wants = [
      "wireguard-olympus.service"
      "vpn-egress-watch@${name}.service"
    ];
    after = [
      "wireguard-olympus.service"
    ]
    ++ map (n: "${n}.service") (lib.take (lib.lists.findFirstIndex (n: n == name) null egressUnits) egressUnits);
    conflicts =
      map (n: "${n}.service") (lib.filter (n: n != name) egressUnits)
      ++ lib.optional (self.tukl != null) "wg-quick-tukl.service";
    # a deploy must not bounce the selected exit
    restartIfChanged = false;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStartPre = egressGuard;
      ExecStart = egressScriptsOf.${name}.start;
      ExecStop = egressScriptsOf.${name}.stop;
    };
  };

  # Pings through the egress table (the unit's rules are active) and shouts when
  # the exit stops forwarding; the tunnel then drops traffic instead of leaking it.
  egressWatch = pkgs.writeShellApplication {
    name = "vpn-egress-watch";
    runtimeInputs = [
      pkgs.iputils
      pkgs.iproute2
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
      # a marker left by a killed predecessor must not outlive its watcher
      rm -f "$marker"
      trap 'rm -f "$marker"' EXIT
      trap 'exit 0' TERM INT

      notify() {
        bus="/run/user/$(id -u dk)/bus"
        if [ -S "$bus" ]; then
          runuser -u dk -- env "DBUS_SESSION_BUS_ADDRESS=unix:path=$bus" \
            ${pkgs.libnotify}/bin/notify-send -u "$1" -a vpn "$2" "$3" || true
        fi
      }

      # the probe must still be routed into the tunnel, not around it
      reason=""
      healthy() {
        local got
        got=$(ip route get ${cfg.probe} 2>&1 || true)
        case $got in
          *" dev olympus "* | *" dev tukl "*) ;;
          *)
            reason="path left the tunnel (route to the probe: $(echo "$got" | head -n1))"
            return 1
            ;;
        esac
        if ! ping -c1 -W5 -n ${cfg.probe} >/dev/null 2>&1; then
          reason="no internet through the exit — traffic is dropped"
          return 1
        fi
      }

      while true; do
        if healthy; then
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
            echo "$unit: $reason"
            notify critical "VPN exit down" "$unit: $reason — 'vpn egress direct' goes direct"
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
    phones.clearHooksSql = lib.mkOption {
      internal = true;
      readOnly = true;
      type = lib.types.str;
      default = "UPDATE hooks_table SET pre_up='', post_up='', pre_down='', post_down='' WHERE id='${cfg.phones.interface}';";
      description = "SQL that empties wg-easy's interface hooks; shared by the watcher and the wg-easy module.";
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
            dynamicEndpointRefreshSeconds = 300;
            # wg retries only temporary DNS errors; a hard one (no resolver yet at
            # boot or mid-switch) exits the unit, which the ExecStartPre below covers
            dynamicEndpointRefreshRestartSeconds = 10;
          }
        ];
        # rules are deleted first so a re-run after a crashed stop stays idempotent
        postSetup = ''
          ${meshRoutes}
          ${lib.optionalString self.exit exitSetup}
          # a selected egress survives a mesh restart: put its routes back (until then the
          # blackhole drops), but only for a unit that is still running
          case "$(cat ${owner} 2>/dev/null || true)" in
          ${lib.concatMapStrings (n: ''
            ${n}) if ${systemctl} is-active --quiet ${n}.service; then ${egressScriptsOf.${n}.attach} || true; fi ;;
          '') egressUnits}
          esac
          ${pkgs.coreutils}/bin/install -m 0600 -o ${sshUser.name} -g ${sshUser.group} ${sshTunnelConfig} ${sshLocalConfig}
        '';
        postShutdown = ''
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
      ++ [ "vpn-egress-reset.service" ]
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
          # Hold the peer unit until the endpoint resolves, so neither an offline
          # boot nor the moment a switch replaces the network setup leaves the
          # mesh without its peer (and `switch-to-configuration` without a failure).
          wireguard-olympus-peer-olympus-refresh.serviceConfig = {
            ExecStartPre = pkgs.writeShellScript "vpn-wait-endpoint" ''
              until ${pkgs.glibc.getent}/bin/getent ahosts ${lib.head (lib.splitString ":" cfg.endpoint)} >/dev/null; do
                sleep 2
              done
            '';
            TimeoutStartSec = "infinity";
          };
          # follows the local links while the slot is taken (started by its scripts, stopped by reset)
          vpn-onlink.serviceConfig = {
            Type = "notify";
            NotifyAccess = "all";
            ExecStart = "${onlink}/bin/vpn-onlink watch";
            ExecStopPost = "${onlink}/bin/vpn-onlink clear";
            Restart = "always";
            RestartSec = 1;
          };
          # always on, before the network: the mesh socket stays out of any tunnel
          # (rule 5000) and the mesh prefixes have their blackholes (rule 4960)
          vpn-underlay = {
            wantedBy = [ "multi-user.target" ];
            wants = [ "network-pre.target" ];
            before = [ "network-pre.target" ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              ExecStart = underlay;
            };
          };
          wireguard-olympus = {
            wants = [ "vpn-underlay.service" ];
            after = [ "vpn-underlay.service" ];
          };
          vpn-egress-reset.serviceConfig = {
            Type = "oneshot";
            ExecStart = resetScript;
          };
          "vpn-egress-watch@" = {
            bindsTo = [ "%i.service" ];
            after = [ "%i.service" ];
            serviceConfig = {
              Type = "simple";
              ExecStart = "${egressWatch}/bin/vpn-egress-watch %i";
              Restart = "on-failure";
              RestartSec = 2;
            };
          };
          wg-quick-tukl = lib.mkIf (self.tukl != null) {
            # a deploy must not bounce the selected exit
            restartIfChanged = false;
            wants = [ "vpn-egress-watch@wg-quick-tukl.service" ];
            after = map (n: "${n}.service") egressUnits;
          };
        }
        // lib.genAttrs egressUnits egressUnit
      ))
      (lib.mkIf isServer {
        # a reload empties local_home: restart vpn-home (partOf) to refill it
        vpn-hub-nft = lib.recursiveUpdate (nftUnit "${nft} -f ${hubRuleset}" [
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
            RestartSec = 5;
          };
          startLimitIntervalSec = 0;
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
        vpn-exit-nft = nftUnit "${exitLoad}/bin/vpn-exit-load" [ ];
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
    systemd.tmpfiles.rules =
      if isServer then
        [ "d ${phoneStateDir} 0700 root root -" ]
      else
        # the `vpn` CLI serialises its calls on a lock here
        [ "f /run/lock/vpn.lock 0644 root root -" ];
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
      # tukl shares the egress slot (table 2100, rules 5200/5300) instead of wg-quick's
      # own policy routing; fwMark + rule 5000 keep its socket out of the tunnel.
      table = "off";
      extraOptions.FwMark = mark;
      preUp = "${tuklGuard}";
      postUp = "${egressScriptsOf.wg-quick-tukl.start}";
      preDown = "${egressScriptsOf.wg-quick-tukl.stop}";
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
