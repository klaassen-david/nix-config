{ config, ... }:

{
  imports = [
    ./completion.nix
    ./lsp.nix
    ./lean.nix
    ./markdown.nix
    ./claude.nix
    ./navigation.nix
    ./typst.nix
  ];

  programs.nixvim = {
    enable = true;
    defaultEditor = true;

    globals.mapleader = " ";

    opts = {
      number = true;
      relativenumber = true;
      shiftwidth = 4;
      tabstop = 2;

      breakindent = true;
      signcolumn = "yes";
      list = true;
      listchars = {
        tab = "» ";
        trail = "·";
        nbsp = "␣";
      };
      cursorline = true;
      scrolloff = 10;
      hlsearch = true;

      undofile = true;
      ignorecase = true;
      smartcase = true;
      updatetime = 250;
    };

    keymaps = [
      {
        mode = "n";
        key = "<ESC>";
        action = "<cmd>nohlsearch<CR>";
      }
      {
        mode = "n";
        key = "<C-s-c>";
        action = ''"+yy'';
        options.desc = "Yank line to system clipboard";
      }
      {
        mode = "v";
        key = "<C-s-c>";
        action = ''"+y'';
        options.desc = "Yank selection to system clipboard";
      }
    ];

    autoGroups = {
      kickstart-highlight-yank.clear = true;
    };

    autoCmd = [
      {
        event = [ "TextYankPost" ];
        desc = "Highlight when yanking text";
        group = "kickstart-highlight-yank";
        callback.__raw = ''
          function()
            vim.hl.on_yank()
          end
        '';
      }
      {
        event = [
          "BufRead"
          "BufNewFile"
        ];
        pattern = [ "*.age" ];
        desc = "Don't append a trailing newline to agenix secrets";
        command = "setlocal noeol nofixeol";
      }
    ];

    plugins = {
      lualine.enable = true;

      treesitter = {
        enable = true;
        # not pkgs.vimPlugins: those grammars ship upstream queries nvim has no handlers for
        grammarPackages = with config.programs.nixvim.plugins.treesitter.package.builtGrammars; [
          rust
          python
          nix
          toml
          json
          yaml
          html
          javascript
          erlang
          elixir
          vim
          vimdoc
          c
          lua
          markdown
          markdown_inline
          query
          agda
          bash
          c_sharp
          cmake
          make
          diff
          latex
          ocaml
        ];
        settings = {
          highlight.enable = true;
          indent.enable = true;
          incremental_selection.enable = true;
        };
      };

      indent-blankline.enable = true;
      guess-indent.enable = true;
      web-devicons.enable = true;
      nvim-autopairs.enable = true;
      transparent = {
        enable = true;
        autoLoad = true;
      };
      lazydev.enable = true;
      undotree.enable = true;
      mini-ai.enable = true;
    };

    userCommands = {
      Q = {
        command = "mks!|wqa";
      };
    };

    # stylix's base16 rendering on the desktops (home-manager/modules/theme);
    # olympus keeps the plugin
    colorschemes.nord.enable = !config.stylix.targets.nixvim.enable;

    # mini.base16 only knows the older @property, so fields would render as plain text
    highlightOverride."@variable.member".link = "@property";
  };
}
