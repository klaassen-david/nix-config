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

      ls = { body = "exa"; };
      la = { body = "exa -la"; };
      l = { body = "exa -l"; };
      ll = { body = "exa -l"; };

      cat = { body = "bat"; };

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
    du-dust
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
