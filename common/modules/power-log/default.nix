{
  config,
  lib,
  pkgs,
  ...
}:

# ---------------------------------------------------------------------------
# power-log — always-on power telemetry for the hermes battery-life work
# ---------------------------------------------------------------------------
# Battery life is tuned by changing one thing and waiting a day, which only
# works if the before/after is on disk (scope: decisions/power-log-scope.md).
# A root oneshot samples once a minute, plus once before suspend and once after
# resume, and appends one JSON line per sample: battery, package/core RAPL
# watts, GPU, power profile, brightness, panel power savings, bluetooth rfkill,
# wifi power save, lid, screen state, and CPU seconds per leaf cgroup (top 10)
# so a wakeup-heavy unit shows up by name. Field contract: see power-log.py.
#
# Data: /var/lib/power-log/samples-YYYY-MM.jsonl (root writes, world-readable
# by design: nothing in it is secret and the reader needs no sudo) and
# marks.jsonl (owned by dk). state.json holds the previous counters.
#
#   power-log mark <label>   open a named window (next mark closes it; `end`
#                            just closes), e.g. before a test workload
#   power-report             summarise by context, generation, or mark
#
# Battery fields only mean something on battery: host.chargeLimitPercent idles
# the battery on AC, so charge deltas there are ~0 and bat_discharge_w is null.
# RAPL is root-only, so `power-log sample --dry-run` unprivileged shows null.
#
# Importing this module is the opt-in; there is no enable option.
let
  powerLog = pkgs.writers.writePython3Bin "power-log" {
    flakeIgnore = [ "E501" "W503" "W504" ];
  } (
    builtins.replaceStrings
      [ "@powerprofilesctl@" "@iw@" "@lid_state@" ]
      [
        "${pkgs.power-profiles-daemon}/bin/powerprofilesctl"
        "${pkgs.iw}/bin/iw"
        (lib.optionalString (config.host.lid_state != null) "${config.host.lid_state}")
      ]
      (builtins.readFile ./power-log.py)
  );

  powerReport = pkgs.writers.writePython3Bin "power-report" {
    flakeIgnore = [ "E501" "W503" "W504" ];
  } (builtins.readFile ./power-report.py);

  # Sleep hooks run as root outside the service's sandbox; never block sleep.
  hook = kind: "${powerLog}/bin/power-log sample --kind ${kind} || true";
in
{
  environment.systemPackages = [
    powerLog
    powerReport
  ];

  systemd.services.power-log = {
    description = "Append one power telemetry sample";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${powerLog}/bin/power-log sample --kind tick";
      StateDirectory = "power-log";
      StateDirectoryMode = "0755";
      # Needs /sys, /proc, the system bus (powerprofilesctl) and netlink (iw).
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      NoNewPrivileges = true;
      ProtectControlGroups = false; # leaf-cgroup walk reads /sys/fs/cgroup
      RestrictAddressFamilies = [
        "AF_UNIX"
        "AF_NETLINK"
      ];
      RestrictNamespaces = true;
      LockPersonality = true;
      MemoryDenyWriteExecute = true;
    };
  };

  systemd.timers.power-log = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "1min";
      OnUnitActiveSec = "60s";
      AccuracySec = "20s"; # lets systemd coalesce the wakeup with others
    };
  };

  powerManagement.powerDownCommands = hook "suspend";
  powerManagement.resumeCommands = hook "resume";

  systemd.tmpfiles.rules = [ "f /var/lib/power-log/marks.jsonl 0644 dk users -" ];
}
