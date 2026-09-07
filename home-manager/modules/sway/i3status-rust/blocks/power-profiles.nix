{ wrapIcon, manualFile, updateSignal, ... }:

# The click is the only manual input to the profile rule in ../power-profile.nix:
# it cycles the profile and records the choice, which the reconcile script falls
# back to on the next lid/AC transition.
#
# The profile only moves when something sets it, so the block is signal-driven:
# `signal` is the RT offset ../power-profile.nix's `refresh` raises after the
# reconcile rule changes the profile, and the click repaints itself via
# sync+update. The interval is only a backstop for a set from outside both paths
# (a bare `powerprofilesctl set`).

{
  block = "custom";
  interval = 60;
  signal = updateSignal;
  shell = "sh";
  json = true;
  command = ''
    case $(powerprofilesctl get) in
      performance) icon="󰑮"; state="Warning" ;;
      balanced)    icon="󰜎"; state="Info" ;;
      power-saver) icon=""; state="Good" ;;
    esac

    printf '{"text": "%s", "state": "%s"}' "${wrapIcon "$icon"}" "$state"
  '';
  click = [
    {
      button = "left";
      # both default false: without them the block would re-read before
      # `set` returned, and then not refresh until the next interval
      sync = true;
      update = true;
      cmd = ''
        case "$(powerprofilesctl get)" in
          power-saver) next=balanced ;;
          balanced) next=performance ;;
          performance) next=power-saver ;;
        esac
        powerprofilesctl set "$next"
        # Record as the manual value the reconcile script restores to.
        manual=${manualFile}
        mkdir -p "$(dirname "$manual")"
        printf '%s\n' "$next" > "$manual"
      '';
    }
  ];
}
