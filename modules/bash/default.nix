{ pkgs, ... }:

{
  programs.bash = {
    enable = true;
    enableCompletion = true;
    bashrcExtra = "";
    shellAliases = {
      ns = "nix-shell";
      nd = "nix develop";
      l = "ls -l";
      ll = "ls -lA";
      la = "ls -la";
      nvims = "nvim -S";
    };
    initExtra = ''
      # if [[ -z ''${BASH_EXECUTION_STRING} ]]
      # then
      #   shopt -q login_shell && LOGIN_OPTION='--login' || LOGIN_OPTION=""
      #   exec ${pkgs.fish}/bin/fish $LOGIN_OPTION
      # fi
    '';
  };

  programs.direnv.nix-direnv.enable = true;
}
