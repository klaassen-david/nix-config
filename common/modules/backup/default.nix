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
# The host whose `host.backup.pull` is non-empty owns a single local restic
# repository; every source listed there writes into it with its own
# `--host`/`--tag`, and retention is applied per `--group-by host,tags` so one
# job can never evict another source's monthly snapshots. Mail (../mail-backup)
# is the first source; adding another is an entry in `sources` below plus a
# module that streams it, not a second repository — dedup is repository-wide,
# so overlapping data is stored once.
#
# Shared fate is the price: one password opens every snapshot in here, and
# repo-level damage hits all of them.
#
# Everything about the repository is fixed here rather than exposed per host:
# there is exactly one repo in the fleet, so path, retention and check schedule
# have nothing to vary against. The host struct only names the sources.
#
# ---------------------------------------------------------------------------
# Verification — the two ways a backup lies
# ---------------------------------------------------------------------------
# A repository nobody reads back is a guess, and it fails silently in two
# independent ways, so `restic-check.timer` tests for both and exits non-zero
# on either:
#
#   1. the repository rots — `restic check` walks the structure, and
#      --read-data-subset re-hashes a random tenth of the pack files each run,
#      so everything is re-read over ~10 weekly runs. Deliberately *without*
#      --with-cache: trusting the local metadata cache is exactly what would
#      hide a damaged index.
#   2. a job stops running — an abandoned repository passes `check` forever.
#      Each source declares how stale it may get (`maxAgeDays`), and the check
#      fails once the newest snapshot carrying its tags is older than that.
#
# Failures are never left to the journal alone. Every backup unit carries
# `alertHook`, so a failure runs backup-alert@ — desktop notification plus a
# stamp file under alertDir, which the next successful run of that unit
# removes. The stamp is what survives a failure nobody was logged in for; the
# sway bar polls that directory (home-manager/modules/sway/i3status-rust.nix).
# This is not optional and has no off switch: an alert you can disable per host
# is how a repository goes quietly stale.
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
  pull = config.host.backup.pull;
  enabled = pull != [ ];

  repository = "/var/backup/restic";
  # restic derives its cache from $XDG_CACHE_HOME or $HOME and systemd sets
  # neither for a root service, so the cache dir has to be named explicitly or
  # every command that opens the repository aborts.
  cacheDir = "/var/cache/restic";
  alertDir = "/var/lib/backup-alerts";

  retention = [
    "--keep-daily=7"
    "--keep-weekly=5"
    "--keep-monthly=12"
  ];

  # Where each pullable source lands in the repository, and how stale it may
  # get before the check calls it a failure. ../mail-backup consumes `flags`
  # for the write, so the writer and the freshness check cannot disagree about
  # the tag. mail: the pull needs a boot (OnBootSec) or a week of uptime to
  # fire, so a fortnight is the first age that is not just a quiet stretch.
  sources = {
    mail = {
      flags = "--host olympus --tag mail";
      maxAgeDays = 14;
    };
  };

  env = ''
    export RESTIC_REPOSITORY=${repository}
    export RESTIC_PASSWORD_FILE=${config.age.secrets.restic-repo-pass.path or ""}
    export RESTIC_CACHE_DIR=${cacheDir}
  '';

  # Merged into every backup unit (`lib.mkMerge [ backupRepo.alertHook {...} ]`):
  # a failure raises that unit's stamp, its next success clears it. %n/%N are
  # expanded by systemd, so one attrset serves every job.
  alertHook = {
    onFailure = [ "backup-alert@%n.service" ];
    serviceConfig.ExecStartPost = "-${pkgs.coreutils}/bin/rm -f ${alertDir}/%N";
  };

  alert = pkgs.writeShellApplication {
    name = "backup-alert";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.systemd
      pkgs.util-linux
    ];
    text = ''
      unit="''${1:?usage: backup-alert <unit>}"

      date -Is > "${alertDir}/''${unit%.service}"

      echo "$unit failed; last lines:" >&2
      journalctl -u "$unit" -n 20 --no-pager >&2 || true

      # Best effort — this only lands while dk has a session running a
      # notification daemon. The stamp above is the part that keeps working
      # when the machine backed up unattended.
      bus="/run/user/$(id -u dk)/bus"
      if [ -S "$bus" ]; then
        runuser -u dk -- env "DBUS_SESSION_BUS_ADDRESS=unix:path=$bus" \
          ${pkgs.libnotify}/bin/notify-send -u critical -a backup \
          "Backup failed" "$unit — systemctl status $unit" || true
      fi
    '';
  };

  freshnessChecks = lib.concatMapStrings (
    name:
    let
      s = sources.${name};
    in
    ''

      latest=$(restic snapshots --json --latest 1 ${s.flags} | jq -r '.[0].time // empty' || true)
      if [ -z "$latest" ]; then
        echo "${name}: no snapshot at all (${s.flags})" >&2
        fail=1
      else
        age=$(( ( $(date +%s) - $(date -d "$latest" +%s) ) / 86400 ))
        if [ "$age" -gt ${toString s.maxAgeDays} ]; then
          echo "${name}: newest snapshot is ''${age}d old, over the ${toString s.maxAgeDays}d limit" >&2
          fail=1
        else
          echo "${name}: newest snapshot ''${age}d old"
        fi
      fi
    ''
  ) pull;

  checkScript = pkgs.writeShellApplication {
    name = "restic-check-run";
    runtimeInputs = [
      pkgs.restic
      pkgs.jq
      pkgs.coreutils
    ];
    text = ''
      ${env}
      fail=0

      # --retry-lock rather than failing outright: this can collide with a
      # backup started 30 min into the same boot, which is not a fault.
      if ! restic check --retry-lock=15m --read-data-subset=10%; then
        echo "restic check reported repository damage" >&2
        fail=1
      fi
      ${freshnessChecks}
      exit "$fail"
    '';
  };
