# nextcloud.nix
# Drop this file into your flake-based NixOS configuration and add it to your
# imports list. It assumes agenix is already wired into your flake inputs and
# that the encrypted secret files listed under age.secrets exist in your repo.
#
# Minimal flake.nix wiring reminder:
#
#   inputs.agenix.url = "github:ryantm/agenix";
#
#   nixosConfigurations.yourhost = nixpkgs.lib.nixosSystem {
#     modules = [
#       inputs.agenix.nixosModules.default
#       ./nextcloud.nix
#       # ... rest of your modules
#     ];
#   };

{
  config,
  pkgs,
  lib,
  ...
}:

{
  # ---------------------------------------------------------------------------
  # Secrets (agenix)
  # ---------------------------------------------------------------------------
  # Encrypt these files with:
  #   agenix -e secrets/nextcloud-admin-pass.age
  #   agenix -e secrets/ssl-fullchain.age
  #   agenix -e secrets/ssl-key.age
  #
  # Your secrets/secrets.nix should include your SSH public key and the
  # server's /etc/ssh/ssh_host_ed25519_key.pub as recipients for each secret.

  age.secrets = {
    nextcloud-admin-pass = {
      file = ./secrets/nextcloud-admin-pass.age;
      owner = "nextcloud";
      mode = "0400";
    };
    ssl-fullchain = {
      file = ./secrets/ssl-fullchain.age;
      owner = "nginx";
      mode = "0444";
    };
    ssl-key = {
      file = ./secrets/ssl-key.age;
      owner = "nginx";
      mode = "0400";
    };
  };

  # ---------------------------------------------------------------------------
  # Redis (caching + file locking)
  # ---------------------------------------------------------------------------
  # A Unix-socket Redis instance avoids opening a network port and is
  # measurably faster than TCP for local IPC.

  services.redis.servers.nextcloud = {
    enable = true;
    port = 0; # disable TCP; socket only
    unixSocket = "/run/redis-nextcloud/redis.sock";
    unixSocketPerm = 770;
  };

  # Redis socket must be readable by the nextcloud user
  users.users.nextcloud.extraGroups = [ "redis-nextcloud" ];

  # ---------------------------------------------------------------------------
  # Nextcloud
  # ---------------------------------------------------------------------------

  services.nextcloud = {
    enable = true;
    package = pkgs.nextcloud30; # pin to a major version; update deliberately

    hostName = "nextcloud.dklaassen.de";
    https = true;

    # Let Nextcloud manage nginx — the module creates a suitable vhost for you
    # and this avoids subtle mismatches with headers / PHP socket paths.
    nginx.enable = true;

    # Database
    config.dbtype = "pgsql";
    database.createLocally = true;

    # Admin credentials
    config = {
      adminuser = "admin";
      adminpassFile = config.age.secrets.nextcloud-admin-pass.path;
    };

    # Redis caching
    redis = {
      enable = true;
      unixSocket = config.services.redis.servers.nextcloud.unixSocket;
    };

    # Extra PHP / Nextcloud settings
    settings = {
      # Trusted proxies — nginx runs on the same host
      trusted_proxies = [
        "127.0.0.1"
        "::1"
      ];

      # Mail — fill in your SMTP details or remove this block
      # mail_smtpmode    = "smtp";
      # mail_smtphost    = "smtp.dklaassen.de";
      # mail_smtpport    = 587;
      # mail_smtpauthtype = "LOGIN";

      # Recommended: restrict access to local subnet during setup,
      # then expand or remove once you're happy.
      # trusted_domains = [ "nextcloud.dklaassen.de" ];

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

    # Security headers applied to all vhosts
    appendHttpConfig = ''
      add_header X-Content-Type-Options  "nosniff"            always;
      add_header X-Frame-Options         "SAMEORIGIN"         always;
      add_header X-XSS-Protection        "1; mode=block"      always;
      add_header Referrer-Policy         "strict-origin-when-cross-origin" always;
    '';

    virtualHosts."nextcloud.dklaassen.de" = {
      forceSSL = true;

      # certs — paths resolve to /run/agenix/... at runtime
      sslCertificate = config.age.secrets.ssl-fullchain.path;
      sslCertificateKey = config.age.secrets.ssl-key.path;

      # HSTS — only enable once you're confident TLS is working correctly.
      # Start with a short max-age (300 s) during testing, then ramp up.
      extraConfig = ''
        add_header Strict-Transport-Security "max-age=300; includeSubDomains" always;
      '';
    };
  };

  # ---------------------------------------------------------------------------
  # Firewall
  # ---------------------------------------------------------------------------
  # Only expose what is needed. SSH is included so you don't lock yourself out.

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [
      22
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
    findtime = "10m"; # window in which maxretry must occur

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

