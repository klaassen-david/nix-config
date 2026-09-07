{
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
  helpers = import ./helpers.nix { inherit pkgs lib; };
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
    ++ lib.optional host.capabilities.onDemandSshServer (block ./blocks/ssh-server.nix)
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
    (with pkgs; [
      iwgtk # net block, middle click
    ])
    ++ [ helpers.unitStatusView ]
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
      icons = "material-nf";
      inherit blocks;
    };
  };
}