in
{
  config = lib.mkMerge [
    # Exported unconditionally: ../mail-backup takes this arg and is imported on
    # olympus too, where the repository itself is not enabled.
    {
      _module.args.backupRepo = {
        inherit
          env
          sources
          retention
          alertHook
          ;
      };
    }

    (lib.mkIf enabled {
      age.secrets.restic-repo-pass = {
        file = "${secretsPath}/restic-repo-pass.age";
        mode = "0400";
      };

      systemd.tmpfiles.rules = [
        # 0700 root: snapshot contents are as sensitive as the mail they hold
        "d ${repository} 0700 root root -"
        # unit names and timestamps only — readable so the bar can poll it
        "d ${alertDir} 0755 root root -"
      ];

      systemd.services."backup-alert@" = {
        description = "Announce the failed backup unit %i";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${lib.getExe alert} %i";
        };
      };

      systemd.services.restic-check = lib.mkMerge [
        alertHook
        {
          description = "Verify the restic repository and the age of its snapshots";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = lib.getExe checkScript;
            # re-hashing pack files is heavy and never urgent
            IOSchedulingClass = "idle";
            Nice = 10;
          };
        }
      ];

      # Persistent: the repository host is off half the time, so a weekly check
      # tied to the wall clock alone would mostly be skipped. RandomizedDelaySec
      # keeps the catch-up run out of the boot storm.
      systemd.timers.restic-check = {
        description = "Weekly restic repository check";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "weekly";
          Persistent = true;
          RandomizedDelaySec = "30m";
        };
      };

      # run a check by hand without sudo: systemctl start restic-check
      host.userManagedUnits = [ "restic-check.service" ];

      # `restic-repo <args>` = restic against this repo, with the password wired
      # in — the interactive counterpart to the units above and in ../mail-backup,
      # and the only sane way to run snapshots/check/restore by hand. Needs root
      # to read the password file and the repo.
      environment.systemPackages = [
        (pkgs.writeShellApplication {
          name = "restic-repo";
          runtimeInputs = [ pkgs.restic ];
          text = ''
            ${env}
            exec restic "$@"
          '';
        })
      ];
    })
  ];
}
