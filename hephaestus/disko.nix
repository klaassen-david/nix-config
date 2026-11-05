# Two disks, so a full build disk cannot take down the system. Both by-id paths
# were read from the installer; nixos-anywhere wipes exactly these.
{ ... }:

{
  disko.devices.disk = {
    # M.2: ESP and root
    system = {
      type = "disk";
      device = "/dev/disk/by-id/ata-Micron_1100_MTFDDAV256TBN_18351E7E9AA2";
      content = {
        type = "gpt";
        partitions = {
          ESP = {
            size = "1G";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = [ "umask=0077" ];
            };
          };
          root = {
            size = "100%";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
              mountOptions = [ "noatime" ];
            };
          };
        };
      };
    };

    # SATA: worktrees and build output. nofail keeps a dead disk from stopping boot
    # and sshd.
    work = {
      type = "disk";
      device = "/dev/disk/by-id/ata-MTFDDAK256MBF-1AN1ZABHA_16401473E373";
      content = {
        type = "gpt";
        partitions.dev = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/mnt/dev";
            mountOptions = [
              "noatime"
              "nofail"
            ];
            extraArgs = [
              "-L"
              "hephaestus-dev"
            ];
          };
        };
      };
    };
  };
}
