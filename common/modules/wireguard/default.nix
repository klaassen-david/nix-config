{
  config,
  lib,
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
  port = 51820;
  endpoint = "vpn.dklaassen.de:${toString port}";

  nodes = {
    olympus = {
      ip = "${subnet}.1";
      publicKey = "8ujDiLPMOK3X0BdAWVTDWPMUOxPSnGNdFKtYD1MgxRk=";
    };
    hestia = {
      ip = "${subnet}.2";
      publicKey = "bAad0LzXDbsnk4NISns3VOfWiOlmgVMc3dkWd4Z2KTM=";
    };
    hermes = {
      ip = "${subnet}.3";
      publicKey = "4YGKRQjZN2l4OmoxOfvL9zAa5hVFBb3IoE6+uUGz4kk=";
    };
  };

  selfName = config.host.hostName;
  self = nodes.${selfName};
  isServer = config.host.role == "vps";
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
      ips = [ "${self.ip}/24" ];
      listenPort = port;
      privateKeyFile = config.age.secrets."wg-${selfName}".path;
      peers = [
        {
          publicKey = nodes.hestia.publicKey;
          allowedIPs = [ "${nodes.hestia.ip}/32" ];
        }
        {
          publicKey = nodes.hermes.publicKey;
          allowedIPs = [ "${nodes.hermes.ip}/32" ];
        }
      ];
    };
  };

  # networking.nat enables ip_forward and installs the masquerade/forward rules
  # so client traffic (0.0.0.0/0) can egress via olympus's WAN interface.
  networking.nat = lib.mkIf isServer {
    enable = true;
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
  #   sudo systemctl start wg-quick-olympus   (stop to return to direct connectivity)
  # Full tunnel means DNS queries also egress via olympus; the clients' existing
  # public resolvers (1.1.1.1/8.8.8.8) keep working, so no `dns` override needed.
  networking.wg-quick.interfaces.olympus = lib.mkIf (!isServer) {
    autostart = false;
    address = [ "${self.ip}/24" ];
    privateKeyFile = config.age.secrets."wg-${selfName}".path;
    peers = [
      {
        publicKey = nodes.olympus.publicKey;
        allowedIPs = [
          "0.0.0.0/0"
          "::/0"
        ];
        endpoint = endpoint;
        persistentKeepalive = 25;
      }
    ];
  };

  # keep NetworkManager off the tunnel iface on the desktop clients
  networking.networkmanager.unmanaged = lib.mkIf (!isServer) [ "interface-name:olympus" ];

  # ---------------------------------------------------------------------------
  # tukl — TU Kaiserslautern university VPN, desktop clients only
  # ---------------------------------------------------------------------------
  # Modeled declaratively from the upstream wg-quick config. Only the private
  # key is secret: it lives in agenix (wg-tukl.age) and is referenced via
  # privateKeyFile so it never lands in the Nix store. Everything else (addresses,
  # DNS, peer/endpoint) is public config inlined below. On-demand, like olympus:
  #   sudo systemctl start wg-quick-tukl   (stop to disconnect)
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
