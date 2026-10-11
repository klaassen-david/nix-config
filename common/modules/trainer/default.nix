{
  inputs,
  lib,
  pkgs,
  sslVhost,
  ...
}:

# The music trainer (flake input `trainer`, from olympus:~/code/trainer) at
# trainer.dklaassen.de, VPN only. See decisions/trainer.md.
#
# The node server serves the app and an unauthenticated event log, so nginx
# admits only the mesh supernet (hosts, phones; 10.100.0.0/16) and 403s the
# rest. The name resolves to the hub's mesh address (10.100.0.1): a public A
# record plus a static hosts entry in common.nix, because a router's DNS-rebind
# protection may drop private answers. YouTube refuses embeds on bare-IP origins,
# hence the name.
#
# The log is the learning progress: /var/lib/trainer/log.jsonl. Not backed up.

let
  port = 3030;
  domain = "trainer.dklaassen.de";
  pkg = inputs.trainer.packages.${pkgs.stdenv.hostPlatform.system}.default;
in
{
  imports = [ ../nginx ];

  systemd.services.trainer = {
    description = "Music trainer";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    environment = {
      HOST = "127.0.0.1";
      PORT = toString port;
      LOG_FILE = "/var/lib/trainer/log.jsonl";
    };
    serviceConfig = {
      # the server answers only known Host names (DNS-rebinding guard)
      ExecStart = "${lib.getExe pkg} --allow-host ${domain}";
      DynamicUser = true;
      StateDirectory = "trainer";
      Restart = "on-failure";
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateDevices = true;
      NoNewPrivileges = true;
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
      ];
    };
  };

  services.nginx.virtualHosts.${domain} = sslVhost { } // {
    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString port}";
      extraConfig = ''
        allow 10.100.0.0/16;
        deny all;
      '';
    };
  };
}
