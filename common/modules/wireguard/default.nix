{
  config,
  lib,
  pkgs,
  secretsPath,
  ...
}:

# ---------------------------------------------------------------------------
# WireGuard tunnels — infra hub `olympus` (+ the `tukl` university VPN)
# ---------------------------------------------------------------------------
# Hub-and-spoke: olympus (the VPS) is the server; hermes and hestia keep an
# always-on split tunnel to it on the `olympus` interface — only the mesh
# supernet goes through it, everything else stays direct. Full-tunnel egress
# is a separate, opt-in layer (the `vpn-egress-*` units). The desktops also carry
# a second, independent on-demand tunnel `tukl` (the TU Kaiserslautern VPN; see
# bottom of file).
#
# DNS records to add (registrar / DNS provider for dklaassen.de):
#   vpn.dklaassen.de.  A     <olympus public IPv4>
#   vpn.dklaassen.de.  AAAA  <olympus public IPv6>   # only if dialing over IPv6
# One record serves both planes: olympus endpoint :51820 (this module) and the
# wg-easy phone plane :51821 (see ../wg-easy). WireGuard only needs name->IP
# resolution; there is no TLS/HTTP on these ports.
#
# Key material:
#   - private keys live in agenix (secrets/wg-<host>.age), one per host, each
#     decryptable by every host via the shared id_priv recipient.
#   - public keys are NOT secret and live in the `vpn.nodes` registry below. After
#     generating the keypairs (see the plan / `wg genkey | wg pubkey`), paste
#     each host's public key in place of the REPLACE_ME_* placeholders.

let
  subnet = "10.100.0";
  # ULA (RFC 4193, randomly generated). The tunnel is dual-stack so a client with
  # native IPv6 does not silently blackhole AAAA traffic into a v4-only tunnel.
  # Egress caveat on networking.nat below.
  subnet6 = "fdaa:e184:83f::";
  port = 51820;
  cfg = config.vpn;

  # Registry entries plus the addresses derived from `octet`.
  nodes = lib.mapAttrs (
    _: node:
    node
    // {
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

  # Egress units on this host; each conflicts with all the others and with tukl.
  egressUnits = [ "vpn-egress-olympus" ];

  # Egress table 2100 is consulted by rules 5200/5300 while the unit is active.
  # `extra` are addresses added to `olympus` for the unit's lifetime.
  egressScripts =
    {
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
      stop = pkgs.writeShellScript "vpn-egress-stop" ''
        ${each (f: ''
          ${ip} ${f} rule del pref 5200 || true
          ${ip} ${f} rule del pref 5300 || true
          ${ip} ${f} route flush table 2100 || true
        '')}
        ${lib.concatMapStringsSep "\n" (a: "${ip} ${addrFlags a}addr del ${a} dev olympus || true") extra}
      '';
    };

  egressUnit =
    name: args:
    let
      scripts = egressScripts args;
    in
    {
      bindsTo = [ "wireguard-olympus.service" ];
      after = [ "wireguard-olympus.service" ];
      partOf = [ "wireguard-olympus.service" ];
      conflicts =
        map (n: "${n}.service") (lib.filter (n: n != name) egressUnits)
        ++ lib.optional (self.tukl != null) "wg-quick-tukl.service";
      wants = [ "vpn-egress-watch@${name}.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
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
            echo "$unit: reachable again"
            notify normal "VPN exit back" "$unit: internet reachable again"
          fi
        else
          fails=$((fails + 1))
          if [ "$fails" -ge 2 ] && [ "$down" = 0 ]; then
            down=1
            echo "$unit: no internet through the exit — traffic is dropped"
            notify critical "VPN exit down" "$unit: no internet, traffic is dropped — systemctl stop $unit to go direct"
          fi
        fi
        sleep 15
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
          # Today's single RPTU config, dialled from both desktops until each
          # gets its own `wg-tukl-<host>` — never up on both at once.
          sharedTukl = {
            secret = "wg-tukl";
            address = [
              "172.27.221.17/32"
              "2001:638:208:fd49:1:aff:fea0:40da/128"
            ];
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
            tukl = sharedTukl;
          };
          hermes = {
            octet = 3;
            publicKey = "bAad0LzXDbsnk4NISns3VOfWiOlmgVMc3dkWd4Z2KTM=";
            exit = true;
            tukl = sharedTukl;
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
    # SERVER (olympus) — plain wireguard interface + NAT for full-tunnel egress
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
          ];
        }) spokes;
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
          ${pkgs.coreutils}/bin/install -m 0600 -o ${sshUser.name} -g ${sshUser.group} ${sshTunnelConfig} ${sshLocalConfig}
        '';
        postShutdown = ''
          ${underlayRules "del"}
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
        "vpn-egress-olympus.service"
      ]
      ++ lib.optional (self.tukl != null) "wg-quick-tukl.service"
    );

    # ---------------------------------------------------------------------------
    # Egress — opt-in full tunnel
    # ---------------------------------------------------------------------------
    # "Direct" means no egress unit is active. Starting one routes everything but
    # the mesh through the exit (rules 5200/5300, table 2100); units conflict with
    # each other and with wg-quick-tukl, so at most one is up. The watcher makes a
    # dead exit loud: traffic is dropped, never silently sent direct.
    #   systemctl start vpn-egress-olympus   (stop to go direct)
    systemd.services = lib.mkIf (!isServer) {
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
      };
    };

    # keep NetworkManager off the mesh and (later) GRE ifaces on the desktops
    networking.networkmanager.unmanaged = lib.mkIf (!isServer) [
      "interface-name:olympus"
      "interface-name:vpn-*"
    ];

    # ---------------------------------------------------------------------------
    # tukl — TU Kaiserslautern university VPN, per-node config from registry
    # ---------------------------------------------------------------------------
    # Modeled declaratively from the upstream wg-quick config. Only the private
    # key is secret: it lives in agenix and is referenced via privateKeyFile so
    # it never lands in the Nix store. On-demand:
    #   systemctl start wg-quick-tukl   (stop to disconnect)
    age.secrets.wg-tukl = lib.mkIf (self.tukl != null) {
      file = "${secretsPath}/${self.tukl.secret}.age";
      mode = "0400";
    };

    networking.wg-quick.interfaces.tukl = lib.mkIf (self.tukl != null) {
      autostart = false;
      privateKeyFile = config.age.secrets.wg-tukl.path;
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
