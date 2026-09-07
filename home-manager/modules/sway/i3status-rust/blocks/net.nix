{ ... }:

{
  block = "net";
  format = " $icon {$signal_strength $ssid |Wired connection}";
  click = [
    {
      button = "right";
      cmd = "rfkill toggle wifi";
    }
    {
      button = "middle";
      cmd = "iwgtk";
    }
  ];
}
