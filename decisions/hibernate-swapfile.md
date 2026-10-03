# Hibernation swapfile

**Ruling** [USER 2026-09-30]: hermes hibernates into a 32 GiB swapfile on `/`,
enabling `suspend-then-hibernate` on lid close.
**Amended** [USER 2026-10-03]: nothing hibernates automatically. Lid close ends
in plain `systemctl suspend` again (`common/modules/wifi`); hibernation is
`systemctl hibernate` by hand. The swapfile, `HibernateMode = "shutdown"` and
`common/modules/hibernate-console` stay — they are what makes the manual
command work.

**Delay** [USER 2026-09-30]: hibernate after 1 h of suspend
(`HibernateDelaySec = "1h"`, hermes). [AGENT] This applies on AC too
(systemd's `HibernateOnACPower` default); not ruled on.
**Superseded** [USER 2026-10-03]: `HibernateDelaySec` is unset — it only steers
`suspend-then-hibernate`, which nothing triggers now.

**Docked** [USER 2026-09-30]: lid close with an external display connected
triggers no sleep at all. `lid-suspend-delay` (`common/modules/wifi/default.nix`)
exits on any connected non-eDP connector before its final `systemctl` call, so
changing that call does not touch this.

**Critical battery** [USER 2026-10-03]: upower keeps the NixOS default
`criticalPowerAction = "HybridSleep"` (hermes), which does write an image at 2 %.
That is the exception to "no automatic hibernation" — a last-resort save, not a
routine sleep; `PowerOff` loses the session and `Suspend`/`Ignore` need
`allowRiskyCriticalPowerAction`.

**Why** [AGENT 2026-09-26]: the swap partition (`nvme0n1p3`, 8.8 GiB) is
smaller than RAM (30.7 GiB) and than the kernel's 12.2 GiB `image_size` target,
so an image does not reliably fit; `/` is ext4 with 810 GiB free.

**Wake** [USER 2026-09-30]: only the power button resumes from hibernation;
a keypress must not (it did on the first working test, via ACPI S4
`platform` mode). Met by `HibernateMode = "shutdown"` (S5 after the image).

**Feedback** [USER 2026-09-30]: hibernating must not look like a frozen
screen — show what is happening while the image is written. Met by
`common/modules/hibernate-console` (text console + kernel progress lines);
rejected: blanking the panel (no feedback), a notification (sway is frozen),
Plymouth (systemd does not drive it for hibernation).

**Rejected**: repartitioning to grow the swap partition; a swapfile sized to
`image_size` only (fails exactly when memory is fullest).

**Revisit if**: `/` gets tight on space, or `/` moves to a filesystem where a
swapfile's `resume_offset` is not stable (e.g. btrfs without a nocow file).
