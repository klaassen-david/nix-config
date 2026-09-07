# Password manager: Vaultwarden on olympus

**Ruling** [USER 2026-08-31]: self-host Vaultwarden on olympus, behind the
existing nginx wildcard vhost and agenix; Bitwarden clients + browser
extension point at it.

**Rejected**: KeePassXC-over-Nextcloud (`.kdbx` conflict copies instead of
real sync semantics); keeping Proton Pass as the primary.

**Open sub-decision**: whether Proton Pass leaves the desktop module at
cutover or stays as a second, unrelated vault.

**Revisit if**: Vaultwarden upstream stalls, or the Bitwarden clients stop
working against it. Build notes (vhost shape, no SSO gate on the API, admin
token secret) live with the TODO item.
