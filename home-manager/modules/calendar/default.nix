{
  pkgs,
  config,
  ...
}:

# ---------------------------------------------------------------------------
# Nextcloud calendars + contacts -> local vdir, surfaced in khal/khard
# ---------------------------------------------------------------------------
# A CalDAV/CardDAV pipeline built on home-manager's `accounts.{calendar,contact}`
# registry: one account definition is consumed by both the sync engine and the
# CLI clients, so the server URL / user / local path are declared once.
#
#   pimsync  — sync engine. Pulls every calendar/addressbook collection under the
#              Nextcloud account into a local vdir (one subdir per collection).
#   khal     — reads the calendar vdir (status bar + `ikhal` editing).
#   khard    — reads the contact vdir (terminal address book).
#
# This is calendar/contact sync ONLY. It does NOT touch file sync — that stays
# with the `nextcloud-sync` module (`nextcloudcmd`, Nextcloud Files/WebDAV). The
# two are complementary: same server, different protocols.
#
# Secret: reuses the Nextcloud *app password* already provisioned for file sync
# (`age.secrets.nextcloud-cmd`, declared in ../nextcloud-sync). App passwords
# authenticate CalDAV/CardDAV too, so no new agenix file is needed. NOTE the
# dependency: this module relies on ../nextcloud-sync (same desktop bundle) to
# declare that secret and import the home-manager agenix module.
#
# Scheduling gotcha: neither the pimsync HM module nor the nixpkgs package ships
# a service/timer. pimsync's `interval` directive is daemon-only and inert under
# one-shot `sync`. So we drive a one-shot `pimsync sync` from a systemd-user
# timer, mirroring ../nextcloud-sync's service+timer pattern.

let
  ncUser = "dk";
  base = "https://nextcloud.dklaassen.de/remote.php/dav";

  # The agenix-home path string contains a literal $XDG_RUNTIME_DIR (decrypted
  # into a user tmpfs at session start); wrap in `sh -c` so it expands at runtime.
  passwordCommand = [
    "sh"
    "-c"
    ''exec cat "${config.age.secrets.nextcloud-cmd.path}"''
  ];

  # multiple calendars/addressbooks live under one account -> discover them all
  discoverAll = [
    {
      name = "collections";
      params = [ "all" ];
    }
  ];
in
{
  programs.pimsync.enable = true;
  programs.khal.enable = true;
  programs.khard.enable = true;

  # 24h HH:MM for khal's {start-time} (used by the i3status calendar block + ikhal)
  programs.khal.locale.timeformat = "%H:%M";

  accounts.calendar = {
    basePath = "${config.xdg.dataHome}/calendars";
    accounts.nextcloud = {
      primary = true;
      # khal's default_calendar for newly created events. Must name a discovered
      # collection subdir (not the account); `discover` still loads ALL collections.
      primaryCollection = "work";
      remote = {
        type = "caldav";
        url = "${base}/calendars/${ncUser}/";
        userName = ncUser;
        inherit passwordCommand;
      };
      # local defaults are filesystem + ".ics" at <basePath>/nextcloud
      pimsync = {
        enable = true;
        extraPairDirectives = discoverAll;
      };
      # `discover` globs the per-collection subdirs as separate khal calendars.
      khal = {
        enable = true;
        type = "discover";
      };
    };
  };

  accounts.contact = {
    basePath = "${config.xdg.dataHome}/contacts";
    accounts.nextcloud = {
      remote = {
        type = "carddav";
        url = "${base}/addressbooks/users/${ncUser}/";
        userName = ncUser;
        inherit passwordCommand;
      };
      # local defaults are filesystem + ".vcf" at <basePath>/nextcloud
      pimsync = {
        enable = true;
        extraPairDirectives = discoverAll;
      };
      khard.enable = true;
    };
  };

  # One-shot sync on a timer (pimsync provides no unit of its own). Order after
  # agenix.service so a boot-time run can't race app-password decryption.
  systemd.user.services.pimsync-sync = {
    Unit = {
      Description = "Sync Nextcloud calendars/contacts via pimsync";
      After = [ "agenix.service" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${pkgs.pimsync}/bin/pimsync sync";
    };
  };

  systemd.user.timers.pimsync-sync = {
    Unit.Description = "Periodic pimsync sync";
    Timer = {
      OnBootSec = "2m";
      OnUnitActiveSec = "5m";
      Persistent = true;
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
