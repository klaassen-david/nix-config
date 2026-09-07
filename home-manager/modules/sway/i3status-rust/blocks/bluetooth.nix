{ ... }:

{
  block = "bluetooth";
  mac = "00:1B:66:27:65:39";
  format = " $icon $name{ $percentage|} ";
  disconnected_format = " $icon ";
  click = [
    {
      button = "right";
      cmd = ''
        state=$(bluetoothctl show | sed -n 's/.*Powered: //p')
        case "$state" in
          yes) bluetoothctl power off ;;
          no) bluetoothctl power on ;;
        esac
      '';
    }
    {
      button = "middle";
      cmd = "blueman-manager";
    }
  ];
}
