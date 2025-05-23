{ pkgs, lib, ... } :

{
  programs.fish = {
    enable = true;
    interactiveShellInit = ''
      set fish_greeting # disable greeting
    '';
    plugins = [
    ];

    functions = {
      nvims = {
        body = "nvim -S";
      };
    };
  };

  home.packages = with pkgs; [
    fzf
  ];

  programs.starship = {
    enable = true;
    enableFishIntegration = true;
  };
}
