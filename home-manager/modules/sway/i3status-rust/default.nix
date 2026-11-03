{
  config,
  pkgs,
  host,
  lib,
  ...
}:

# The swaybar status line, one block per file under ./blocks.
#
# ./helpers.nix is the shared vocabulary (icon styling, the on/off colours, the
# unit viewer) and ./power-profile.nix the lid/AC machinery behind the power
# profile block. Both are plain functions, evaluated once here and splatted into
# every block's argument set, so a block file names only what it uses:
# `{ wrapIcon, ... }:`. Each block file evaluates to a single i3status-rs block
# attrset — order and the host.capabilities gating live in `blocks` below.

let
  helpers = import ./helpers.nix {
    inherit pkgs lib;
    colors = config.lib.stylix.colors.withHashtag;
  };
  powerProfile = import ./power-profile.nix { inherit pkgs lib host; };

  block =
    path:
    import path (
      {
        inherit pkgs lib host;
      }
      // helpers
      // {
        inherit (powerProfile) manualFile updateSignal;
      }
    );

  blocks =
    [ (block ./blocks/net.nix) ]
    ++ lib.optional host.capabilities.sshServer (block ./blocks/ssh-server.nix)
    ++ [ (block ./blocks/vpn-exit.nix) ]
    ++ map block [
      ./blocks/disk-space.nix
      ./blocks/memory.nix
      ./blocks/cpu.nix
      ./blocks/sound.nix
      ./blocks/calendar.nix
      ./blocks/time.nix
    ]
    ++ lib.optional host.capabilities.bluetooth (block ./blocks/bluetooth.nix)
    ++ lib.optionals host.capabilities.battery (
      [ (block ./blocks/battery.nix) ]
      # not every battery exposes charge_control_end_threshold
      ++ lib.optional host.capabilities.chargeLimit (block ./blocks/charge-limit.nix)
      ++ [ (block ./blocks/power-profiles.nix) ]
    );
in
{
  home.packages =
    [ helpers.unitStatusView ]
    ++ lib.optional host.capabilities.battery powerProfile.reconcile;

  systemd.user.services.power-profile-reconcile = lib.mkIf host.capabilities.battery {
    Unit = {
      Description = "Reconcile power profile on lid/AC change (lid > AC > manual)";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = powerProfile.monitor;
      Restart = "on-failure";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  programs.i3status-rust = {
    enable = true;
    bars.default = {
      settings.icons_format = helpers.wrapIcon "{icon}";
      # Block state as text colour only, like the `plain` theme before stylix:
      # every background is the bar's own (base00), the palette colours the
      # text, escalating yellow -> orange -> red. (stylix's lib attrset fills
      # the backgrounds instead, info orange before warning yellow.)
      settings.theme.overrides =
        let
          c = config.lib.stylix.colors.withHashtag;
          bg = c.base00;
        in
        {
          idle_bg = bg;
          info_bg = bg;
          good_bg = bg;
          warning_bg = bg;
          critical_bg = bg;
          separator_bg = bg;
          idle_fg = c.base05;
          info_fg = c.base0A;
          good_fg = c.base0B;
          warning_fg = c.base09;
          critical_fg = c.base08;
          separator_fg = c.base03;
        };
      icons = "material-nf";
      inherit blocks;
    };
  };
}
