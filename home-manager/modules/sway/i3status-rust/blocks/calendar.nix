{ pkgs, wrapIcon, ... }:

# next appointment from the pimsync-synced khal calendars
# (../../calendar). left-click opens ikhal. khal format flags / icon may want
# tuning once real events exist; before the first pimsync sync this shows
# "No events".

{
  block = "custom";
  shell = "sh";
  interval = 60;
  json = true;
  command = ''
    next=$(${pkgs.khal}/bin/khal list --notstarted -df "" -f "{start-time} {title}" now 24h 2>/dev/null | grep -m1 . | tr -d '"')
    printf '{"text": "%s %s"}' "${wrapIcon "󰃭"}" "''${next:-No events}"
  '';
  click = [
    {
      button = "middle";
      cmd = "ghostty -e ikhal";
    }
  ];
}
