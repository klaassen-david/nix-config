{ lib, ... }:
let
  bufferMap = key: command: {
    mode = "n";
    inherit key;
    action = "<cmd>${command}<CR>";
  };
in
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
      (bufferMap "<C-Right>" "BufferNext")
      (bufferMap "<C-Left>" "BufferPrevious")
      (bufferMap "<C-c>" "BufferClose")
      (bufferMap "<C-s-w>" "BufferRestore")
      (bufferMap "<C-s-Left>" "BufferMovePrevious")
      (bufferMap "<C-s-Right>" "BufferMoveNext")
    ];
  };
}
