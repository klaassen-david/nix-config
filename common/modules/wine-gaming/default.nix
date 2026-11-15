{
  config,
  lib,
  pkgs,
  ...
}:

# `wine-gaming <game.exe> [args]` runs a Windows game under GE-Proton through
# umu-launcher (Steam's runtime container, no Steam client), in a prefix of its
# own instead of borrowing a Steam game's compatdata. DXVK/VKD3D/NVAPI come with
# GE-Proton; the first run creates the prefix and fetches the Steam runtime
# into ~/.local/share/umu.
#
#   wine-gaming winecfg                        # any wine tool runs in the prefix
#   GAMEID=umu-<steam appid> wine-gaming x.exe # apply that game's protonfixes
#   WINEPREFIX=... wine-gaming x.exe           # another prefix
#   mangohud wine-gaming x.exe                 # overlay

let
  wineGaming = pkgs.writeShellApplication {
    name = "wine-gaming";
    runtimeInputs = [
      pkgs.umu-launcher
      pkgs.gamemode
    ];
    text = ''
      export WINEPREFIX="''${WINEPREFIX:-$HOME/mnt/games/wine_gaming}"
      export PROTONPATH="''${PROTONPATH:-${pkgs.proton-ge-bin.steamcompattool}}"
      export GAMEID="''${GAMEID:-umu-default}"
      export STORE="''${STORE:-none}"
      export PROTON_ENABLE_NVAPI="''${PROTON_ENABLE_NVAPI:-${if config.host.gpu == "nvidia" then "1" else "0"}}"
      # gamemoderun's LD_PRELOAD lib is not visible inside umu's container;
      # hold gamemode from outside for the game's lifetime instead
      gamemoded -r >/dev/null 2>&1 &
      gm=$!
      trap 'kill "$gm" 2>/dev/null' EXIT
      umu-run "$@"
    '';
  };
in
lib.mkIf config.host.capabilities.wineGaming {
  environment.systemPackages = [
    wineGaming
    pkgs.umu-launcher
  ];
}
