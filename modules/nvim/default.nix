{ config, pkgs,  ... }:

{
  programs.nixvim = {
    enable = true;
    defaultEditor = true;
    globals.mapleader = " ";
    
    # options = {
    #   number = true;
    #   relativenumber = true;
    #   shiftwidth = 4;
    # };

    plugins = {
      lualine.enable = true;

      lsp = {
        enable = true;
        servers = { 
          lua_ls.enable = true;
          rust_analyzer = {
            enable = true;
            installCargo = true;
            installRustc = true;
          };
          pyright.enable = true;
        };
      };

      luasnip.enable = true;
      cmp = {
        enable = true;
        autoEnableSources = true;
        settings = {
          sources = [
            { name = "nvim_lsp";}
            { name = "luasnip";}
            { name = "path";}
            { name = "buffer";}
          ];

          # mapping = {
          #   "<CR>" = "cmp.mapping.confirm({ select = true })";
          #   "<Tab>" = ''
          #     function(fallback)
          #       if cmp.visible() then
          #         cmp.select_next_item()
          #       elseif luasnip.exandable() then
          #         luasnip.expand()
          #       elseif luasnip.expand_or_jumpable() then
          #         luasnip.expand_or_jump()
          #       elseif check_backspace() then
          #         fallback()
          #       else 
          #         fallback()
          #       end
          #   '';
            # };
        };
      };

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
      web-devicons.enable = true;
    };
  };
}
