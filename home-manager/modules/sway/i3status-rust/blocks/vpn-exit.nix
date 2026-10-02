{ wrapIcon, ... }:

# current VPN exit (common/modules/wireguard: `vpn status`): direct, olympus,
# another host or tukl, plus `+home` / `!down`. The JSON line carries the
# state, so a dead exit or an inconsistent routing state turns the block red.

{
  block = "custom";
  interval = 5;
  json = true;
  format = " ${wrapIcon "󰖂"} $text ";
  command = ''vpn status --json 2>/dev/null || echo '{"text":"?","state":"Critical"}' '';
  click = [
    {
      button = "middle";
      cmd = "ghostty -e sh -c 'vpn status; read -r _'";
    }
  ];
}
