{
  config,
  host,
  lib,
  ...
}:

let
  inherit (host.theme) nvim;
  stylixRendered = nvim.plugin == "mini.base16";
in
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

  stylix.targets.nixvim.enable = stylixRendered;

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
      signcolumn = "auto";
      numberwidth = 3;
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

      indent-blankline = {
        enable = true;
        # ibl copies LineNr into IblScope, background included
        luaConfig.pre = ''
          local hooks = require("ibl.hooks")
          hooks.register(hooks.type.HIGHLIGHT_SETUP, function()
            local fg = vim.api.nvim_get_hl(0, { name = "CursorLineNr", link = false }).fg
            vim.api.nvim_set_hl(0, "IblScope", { fg = fg })
          end)
        '';
      };
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

    colorschemes = lib.optionalAttrs (!stylixRendered) {
      ${nvim.plugin} = {
        enable = true;
        settings = nvim.settings or { };
      };
    };

    # nord.nvim and mini.base16 predate @variable.member, so fields would render as plain text
    highlightOverride."@variable.member".link = "@property";
  };
}
