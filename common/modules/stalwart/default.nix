{
  config,
  lib,
  secretsPath,
  sslVhost,
  tlsCert,
  nextcloudSSO,
  ...
}:

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
  imports = [ ../nginx ];

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
      # Keys set here always shadow the web admin's database copy (local wins),
      # so declare them local: an edit in the UI then fails instead of being
      # silently ignored. Replaces Stalwart's default list, which is repeated.
      config.local-keys = [
        "store.*"
        "directory.*"
        "tracer.*"
        "!server.blocked-ip.*"
        "!server.allowed-ip.*"
        "server.*"
        "certificate.*"
        "authentication.fallback-admin.*"
        "cluster.*"
        "storage.data"
        "storage.blob"
        "storage.lookup"
        "storage.fts"
        "storage.directory"
        "enterprise.license-key"
        # set by this module or the nixpkgs one
        "webadmin.*"
        "spam-filter.resource"
        "resolver.*"
        "lookup.default.*"
        "session.auth.*"
        "session.rcpt.directory"
      ];

      # The web admin's Logs view only reads a file tracer's directory; the
      # journal tracer the nixpkgs module sets up is invisible to it.
      tracer.log = {
        type = "log";
        level = "info";
        path = "/var/log/stalwart";
        prefix = "stalwart.log";
        rotate = "daily";
        ansi = false;
        enable = true;
      };

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

      # PEMs are inlined at startup, so a renewal only takes effect on restart —
      # ../acme lists stalwart.service in reloadServices for exactly that.
      certificate.sectigo = {
        cert = "%{file:${tlsCert.fullchain}}%";
        private-key = "%{file:${tlsCert.key}}%";
      };

      lookup.default = {
        hostname = mailHostname;
        inherit domain;
      };

      session.auth = {
        mechanisms = "[plain, login]"; # Stalwart has no SCRAM
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

  # resolver.type = "system" reads resolv.conf once at startup; before DHCP it
  # is empty and pyzor/ASN lookups fail for the whole run.
  systemd.services.stalwart = {
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    # ProtectSystem=strict needs LogsDirectory for tracer.log to write.
    serviceConfig.LogsDirectory = "stalwart";
  };
  # Stalwart rotates logs but never prunes them.
  systemd.tmpfiles.rules = [ "e /var/log/stalwart - - - 14d" ];

  # ---------------------------------------------------------------------------
  # nginx — proxy web admin UI
  # ---------------------------------------------------------------------------
  # Gated by Nextcloud SSO (../nginx) like control/vpn: the admin UI can read
  # all mail and rewrite server config, so a password alone (with only
  # Stalwart's internal auto-ban behind it) must not be the only barrier.
  # Stalwart's own login still applies *after* the SSO gate. Mail protocols
  # (25/465/993) don't pass through nginx and are unaffected.

  services.nginx.virtualHosts."${mailHostname}" = lib.recursiveUpdate (sslVhost { } // nextcloudSSO) {
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
  # Brute-force protection
  # ---------------------------------------------------------------------------
  # No external fail2ban jail here: Stalwart has its own built-in auto-ban that
  # tracks auth failures across SMTP/IMAP/JMAP and drops connections at the
  # application layer (it does not touch the firewall). It also bans by account
  # name, not just IP. Configure thresholds under Settings -> Server -> Security
  # in the web admin (authBanRate / authBanPeriod); default is 100 failures/day.
  # External log-based fail2ban is unreliable here anyway — Stalwart logs auth
  # failures below the journal's default level, so there is nothing to match.
}
