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
    # oauth2-proxy reads these via systemd LoadCredential (run as root before the
    # service drops privileges), so root-owned 0400 defaults are correct.
    oauth2-client-secret.file = "${secretsPath}/oauth2-client-secret.age";
    oauth2-cookie-secret.file = "${secretsPath}/oauth2-cookie-secret.age";
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
  # oauth2-proxy — SSO gate for control.dklaassen.de via Nextcloud
  # ---------------------------------------------------------------------------
  # Puts the control panel (proxied to :8080) behind Nextcloud login: an
  # unauthenticated request is bounced to Nextcloud, and only users who can log
  # in there get through. Any Nextcloud account passes (email.domains = "*");
  # the built-in OAuth2 provider has no group filtering.
  #
  # The nginx integration module auto-injects `auth_request` + the /oauth2/
  # endpoints into the existing control.dklaassen.de vhost defined above.
  #
  # One-time manual setup (the only non-declarative step):
  #   1. Nextcloud -> Settings -> Administration -> Security -> OAuth 2.0 clients:
  #      add a client (redirect URI https://control.dklaassen.de/oauth2/callback).
  #   2. Put the generated Client Identifier into `clientID` below.
  #   3. agenix-encrypt the generated Secret as oauth2-client-secret.age.
  #   4. agenix-encrypt a random cookie seed as oauth2-cookie-secret.age, e.g.:
  #        dd if=/dev/urandom bs=32 count=1 2>/dev/null | base64 | tr '+/' '-_'
  services.oauth2-proxy = {
    enable = true;
    provider = "nextcloud";

    clientID = "Q9BepF3akdtrdxIZfz7CSiEKzcjARdw4S44g9o4cJ0O53RkWPNFj3w4bOyCA0BUy";
    clientSecretFile = config.age.secrets.oauth2-client-secret.path;
    cookie.secretFile = config.age.secrets.oauth2-cookie-secret.path;

    loginURL = "https://nextcloud.dklaassen.de/index.php/apps/oauth2/authorize";
    redeemURL = "https://nextcloud.dklaassen.de/index.php/apps/oauth2/api/v1/token";
    validateURL = "https://nextcloud.dklaassen.de/ocs/v2.php/cloud/user?format=json";

    redirectURL = "https://control.dklaassen.de/oauth2/callback";

    email.domains = [ "*" ];
    setXauthrequest = true;
    reverseProxy = true;
    # Only nginx (localhost) may supply X-Forwarded-* headers; without this
    # oauth2-proxy trusts every source IP and the headers can be spoofed.
    trustedProxyIP = [
      "127.0.0.1"
      "::1"
    ];
    cookie.domain = "control.dklaassen.de";

    nginx = {
      domain = "control.dklaassen.de";
      virtualHosts."control.dklaassen.de" = { };
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
      # Reads Nextcloud login failures from the systemd journal.
      # Nextcloud logs via syslog (tag "Nextcloud") on NixOS.
      nextcloud = {
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

      # Catches repeated HTTP Basic Auth failures. nginx errors go to the
      # journal, so this uses the module's default systemd backend.
      nginx-http-auth = {
        settings = {
          enabled = true;
          port = "80,443";
          filter = "nginx-http-auth";
          maxretry = 5;
          bantime = "1h";
        };
      };

      # Bans on repeated nginx 4xx errors (catches scanners/bots).
      # Access logs go to a file, not the journal, so override the global
      # systemd backend to poll the file directly.
      nginx-botsearch = {
        settings = {
          enabled = true;
          port = "80,443";
          filter = "nginx-botsearch";
          backend = "polling";
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
    failregex = ^Login failed: '.*' \(Remote IP: '<HOST>'\).*$
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
