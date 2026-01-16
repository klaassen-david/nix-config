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
        body = "nvim -S $argv";
      };

      nd = { body = "nix develop --command ${pkgs.fish}/bin/fish $argv"; };
      ns = { body = "nix-shell --command ${pkgs.fish}/bin/fish $argv"; };

      ls = { body = "exa $argv"; };
      la = { body = "exa -la $argv"; };
      l = { body = "exa -l $argv"; };
      ll = { body = "exa -l $argv"; };

      cat = { body = "bat $argv"; };

      # y = { body = ''
      #   function y
      #     set tmp (mktemp -t "yazi-cwd.XXXXXX")
      #     yazi $argv --cwd-file="$tmp"
      #     if read -z cwd < "$tmp"; and [ -n "$cwd" ]; and [ "$cwd" != "$PWD" ]
      #       builtin cd -- "$cwd"
      #     end
      #     rm -f -- "$tmp"
      #   end
      # ''; };
    };
  };

  home.packages = with pkgs; [
    fzf
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
}
