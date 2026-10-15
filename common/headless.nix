_:

{
  imports = [
    ./common.nix
    # servers terminate TLS + run the SSO gate; importing here makes headless a
    # self-contained nginx consumer (dedup makes any host's repeat import a no-op).
    ./modules/nginx
  ];

  networking.firewall = {
    enable = true;
    checkReversePath = true;
  };

  services.openssh = {
    enable = true;
    ports = [ 22 ];
    settings = {
      UseDns = false;
      PasswordAuthentication = false;
      # NixOS defaults this to true; with UsePAM that re-offers a password
      # prompt over keyboard-interactive despite PasswordAuthentication = false.
      KbdInteractiveAuthentication = false;
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
