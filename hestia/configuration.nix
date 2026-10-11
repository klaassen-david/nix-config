{
  config,
  lib,
  pkgs,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix
    ../common/desktop.nix
    ../common/modules/backup
    ../common/modules/mail-backup
    # hot-swapped from ~/deploy, dashboards proxied by olympus (decisions/hot-swap.md)
    ../common/modules/orchestrator
    ../common/modules/coordinator
  ];

  host = {
    hostName = "hestia";
    role = "tower";
    stateVersion = "25.05";
    gpu = "nvidia";
    # 370 W factory limit on a 750 W PSU that also feeds a 3900X. Capped to shrink
    # the Ampere transients suspected behind the recurring Xid 79 lockups; this is
    # a diagnostic, not a settled value. See decisions/hestia-gpu-lockups.md.
    gpuPowerLimitWatts = 280;
    display.primary = "DP-3";
    display.startupWorkspace = 2;
    theme.wallpaper = "/home/dk/wallpaper/current";
    browser = "firefox";
    # dvorak first = active once sway starts; the console fallback takes only
    # the bare first layout, so it stays plain us
    keyboard = {
      layout = "us,gb,de";
      variant = "dvorak,,";
    };
    capabilities.samba = true;
    # owns the fleet restic repo; ../common/modules/backup pulls each listed
    # source into it and verifies the result on a weekly timer
    backup.pull = [ "mail" ];
    # 510M ESP only fits ~2 kernel+initrd pairs (initrd ~198M each); the
    # default of 10 overflows /boot/efi and breaks the systemd-boot install.
    keepGenerations = 2;
    # recurring hard freezes (display off, fans pinned, hard reset) leave no
    # journal — capture the next lockup's dmesg to pstore. See modules/crash-capture.
    debug.crashCapture = true;
  };

  environment.systemPackages = [ pkgs.lutris ];

  # declared, not left to `loginctl`: the coordinator and orchestrator start
  # work with `systemd-run --user`, which needs dk's manager up without a login
  users.users.dk.linger = true;

  # decisions/hot-swap.md, "Night window": fstrim and the restic check default
  # to Monday 00:00, inside the overnight build window, where an I/O stall over
  # 60 s panics this host (modules/crash-capture). Monday morning instead; both
  # timers are Persistent, so a missed run catches up at boot.
  services.fstrim.interval = "Mon 07:30";
  systemd.timers.restic-check.timerConfig.OnCalendar = lib.mkForce "Mon 08:00";

  # games library on the second NVMe — mount by UUID so it survives the
  # nvme0/nvme1 enumeration swap; nofail keeps boot going if the disk is absent.
  fileSystems."/mnt/games" = {
    device = "/dev/disk/by-uuid/458b8b57-edd0-4426-bf5e-6d06543c46b0";
    fsType = "ext4";
    options = [
      "nofail"
      "x-systemd.device-timeout=5s"
    ];
  };

  # Bootloader
  boot.loader = {
    systemd-boot.enable = true;
    systemd-boot.configurationLimit = config.host.keepGenerations;
    efi.canTouchEfiVariables = true;
    efi.efiSysMountPoint = "/boot/efi";
  };

  # nvidia
  boot.initrd.kernelModules = [
    "nvidia"
    "nvidia_modeset"
    "nvidia_uvm"
    "nvidia_drm"
  ];
  services.seatd.enable = true;
  users.users.dk.extraGroups = [ "seat" ];
  hardware = {
    graphics = {
      enable = true;
      enable32Bit = true;
      extraPackages = with pkgs; [
        vulkan-validation-layers
        vulkan-extension-layer
        vulkan-loader
        nvidia-vaapi-driver
        gamescope-wsi
      ];
    };
    nvidia = {
      package = config.boot.kernelPackages.nvidiaPackages.production;
      open = false;
      nvidiaSettings = true;
      modesetting.enable = true;
    };
  };
  services.xserver.videoDrivers = [ "nvidia" ];

  networking = {
    nameservers = [
      "1.1.1.1"
      "8.8.8.8"
    ];
    useDHCP = false;
    dhcpcd.enable = false;
    networkmanager = {
      enable = true;
      # mkForce beats resolved.nix, which sets this to "systemd-resolved"
      dns = lib.mkForce "none";
    };
  };
  services.resolved.enable = true;
}
