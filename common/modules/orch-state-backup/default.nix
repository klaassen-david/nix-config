{
  config,
  lib,
  pkgs,
  backupRepo,
  ...
}:

# ---------------------------------------------------------------------------
# Agent-harness state — orchestrator/coordinator data into the restic repos
# ---------------------------------------------------------------------------
# A source of ../backup, filed as --host hestia --tag orch-state
# (backupRepo.sources.orch-state.flags) by every host that lists "orch-state"
# in host.backup.pull (hestia, hermes), each into its own repository, hourly
# and keeping the last two (sources.orch-state.retention).
#
# Hourly runs fall into hestia's 21:00-07:00 build window too
# (decisions/hot-swap.md, "Night window"), so each one is kept light: idle
# I/O class, an incremental restic run over ~300 MB, and `--prune` (the part
# that rewrites packs) at most once a day, and only between 07:00 and 21:00.
#
# What it covers (all dk-owned, on the node the apps run on, ../hot-swap/apps.nix;
# decisions/orch-state-backup.md):
#   ~/deploy/orchestrator/state   orchestrator.db, transcripts/, secrets/,
#                                 profiles/, agents/, backups/, gates/, merge/
#   ~/deploy/coordinator/state    coordinator.sqlite, tasks/, secrets/, backups/
#   ~/night/orchestrator/{state,logs}
#                                 the retired night kit's history, still read
#                                 by the orchestrator (ORCH_NIGHT_ROOT)
# secrets/ (admin token, account tokens) is included on purpose: the
# repositories are encrypted, and a restore without them is not a restore.
#
# Consistency: both databases run in WAL mode and are written while this runs,
# so the live .db/-wal/-shm triple is never copied (excluded below). Instead
# `orch-state-snapshot` (as dk) writes each one with `VACUUM INTO` to
# /var/lib/orch-state-snapshot: one read transaction, so a consistent single file however busy
# the writer is (the CLI's `.backup` steps 100 pages at a time and restarts on
# every concurrent write). A copy failing quick_check is never moved into
# place. The rest of the tree (transcripts, task logs) is append-mostly and
# taken as it is.
#
# Two roles, picked by whether the apps run here:
#   - the apps' node backs up its own files, snapshots included;
#   - any other puller (hermes) runs the snapshot on that node over ssh as dk
#     (id_priv, like mail), rsyncs the same set into /var/lib/orch-state-mirror (only the delta
#     crosses the mesh) and backs up the mirror. Switch the apps' node first:
#     the remote command is its /run/current-system/sw/bin/orch-state-snapshot.
#     An unreachable node is a skip (exit 75), not an alert: hermes is offline
#     as a matter of course, and ../backup's maxAgeDays catches a long gap.
#
# Restore (apps stopped: `systemctl stop orchestrator coordinator`):
#   sudo restic-repo restore latest --tag orch-state --target /tmp/orch-restore
#   copy the trees back under ~dk (from a puller's repo they sit under
#   /var/lib/orch-state-mirror), then the files in /var/lib/orch-state-snapshot/
#   over the live .db/.sqlite,
#   deleting any -wal/-shm.

