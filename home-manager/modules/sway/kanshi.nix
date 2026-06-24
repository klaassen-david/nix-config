{
  config,
  pkgs,
  host,
  lib,
  ...
}:
let
  # bar/tray/workspace placement is topology-dependent, so it's driven per kanshi
  # profile via `exec` (see below) rather than statically in the bar block.
  # each profile resets with `output *` / `tray_output *` first so state from a
  # previously-applied profile can't leak in.
  swaymsg = "${pkgs.sway}/bin/swaymsg";
  jq = "${pkgs.jq}/bin/jq";
  # explicit, stable bar id so the exec `swaymsg bar <id> …` calls have a known handle
  barId = "bar-default";

  # build a kanshi `exec` script from a bar/tray command list and a list of workspace
  # pins ({ ws; out; }). kanshi tokenizes the exec line and re-escapes spaces but NOT
  # `;`, so each swaymsg call wraps its `;`-chained commands in single quotes inside a
  # script — kanshi then only sees one space-free store-path token, and the quoting
  # that stops `*` globbing / `;` splitting lives where sh actually honors it.
  #
  # bar/tray and workspace commands MUST be separate swaymsg calls: a single call that
  # begins with `bar <id> …` leaves the parser in bar context, so trailing
  # `workspace …` commands get mis-parsed and silently dropped.
  #
  # each pin both sets the assignment (honoured when the workspace is next created)
  # AND moves the workspace now — `workspace N output X` alone is inert for an
  # already-existing workspace, which is the common case once a session is up. moving
  # focuses the workspace, so capture the focused workspace up front and restore it
  # after all pins so session start doesn't yank focus to the last pin.
  mkExec =
    {
      bar,
      pins ? [ ],
    }:
    let
      barLine = "${swaymsg} '${lib.concatStringsSep "; " bar}'";
      captureFocus = "focused=$(${swaymsg} -t get_workspaces | ${jq} -r '.[] | select(.focused) | .name')";
      pinLines = lib.concatMap (p: [
        "${swaymsg} 'workspace ${toString p.ws} output ${p.out}'"
        "${swaymsg} 'workspace number ${toString p.ws}; move workspace to output ${p.out}'"
      ]) pins;
      restoreFocus = ''[ -n "$focused" ] && ${swaymsg} "workspace \"$focused\""'';
      lines = [
        barLine
      ]
      ++ lib.optionals (pins != [ ]) ([ captureFocus ] ++ pinLines ++ [ restoreFocus ]);
    in
    "${pkgs.writeShellScript "kanshi-exec" (lib.concatStringsSep "\n" lines + "\n")}";
in
{
  wayland.windowManager.sway.extraConfig = lib.mkOrder 1500 (
    let
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
    "bar ${barId} {\n" + common + "\n}"
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
            mode = "3840x2160@240Hz";
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
        profile.exec = mkExec {
          # bar + tray on the primary and DP-1 only
          bar = [
            "bar ${barId} output *"
            "bar ${barId} output ${host.display.primary}"
            "bar ${barId} output DP-1"
            "bar ${barId} tray_output *"
            "bar ${barId} tray_output ${host.display.primary}"
            "bar ${barId} tray_output DP-1"
          ];
          pins = [
            {
              ws = 1;
              out = "DP-1";
            }
            {
              ws = 2;
              out = host.display.primary;
            }
            {
              ws = 3;
              out = "HDMI-A-1";
            }
          ];
        };
      }

      {
        profile.name = "hermes-work-01";
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
        # bar + tray on all outputs; adjust if you want them pinned to one screen
        profile.exec = mkExec {
          bar = [
            "bar ${barId} output *"
            "bar ${barId} tray_output *"
          ];
        };
      }

      {
        profile.name = "hermes-work-02";
        profile.outputs = [
          {
            criteria = "BOE 0x0BC9 Unknown";
            position = "0,560";
            status = "enable";
          }
          {
            criteria = "BNQ BenQ MA320U ET37S01742SL0";
            mode = "3840x2160";
            position = "2560,0";
            status = "enable";
          }
          {
            criteria = "BNQ BenQ MA320U ET37S01390SL0";
            mode = "3840x2160";
            position = "6400,0";
            status = "enable";
          }
        ];
        # bar + tray on all outputs; adjust if you want them pinned to one screen
        profile.exec = mkExec {
          bar = [
            "bar ${barId} output *"
            "bar ${barId} tray_output *"
          ];
        };
      }

      # catch-all so switching to a laptop-only layout resets bar/tray state
      # instead of inheriting whatever the last profile set
      {
        profile.name = "hermes-solo";
        profile.outputs = [
          {
            criteria = "eDP-1";
            status = "enable";
          }
        ];
        profile.exec = mkExec {
          bar = [
            "bar ${barId} output *"
            "bar ${barId} tray_output *"
          ];
        };
      }

    ];
  };

  # kanshi's ExecStart is bare `kanshi` (no config path), so a changed config file
  # leaves the unit byte-identical and sd-switch won't restart it on rebuild — the
  # daemon keeps applying its stale in-memory profile until manually restarted.
  # Trigger a restart whenever the generated config changes so a rebuild re-applies.
  systemd.user.services.kanshi.Unit.X-Restart-Triggers = [
    config.xdg.configFile."kanshi/config".source
  ];
}
