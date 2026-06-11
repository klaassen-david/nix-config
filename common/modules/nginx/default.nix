{
  config,
  lib,
  secretsPath,
  ...
}:

let
  # reusable forceSSL + shared-cert vhost base; exported below as a module arg
  sslVhost = {
    forceSSL = true;
    sslCertificate = config.age.secrets.ssl-fullchain.path;
    sslCertificateKey = config.age.secrets.ssl-key.path;
  };

  # Per-vhost Nextcloud-SSO gate; exported below as a module arg. Spreading this
  # into a vhost makes every request pass through oauth2-proxy first: an
  # unauthenticated request 307s to auth.dklaassen.de, logs in via Nextcloud,
  # and returns. It mirrors what the nixpkgs oauth2-proxy-nginx integration
  # injects, but as a value consumers opt into explicitly (like sslVhost).
  #
  # `locations` here collides with the consumer's own `locations."/"` under a
  # shallow `//`, so combine with lib.recursiveUpdate, NOT //:
  #   "host" = lib.recursiveUpdate (sslVhost // nextcloudSSO) {
  #     locations."/" = { proxyPass = "..."; };
  #   };
  nextcloudSSO = {
    extraConfig = ''
      auth_request /oauth2/auth;
      error_page 401 = @redirectToAuth2ProxyLogin;
    '';
    locations."@redirectToAuth2ProxyLogin".extraConfig = ''
      return 307 https://auth.dklaassen.de/oauth2/start?rd=$scheme://$host$request_uri;
    '';
    locations."= /oauth2/auth" = {
      proxyPass = "http://127.0.0.1:4180";
      extraConfig = ''
        auth_request      off;
        proxy_set_header  X-Scheme                 $scheme;
        proxy_set_header  X-Auth-Request-Redirect  $scheme://$host$request_uri;
        proxy_set_header  Content-Length           "";
        proxy_pass_request_body                     off;
      '';
    };
  };
in
{
  # ---------------------------------------------------------------------------
  # Shared TLS material
  # ---------------------------------------------------------------------------
  # One wildcard/SAN cert shared by every vhost (nextcloud, stalwart, ...).
  # nginx reads it via the ssl-cert group.
  users.groups.ssl-cert = { };
  users.users.nginx.extraGroups = [ "ssl-cert" ];

  age.secrets = {
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

  # Consumers (nextcloud, stalwart, ...) take `sslVhost` / `nextcloudSSO` as
  # module args and spread them into their own vhost attrset:
  #   "host" = sslVhost // { ... };                                 (TLS only)
  #   "host" = lib.recursiveUpdate (sslVhost // nextcloudSSO) {...}; (TLS + SSO)
  _module.args.sslVhost = sslVhost;
  _module.args.nextcloudSSO = nextcloudSSO;

  # ---------------------------------------------------------------------------
  # nginx base
  # ---------------------------------------------------------------------------
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

    virtualHosts = {
      # apex serves nothing
      "dklaassen.de" = sslVhost // {
        locations."/".extraConfig = "return 404;";
      };
      # drop connections to unknown host names
      "_" = {
        default = true;
        extraConfig = "return 444;";
      };
      # dedicated SSO login/callback host fronting oauth2-proxy. Every protected
      # vhost (control, vpn, ...) bounces unauthenticated requests here.
      "auth.dklaassen.de" = sslVhost // {
        locations."/oauth2/" = {
          proxyPass = "http://127.0.0.1:4180";
          extraConfig = ''
            proxy_set_header Host                    $host;
            proxy_set_header X-Real-IP               $remote_addr;
            proxy_set_header X-Scheme                $scheme;
            proxy_set_header X-Auth-Request-Redirect $request_uri;
          '';
        };
      };
    };
  };

  # ---------------------------------------------------------------------------
  # oauth2-proxy — shared Nextcloud SSO gate
  # ---------------------------------------------------------------------------
  # One proxy guards every vhost that spreads in `nextcloudSSO`. An
  # unauthenticated request is bounced to Nextcloud login; any Nextcloud account
  # passes (email.domains = "*"; the built-in OAuth2 provider has no group
  # filtering). The session cookie is set on the parent domain so a single login
  # covers control / vpn / any future subdomain.
  #
  # One-time manual setup (the only non-declarative step):
  #   1. Nextcloud -> Settings -> Administration -> Security -> OAuth 2.0 clients:
  #      add a client (redirect URI https://auth.dklaassen.de/oauth2/callback).
  #   2. Put the generated Client Identifier into `clientID` below.
  #   3. agenix-encrypt the generated Secret as oauth2-client-secret.age.
  #   4. agenix-encrypt a random cookie seed as oauth2-cookie-secret.age, e.g.:
  #        dd if=/dev/urandom bs=32 count=1 2>/dev/null | base64 | tr '+/' '-_'
  services.oauth2-proxy = {
    enable = true;
    provider = "nextcloud";

    clientID = "iGHtPJSIZg11CyRE21FKVk8nH8JLiRLKTxGJ3lZ6KYLwsaUYqOCT3d2brSiZddY5";
    clientSecretFile = config.age.secrets.oauth2-client-secret.path;
    cookie.secretFile = config.age.secrets.oauth2-cookie-secret.path;

    loginURL = "https://nextcloud.dklaassen.de/index.php/apps/oauth2/authorize";
    redeemURL = "https://nextcloud.dklaassen.de/index.php/apps/oauth2/api/v1/token";
    validateURL = "https://nextcloud.dklaassen.de/ocs/v2.php/cloud/user?format=json";

    redirectURL = "https://auth.dklaassen.de/oauth2/callback";

    email.domains = [ "*" ];
    setXauthrequest = true;
    reverseProxy = true;
    # Only nginx (localhost) may supply X-Forwarded-* headers; without this
    # oauth2-proxy trusts every source IP and the headers can be spoofed.
    trustedProxyIP = [
      "127.0.0.1"
      "::1"
    ];
    # Parent-domain cookie so one login is shared across all *.dklaassen.de
    # vhosts; whitelist-domain allows the post-login `rd=` back to those subdomains.
    cookie.domain = ".dklaassen.de";
    extraConfig.whitelist-domain = ".dklaassen.de";
  };

  # ---------------------------------------------------------------------------
  # Firewall
  # ---------------------------------------------------------------------------
  # Port 80 is needed for the redirect to 443; nginx handles it automatically
  # when forceSSL = true.
  networking.firewall.allowedTCPPorts = lib.mkOrder 1200 [
    80
    443
  ];

  # ---------------------------------------------------------------------------
  # Fail2ban — generic nginx jails
  # ---------------------------------------------------------------------------
  # Service-specific jails (e.g. the Nextcloud login filter) live with their
  # service module.
  services.fail2ban = {
    enable = true;
    maxretry = 5;
    bantime = "1h";

    jails = {
      # Repeated HTTP Basic Auth failures. nginx errors go to the journal, so
      # this uses the module's default systemd backend.
      nginx-http-auth = {
        settings = {
          enabled = true;
          port = "80,443";
          filter = "nginx-http-auth";
          maxretry = 5;
          bantime = "1h";
        };
      };

      # Repeated nginx 4xx errors (scanners/bots). Access logs go to a file, not
      # the journal, so poll the file directly.
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

  # ---------------------------------------------------------------------------
  # Logging
  # ---------------------------------------------------------------------------
  # Persist journals to disk so you can audit fail2ban hits and service errors
  # across reboots.
  services.journald.extraConfig = ''
    Storage=persistent
    SystemMaxUse=500M
  '';
}
