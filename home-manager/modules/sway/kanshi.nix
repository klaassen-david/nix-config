{
  pkgs,
  host,
  mainDisplay,
  lib,
  ...
}:
{
  wayland.windowManager.sway.extraConfig = lib.mkOrder 1500 (
    let
      hostSpecific =
        if host == "hestia" then
          ''
            tray_output ${mainDisplay}
            output ${mainDisplay}
            tray_output DP-1
            output DP-1
          ''
        else if host == "hermes" then
          ''

          ''
        else
          "";
      common = ''
        font pango:FiraCode Nerd Font Propo 8.000000
        mode dock
        hidden_state hide
        position bottom
        status_command i3status-rs ~/.config/i3status-rust/config-default.toml
        swaybar_command ${pkgs.sway}/bin/swaybar
        workspace_buttons yes
        strip_workspace_numbers no
        colors {
          background #000000
          statusline #ffffff
          separator #666666
          focused_workspace #4c7899 #285577 #ffffff
          active_workspace #333333 #5f676a #ffffff
          inactive_workspace #333333 #222222 #888888
          urgent_workspace #2f343a #900000 #ffffff
          binding_mode #2f343a #900000 #ffffff
        }
      '';
    in
    "bar {\n" + common + hostSpecific + "\n}"
  );

  services.kanshi = {
    enable = true;
    systemdTarget = "sway-session.target";
    settings = [

      {
        profile.name = "hestia-home";
        profile.outputs = [
          {
            criteria = "Philips Consumer Electronics Company 32M2N8900 AU42435000091";
            position = "0,0";
          }
          {
            criteria = "Samsung Electric Company U32J59x HNMXC00245";
            position = "3840,0";
            scale = 1.5;
          }
          {
            criteria = "Infotronic America, Inc. INFOTRONIC  0x00000F4E";
            position = "6400,240";
          }
        ];
      }

      {
        profile.name = "hermes-work";
        profile.outputs = [
          {
            criteria = "BOE 0x0BC9 Unknown";
            position = "0,360";
            status = "enable";
          }
          {
            criteria = "LG Electronics 24MB37 607NTNHC8631";
            mode = "1920x1080";
            position = "2560,360";
            status = "enable";
          }
          {
            criteria = "ASUSTek COMPUTER INC ASUS VA27A S9LMTF073523";
            mode = "2560x1440";
            position = "4480,0";
            status = "enable";
          }
        ];
      }

    ];
  };
}
