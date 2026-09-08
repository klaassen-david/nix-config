# dk's password: per host, set with passwd

**Ruling** [USER 2026-09-08]: every host has its own dk password, set with
`passwd` after install. `initialHashedPassword` in `common/common.nix` stays
as the bootstrap value: without it a fresh host's account is locked, and
neither `sudo` nor `passwd` can be run over ssh to set one — that would need
the console or `nixos-enter`. The committed hash being public is accepted
because no live host still uses it.

**Rejected**: `hashedPasswordFile` from agenix (tried 2026-09-08, reverted the
same day). With `users.mutableUsers = true` the file is re-applied on every
activation, so one fleet secret would overwrite the three per-host passwords
with the same one, and `passwd` would stop sticking. A per-host secret copied
from each `/etc/shadow` would keep the passwords but not the `passwd` workflow.

**Revisit if**: a host's password is ever meant to be rotated declaratively,
or NixOS grows an `initialHashedPasswordFile`.
