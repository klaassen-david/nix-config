{ pkgs, wrapIcon, ... }:

# Charge limit via the kernel's power_supply attribute, not framework_tool --
# that tool needs root for SMBIOS platform detection even to read (see
# common/modules/charge-limit). The read is world-readable; the write works
# because that module hands the attribute to the charge-limit group.
# An empty read means the attribute is absent (no such battery, or the module
# is off), not "0%", so both the block and the toggle bail rather than
# comparing an empty string against 60.

let
  attr = "/sys/class/power_supply/*/charge_control_end_threshold";

  get = pkgs.writeShellScript "charge-limit-get" ''
    cat ${attr} 2>/dev/null | head -1
  '';

  toggle = pkgs.writeShellScript "charge-limit-toggle" ''
    current=$(${get})
    [ -n "$current" ] || exit 1
    if [ "$current" -le 60 ]; then target=100; else target=60; fi
    for f in ${attr}; do
      [ -w "$f" ] || exit 1
      echo "$target" > "$f"
    done
  '';
in
{
  block = "custom";
  shell = "sh";
  interval = 60;
  json = true;
  command = ''
    LIMIT=$(${get})
    if [ -z "$LIMIT" ]; then
      printf '{"text": "%s ?", "state": "Critical"}' "${wrapIcon "󱞜"}"
    else
      STATE=$([ "$LIMIT" -le 60 ] && echo "Good" || echo "Warning")
      printf '{"text": "%s %s", "state": "%s"}' "${wrapIcon "󱞜"}" "$LIMIT" "$STATE"
    fi
  '';
  click = [
    {
      button = "left";
      cmd = "${toggle}";
      # both default false: without them the block would re-read before
      # the write landed, and then not refresh until the next interval
      sync = true;
      update = true;
    }
  ];
}
