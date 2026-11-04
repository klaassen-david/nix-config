{ lib, ... }:
{
  programs.nixvim = {
    # barbar.nvim carries the JSON license, which nixpkgs counts as unfree
    nixpkgs.config.allowUnfreePredicate = pkg: lib.getName pkg == "barbar.nvim";

    plugins = {
      barbar.enable = true;
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
    };

    keymaps = [
      {
        mode = "n";
        key = "-";
        action = "<cmd>Oil<CR>";
      }
      {
        mode = "n";
        key = "<C-Right>";
        action = "<cmd>BufferNext<CR>";
      }
      {
        mode = "n";
        key = "<C-Left>";
        action = "<cmd>BufferPrevious<CR>";
      }
      {
        mode = "n";
        key = "<C-c>";
        action = "<cmd>BufferClose<CR>";
      }
      {
        mode = "n";
        key = "<C-s-w>";
        action = "<cmd>BufferRestore<CR>";
      }
      {
        mode = "n";
        key = "<C-s-Left>";
        action = "<cmd>BufferMovePrevious<CR>";
      }
      {
        mode = "n";
        key = "<C-s-Right>";
        action = "<cmd>BufferMoveNext<CR>";
      }
    ];
  };
}
