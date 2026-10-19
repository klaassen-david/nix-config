# hestia: schedutil by default, performance during measurement sessions

**Ruling** [USER 2026-10-18, amends 2026-10-17]: hestia runs `schedutil`
(`powerManagement.cpuFreqGovernor`). The coordinator switches every core to
`performance` for the length of a measurement session, its
demand-driven measure hold (D219), by starting
`cpu-governor-performance.service` when the session begins and
`cpu-governor-schedutil.service` when it ends. Both are oneshot units in
`hestia/configuration.nix`; dk may start them without sudo through
`host.userManagedUnits`. gamemode keeps `desiredgov = performance` and restores
what it found, so it still works between sessions. Every timed run therefore sees
`performance`; everything else runs on `schedutil`.

**Why the amendment.** With `performance` all the time, hestia ran 7-10 C hotter
at the same partial load: minutes at or above 85 C went from 10 % to 55 %, and
the coordinator's thermal hold (85 C) refused dispatches all evening on
2026-10-17 and again on 2026-10-18. Measurements now run in explicit sessions,
so the switch can follow them instead of a clock.

**Mechanics** (review 2026-10-19): the units take a lock (`/run/cpu-governor.lock`),
write every core and fail if any write failed; they order after
`cpufreq.service`, which a switch no longer restarts (`restartIfChanged = false`),
so a rebuild cannot reset the governor under a running session. gamemode ends on
`schedutil` (`defaultgov`). Boost is not touched: it stays at its default (on).

**Failure modes**: a coordinator restart re-runs the switch for the session it
re-adopts; a coordinator that stays down inside a session leaves `performance`
until the next session or a reboot (boot default `schedutil`). A failed switch
back to `schedutil` is retried by the coordinator's sampler (the harness side of
this ruling); until that lands, heat and thermal holds are the cost.

**Rejected**: fixed time windows for the governor (the first version of this
amendment; D219 replaced the windows with sessions); `performance` permanently
(the 2026-10-17 ruling; 7-10 C hotter, thermal holds); gamemode as the switch
(needs the user's session bus inside the coordinator, and a client that ends
early restores the wrong governor).

**Revisit if**: measurement sessions are replaced, or a better cooler makes the
permanent `performance` governor cheap.

---

## History: 2026-10-17 ruling (superseded)

### hestia runs the performance governor permanently

**Ruling** [USER 2026-10-17]: every core of hestia's 3900X runs the
`performance` cpufreq governor all the time (`powerManagement.cpuFreqGovernor`
in `hestia/configuration.nix`). Boost stays on. gamemode is configured to
request and restore `performance`, so starting or ending a gamemode client no
longer changes the governor.

**Why.** hestia hosts the ostt3 timing measurements. Under the default
`schedutil` (acpi-cpufreq, P-states 2.2/2.8/3.8 GHz plus boost to ~4.6 GHz),
the clock follows each core's recent load, so short-lived work never ramps up.
The research sweep of 2026-10-17 found sstt's per-row forked children running
at the 2.2 GHz floor while the long-running engine ran boosted, a 1.94× clock
gap inside the compared spans. On 2026-10-16 a gamemode client switched the
governor to `performance` for 2 h, and the one measurement taken in that window
became a reference that the other runs could not match. With `performance`
fixed, nothing runs at the floor and nothing changes the governor between runs.

**Cost.** A little more power when some cores are busy. No change under
sustained full load (schedutil already runs at the top P-state there) or when
idle (idle cores still enter C-states).

**Rejected**:
- keeping schedutil and declaring it the measured state: leaves the ramp-up
  asymmetry between short and long processes in place;
- boost off: steadier clocks, but everything, builds included, runs about 20 %
  slower;
- an isolated measurement core (`isolcpus`/`nohz_full`, SMT sibling offline):
  boot-level change, not needed yet. Pinning timed runs to equally rated fast
  cores (per-core CPPC `highest_perf` 166–216) is done by the measurement
  harness, not here.

**Background timers** checked at the same time (systemd CPU accounting): the
5-minute nextcloud-cmd (0.45 s CPU) and pimsync-sync (0.15 s), the daily
fstrim (I/O only) and the weekly checks are left as they are; only the hourly
orch-state backup (~24 s CPU over 22 s, idle I/O) is worth keeping out of
exclusive measurements; the coordinator handles that on its side.

**Revisit if**: package temperatures under sustained load reach ~90 °C again
(hestia hit 95 °C on 2026-10-16), or the measurements move to fixed clocks
(boost off) or an isolated core.
