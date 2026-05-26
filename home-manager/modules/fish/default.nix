{ pkgs, lib, ... }:

{
  programs.fish = {
    enable = true;
    interactiveShellInit = ''
      set fish_greeting # disable greeting
      fish_vi_key_bindings
    '';
    plugins = [
      {
        name = "autopair";
        src = pkgs.fishPlugins.autopair;
      }
      {
        name = "fzf-fish";
        src = pkgs.fishPlugins.fzf-fish;
      }
    ];

    functions = {
      nvims = {
        body = "nvim -S $argv";
      };

      nd = {
        body = "nix develop $argv";
      };
      ns = {
        body = "nix-shell $argv";
      };

      ls = {
        body = "eza $argv";
      };
      la = {
        body = "eza -la $argv";
      };
      l = {
        body = "eza -l $argv";
      };
      ll = {
        body = "eza -l $argv";
      };

      cat = {
        body = "bat $argv";
      };

      mkcd = {
        body = "mkdir -p $argv && cd $argv";
      };
    };
  };

  home.packages = with pkgs; [
    bat
    eza
    dust
  ];

  programs.starship = {
    enable = true;
    enableFishIntegration = true;
  };

  programs.zoxide = {
    enable = true;
    enableFishIntegration = true;
  };

  programs.fzf = {
    enable = true;
    enableFishIntegration = true;
  };
}
