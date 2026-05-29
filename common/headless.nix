{ lib, ... }:

{
  imports = [ ./common.nix ];

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
      UseDns = true;
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
