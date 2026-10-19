{ ... }:

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
        IdentityFile = "~/.ssh/id_priv";
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
    };
  };
}
