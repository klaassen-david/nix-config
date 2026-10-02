{
  lib,
  pkgs,
  sslVhost,
  nextcloudSSO,
  ...
}:

# ---------------------------------------------------------------------------
# wg-easy v15 — the phone plane
# ---------------------------------------------------------------------------
# v15 runs in the host network namespace ("routed" mode): wg0 is now a host
# interface (10.100.1.0/24; v6 fdcc:ad94:bacf:61a4::cafe:0/112) that olympus
# sees directly. Phones are routed by the host — forwarding/NAT/filtering are
# the host's job via the wireguard module. v15 config lives in the sqlite db
# `/var/lib/wg-easy/wg-easy.db`. Admin login is its own, behind the SSO gate
# (../nginx). One-time v14→v15 migration: the setup wizard at vpn.dklaassen.de
# → create the admin → "existing configuration" → upload the old wg0.json
# (keys and v4 addresses carry over) → host vpn.dklaassen.de, port 51821; then
# `systemctl restart podman-wg-easy` so the ExecStartPre below applies.

let
  image = "ghcr.io/wg-easy/wg-easy:15"; # pinned; do not use :latest
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
      HOST = "127.0.0.1"; # web UI bind address
      PORT = "51821"; # web UI TCP port (nginx proxies here)
    };

    volumes = [ "/var/lib/wg-easy:/etc/wireguard" ]; # persistent state/keys

    extraOptions = [
      "--network=host"
      "--cap-add=NET_ADMIN"
      "--cap-add=SYS_MODULE"
    ];
  };

  # Podman bind-mounts do NOT create the host source dir; create it ahead of the
  # container so the first start doesn't fail with "statfs ...: no such file".
  systemd.tmpfiles.rules = [ "d /var/lib/wg-easy 0700 root root -" ];

  # v15 runs in the host netns; olympus interface owns UDP 51820. v15's default
  # hooks run iptables-legacy (the image pins it) — olympus kernel has nftables
  # only, so they'd fail. Disable all hooks and enforce port 51821 (not 51820) to
  # avoid collision with the host's mesh interface, since both share the netns now.
  systemd.services.podman-wg-easy.serviceConfig.ExecStartPre =
    let
      migrate-wg-easy-db = pkgs.writeShellScript "migrate-wg-easy-db" ''
        db=/var/lib/wg-easy/wg-easy.db
        if [ -f "$db" ]; then
          ${pkgs.sqlite}/bin/sqlite3 "$db" <<SQL
        UPDATE hooks_table SET pre_up=''', post_up=''', pre_down=''', post_down=''' WHERE id='wg0';
        UPDATE interfaces_table SET port=51821 WHERE name='wg0';
        UPDATE user_configs_table SET port=51821 WHERE id='wg0';
        SQL
        fi
      '';
    in
    [ (toString migrate-wg-easy-db) ];

  # Phones are routed by the host now: wg0 on the host sees each phone's address.
  networking.nat.internalInterfaces = [ "wg0" ];

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
