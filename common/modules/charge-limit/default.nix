{
  config,
  lib,
  pkgs,
  ...
}:

{
  # Unprivileged battery charge limit.
  #
  # Not via framework_tool: it gates every operation behind SMBIOS platform
  # detection, which reads /sys/firmware/dmi/tables/{smbios_entry_point,DMI} --
  # both 0400 root, no fallback to the world-readable /sys/class/dmi/id -- so a
  # non-root run dies at "Not a Framework Laptop" before it even picks a driver.
  # No permission grant on /dev/cros_ec changes that, which is why this was once
  # a setuid wrapper. A setuid EC tool is full root for every session, since the
  # EC accepts firmware writes.
  #
  # The kernel exports the limit as a plain power_supply attribute instead:
  # world-readable already, and writable by the group below.
  config = lib.mkIf config.host.capabilities.chargeLimit {
    users.groups.charge-limit = { };
    users.users.dk.extraGroups = [ "charge-limit" ];

    # udev MODE=/GROUP= only apply to device nodes, so chmod the sysfs attribute
    # directly. %p is the DEVPATH, i.e. /sys%p is the battery's sysfs directory.
    services.udev.extraRules = ''
      ACTION=="add|change", SUBSYSTEM=="power_supply", ATTR{charge_control_end_threshold}=="?*", \
        RUN+="${pkgs.coreutils}/bin/chgrp charge-limit /sys%p/charge_control_end_threshold", \
        RUN+="${pkgs.coreutils}/bin/chmod 0664 /sys%p/charge_control_end_threshold"
    '';
  };
}
