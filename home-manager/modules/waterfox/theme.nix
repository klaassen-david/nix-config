# Waterfox/Firefox theme add-on generated from a base16 palette, so the browser
# UI follows the same scheme as the rest of the desktop (stylix).
#
# The palette's hash is part of the add-on id: a force_installed add-on is only
# replaced when its version goes *up*, which a palette change cannot express,
# so a new palette is a new add-on (the profile's activeThemeID follows it;
# the previous theme stays installed but inactive).
{
  lib,
  runCommand,
  writeText,
  zip,
  palette, # { base00 = "#2e3440"; ... base0F = "#..."; }
  polarity ? "dark",
}:

let
  c = palette;
  hash = builtins.substring 0 12 (builtins.hashString "sha256" (builtins.toJSON palette));
  addonId = "base16-${hash}@nix-config";
  manifest = writeText "manifest.json" (
    builtins.toJSON {
      manifest_version = 2;
      name = "base16 (${hash})";
      version = "1.0";
      browser_specific_settings.gecko.id = addonId;
      theme = {
        colors = {
          frame = c.base00;
          frame_inactive = c.base00;
          toolbar = c.base00;
          toolbar_text = c.base05;
          toolbar_top_separator = c.base01;
          toolbar_bottom_separator = c.base01;
          toolbar_vertical_separator = c.base01;
          toolbar_field = c.base01;
          toolbar_field_text = c.base05;
          toolbar_field_border = c.base02;
          toolbar_field_focus = c.base01;
          toolbar_field_text_focus = c.base06;
          toolbar_field_border_focus = c.base0D;
          toolbar_field_highlight = c.base0D;
          toolbar_field_highlight_text = c.base00;
          tab_background_text = c.base05;
          tab_text = c.base06;
          tab_selected = c.base02;
          tab_line = c.base0D;
          tab_loading = c.base0D;
          sidebar = c.base00;
          sidebar_text = c.base05;
          sidebar_border = c.base01;
          sidebar_highlight = c.base02;
          sidebar_highlight_text = c.base06;
          popup = c.base01;
          popup_text = c.base05;
          popup_border = c.base02;
          popup_highlight = c.base02;
          popup_highlight_text = c.base06;
          button_background_hover = c.base01;
          button_background_active = c.base02;
          icons = c.base04;
          icons_attention = c.base0A;
          ntp_background = c.base00;
          ntp_text = c.base05;
          ntp_card_background = c.base01;
          waterfox_accent_primary = c.base0D;
          waterfox_accent_primary_hover = c.base0C;
          waterfox_accent_primary_active = c.base0F;
        };
        properties = {
          color_scheme = polarity;
          content_color_scheme = polarity;
        };
      };
    }
  );
in
runCommand "waterfox-theme-base16-${hash}"
  {
    nativeBuildInputs = [ zip ];
    # home-manager's globalExtensions reads the id from here and installs
    # $out/share/mozilla/extensions/{ec8030f7-…}/<id>.xpi
    passthru = { inherit addonId; };
  }
  ''
    dir="$out/share/mozilla/extensions/{ec8030f7-c20a-464f-9b0e-13a3a9e97384}"
    mkdir -p "$dir" build
    cp ${manifest} build/manifest.json
    (cd build && zip -qX "$dir/${addonId}.xpi" manifest.json)
  ''
