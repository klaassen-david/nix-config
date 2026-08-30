{
  lib,
  sslVhost,
  nextcloudSSO,
  ...
}:

# ---------------------------------------------------------------------------
# wg-easy — the phone plane
# ---------------------------------------------------------------------------
# Independent of the fleet hub in ../wireguard. That one is a host interface
# literally named `olympus` (10.100.0.0/24, UDP 51820) — the one `ip a` shows
# here. wg-easy instead runs in a podman netns and creates its own `wg0` there
# (10.100.1.0/24, UDP 51821), which never appears on the host. Every `wg0` and
# `eth0` below names a *container* interface.

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
      WG_DEFAULT_ADDRESS = "10.100.1.x";
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
  services.nginx.virtualHosts."vpn.dklaassen.de" =
    lib.recursiveUpdate (sslVhost { } // nextcloudSSO)
      {
        locations."/" = {
          proxyPass = "http://127.0.0.1:51821/";
          proxyWebsockets = true; # wg-easy UI uses websockets
        };
      };

  # Public UDP for the phone tunnel. The web UI is not opened here — it is bound
  # to 127.0.0.1 and reached only via nginx (443, already open in ../nginx).
  networking.firewall.allowedUDPPorts = [ 51821 ];
}
