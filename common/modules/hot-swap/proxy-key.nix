{ lib, ... }:

# The shared key between olympus's nginx (./vhosts.nix) and the hot-swapped apps
# on hestia (./default.nix); both sides read secrets/orch-proxy-key.age.
# decisions/hot-swap.md, "Proxy key".
{
  options.hotSwap.proxyKey = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = ''
      Shared proxy key: olympus's nginx sends it as X-Orch-Proxy-Key, the apps
      (TRUSTED_PROXY_KEY_FILE) trust a request from the hub only with it.
      Set it on olympus first, then on the app host.
    '';
  };
}
