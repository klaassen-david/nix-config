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
    # titles are free text inside pango markup: a bare & makes swaybar drop
    # the markup and print the icon's <span> literally. They are also inside a
    # JSON string, so backslashes and quotes are escaped and control
    # characters (which serde_json rejects) become spaces.
    next=$(${pkgs.khal}/bin/khal list --notstarted -df "" -f "{start-time} {title}" now 24h 2>/dev/null | grep -m1 . \
      | sed 's/[[:cntrl:]]/ /g; s/\\/\\\\/g; s/"/\\"/g; s/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
    printf '{"text": "%s %s"}' "${wrapIcon "󰃭"}" "''${next:-No events}"
  '';
  click = [
    {
      button = "middle";
      cmd = "ghostty -e ikhal";
    }
  ];
}
