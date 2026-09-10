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
# Hub-and-spoke: olympus (the VPS) is the server; hermes and hestia dial in
# on-demand on the `olympus` interface and route ALL their traffic (full
# tunnel) out through olympus. The desktops also carry a second, independent
# on-demand tunnel `tukl` (the TU Kaiserslautern VPN; see bottom of file).
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
#   - public keys are NOT secret and live in the `nodes` registry below. After
#     generating the keypairs (see the plan / `wg genkey | wg pubkey`), paste
#     each host's public key in place of the REPLACE_ME_* placeholders.

let
  subnet = "10.100.0";
  # ULA (RFC 4193, randomly generated). The tunnel is dual-stack so a client with
  # native IPv6 does not silently blackhole AAAA traffic into a v4-only tunnel.
  # Egress caveat on networking.nat below.
  subnet6 = "fdaa:e184:83f::";
  port = 51820;
  endpoint = "vpn.dklaassen.de:${toString port}";

  nodes = {
    olympus = {
      ip = "${subnet}.1";
      ip6 = "${subnet6}1";
      publicKey = "8ujDiLPMOK3X0BdAWVTDWPMUOxPSnGNdFKtYD1MgxRk=";
    };
    hestia = {
      ip = "${subnet}.2";
      ip6 = "${subnet6}2";
      publicKey = "4YGKRQjZN2l4OmoxOfvL9zAa5hVFBb3IoE6+uUGz4kk=";
    };
    hermes = {
      ip = "${subnet}.3";
      ip6 = "${subnet6}3";
      publicKey = "bAad0LzXDbsnk4NISns3VOfWiOlmgVMc3dkWd4Z2KTM=";
    };
  };

  selfName = config.host.hostName;
  self = nodes.${selfName};
  isServer = config.host.role == "vps";

  # ssh over the tunnel. While `olympus` is up, `ssh hestia` must resolve to the
  # peer's tunnel address — its LAN name is unreachable from anywhere else, and
  # a full tunnel puts the client "anywhere else" even at home. Every node in the
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
  age.secrets."wg-${selfName}" = {
    file = "${secretsPath}/wg-${selfName}.age";
    mode = "0400";
  };

  # ---------------------------------------------------------------------------
  # SERVER (olympus) — plain wireguard interface + NAT for full-tunnel egress
  # ---------------------------------------------------------------------------
  networking.wireguard.interfaces = lib.mkIf isServer {
    olympus = {
      ips = [
        "${self.ip}/24"
        "${self.ip6}/64"
      ];
      listenPort = port;
      privateKeyFile = config.age.secrets."wg-${selfName}".path;
      peers = [
        {
          publicKey = nodes.hestia.publicKey;
          allowedIPs = [
            "${nodes.hestia.ip}/32"
            "${nodes.hestia.ip6}/128"
          ];
        }
        {
          publicKey = nodes.hermes.publicKey;
          allowedIPs = [
            "${nodes.hermes.ip}/32"
            "${nodes.hermes.ip6}/128"
          ];
        }
      ];
    };
  };

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
    externalInterface = "ens6";
    internalInterfaces = [ "olympus" ];
  };

  networking.firewall.allowedUDPPorts = lib.mkIf isServer [ port ];

  # ---------------------------------------------------------------------------
  # CLIENTS (hermes / hestia) — wg-quick handles full-tunnel policy routing
  # ---------------------------------------------------------------------------
  # wg-quick installs the fwmark + ip rules that keep the handshake to the
  # endpoint reachable while 0.0.0.0/0 becomes the default route. Plain
  # networking.wireguard does NOT do this and would blackhole the handshake.
  #
  # On-demand: autostart = false. Dial in deliberately with
  #   systemctl start wg-quick-olympus   (stop to return to direct connectivity)
  # No sudo needed — the unit is registered in host.userManagedUnits below, which
  # common/modules/polkit-units turns into a polkit exemption for wheel.
  # Full tunnel means DNS queries also egress via olympus; the clients' existing
  # public resolvers (1.1.1.1/8.8.8.8) keep working, so no `dns` override needed.
  networking.wg-quick.interfaces.olympus = lib.mkIf (!isServer) {
    autostart = false;
    address = [
      "${self.ip}/24"
      "${self.ip6}/64"
    ];
    privateKeyFile = config.age.secrets."wg-${selfName}".path;
    peers = [
      {
        publicKey = nodes.olympus.publicKey;
        allowedIPs = [
          "0.0.0.0/0"
          "::/0"
        ];
        inherit endpoint;
        persistentKeepalive = 25;
      }
    ];
    postUp = "${pkgs.coreutils}/bin/install -m 0600 -o ${sshUser.name} -g ${sshUser.group} ${sshTunnelConfig} ${sshLocalConfig}";
    preDown = "${pkgs.coreutils}/bin/rm -f ${sshLocalConfig}";
  };

  # both client tunnels are hand-dialled, so let wheel flip them without sudo
  host.userManagedUnits = lib.optionals (!isServer) [
    "wg-quick-olympus.service"
    "wg-quick-tukl.service"
  ];

  # keep NetworkManager off the tunnel iface on the desktop clients
  networking.networkmanager.unmanaged = lib.mkIf (!isServer) [ "interface-name:olympus" ];

  # ---------------------------------------------------------------------------
  # tukl — TU Kaiserslautern university VPN, desktop clients only
  # ---------------------------------------------------------------------------
  # Modeled declaratively from the upstream wg-quick config. Only the private
  # key is secret: it lives in agenix (wg-tukl.age) and is referenced via
  # privateKeyFile so it never lands in the Nix store. Everything else (addresses,
  # DNS, peer/endpoint) is public config inlined below. On-demand, like olympus:
  #   systemctl start wg-quick-tukl   (stop to disconnect)
  age.secrets.wg-tukl = lib.mkIf (!isServer) {
    file = "${secretsPath}/wg-tukl.age";
    mode = "0400";
  };

  networking.wg-quick.interfaces.tukl = lib.mkIf (!isServer) {
    autostart = false;
    privateKeyFile = config.age.secrets.wg-tukl.path;
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
    peers = [
      {
        publicKey = "j77guFVKQ4sxwJCgqt/vFvHxkvX4Bwqh7B3Za6oOOk4=";
        endpoint = "vpnwg.uni-kl.de:51820";
        allowedIPs = [
          "0.0.0.0/0"
          "::/0"
        ];
        persistentKeepalive = 25;
      }
    ];
  };
}
