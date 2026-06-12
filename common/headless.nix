{
  lib,
  sslVhost,
  nextcloudSSO,
  ...
}:

{
  imports = [
    ./common.nix
    # servers terminate TLS + run the SSO gate; importing here makes headless a
    # self-contained nginx consumer (dedup makes any host's repeat import a no-op).
    ./modules/nginx
  ];

  # External control panel (bound to :8080 by something off-repo), exposed only
  # behind Nextcloud SSO.
  services.nginx.virtualHosts."control.dklaassen.de" =
    lib.recursiveUpdate (sslVhost { } // nextcloudSSO)
      {
        locations."/" = {
          proxyPass = "http://127.0.0.1:8080/";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header Host              $host;
            proxy_set_header X-Real-IP         $remote_addr;
            proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_read_timeout                 3600s;
            proxy_send_timeout                 3600s;
          '';
        };
      };

  networking = {
    enableIPv6 = true;
    firewall =
      let
        ranges = [ ];
        ports = [ ];
      in
      {
        enable = true;
        checkReversePath = true;
        allowedTCPPorts = lib.mkOrder 1000 ports;
        allowedTCPPortRanges = lib.mkOrder 1000 ranges;
        allowedUDPPorts = lib.mkOrder 1000 ports;
        allowedUDPPortRanges = lib.mkOrder 1000 ranges;
      };
  };

  services.openssh = {
    enable = true;
    ports = [ 22 ];
    settings = {
      UseDns = false;
      PasswordAuthentication = false;
      AllowUsers = [ "dk" ];
      PermitRootLogin = "no";
    };
  };

  services.fail2ban = {
    enable = true;
    jails.sshd = {
      settings = {
        enabled = true;
        filter = "sshd";
        maxretry = 5;
        bantime = "1h";
      };
    };
  };
}
