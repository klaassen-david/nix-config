{ ... }:

{
  programs.ssh = {
    enable = true;

    includes = [ "config.local" ];

    enableDefaultConfig = false;

    settings = {
      "dklaassen.de hestia hestia.local hermes hermes.local" = {
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
