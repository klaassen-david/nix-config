{ config, sslVhost, ... }:

# control.dklaassen.de: the phone_controller relay (~/uni/code/phone_controller
# on hermes), hot-swapped on olympus (../hot-swap, decisions/control.md). Builds
# happen on a desktop; a release is a static musl `bin/control` plus the phone
# UI in `share/phone_ui` (found next to the binary), rsynced to
# ~/deploy/control/releases/<v>/ and activated with
#   echo <v> > ~/deploy/control/want && systemctl start control-swap
# The binary honours LISTEN and answers GET /healthz with exactly <v>.
#
# Public, no SSO [USER 2026-10-15]: phones open join links without a Nextcloud
# login and games authenticate with API tokens (`control token create`, run as
# dk; stored hashed in ~/deploy/control/state). The relay binds loopback only,
# so nginx is the only door and no firewall hole is needed (sources = [ ]).
#
# Same-site with every SSO vhost: the browser sends the parent-domain
# oauth2-proxy cookie here too, so nginx strips Cookie/Set-Cookie and the page
# runs under a strict CSP. Join links are secrets in the path: no access log on
# the TLS vhost.
#
# Sandbox: the relay parses input from anyone holding a link and runs as dk, so
# the unit sees only its own deploy dir (state writable), no other part of
# home, no network beyond loopback. PrivatePIDs and no AF_UNIX: otherwise it
# could reach home through another dk process's /proc/<pid>/root, or the user
# bus. As PID 1 of its namespace it would ignore SIGTERM, hence SIGKILL.

let
  inherit ((import ../hot-swap/apps.nix).control) port;
  domain = "control.dklaassen.de";
  dir = "${config.users.users.dk.home}/deploy/control";
in
{
  imports = [
    ../hot-swap
    ../nginx
  ];

  hotSwap.apps.control = {
    inherit port;
    sources = [ ];
    proxyKey = false;
    environment = {
      LISTEN = "127.0.0.1:${toString port}";
      PUBLIC_HOST = domain;
    };
    serviceConfig = {
      ProtectHome = "tmpfs";
      BindReadOnlyPaths = [ dir ];
      BindPaths = [ "${dir}/state" ];
      ProtectSystem = "strict";
      PrivateTmp = true;
      PrivateDevices = true;
      NoNewPrivileges = true;
      CapabilityBoundingSet = "";
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
      ];
      IPAddressDeny = "any";
      IPAddressAllow = "localhost";
      SystemCallFilter = [ "@system-service" ];
      SystemCallArchitectures = "native";
      LockPersonality = true;
      MemoryDenyWriteExecute = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      RestrictNamespaces = true;
      RestrictSUIDSGID = true;
      MemoryMax = "256M";
      TasksMax = 64;
      PrivatePIDs = true;
      ProtectProc = "invisible";
      KillSignal = "SIGKILL";
      SystemCallErrorNumber = "EPERM";
      ProtectClock = true;
      ProtectKernelLogs = true;
      ProtectHostname = true;
      RestrictRealtime = true;
      UMask = "0077";
    };
  };

  services.nginx.virtualHosts.${domain} = sslVhost { } // {
    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString port}";
      proxyWebsockets = true;
      recommendedProxySettings = true;
      # websockets held open for a whole game; the relay pings every 10 s
      extraConfig = ''
        access_log off;
        proxy_set_header Cookie "";
        proxy_hide_header Set-Cookie;
        # any add_header here drops the server-level HSTS from sslVhost: repeat it
        add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
        add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'wasm-unsafe-eval'; style-src 'self' 'unsafe-inline'; connect-src 'self'; img-src 'self' data:; frame-ancestors 'none'; base-uri 'none'; form-action 'none'" always;
        add_header X-Content-Type-Options nosniff always;
        add_header Referrer-Policy no-referrer always;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
      '';
    };
  };
}
