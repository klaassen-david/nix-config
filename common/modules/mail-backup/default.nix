{
  config,
  lib,
  pkgs,
  backupRepo,
  ...
}:

# ---------------------------------------------------------------------------
# Mail backup — olympus's stalwart store into hestia's restic repository
# ---------------------------------------------------------------------------
# Pull, not push: hestia dials out 30 min after boot (it is the machine that is
# off half the time, so "30 min after *its* startup" is the only schedule that
# fires reliably), streams a stalwart dump over ssh, and files it in the local
# restic repo from ../backup as --host olympus --tag mail.
#
# Snapshot mechanism is stalwart's own `--export` / `--import`, which was
# verified against the live server: it runs with the service up, needs no
# downtime, and round-trips the fs blob store as well as the sqlite data store.
# It is also backend-portable, so a future sqlite -> postgres move does not
# invalidate old snapshots. The alternative — copying accounts.sqlite3 + blobs/
# by hand — is coupled to today's store layout for no gain.
#
# The channel is one forced-command ssh key. Verbs are named `<service>-<verb>`
# so a second service can be added to the same key without renaming these:
#
#   ssh root@olympus stalwart-export   ->  tar of a fresh dump on stdout
#   ssh root@olympus stalwart-import   ->  tar on stdin replaces the live store
#
# sshd runs `mail-backup-channel` no matter what the client asks for, so that
# key cannot get a shell, forward a port, or read anything else; the client's
# command arrives as data in $SSH_ORIGINAL_COMMAND. It reuses the existing
# id_priv key rather than minting a new one: id_priv is already the sole agenix
# recipient for the whole repo — it decrypts the mail passwords and the TLS key
# — so a key that can only dump mail adds no privilege it did not already have.
#
# Which side a host takes is not configured twice: the serving end keys on
# services.stalwart (only the host with the store can dump it), the pulling end
# on "mail" appearing in host.backup.pull.
#
# `stalwart-import` is destructive by nature. It never deletes: the live store
# is renamed to /var/lib/stalwart/data.bak-<timestamp> first, and put back if
# the import fails. Clean those out by hand once a restore is confirmed good.

let
  # the repository, its snapshot flags and the failure alert all come from
  # ../backup; this module only moves the bytes
  inherit (backupRepo) env alertHook retention;
  mail = backupRepo.sources.mail;

  # olympus's public ssh endpoint and host key. Both are public data and live
  # inline here like the wireguard peer pubkeys — pinning the key keeps the
  # unattended pull from ever falling back to trust-on-first-use.
  remote = "root@dklaassen.de";
  knownHosts = pkgs.writeText "olympus-known-hosts" ''
    dklaassen.de ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICC2ITqo7NHmJIn8Cgd3O5ezGJAmLSE/Srlq9l8Ix9io
  '';

  dataDir = "/var/lib/stalwart/data";

  # ---------------------------------------------------------------------------
  # olympus side
  # ---------------------------------------------------------------------------

  # Store-only config for the export/import runs, derived from the live
  # settings so the paths cannot drift out of sync with ../stalwart. The
  # generated service config is unusable here: it references
  # /run/credentials/stalwart.service/*, which resolves only inside the running
  # unit's namespace. Nothing secret is left in this one — it is stores only.
  storeConfig = (pkgs.formats.toml { }).generate "stalwart-store.toml" {
    store = config.services.stalwart.settings.store or { };
    storage = config.services.stalwart.settings.storage or { };
  };

  channel = pkgs.writeShellApplication {
    name = "mail-backup-channel";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnutar
      pkgs.util-linux
      pkgs.systemd
      config.services.stalwart.package
    ];
    text = ''
      work="$(mktemp -d /var/tmp/mail-backup.XXXXXXXX)"
      trap 'rm -rf "$work"' EXIT
      chown stalwart:stalwart "$work"
      chmod 0700 "$work"

      case "''${SSH_ORIGINAL_COMMAND:-}" in
        stalwart-export)
          # stalwart reports progress on stdout — keep it out of the tar stream
          runuser -u stalwart -- stalwart --config ${storeConfig} --export "$work" >&2
          # normalised metadata so an unchanged dump dedups against the last one
          tar -C "$work" --sort=name --owner=0 --group=0 --numeric-owner --mtime=@0 -cf - .
          ;;

        stalwart-import)
          tar -C "$work" -xf -
          chown -R stalwart:stalwart "$work"

          stamp="$(date +%Y%m%d-%H%M%S)"
          systemctl stop stalwart.service
          mv ${dataDir} ${dataDir}.bak-"$stamp"
          install -d -o stalwart -g stalwart -m 0700 ${dataDir}

          if runuser -u stalwart -- stalwart --config ${storeConfig} --import "$work" >&2; then
            systemctl start stalwart.service
            echo "restored; previous store kept at ${dataDir}.bak-$stamp" >&2
          else
            rm -rf ${dataDir}
            mv ${dataDir}.bak-"$stamp" ${dataDir}
            systemctl start stalwart.service
            echo "import failed; original store put back" >&2
            exit 1
          fi
          ;;

        *)
          echo "mail-backup: only 'stalwart-export' and 'stalwart-import' are accepted" >&2
          exit 1
          ;;
      esac
    '';
  };

  # ---------------------------------------------------------------------------
  # hestia side
  # ---------------------------------------------------------------------------

  ssh = "ssh -i /home/dk/.ssh/id_priv -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=${knownHosts} -o ConnectTimeout=15";

  backupScript = pkgs.writeShellApplication {
    name = "mail-backup-run";
    runtimeInputs = [
      pkgs.openssh
      pkgs.restic
      pkgs.coreutils
      pkgs.gnutar
    ];
    text = ''
      ${env}

      # first run of any job in the fleet creates the repository
      restic cat config >/dev/null 2>&1 || restic init

      work="$(mktemp -d -p /var/tmp mail-backup.XXXXXXXX)"
      trap 'rm -rf "$work"' EXIT

      # 30 min after boot the link is normally up, but a laptop-ish tower can
      # still be offline or olympus mid-reboot; retry before calling it a failure
      attempt=1
      until ${ssh} -o BatchMode=yes ${remote} stalwart-export > "$work/mail-export.tar"; do
        if [ "$attempt" -ge 3 ]; then
          echo "olympus unreachable after $attempt attempts" >&2
          exit 1
        fi
        attempt=$((attempt + 1))
        sleep 120
      done

      # a stream truncated by a dropped connection must never become a snapshot
      tar -tf "$work/mail-export.tar" >/dev/null

      # --retry-lock: restic-check (../backup) takes the repository lock
      # exclusively and both can be triggered by the same boot; waiting for it
      # is correct, failing the backup over it would be a false alarm.
      restic backup --retry-lock=30m --stdin --stdin-filename mail-export.tar \
        ${mail.flags} < "$work/mail-export.tar"

      restic forget --retry-lock=30m ${mail.flags} --group-by host,tags \
        ${lib.concatStringsSep " " retention} --prune
    '';
  };

  restoreScript = pkgs.writeShellApplication {
    name = "mail-restore";
    runtimeInputs = [
      pkgs.openssh
      pkgs.restic
      pkgs.coreutils
    ];
    text = ''
      ${env}

      snapshot="latest"
      confirmed=""
      while [ $# -gt 0 ]; do
        case "$1" in
          --snapshot) snapshot="''${2:?--snapshot needs an id}"; shift 2 ;;
          --yes)      confirmed="yes"; shift ;;
          *)          echo "usage: mail-restore [--snapshot ID] --yes" >&2; exit 1 ;;
        esac
      done

      if [ -z "$confirmed" ]; then
        echo "mail-restore replaces the LIVE mail store on olympus with snapshot '$snapshot'."
        echo "stalwart is stopped for the import and the current store is renamed to"
        echo "${dataDir}.bak-<timestamp> — nothing is deleted."
        echo
        restic snapshots ${mail.flags}
        echo
        echo "Re-run with --yes to proceed."
        exit 1
      fi

      restic dump "$snapshot" /mail-export.tar | ${ssh} ${remote} stalwart-import
    '';
  };
