{
  config,
  lib,
  ...
}:

lib.mkIf config.host.capabilities.fingerprint (
  lib.mkMerge [
    {
      # fingerprint auth
      services.fprintd.enable = true;
      security.pam.services.sudo.fprintAuth = true;
      security.pam.services.login.fprintAuth = true;
      security.pam.services.swaylock.fprintAuth = true;

    }
  ]
)
