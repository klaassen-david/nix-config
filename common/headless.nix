{ ... }:

{
  imports = [ ./main.nix ];

  networking = {
    enableIPv6 = true;
    firewall =
      let
        ranges = [ ];
        ports = [ ];
      in
      {
        enable = true;
        checkReversePath = false;
        allowedTCPPorts = ports;
        allowedTCPPortRanges = ranges;
        allowedUDPPorts = ports;
        allowedUDPPortRanges = ranges;
      };
  };

  services.openssh = {
    enable = true;
    ports = [ 22 ];
    settings = {
      UseDns = true;
      PasswordAuthentication = true;
      AllowUsers = null;
      PermitRootLogin = "yes";
    };
  };
}
