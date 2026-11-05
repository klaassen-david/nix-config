{ lib, host, ... }:

let
  # wg-easy clients, not in the mesh's config.vpn (common/implementers.nix)
  implementers = lib.filterAttrs (name: addr: addr != null && name != host.hostName) (
    import ../../../common/implementers.nix
  );
in
{
  programs.ssh = {
    enable = true;

    # config.local: hand-maintained, untouched by nix; listed first so its values win.
    # config.vpn: written by the mesh interface's postSetup and removed by postShutdown
    # (common/modules/wireguard): peer HostNames on the tunnel while `olympus` is up.
    includes = [
      "config.local"
      "config.vpn"
    ];

    enableDefaultConfig = false;

    settings = {
      "dklaassen.de olympus hestia hestia.local hermes hermes.local" = {
        PreferredAuthentications = "publickey,password";
        IdentityFile = host.sshIdentity;
        IdentitiesOnly = true;
      };

      "github.com" = {
        PreferredAuthentications = "publickey";
        IdentityFile = "~/.ssh/id_github";
        IdentitiesOnly = true;
      };

      "softech-git.informatik.uni-kl.de" = {
        PreferredAuthentications = "publickey";
        IdentityFile = "~/.ssh/tukl";
        IdentitiesOnly = true;
      };
    }
    // lib.mapAttrs (_: addr: {
      HostName = addr;
      PreferredAuthentications = "publickey";
      IdentityFile = host.sshIdentity;
      IdentitiesOnly = true;
    }) implementers;
  };
}
