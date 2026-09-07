# Nextcloud data is deliberately not backed up

**Ruling** [USER 2026-08-31]: `common/modules/mail-backup` covers the stalwart
store only (`--host olympus --tag mail`); olympus's `/var/lib/nextcloud` and
its database are in **no** backup.

**Why**: the Nextcloud content is itself continuously synced down to the
desktops (`home-manager/modules/nextcloud-sync` → `~/sync`), so the
irreplaceable-state argument that justified the mail backup does not apply.
Mail is different — it exists nowhere but olympus.

**Accepted exposure**: server-side-only state (share links, app config,
calendars/contacts beyond the vdir mirror, anything never synced to a desktop)
is lost with the VPS disk, and a sync-propagated deletion has no history to
roll back to.

**Revisit if**: server-side-only state starts to matter (share links or app
config become load-bearing), or a second backup source makes adding one cheap.
