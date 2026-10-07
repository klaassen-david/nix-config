{ pkgs, lib, ... }:

{
  programs.ghostty = {
    enable = true;
    enableBashIntegration = true;
    enableFishIntegration = true;
    settings = {
      font-size = 16;
      background-opacity = 0.8;
      gtk-tabs-location = "hidden";
      keybind = [
        "ctrl+shift+w=unbind"
        # default toggle_fullscreen; alt+f does that too
        "ctrl+enter=unbind"
      ];
    };
  };

  # Every surface gets its own transient scope (linux-cgroup = single-instance),
  # and DefaultOOMPolicy=stop tears the whole scope down when the kernel
  # OOM-kills one process in it — losing the terminal because claude-code grew.
  # systemd searches the dash-truncated prefix dir, so this covers every
  # app-ghostty-surface-transient-<pid>.scope.
  xdg.configFile."systemd/user/app-ghostty-surface-transient-.scope.d/oom.conf".text = ''
    [Scope]
    OOMPolicy=continue
  '';
}
