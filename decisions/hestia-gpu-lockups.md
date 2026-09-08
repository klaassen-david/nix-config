# hestia hard lockups are the GPU falling off the PCIe bus

**Ruling** [AGENT 2026-09-08]: the recurring freezes — screens black, fans
pinned, no input, hard reset the only way out — are **Xid 79, "GPU has fallen
off the bus"**, not a software fault in whatever happened to be running. The
2026-09-07 instance was blamed on Minecraft/ATM11; the game logged normal play
until 16:20:15 and the kernel logged the Xid six seconds later. Every GL client
then aborted through `libnvidia-glcore` (Xwayland, ghostty, swaync, steam, java)
because the card was already gone.

Thirteen Xid 79 events between 2026-06-21 and 2026-09-07 across entirely
unrelated workloads (`steamwebhelper`, `forhonor.exe`, `CrimsonDesert.exe`,
`java`). The journal only reaches back to 2026-06-19 — it rotated at 854 MB, not
by policy — so June is the oldest surviving event, **not** the first.

**Leading cause: transient power delivery.** The card is a 370 W Gigabyte RTX
3080 (2× 8-pin, which is that model's design — no missing connector) on a
be quiet! Straight Power 11 750 W that also feeds a 3900X: ~560 W sustained,
leaving ~190 W of headroom for Ampere transients that spike ~2× for ~1 ms. The
PSU is a good unit but is past its 5-year warranty, and capacitor aging degrades
exactly the transient response Ampere stresses. No PCIe AER errors were logged in
any of the 13 events, which points at the card browning out rather than the link
degrading.

**Rejected**: thermal (a thermal event powers off, it does not sit there with
fans pinned); missing PCIe power connector (the card has two sockets and both are
populated); anything in the Minecraft or NixOS configuration.

**Open test**: `host.gpuPowerLimitWatts = 280` on hestia
(`common/modules/nvidia-power-limit`). Clean sessions at 280 W after 13 crashes
at 370 W confirms power delivery, and the cap can then simply stay — a 3080 gives
up ~5-8% for it. Still crashing at 280 W moves suspicion to the card itself, and
the next steps are the BIOS (still the launch `A.00` of 2020-05-15, six years of
AGESA/PCIe fixes unapplied) and a reseat.

**crash-capture did not fire, and that is not a bug.** `host.debug.crashCapture`
was already on for this event. Its trigger is panic-on-hang — hung tasks, soft
lockups, oops. None happened: the kernel stayed healthy, userspace aborted
cleanly, and journald kept writing right through the fault, which is why the
ordinary journal carried the whole diagnosis. pstore was empty and correct to be.
The module still covers the case where a hang wedges the scheduler; it just never
covered this one.

**Revisit if**: the 280 W cap holds for a month (make it permanent, or replace
the PSU and lift it), or crashes continue at 280 W (card/BIOS, not power).
