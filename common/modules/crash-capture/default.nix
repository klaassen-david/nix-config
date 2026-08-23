# Crash capture for hard lockups
# ==============================
# A GPU/kernel *hang* (display dead, box unresponsive, fans pinned, requires a
# hard reset) flushes nothing to the journal — journald never runs again, so every
# post-mortem dead-ends on the last routine log line. This module makes the next
# lockup leave evidence. Gated behind host.debug.crashCapture (default off), so
# only a misbehaving host pays the cost.
#
# 1. Capture — pstore.
#    On panic/oops the kernel writes a compressed dmesg tail to a persistent
#    backend. Here that backend is efi_pstore (EFI NVRAM), which — unlike ramoops
#    in DRAM — survives the full power-cycle a hard reset performs. NixOS already
#    mounts /sys/fs/pstore and ships systemd-pstore.service, which on the next boot
#    moves the record into /var/lib/systemd/pstore/. So archiving is already
#    handled; the missing piece is a *trigger*, because a hang is not a panic.
#
# 2. Trigger — panic-on-hang ("panic-on-Xid" by proxy).
#    The Nvidia driver exposes no "panic on Xid" knob, so we catch the hang's
#    downstream symptoms instead. A GPU hang typically wedges the compositor / GL
#    clients in uninterruptible (D) sleep on a stuck GPU fence, or soft-locks a
#    CPU; the sysctls below turn those — and any nvidia oops — into a panic, which
#    is what drives the pstore dump. kernel.panic=30 then auto-reboots so the box
#    self-recovers and archives the dump on the way back up.
#
# Safety net — hardware watchdog.
#    If the lockup is total (scheduler dead, so khungtaskd/softlockup never run and
#    no panic fires), pstore stays empty. systemd pets the SP5100 TCO timer while
#    it lives; once systemd stops, the timer force-resets the machine. Complementary
#    to (2): soft enough → panic + dump; hard enough → watchdog reset with no dump
#    but at least no manual hard reset.
#
# Inspect a captured crash after it reboots:  ls /var/lib/systemd/pstore/
{ config, lib, ... }:

let
  cfg = config.host.debug.crashCapture;
in
{
  config = lib.mkIf cfg {
    # bound the dmesg written per pstore record — protects EFI NVRAM from large or
    # repeated dumps; the last 32 KiB of kmsg is plenty of tail for a post-mortem.
    boot.kernelParams = [ "pstore.kmsg_bytes=32768" ];

    boot.kernel.sysctl = {
      # GPU hang → clients stuck in D-state on a fence; fire faster than the 120s
      # default and panic so it dumps. Rare enough on local NVMe that a legitimate
      # >30s uninterruptible wait won't false-positive in practice.
      "kernel.hung_task_panic" = 1;
      "kernel.hung_task_timeout_secs" = 30;
      # CPU soft/hard lockup → panic (softlockup detection rides the NMI watchdog,
      # already on by default).
      "kernel.softlockup_panic" = 1;
      # nvidia oops → panic immediately rather than limping into an unrecoverable
      # state where nothing gets captured.
      "kernel.panic_on_oops" = 1;
      # after a panic + pstore dump, reboot in 30s so the host self-recovers.
      "kernel.panic" = 30;
    };

    # arm the SP5100 TCO hardware watchdog: systemd pets /dev/watchdog while alive,
    # and a total lockup stops the pets so the timer resets the box. Recovery-only
    # — a watchdog cold reset leaves no pstore dump; the panic path above is what
    # captures. 30s tolerates brief load spikes / heavy swap before resetting.
    systemd.settings.Manager.RuntimeWatchdogSec = "30s";
  };
}
