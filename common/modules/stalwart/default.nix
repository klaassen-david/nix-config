{ config, secretsPath, ... }:

let
  domain = "dklaassen.de";
  mailHostname = "mail.${domain}";
  adminAddr = "127.0.0.1";
  adminPort = 8418;
  adminBind = "${adminAddr}:${toString adminPort}";

  # Stalwart credential path helper
  cred = name: "%{file:/run/credentials/stalwart.service/${name}}%";
in
{
  # ---------------------------------------------------------------------------
  # Secrets
  # ---------------------------------------------------------------------------
  users.users.stalwart.extraGroups = [ "ssl-cert" ];

  age.secrets = {
    stalwart-admin-pass = {
      file = "${secretsPath}/stalwart-admin-pass.age";
      owner = "stalwart";
      mode = "0400";
    };
    stalwart-dk-pass = {
      file = "${secretsPath}/stalwart-dk-pass.age";
      owner = "stalwart";
      mode = "0400";
    };
    stalwart-nextcloud-pass = {
      file = "${secretsPath}/stalwart-nextcloud-pass.age";
      owner = "stalwart";
      mode = "0400";
    };
  };

  # ---------------------------------------------------------------------------
  # Stalwart
  # ---------------------------------------------------------------------------

  services.stalwart = {
    enable = true;
    openFirewall = false;
    stateVersion = "26.05";

    credentials = {
      admin-pass = config.age.secrets.stalwart-admin-pass.path;
      dk-pass = config.age.secrets.stalwart-dk-pass.path;
      nextcloud-pass = config.age.secrets.stalwart-nextcloud-pass.path;
    };

    settings = {
      global.tracing.level = "debug";

      webadmin = {
        resource = "file://${config.services.stalwart.package.webadmin}/webadmin.zip";
        path = "/var/cache/stalwart";
      };
      spam-filter.resource = "file://${config.services.stalwart.package}/etc/stalwart/spamfilter.toml";

      server = {
        hostname = mailHostname;

        tls = {
          enable = true;
          implicit = true;
          certificate = "sectigo";
        };

        listener = {
          smtp = {
            bind = "[::]:25";
            protocol = "smtp";
          };
          submissions = {
            bind = "[::]:465";
            protocol = "smtp";
            tls.implicit = true;
          };
          imaps = {
            bind = "[::]:993";
            protocol = "imap";
            tls.implicit = true;
          };
          management = {
            bind = [ adminBind ];
            protocol = "http";
          };
        };
      };

      certificate.sectigo = {
        cert = "%{file:${config.age.secrets.ssl-fullchain.path}}%";
        private-key = "%{file:${config.age.secrets.ssl-key.path}}%";
      };

      lookup.default = {
        hostname = mailHostname;
        domain = domain;
      };

      session.auth = {
        mechanisms = "[plain, login, scram-sha-256, scram-sha-512]";
        directory = "'db'";
      };

      store.db = {
        type = "sqlite";
        path = "/var/lib/stalwart/data/accounts.sqlite3";
      };

      store.blob = {
        type = "fs";
        path = "/var/lib/stalwart/data/blobs";
      };

      storage = {
        data = "db";
        fts = "db";
        blob = "blob";
        lookup = "db";
        directory = "db";
      };

      session.rcpt.directory = "'db'";

      directory."db" = {
        type = "internal";
        store = "db";
        principals = [
          {
            class = "individual";
            name = "dk";
            secret = cred "dk-pass"; # password from agenix, not in Nix store
            email = [
              "dk@${domain}"
              "info@${domain}"
              "postmaster@${domain}"
            ];
          }
          {
            class = "individual";
            name = "nextcloud";
            secret = cred "nextcloud-pass";
            email = [ "nextcloud@${domain}" ];
          }
        ];
      };

      authentication.fallback-admin = {
        user = "admin";
        secret = cred "admin-pass";
      };
    };
  };

  # ---------------------------------------------------------------------------
  # nginx — proxy web admin UI
  # ---------------------------------------------------------------------------

  services.nginx.virtualHosts."${mailHostname}" = {
    forceSSL = true;
    sslCertificate = config.age.secrets.ssl-fullchain.path;
    sslCertificateKey = config.age.secrets.ssl-key.path;

    locations."/" = {
      proxyPass = "http://${adminBind}";
      extraConfig = ''
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
      '';
    };
  };

  # ---------------------------------------------------------------------------
  # Firewall
  # ---------------------------------------------------------------------------

  networking.firewall.allowedTCPPorts = [
    25
    465
    993
  ];

  # ---------------------------------------------------------------------------
  # Fail2ban — brute-force protection for mail ports
  # ---------------------------------------------------------------------------
  # Reads Stalwart's systemd journal entries for authentication failures.
  # Verify the regex against `journalctl -u stalwart` after first deploy and
  # adjust if Stalwart's log format differs from the pattern below.

  services.fail2ban.jails.stalwart = {
    settings = {
      enabled = true;
      filter = "stalwart";
      backend = "systemd";
      journalmatch = "_SYSTEMD_UNIT=stalwart.service";
      port = "25,465,993";
      maxretry = 5;
      bantime = "1h";
    };
  };

  environment.etc."fail2ban/filter.d/stalwart.conf".text = ''
    [Definition]
    failregex = Authentication failed .* from <HOST>
    ignoreregex =
  '';
}
