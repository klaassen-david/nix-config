{
  lib,
  sslVhost,
  nextcloudSSO,
  ...
}:

# ---------------------------------------------------------------------------
# wg-easy — ad-hoc phone/guest WireGuard plane (olympus only)
# ---------------------------------------------------------------------------
# A web UI for enrolling phones/guests on the fly: it generates a keypair,
# adds the peer, and renders a QR you scan with the WireGuard mobile app — no
# rebuild per device. Runs on its OWN WireGuard interface, subnet and UDP port
# so the declarative wg0 hub (../wireguard) stays untouched and managed-host
# config never depends on wg-easy's runtime-generated server key.
#
# Two surfaces:
#   - WireGuard UDP 51821  -> published publicly (phones dial in from anywhere).
#   - Web admin UI         -> https://vpn.dklaassen.de, published publicly but
#     gated by Nextcloud SSO (../nginx). wg-easy's own login is DISABLED; SSO is
#     the real auth.
#
# Endpoint: vpn.dklaassen.de:51821 (UDP tunnel). The same name serves the UI on
# 443. Phones are full tunnel (wg-easy's default WG_ALLOWED_IPS = 0.0.0.0/0,
# ::/0); wg-easy NATs its own clients, so no extra host NAT entries are needed
# beyond what wg0 already set up.
#
# Enrolling a phone (no rebuild — all done in the web UI):
#   1. Browse to https://vpn.dklaassen.de and log in with your Nextcloud account
#      (SSO; no separate wg-easy password).
#   2. "+ New Client" -> name it. wg-easy generates the keypair, assigns the
#      next 10.100.1.0/24 IP, and renders a QR inline.
#   3. On the phone: WireGuard app -> + -> "Scan from QR code". The tunnel
#      imports full-tunnel (all traffic egresses via olympus). The client row
#      also has a .conf download button if you'd rather send the file.
#   4. Revoke any time by deleting that client row — keys are per-client.

let
  image = "ghcr.io/wg-easy/wg-easy:14"; # pinned; do not use :latest
in
{
  imports = [ ../nginx ];

  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
  };
  virtualisation.oci-containers.backend = "podman";

  virtualisation.oci-containers.containers.wg-easy = {
    inherit image;
    autoStart = true;

    environment = {
      WG_HOST = "vpn.dklaassen.de";
      WG_PORT = "51821"; # UDP port advertised in generated client configs
      WG_DEFAULT_ADDRESS = "10.100.1.x"; # own client subnet, separate from wg0
      # No PASSWORD / PASSWORD_HASH: this v14 image hard-errors on PASSWORD, and with
      # neither set its own login is disabled — exactly what we want, since the real
      # gate is Nextcloud SSO in front (../nginx) and the UI binds to 127.0.0.1 only.

      # This host's kernel has NO legacy-iptables modules (nftables-only), so
      # wg-easy's default PostUp/PostDown — which shell out to `iptables` (legacy)
      # — die with "nat: Table does not exist". Override them to call the image's
      # `iptables-nft` binary, which binds to the nf_tables backend the host
      # already provides (nf_nat / nft_chain_nat). Rules mirror wg-easy's v14
      # defaults: MASQUERADE the client subnet out eth0, accept the tunnel port,
      # and forward across wg0. Kept single-line (INI PostUp = ... is one line).
      WG_POST_UP = "iptables-nft -t nat -A POSTROUTING -s 10.100.1.0/24 -o eth0 -j MASQUERADE; iptables-nft -A INPUT -p udp -m udp --dport 51821 -j ACCEPT; iptables-nft -A FORWARD -i wg0 -j ACCEPT; iptables-nft -A FORWARD -o wg0 -j ACCEPT;";
      WG_POST_DOWN = "iptables-nft -t nat -D POSTROUTING -s 10.100.1.0/24 -o eth0 -j MASQUERADE; iptables-nft -D INPUT -p udp -m udp --dport 51821 -j ACCEPT; iptables-nft -D FORWARD -i wg0 -j ACCEPT; iptables-nft -D FORWARD -o wg0 -j ACCEPT;";
    };

    ports = [
      "51821:51821/udp" # public WireGuard tunnel
      "127.0.0.1:51821:51821/tcp" # web admin UI, fronted by nginx + SSO
    ];

    volumes = [ "/var/lib/wg-easy:/etc/wireguard" ]; # persistent state/keys

    extraOptions = [
      "--cap-add=NET_ADMIN"
      "--cap-add=SYS_MODULE"
      "--sysctl=net.ipv4.conf.all.src_valid_mark=1"
      "--sysctl=net.ipv4.ip_forward=1"
    ];
  };

  # Podman bind-mounts do NOT create the host source dir; create it ahead of the
  # container so the first start doesn't fail with "statfs ...: no such file".
  systemd.tmpfiles.rules = [ "d /var/lib/wg-easy 0700 root root -" ];

  # Public UI behind Nextcloud SSO. nginx terminates TLS and oauth2-proxy gates
  # access before proxying to the container's localhost-bound UI.
  services.nginx.virtualHosts."vpn.dklaassen.de" = lib.recursiveUpdate (sslVhost { } // nextcloudSSO) {
    locations."/" = {
      proxyPass = "http://127.0.0.1:51821/";
      proxyWebsockets = true; # wg-easy UI uses websockets
    };
  };

  # Public UDP for the phone tunnel. The web UI is not opened here — it is bound
  # to 127.0.0.1 and reached only via nginx (443, already open in ../nginx).
  networking.firewall.allowedUDPPorts = [ 51821 ];
}
