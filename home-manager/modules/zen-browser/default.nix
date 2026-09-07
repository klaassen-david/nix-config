{ inputs, ... }:

{
  imports = [
    inputs.zen-browser.homeModules.beta
  ];

  # Use DBus remoting so links opened from other apps hand off to the running
  # instance instead of trying to start a second one (which hits the profile
  # lock and fails with "Zen is already running but is not responding").
  home.sessionVariables.MOZ_DBUS_REMOTE = "1";

  programs.zen-browser = {
    enable = true;
    policies = {
      DisableAppUpdate = true;
    };
  };
}
