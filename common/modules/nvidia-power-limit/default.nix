# Nvidia board power limit
# ========================
# Caps the GPU's sustained board power below its factory limit, applied at boot
# and driven by host.gpuPowerLimitWatts. null (the default) leaves the card's own
# limit alone, so this module is inert on every host that has not opted in.
#
# Why it exists: Ampere draws microsecond transients far above its rated board
# power, and a PSU whose OCP trips on those spikes drops the card off the PCIe
# bus — Xid 79, display dead, fans pinned, hard reset the only way out. hestia hit
# that 13 times between 2026-06 and 2026-09 across unrelated workloads (steam,
# java, several wine games) with no PCIe AER errors logged, which is the signature
# of the card browning out rather than the link degrading. Lowering the ceiling
# shrinks the transients with it. See decisions/hestia-gpu-lockups.md.
#
# nvidia-persistenced comes along because it has to: without it the driver tears
# down GPU state once the last client closes the device, and a limit applied by a
# oneshot that exits immediately would go with it. The daemon holds the device
# open so the setting survives to the point a compositor picks the GPU up.
#
# A value outside the card's own min/max (read them with `nvidia-smi -q -d POWER`)
# fails the unit rather than being silently ignored — the limit not applying is
# exactly the failure this is meant to make visible, so check
# `systemctl status nvidia-power-limit` after a rebuild.
{ config, lib, ... }:

let
  watts = config.host.gpuPowerLimitWatts;
in
{
  config = lib.mkIf (config.host.gpu == "nvidia" && watts != null) {
    hardware.nvidia.nvidiaPersistenced = true;

    systemd.services.nvidia-power-limit = {
      description = "Apply the configured Nvidia board power limit";
      wantedBy = [ "multi-user.target" ];
      after = [ "nvidia-persistenced.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${config.hardware.nvidia.package.bin}/bin/nvidia-smi --power-limit=${toString watts}";
      };
    };
  };
}
