{
  config,
  ...
}:

{
  # Enabling fprintd is enough: nixpkgs defaults every PAM service's
  # `fprintAuth` to it, so sudo/login/swaylock all gain pam_fprintd.
  # Set unconditionally (no mkIf) so the capability flag can also *disable*
  # what nixos-hardware's framework-16 module turns on by mkDefault.
  services.fprintd.enable = config.host.capabilities.fingerprint;

  # Fingerprints are per-user enrollment state, not config: `fprintd-enroll`.
}
