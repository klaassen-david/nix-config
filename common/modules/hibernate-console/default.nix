{ pkgs, ... }:

# ---------------------------------------------------------------------------
# hibernate-console — show hibernation progress instead of a frozen desktop
# ---------------------------------------------------------------------------
# systemd-sleep freezes user.slice (sway included) before sleeping, so while
# the image is written the panel keeps sway's last frame and looks hung
# (decisions/hibernate-swapfile.md). Before sleep.target — sway still answers
# the VT switch then — this switches to a spare text console, prints a note,
# and raises the console loglevel to 7 so the kernel's own
# "PM: Image saving progress: NN%" lines (pr_info) appear under it. After
# resume, StopWhenUnneeded stops the unit with the sleep target, restoring the
# loglevel and switching back.
#
# Wanted by the hibernating targets only, not plain suspend. For
# suspend-then-hibernate it starts before the suspend phase (screen off), so a
# resume from that phase briefly shows the console before switching back.
let
  vt = "12"; # above logind's NAutoVTs (6): no getty ever claims it
  run = "/run/hibernate-console";

  start = pkgs.writeShellScript "hibernate-console-start" ''
    fgconsole > ${run}.vt
    cut -f1 /proc/sys/kernel/printk > ${run}.loglevel
    printf '\033[2J\033[H\n  Hibernating: writing memory to disk.\n  The power LED goes off when it is done.\n\n' > /dev/tty${vt}
    echo 7 > /proc/sys/kernel/printk
    timeout 5 chvt ${vt}
  '';

  stop = pkgs.writeShellScript "hibernate-console-stop" ''
    [ -s ${run}.loglevel ] && cat ${run}.loglevel > /proc/sys/kernel/printk
    [ -s ${run}.vt ] && timeout 5 chvt "$(cat ${run}.vt)"
    rm -f ${run}.vt ${run}.loglevel
  '';
in
{
  systemd.services.hibernate-console = {
    description = "Show hibernation progress on a text console";
    wantedBy = [
      "hibernate.target"
      "suspend-then-hibernate.target"
    ];
    before = [ "sleep.target" ];
    path = [ pkgs.kbd ]; # fgconsole, chvt
    unitConfig.StopWhenUnneeded = true;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = start;
      ExecStop = stop;
    };
  };
}