let
  # the repository, its snapshot flags and the failure alert come from
  # ../backup; this module only gathers the files
  inherit (backupRepo) env alertHook;
  src = backupRepo.sources.orch-state;

  # both apps share one node (../hot-swap/apps.nix)
  node = (import ../hot-swap/apps.nix).orchestrator.node;
  isNode = config.host.hostName == node;
  nodeAddr = "10.100.0.${toString config.vpn.nodes.${node}.octet}";

  user = config.users.users.dk;
  deploy = "${user.home}/deploy";
  night = "${user.home}/night/orchestrator";

  # on the node: dk-owned, the latest consistent copy of each database
  snapDir = "/var/lib/orch-state-snapshot";
  # on a puller: root-owned rsync mirror, absolute paths kept (rsync -R)
  mirror = "/var/lib/orch-state-mirror";
  # last daily prune (StateDirectory below)
  pruneStamp = "/var/lib/orch-state-backup/last-prune";

  # live database per hot-swapped app: <deploy>/<app>/state/<file>
  databases = {
    orchestrator = "orchestrator.db";
    coordinator = "coordinator.sqlite";
  };
  dbPath = app: file: "${deploy}/${app}/state/${file}";

  paths = [
    "${deploy}/orchestrator/state"
    "${deploy}/coordinator/state"
    "${night}/state"
    "${night}/logs"
    snapDir
  ];

  # absolute patterns; restic and rsync -R both anchor them at /
  excludes =
    lib.concatLists (
      lib.mapAttrsToList (app: file: [
        (dbPath app file)
        "${dbPath app file}-*"
      ]) databases
    )
    ++ [
      # VACUUM INTO's in-progress copies
      "${snapDir}/.*"
      # claude's per-profile scratch: pasted-text and feature-flag caches
      "${deploy}/orchestrator/state/profiles/*/paste-cache"
      "${deploy}/orchestrator/state/profiles/*/statsig"
    ];
  excludeArgs = lib.concatMapStringsSep " " (e: "--exclude=${lib.escapeShellArg e}") excludes;

  snapshot = pkgs.writeShellApplication {
    name = "orch-state-snapshot";
    runtimeInputs = [
      pkgs.sqlite
      pkgs.coreutils
    ];
    text = ''
      if [ "$(id -un)" != dk ]; then
        echo "orch-state-snapshot runs as dk" >&2
        exit 1
      fi
    ''
    + lib.concatStrings (
      lib.mapAttrsToList (app: file: ''
        db=${lib.escapeShellArg (dbPath app file)}
        [ -f "$db" ] || { echo "${app}: $db is missing" >&2; exit 1; }
        # empty temp file: VACUUM INTO accepts one; renamed only once checked
        tmp=$(mktemp ${snapDir}/.${file}.XXXXXX)
        trap 'rm -f "$tmp"' EXIT
        sqlite3 -cmd '.timeout 60000' "$db" "VACUUM INTO '$tmp'"
        check=$(sqlite3 "$tmp" 'PRAGMA quick_check')
        [ "$check" = ok ] || { echo "${app}: snapshot failed quick_check: $check" >&2; exit 1; }
        mv -f "$tmp" ${snapDir}/${file}
      '') databases
    );
  };

  # olympus's host key is pinned in ../mail-backup; this one is hestia's
  knownHosts = pkgs.writeText "orch-node-known-hosts" ''
    ${nodeAddr} ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPIuarjxJW72kpLAPnfnU5lGbxGQBSKot8aimJiaGTIe
  '';
  ssh = "ssh -i /home/dk/.ssh/id_priv -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=${knownHosts} -o ConnectTimeout=15";

  gather =
    if isNode then
      ''
        runuser -u dk -- ${lib.getExe snapshot}
        set -- ${lib.escapeShellArgs paths}
      ''
    else
      ''
        rc=0
        ${ssh} dk@${nodeAddr} /run/current-system/sw/bin/orch-state-snapshot || rc=$?
        if [ "$rc" -eq 255 ]; then
          echo "${node} unreachable; skipped" >&2
          exit 75
        elif [ "$rc" -ne 0 ]; then
          exit "$rc"
        fi
        # rsync 24 = files vanished mid-transfer (agent churn): fine;
        # 255 = the link dropped: a skip, like the ssh above
        for p in ${lib.escapeShellArgs paths}; do
          rc=0
          rsync -aR -z --delete --delete-excluded -e ${lib.escapeShellArg ssh} ${excludeArgs} \
            "dk@${nodeAddr}:$p" ${mirror}/ || rc=$?
          case "$rc" in
            0 | 24) ;;
            255) echo "${node} dropped during rsync; skipped" >&2; exit 75 ;;
            *) exit "$rc" ;;
          esac
        done
        set -- ${mirror}
      '';

  backupScript = pkgs.writeShellApplication {
    name = "orch-state-backup-run";
    runtimeInputs = [
      pkgs.restic
      pkgs.coreutils
      pkgs.util-linux
      pkgs.openssh
      pkgs.rsync
      pkgs.findutils
    ];
    text = ''
      ${env}

      # first run of any job on this host creates its repository
      restic cat config >/dev/null 2>&1 || restic init

      ${gather}
      for p in "$@"; do
        [ -d "$p" ] || { echo "$p is missing" >&2; exit 1; }
      done

      # --retry-lock: the other backup job and restic-check share the lock.
      # Exit 3 = a file vanished between scan and read (agents churn their
      # dirs at any hour); the snapshot is still written, so warn, not fail.
      rc=0
      restic backup --retry-lock=30m ${src.flags} ${excludeArgs} "$@" || rc=$?
      if [ "$rc" -eq 3 ]; then
        echo "warning: some files could not be read; snapshot saved without them" >&2
      elif [ "$rc" -ne 0 ]; then
        exit "$rc"
      fi

      # forget hourly; prune (repacks) once a day, outside the build window
      prune=()
      hour=$(date +%-H)
      if [ "$hour" -ge 7 ] && [ "$hour" -lt 21 ] \
        && { [ ! -e ${pruneStamp} ] || [ -n "$(find ${pruneStamp} -mmin +1380)" ]; }; then
        prune=(--prune)
      fi
      restic forget --retry-lock=30m ${src.flags} --group-by host,tags \
        ${lib.concatStringsSep " " src.retention} "''${prune[@]}"
      [ "''${#prune[@]}" -eq 0 ] || touch ${pruneStamp}
    '';
  };
in
{
  # for `backupRepo`; import-deduped with the host's own import of ../backup
  imports = [ ../backup ];

  config = lib.mkMerge [
    # --- the apps' node: the snapshot command, for itself and the pullers
    (lib.mkIf isNode {
      environment.systemPackages = [ snapshot ];
      systemd.tmpfiles.rules = [ "d ${snapDir} 0700 dk ${user.group} -" ];
    })

    (lib.mkIf (lib.elem "orch-state" config.host.backup.pull) {
      systemd.tmpfiles.rules = lib.optional (!isNode) "d ${mirror} 0700 root root -";

      # alertHook: a failed run is announced and flags itself until a later run
      # succeeds; the tolerated gap is ../backup's sources.orch-state.maxAgeDays.
      systemd.services.orch-state-backup = lib.mkMerge [
        alertHook
        {
          description = "Back up orchestrator/coordinator state into the restic repository";
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = lib.getExe backupScript;
            SuccessExitStatus = 75;
            StateDirectory = "orch-state-backup";
            IOSchedulingClass = "idle";
            Nice = 10;
          };
        }
      ];

      # Persistent: a run missed while off or asleep happens at boot/resume
      systemd.timers.orch-state-backup = {
        description = "Hourly orchestrator/coordinator state backup";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          # pullers at :45, after the node's own run at :30
          OnCalendar = if isNode then "*:30" else "*:45";
          Persistent = true;
          RandomizedDelaySec = "5m";
        };
      };

      # run one by hand without sudo: systemctl start orch-state-backup
      host.userManagedUnits = [ "orch-state-backup.service" ];
    })
  ];
}
