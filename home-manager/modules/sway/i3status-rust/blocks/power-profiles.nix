{ wrapIcon, manualFile, ... }:

# The click is the only manual input to the profile rule in ../power-profile.nix:
# it cycles the profile and records the choice, which the reconcile script falls
# back to on the next lid/AC transition.

{
  block = "custom";
  interval = 1;
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