in
{
  # for `backupRepo` (the repository, its snapshot flags, the alert hook);
  # import-deduped, so olympus pulling it in through here as well as hestia
  # importing it directly is fine
  imports = [ ../backup ];

  config = lib.mkMerge [
    # --- olympus: expose the channel -------------------------------------
    # Keyed on running stalwart, not on a per-host flag: the host with the mail
    # store is the only one that can serve a dump of it, and a flag there could
    # only ever be set to match. Importing this module on a mail host is the
    # opt-in.
    (lib.mkIf config.services.stalwart.enable {
      users.users.root.openssh.authorizedKeys.keys = [
        ''command="${lib.getExe channel}",restrict ${lib.fileContents ../../keys/id_priv.pub}''
      ];

      # forced-commands-only is the narrow form: a root key without a command=
      # option is refused outright, so this permits the backup channel and
      # nothing else. Passwords are already off in headless.nix.
      services.openssh.settings = {
        PermitRootLogin = lib.mkForce "forced-commands-only";
        AllowUsers = [ "root" ];
      };
    })

    # --- hestia: pull on a timer + the restore CLI ------------------------
    (lib.mkIf (lib.elem "mail" config.host.backup.pull) {
      environment.systemPackages = [ restoreScript ];

      # alertHook: a failed pull is announced and flags itself until a later run
      # succeeds. How long a gap between successes is tolerated is ../backup's
      # call (sources.mail.maxAgeDays), since it is the check that notices.
      systemd.services.mail-backup = lib.mkMerge [
        alertHook
        {
          description = "Back up olympus's mail store into the restic repository";
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = lib.getExe backupScript;
          };
        }
      ];

      # OnBootSec is the requirement; OnUnitActiveSec keeps a machine that stays
      # up for weeks from going that long without a backup. Not Persistent= —
      # this is a boot timer, and a missed weekly is covered by the next boot.
      systemd.timers.mail-backup = {
        description = "Mail backup 30 min after boot";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "30min";
          OnUnitActiveSec = "1w";
        };
      };

      # run one by hand without sudo: systemctl start mail-backup
      host.userManagedUnits = [ "mail-backup.service" ];
    })
  ];
}
