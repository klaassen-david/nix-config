# PLACEHOLDER (user, from hermes, before installing): overwrite this file with
#   ssh -i ~/.ssh/id_priv root@131.246.129.70 \
#     nixos-generate-config --no-filesystems --show-hardware-config
# The values below only let the host evaluate until then.
{
  config,
  lib,
  modulesPath,
  ...
}:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  warnings = [ "hephaestus: hardware-configuration.nix is still the placeholder" ];

  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "ahci"
    "usbhid"
    "sd_mod"
  ];
  boot.kernelModules = [ "kvm-intel" ];

  networking.useDHCP = lib.mkDefault true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
