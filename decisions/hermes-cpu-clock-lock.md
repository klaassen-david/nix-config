# hermes locking to 544 MHz: Framework firmware, not the power-profile config

**Ruling** [AGENT 2026-09-10]: the CPU pinning itself at 544 MHz until reboot is
Framework's documented open BIOS bug ("Intermittent CPU frequency lock at 545MHz"
— known issue in [BIOS 4.05](https://resources.frame.work/downloads/laptop-16/amd-ryzen-7040-series/4.05/),
the latest release, which hermes runs). Nothing in this repo causes it and
nothing here can fix it. It is a firmware clamp, not a defective machine.

**Evidence it is below the OS.** Observed 2026-09-09 23:04–01:15 CEST (boot -2)
and again 2026-09-09 00:33 (boot -5), both times with `scaling_governor` =
`performance`, `scaling_max_freq` = `cpuinfo_max_freq` = 5263061, EPP
`performance`, `platform_profile` `performance`, and package temperatures ~50 °C.
cpufreq was wide open and the SoC still ran at a tenth of its ceiling, so the
limit is an SMU/EC power limit. For contrast, `power-saver` does something
visibly different: governor `powersave`, `scaling_max_freq` 4001000,
`platform_profile` `low-power`.

**Trigger: a charger plug/unplug whose PD negotiation fails.** In boot -2 the
battery draw collapsed 83 W → 25 W between 23:04:11 and 23:05:11 *while a
1034 %-CPU process was still running* — a clamp, not idleness — straddling
`ucsi_handle_connector_change: GET_CONNECTOR_STATUS failed (-95)` at 23:04:30
and `UCSI_GET_PDOS failed (-95)` at 23:05:51. The boot -5 occurrence sits the
same way around an unplug (00:22:35) / replug (00:30:08) with UCSI failures at
00:26:39, 00:29:27 and 00:31:33. Re-plugging never restored the clock; both
occurrences ended only at reboot.

**Rejected**: `power-profile-reconcile` / power-profiles-daemon (the profile was
`performance` throughout, and its own effects are the ones listed above);
thermal throttling (~50 °C); a firmware update (4.05 of 2026-07-20 is the newest
on both Framework's downloads page and LVFS — `fwupdmgr get-updates` reports
System Firmware at the latest version — and 4.05 lists the lock as still open).

**Next time it happens**: try `systemctl suspend` before rebooting — a
suspend/resume cycle is the community's usual recovery, sometimes needing two.
Check `grep -m1 'cpu MHz' /proc/cpuinfo` against `cpufreq/cpuinfo_max_freq`
before trusting any benchmark taken on hermes.

**Revisit if**: a BIOS past 4.05 ships (watch the release notes for the 545 MHz
known-issue line disappearing), or the lock appears with no charger transition
anywhere near it — which would point at the resume path instead.
