# Nextcloud major version

**Ruling** [USER 2026-10-22]: olympus runs `pkgs.nextcloud35`, upgraded from 34
at 35.0.0 instead of waiting for a 35.0.x point release. `services.nextcloud.package`
stays an explicit pin; each major is a deliberate one-step bump (Nextcloud
cannot skip majors, and the schema migration has no downgrade).

**Rejected**: staying on 34 until 35.0.1/35.0.2 (the agent's suggestion) — 34
was still maintained, so this was about the nixpkgs "legacy install" warning and
keeping current, not a fix.

**Before each bump**: there is no Nextcloud backup
([nextcloud-not-backed-up](nextcloud-not-backed-up.md)), so take a database dump
and a copy of `/var/lib/nextcloud/config` on olympus first.

**Revisit if**: a `.0` major breaks the SSO login (oauth2) or a declared app —
then wait for a point release next time.
