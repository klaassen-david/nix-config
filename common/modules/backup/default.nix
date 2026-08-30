{
  config,
  lib,
  pkgs,
  secretsPath,
  ...
}:

# ---------------------------------------------------------------------------
# restic repository — the fleet's backup target
# ---------------------------------------------------------------------------
# One host (hestia) owns a single local restic repository; every backup job in
# the fleet writes into it with its own `--host`/`--tag`, and retention is
# applied per `--group-by host,tags` so a daily job can never evict another
# source's monthly snapshots. Mail (../mail-backup) is the first client; adding
# another source is a new timer pointing at this same repo, not a new repo —
# dedup is repository-wide, so overlapping data is stored once.
#
# Shared fate is the price: one password opens every snapshot in here, and
# repo-level damage hits all of them. `restic-repo check` is the counterweight.
#
# ---------------------------------------------------------------------------
# One-time bootstrap
# ---------------------------------------------------------------------------
# The repository password is an agenix secret you must create before the first
# deploy; nothing can decrypt an existing repo without it, so store it where it
# survives losing this host (it is not in the repo it protects):
#
#   1. cd secrets && agenix -e restic-repo-pass.age   # one line, the passphrase
#   2. git add -N secrets/restic-repo-pass.age        # or the flake won't see it
#
# `restic init` itself is not manual: the backup jobs create the repository on
# their first run if it does not exist yet.

let
  cfg = config.host.backup.restic;
in
{
  config = lib.mkIf cfg.enable {
    age.secrets.restic-repo-pass = {
      file = "${secretsPath}/restic-repo-pass.age";
      mode = "0400";
    };

    # 0700 root: snapshot contents are as sensitive as the mail they hold
    systemd.tmpfiles.rules = [ "d ${cfg.repository} 0700 root root -" ];

    # `restic-repo <args>` = restic against this repo, with the password wired
    # in — the interactive counterpart to the units in ../mail-backup, and the
    # only sane way to run snapshots/check/restore by hand. Needs root to read
    # the password file and the repo.
    #
    # RESTIC_CACHE_DIR is not optional: restic derives the cache from
    # $XDG_CACHE_HOME or $HOME, and systemd sets neither for a root service, so
    # without it every command that opens the repository aborts. ../mail-backup
    # exports the same value, keeping interactive and timed runs on one cache.
    environment.systemPackages = [
      (pkgs.writeShellApplication {
        name = "restic-repo";
        runtimeInputs = [ pkgs.restic ];
        text = ''
          export RESTIC_REPOSITORY=${cfg.repository}
          export RESTIC_PASSWORD_FILE=${config.age.secrets.restic-repo-pass.path}
          export RESTIC_CACHE_DIR=${cfg.cacheDir}
          exec restic "$@"
        '';
      })
    ];
  };
}
