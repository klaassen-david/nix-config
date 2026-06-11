{
  config,
  pkgs,
  secretsPath,
  sslVhost,
  ...
}:

{
  imports = [ ../nginx ];

  age.secrets = {
    nextcloud-admin-pass = {
      file = "${secretsPath}/nextcloud-admin-pass.age";
      owner = "nextcloud";
      mode = "0400";
    };
    nextcloud-general = {
      file = "${secretsPath}/nextcloud-general.age";
      owner = "nextcloud";
      mode = "0400";
    };
  };

  # ---------------------------------------------------------------------------
  # Nextcloud
  # ---------------------------------------------------------------------------

  services.nextcloud = {
    enable = true;
    package = pkgs.nextcloud33; # pin to a major version; update deliberately
    secretFile = config.age.secrets.nextcloud-general.path;

    hostName = "nextcloud.dklaassen.de";
    https = true;

    config.dbtype = "pgsql";
    database.createLocally = true;

    # Admin credentials
    config = {
      adminuser = "admin";
      adminpassFile = config.age.secrets.nextcloud-admin-pass.path;
    };

    configureRedis = true;

    # Extra PHP / Nextcloud settings
    settings = {
      # Trusted proxies — nginx runs on the same host
      trusted_proxies = [
        "127.0.0.1"
        "::1"
      ];

      mail_smtpmode = "smtp";
      mail_smtphost = "127.0.0.1";
      mail_smtpport = 465;
      mail_smtpsecure = "ssl";
      mail_smtpauth = true;
      mail_smtpname = "nextcloud@dklaassen.de";
      mail_from_address = "nextcloud";
      mail_domain = "dklaassen.de";

      trusted_domains = [ "nextcloud.dklaassen.de" ];

      # Default phone region (used for contact validation)
      default_phone_region = "DE";

      # Nextcloud will warn without this
      overwriteprotocol = "https";
    };

    # PHP memory limit — 512 MB is Nextcloud's recommendation
    phpOptions."memory_limit" = "512M";

    # Extra apps installed declaratively.
    # The calendar app provides CalDAV at /remote.php/dav/
    extraApps = {
      inherit (config.services.nextcloud.package.packages.apps)
        calendar
        contacts
        mail
        ; # contacts pairs naturally with calendar (CardDAV)
    };
    extraAppsEnable = true;
  };

  # ---------------------------------------------------------------------------
  # nginx — Nextcloud vhosts
  # ---------------------------------------------------------------------------
  # The nginx base (enable, TLS hardening, shared cert, apex/catch-all vhosts)
  # lives in ../nginx; here we only add the Nextcloud-specific vhosts on top of
  # the shared `sslVhost` base.
  # services.nextcloud.nginx.enable = true (above) creates the vhost skeleton;
  # we extend it here with our certificate paths.

  services.nginx.virtualHosts."nextcloud.dklaassen.de" = sslVhost;

  # ---------------------------------------------------------------------------
  # Fail2ban — Nextcloud-specific jail
  # ---------------------------------------------------------------------------
  # Generic nginx jails + global ban settings live in ../nginx. This jail reads
  # Nextcloud login failures from the systemd journal (tag "Nextcloud").

  services.fail2ban.jails.nextcloud = {
    settings = {
      enabled = true;
      port = "80,443";
      filter = "nextcloud";
      backend = "systemd";
      journalmatch = "SYSLOG_IDENTIFIER=Nextcloud";
      maxretry = 3;
      bantime = "1h";
    };
  };

  # Fail2ban needs a filter definition for Nextcloud log format.
  # This teaches fail2ban what a failed Nextcloud login looks like in the log.
  environment.etc."fail2ban/filter.d/nextcloud.conf".text = ''
    [Definition]
    failregex = ^Login failed: '.*' \(Remote IP: '<HOST>'\).*$
    ignoreregex =
  '';
}
