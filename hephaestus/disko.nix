# Three filesystems on two disks, so filling one takes down neither the others nor
# sshd. Both by-id paths were read from the installer; nixos-anywhere wipes exactly
# these. nofail keeps a dead data filesystem from stopping boot. Both data
# filesystems are written by dk only, so no root reserve.
# Layout [USER 2026-11-05]; the evaluation is in decisions/implementer-host.md.
{ ... }:

{
  disko.devices.disk = {
    # M.2: ESP, root with /nix, the rest for compile output
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
            size = "100G";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
              mountOptions = [ "noatime" ];
            };
          };
          scratch = {
            size = "100%";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/mnt/scratch";
              mountOptions = [
                "noatime"
                "nofail"
              ];
              extraArgs = [
                "-L"
                "heph-scratch"
                "-m"
                "0"
              ];
            };
          };
        };
      };
    };

    # SATA, whole disk: worktrees and repos
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
              "heph-dev"
              "-m"
              "0"
            ];
          };
        };
      };
    };
  };
}
