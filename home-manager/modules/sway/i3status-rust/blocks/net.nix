{ ... }:

{
  block = "net";
  format = " $icon {$signal_strength $ssid |Wired connection}";
  # nmtui, not iwgtk: NetworkManager drives wpa_supplicant now
  # (decisions/wifi-backend.md). No rfkill toggle — a stray click killed the
  # link mid-debug and i3status-rust clicks take no modifier to guard it.
  click = [
    {
      button = "middle";
      cmd = "ghostty -e nmtui";
    }
  ];
}
