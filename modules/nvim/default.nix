{ config, pkgs,  ... }:

{
  imports = [
    ./plugins/nvim-cmp.nix
    ./plugins/lsp.nix
  ];

  programs.nixvim = {
    enable = true;
    defaultEditor = true;

    globals = {
      mapleader = " ";
      have_nerd_font = true;
    };
    
    opts = {
      number = true;
      relativenumber = true;
      shiftwidth = 4;

      clipboard.register = "unnamedplus";

      breakindent = true;
      signcolumn = "yes";
      list = true;
      listchars.__raw = "{ tab = '» ', trail = '·', nbsp = '␣' }";
      cursorline = true;
      scrolloff = 10;
      hlsearch = true;

      undofile = true;
      ignorecase = true;
      smartcase = true;
    };

    keymaps = [
      { mode = "n";
        key = "<ESC>";
        action = "<cmd>nohlsearch<CR>";
      }
      { mode = "n";
        key = "<C-Right>";
        action = "<cmd>tabnext<CR>";
      }
      { mode = "n";
        key = "<C-Left>";
        action = "<cmd>tabprevious<CR>";
      }
    ];

    autoGroups = {
      kickstart-highlight-yank.clear = true;
    };

    autoCmd = [
      { event = ["TextYankPost"];
        desc = "Highlight when yanking text";
        group = "kickstart-highlight-yank";
        callback.__raw = ''
          function()
            vim.highlight.on_yank()
          end
        '';
      }
    ];

    plugins = {
      lualine.enable = true;

      lsp = {
        enable = true;
        servers = { 
          lua_ls.enable = true;
        };
      };

      luasnip.enable = true;

      telescope = {
        enable = true;
        extensions.fzf-native.enable = true;
        keymaps = {
          "<leader>sf" = "find_files";
          "<leader>sg" = "live_grep";
          "<leader>sb" = "buffers";
          "<leader>sh" = "help_tags";
        };
      };

      oil.enable = true;
      treesitter.enable = true;
      comment.enable = true;
      indent-blankline.enable = true;
      guess-indent.enable = true;
      sleuth.enable = true;
      web-devicons.enable = true;
    };
  };
}
