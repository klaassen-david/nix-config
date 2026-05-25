{
  config,
  pkgs,
  lib,
  secretsPath,
  ...
}:

{
  users.groups.ssl-cert = { };
  users.users.nginx.extraGroups = [ "ssl-cert" ];

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
    ssl-fullchain = {
      file = "${secretsPath}/ssl-fullchain.age";
      group = "ssl-cert";
      mode = "0440";
    };
    ssl-key = {
      file = "${secretsPath}/ssl-key.age";
      group = "ssl-cert";
      mode = "0440";
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
  # nginx — TLS
  # ---------------------------------------------------------------------------
  # services.nextcloud.nginx.enable = true (above) creates the vhost skeleton;
  # we extend it here with our certificate paths.

  services.nginx = {
    enable = true;

    # Harden TLS — disable old protocols and weak ciphers
    sslProtocols = "TLSv1.2 TLSv1.3";
    sslCiphers = lib.concatStringsSep ":" [
      "ECDHE-ECDSA-AES128-GCM-SHA256"
      "ECDHE-RSA-AES128-GCM-SHA256"
      "ECDHE-ECDSA-AES256-GCM-SHA384"
      "ECDHE-RSA-AES256-GCM-SHA384"
      "ECDHE-ECDSA-CHACHA20-POLY1305"
      "ECDHE-RSA-CHACHA20-POLY1305"
    ];

    virtualHosts =
      let
        sslConfig = {
          forceSSL = true;

          sslCertificate = config.age.secrets.ssl-fullchain.path;
          sslCertificateKey = config.age.secrets.ssl-key.path;
        };
      in
      {
        "nextcloud.dklaassen.de" = sslConfig;
        "dklaassen.de" = sslConfig // {
          locations."/" = {
            extraConfig = "return 404; ";
          };
        };
        "control.dklaassen.de" = sslConfig // {
          locations."/" = {
            proxyPass = "http://127.0.0.1:8080/";
            proxyWebsockets = true;
            extraConfig = ''
              proxy_set_header Host              $host;
              proxy_set_header X-Real-IP         $remote_addr;
              proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
              proxy_set_header X-Forwarded-Proto $scheme;
              proxy_read_timeout                 3600s;
              proxy_send_timeout                 3600s;
            '';
          };
        };
        "_" = {
          default = true;
          extraConfig = ''
            return 444;
          '';
        };
      };
  };

  # ---------------------------------------------------------------------------
  # Firewall
  # ---------------------------------------------------------------------------
  # Only expose what is needed. SSH is included so you don't lock yourself out.

  networking.firewall = {
    enable = true;
    allowedTCPPorts = lib.mkOrder 1200 [
      80
      443
    ];
    # Port 80 is needed for the redirect to 443; nginx handles it automatically
    # when forceSSL = true.
  };

  # ---------------------------------------------------------------------------
  # Fail2ban — brute-force protection
  # ---------------------------------------------------------------------------
  # Reads nginx access logs and bans IPs that repeatedly fail Nextcloud logins.

  services.fail2ban = {
    enable = true;

    # Global ban settings
    maxretry = 5; # attempts before ban
    bantime = "1h"; # duration of ban

    jails = {
      # Nextcloud-specific jail — catches login failures logged by Nextcloud
      nextcloud = {
        settings = {
          enabled = true;
          port = "80,443";
          filter = "nextcloud";
          logpath = "/var/log/nginx/access.log";
          maxretry = 5;
          bantime = "1h";
        };
      };

      # Also ban on repeated nginx 4xx errors (catches scanners/bots)
      nginx-botsearch = {
        settings = {
          enabled = true;
          port = "80,443";
          filter = "nginx-botsearch";
          logpath = "/var/log/nginx/access.log";
          maxretry = 10;
          bantime = "24h";
        };
      };
    };
  };

  # Fail2ban needs a filter definition for Nextcloud log format.
  # This teaches fail2ban what a failed Nextcloud login looks like in the log.
  environment.etc."fail2ban/filter.d/nextcloud.conf".text = ''
    [Definition]
    failregex = ^<HOST>.*"(GET|POST).*\/login.*" (401|403) .*$
                ^.*Login failed: '.*' \(Remote IP: '<HOST>'\).*$
    ignoreregex =
  '';

  # ---------------------------------------------------------------------------
  # Logging
  # ---------------------------------------------------------------------------
  # Persist journals to disk so you can audit fail2ban hits and Nextcloud errors
  # across reboots.

  services.journald.extraConfig = ''
    Storage=persistent
    SystemMaxUse=500M
  '';
}
