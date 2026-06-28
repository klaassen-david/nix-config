{
  config,
  lib,
  pkgs,
  secretsPath,
  ...
}:

# LAN SMB file sharing (smbd serves /home/dk/share; wsdd makes us discoverable in the
# Windows "Network" view). dk's SMB password comes from agenix (smb-dk.age).
#
# Use a folder shared from another PC on the network:
#   smbclient -L //<pc-ip> -U <user>                     # list its shares
#   sudo mkdir -p /mnt/win
#   sudo mount -t cifs //<pc-ip>/<share> /mnt/win \
#     -o username=<user>,uid=dk,gid=users                # prompts for the password
# (use the PC's IP, or resolve its NetBIOS name first with `nmblookup <name>`)

lib.mkIf config.host.capabilities.samba {
  age.secrets."smb-dk".file = "${secretsPath}/smb-dk.age";

  services.samba = {
    enable = true;
    openFirewall = true; # 137,138/udp + 139,445/tcp
    settings = {
      global = {
        "workgroup" = "200";
        "server string" = "hestia";
        "netbios name" = "hestia";
        "security" = "user";
        "map to guest" = "bad user";
        "hosts allow" = "192.168.0.0/16 10.0.0.0/8 172.16.0.0/12 127.0.0.1 localhost";
        "hosts deny" = "0.0.0.0/0";
      };
      share = {
        path = "/home/dk/share";
        browseable = "yes";
        "read only" = "no";
        "guest ok" = "no";
        "create mask" = "0644";
        "directory mask" = "0755";
        "force user" = "dk";
      };
    };
  };

  # makes hestia show up in the Windows "Network" view (modern Windows dropped the
  # legacy NetBIOS browse-master that nmbd alone relied on)
  services.samba-wsdd = {
    enable = true;
    openFirewall = true; # 3702/udp + 5357/tcp
  };

  systemd.tmpfiles.rules = [ "d /home/dk/share 0755 dk users -" ];

  # provision dk's SMB password from agenix on each activation (idempotent)
  systemd.services.samba-smbpasswd = {
    description = "provision dk's Samba password from agenix";
    wantedBy = [ "multi-user.target" ];
    after = [ "agenix.service" ];
    before = [ "samba-smbd.service" ];
    serviceConfig.Type = "oneshot";
    script = ''
      pw=$(cat ${config.age.secrets."smb-dk".path})
      printf '%s\n%s\n' "$pw" "$pw" | ${pkgs.samba}/bin/smbpasswd -s -a dk
    '';
  };

  # client tools for reaching the Windows shares
  environment.systemPackages = with pkgs; [
    cifs-utils
    samba
  ];
}
