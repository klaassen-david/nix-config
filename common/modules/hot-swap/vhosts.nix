{
  config,
  lib,
  secretsPath,
  sslVhost,
  nextcloudSSO,
  ...
}:

# orchestrator.dklaassen.de and coordinator.dklaassen.de: olympus's nginx in
# front of the hot-swapped apps (./apps.nix, both on hestia), over the mesh.
# VPN only, like the trainer: public A records to 10.100.0.1 plus the hosts
# entry in common.nix, the shared wildcard cert, nginx admits 10.100.0.0/16
# only. The app's port on its node accepts the hub alone (./default.nix).
#
# Live transcripts are SSE or websockets held open for hours: no buffering, 1 h
# timeouts. A node that is down or off the mesh fails fast (5 s connect).
#
# hotSwap.sso: these dashboards run code as dk and the VPN ACL admits every
# wg-easy phone. true puts the existing Nextcloud SSO gate (nextcloudSSO, the
# same as every other gated vhost) in front: any SSO-authenticated user, no
# group restriction [USER 2026-10-11]. The PWA manifest, service worker and
# icons stay outside the gate, because Chrome fetches the manifest without
# credentials.
#
# hotSwap.proxyKey (./proxy-key.nix): every proxied location also sends
# X-Orch-Proxy-Key, so the apps can tell this nginx from any other process on
# olympus. nginx needs the header as a directive, the secret holds the raw key:
# nginx-orch-proxy-key renders the include from the root-only secret before
# nginx starts; only nginx's master (root) reads it. proxy_set_header replaces
# any client-sent header of that name.

let
  apps = import ./apps.nix;
  sso = config.hotSwap.sso;
  proxyKey = config.hotSwap.proxyKey;
  keyAge = "${secretsPath}/orch-proxy-key.age";
  keyDir = "/run/nginx-orch-proxy-key";
  keyInclude = lib.optionalString proxyKey "include ${keyDir}/header.conf;";
  mesh = node: "10.100.0.${toString config.vpn.nodes.${node}.octet}";
  acl = ''
    allow 10.100.0.0/16;
    deny all;
  '';

  vhost =
    _: app:
    let
      upstream = "http://${mesh app.node}:${toString app.port}";
      root = {
        proxyPass = upstream;
        proxyWebsockets = true;
        recommendedProxySettings = true;
        extraConfig = ''
          ${acl}
          ${keyInclude}
          proxy_buffering off;
          proxy_connect_timeout 5s;
          proxy_read_timeout 1h;
          proxy_send_timeout 1h;
        '';
      };
      ungated = {
        proxyPass = upstream;
        recommendedProxySettings = true;
        extraConfig = ''
          ${acl}
          ${keyInclude}
          auth_request off;
        '';
      };
    in
    if !sso then
      sslVhost { } // { locations."/" = root; }
    else
      # "/" inherits the server-level `auth_request /oauth2/auth` (any account)
      lib.recursiveUpdate (sslVhost { } // nextcloudSSO) {
        locations = {
          "/" = root;
          "= /manifest.webmanifest" = ungated;
          "= /sw.js" = ungated;
          "/icons/" = ungated;
        };
      };
in
{
  imports = [
    ../nginx
    ./proxy-key.nix
  ];

  options.hotSwap.sso = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Nextcloud SSO (any authenticated user) in front of the hot-swap dashboards; false = VPN ACL only.";
  };

  config = lib.mkMerge [
    {
      services.nginx.virtualHosts = lib.mapAttrs' (
        name: app: lib.nameValuePair "${name}.dklaassen.de" (vhost name app)
      ) apps;
    }
    (lib.mkIf proxyKey {
      age.secrets.orch-proxy-key = {
        file = keyAge;
        mode = "0400";
      };

      systemd.services.nginx-orch-proxy-key = {
        description = "Render X-Orch-Proxy-Key for nginx from the agenix secret";
        before = [ "nginx.service" ];
        requiredBy = [ "nginx.service" ];
        restartTriggers = [ keyAge ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          UMask = "0077";
        };
        script = ''
          key=$(tr -d '[:space:]' < ${config.age.secrets.orch-proxy-key.path})
          if ! [[ $key =~ ^[A-Za-z0-9]{32,}$ ]]; then
            echo "orch-proxy-key: not 32+ alphanumerics" >&2
            exit 1
          fi
          install -d -m 0700 ${keyDir}
          printf 'proxy_set_header X-Orch-Proxy-Key "%s";\n' "$key" > ${keyDir}/header.conf.tmp
          mv -f ${keyDir}/header.conf.tmp ${keyDir}/header.conf
        '';
      };

      # a new key: re-render, then reload nginx
      systemd.services.nginx.reloadTriggers = [ keyAge ];
    })
  ];
}
