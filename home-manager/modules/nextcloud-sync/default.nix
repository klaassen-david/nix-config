{
  pkgs,
  config,
  inputs,
  secretsPath,
  ...
}:
let
  serverUrl = "https://nextcloud.dklaassen.de";
  localDir = "${config.home.homeDirectory}/sync";
  ncUser = "dk";
  # decrypted app password — agenix-home decrypts it into $XDG_RUNTIME_DIR/agenix
  # (user tmpfs, mode 0400) via the per-user agenix.service. the path string still
  # contains the literal $XDG_RUNTIME_DIR, expanded at runtime in the script below.
  credPath = config.age.secrets.nextcloud-cmd.path;

  # flock so the timer and the file-watcher can never run two sync engines at
  # once (concurrent nextcloudcmd on one folder corrupts the sync journal).
  # fd 9 has no close-on-exec, so the lock is held for nextcloudcmd's lifetime.
  # the password is read here and handed to nextcloudcmd on argv: it already
  # sits decrypted at credPath, so argv adds only a transient same-uid exposure.
  syncScript = pkgs.writeShellScript "nextcloud-cmd-sync" ''
    set -euo pipefail
    exec 9>"$XDG_RUNTIME_DIR/nextcloud-cmd.lock"
    if ! ${pkgs.util-linux}/bin/flock -n 9; then
      echo "nextcloud sync already running, skipping" >&2
      exit 0
    fi
    exec ${pkgs.nextcloud-client}/bin/nextcloudcmd \
      --non-interactive --silent \
      -u ${ncUser} -p "$(cat ${credPath})" \
      ${localDir} ${serverUrl}
  '';
in
{
  imports = [ inputs.agenix.homeManagerModules.default ];

  # default identityPaths are id_ed25519/id_rsa; the shared user key is id_priv.
  age.identityPaths = [ "${config.home.homeDirectory}/.ssh/id_priv" ];
  age.secrets.nextcloud-cmd = {
    file = "${secretsPath}/nextcloud-cmd.age";
    mode = "0400";
  };

  systemd.user.services.nextcloud-cmd = {
    Unit = {
      Description = "Headless Nextcloud sync of ~/sync via nextcloudcmd";
      # agenix.service decrypts the app password into $XDG_RUNTIME_DIR at session
      # start; order after it so a boot-time sync never races the decryption.
      After = [ "agenix.service" ];
    };
    Service = {
      Type = "oneshot";
      ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p ${localDir}";
      ExecStart = "${syncScript}";
    };
  };

  # remote-side pulls: the watcher only fires on local changes, so a timer is
  # what brings down edits made on other devices.
  systemd.user.timers.nextcloud-cmd = {
    Unit.Description = "Periodic Nextcloud sync of ~/sync";
    Timer = {
      OnBootSec = "2m";
      OnUnitActiveSec = "5m";
      Persistent = true;
    };
    Install.WantedBy = [ "timers.target" ];
  };

  # local-side pushes: react quickly to local edits. the sync journal db is
  # rewritten on every sync, so it must be ignored or each sync retriggers itself.
  systemd.user.services.nextcloud-cmd-watch = {
    Unit.Description = "Watch ~/sync and trigger nextcloudcmd on change";
    Service = {
      ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p ${localDir}";
      ExecStart = ''
        ${pkgs.watchexec}/bin/watchexec \
          --watch ${localDir} --debounce 3s \
          --ignore '**/.sync_*.db*' \
          --ignore '**/._sync_*.db*' \
          --ignore '**/.owncloudsync.log*' \
          -- systemctl --user start nextcloud-cmd.service
      '';
      Restart = "on-failure";
    };
    Install.WantedBy = [ "default.target" ];
  };
}
