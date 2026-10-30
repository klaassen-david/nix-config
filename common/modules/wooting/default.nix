{
  config,
  lib,
  pkgs,
  ...
}:

# Wooting keyboards are configured over hidraw, which is root-only by default;
# without these udev rules wootility starts but only shows its "demo" device.
# The rules apply on device add: replug after the first switch.
#
# hardware.wooting would install the same two packages, but wootility ships its
# own Mesa: on nvidia its Wayland backend never maps a window, so force XWayland.

let
  wootility =
    if config.host.gpu == "nvidia" then
      pkgs.symlinkJoin {
        name = "wootility-x11";
        paths = [ pkgs.wootility ];
        nativeBuildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          wrapProgram $out/bin/wootility --add-flags --ozone-platform=x11
        '';
      }
    else
      pkgs.wootility;
in
lib.mkIf config.host.capabilities.wooting {
  environment.systemPackages = [ wootility ];
  services.udev.packages = [ pkgs.wooting-udev-rules ];
}
