# hestia: the mkForce on networkmanager.dns is real

**Ruling** [AGENT 2026-09-07]: `networking.networkmanager.dns = lib.mkForce
"none"` in `hestia/configuration.nix` stays. The 2026-08-31 audit claimed
nothing else defines the option; that was wrong — `services.resolved.enable =
true` makes nixpkgs' `resolved.nix` define it as `"systemd-resolved"`, and a
plain assignment fails the eval with conflicting definitions. Verified by
removing it (commit `fef4e91`, reverted in `682f916`); the comment in the
config now names the opponent.

**Revisit if**: hestia drops `services.resolved`, or the NM/resolved wiring in
nixpkgs changes.
