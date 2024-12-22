{ config, pkgs, lib, ... }:

{
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    vimdiffAlias = true;

    extraPackages = with pkgs; [
      fd
      ripgrep
      fzf
      unzip
      unrar
      git
    ];

    extraLuaConfig = ''${lib.strings.fileContents ./init.lua}
    ''; # add newline

    plugins = with pkgs.vimPlugins; [
      nvim-treesitter.withAllGrammars 
      plenary-nvim
      fzf-lua

      telescope-fzf-native-nvim
      { plugin = telescope-nvim;
        type = "lua";
        config = ''
          local telescope_builtin = require('telescope.builtin')
          vim.keymap.set('n', '<leader>sf', telescope_builtin.find_files, { desc = 'Telescope find files' })
          vim.keymap.set('n', '<leader>sg', telescope_builtin.live_grep, { desc = 'Telescope live grep' })
          vim.keymap.set('n', '<leader>sb', telescope_builtin.buffers, { desc = 'Telescope buffers' })
          vim.keymap.set('n', '<leader>sh', telescope_builtin.help_tags, { desc = 'Telescope help tags' })
          require("telescope").setup {
            extensions = {
              fzf = {
                fuzzy = true,
                override_generic_sorter = true,
                override_file_sorter = true,
                case_mode = "smart_case",
              }
            }
          }
          require("telescope").load_extension("fzf")
        '';
      }

      { plugin = nvim-web-devicons;
        type = "lua";
        config = ''require("nvim-web-devicons").setup {}'';
      }

      { plugin = nvim-autopairs;
        type = "lua";
        config = ''require("nvim-autopairs").setup {}'';
      }

      { plugin = indent-blankline-nvim;
        type = "lua";
        config = ''require("ibl").setup {}'';
      }

      { plugin = guess-indent-nvim ;
        type = "lua";
        config = ''require("guess-indent").setup {}'';
      }

    ];
  };
}
