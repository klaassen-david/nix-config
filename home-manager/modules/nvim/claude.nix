{ pkgs, inputs, ... }:
{
  programs.nixvim = {
    extraPlugins = [
      (pkgs.vimUtils.buildVimPlugin {
        name = "claudecode-nvim";
        src = inputs.claudecode-nvim;
      })
    ];

    plugins.snacks.enable = true;

    keymaps = [
      {
        key = "<leader>ac";
        action = "<cmd>ClaudeCode<cr>";
        options.desc = "Toggle Claude";
      }
      {
        key = "<leader>af";
        action = "<cmd>ClaudeCodeFocus<cr>";
        options.desc = "Focus Claude";
      }
      {
        key = "<leader>ar";
        action = "<cmd>ClaudeCode --resume<cr>";
        options.desc = "Resume Claude";
      }
      {
        key = "<leader>aC";
        action = "<cmd>ClaudeCode --continue<cr>";
        options.desc = "Continue Claude";
      }
      {
        key = "<leader>ab";
        action = "<cmd>ClaudeCodeAdd %<cr>";
        options.desc = "Add current buffer";
      }
      {
        key = "<leader>aa";
        action = "<cmd>ClaudeCodeDiffAccept<cr>";
        options.desc = "Accept diff";
      }
      {
        key = "<leader>ad";
        action = "<cmd>ClaudeCodeDiffDeny<cr>";
        options.desc = "Deny diff";
      }
      {
        key = "<leader>as";
        action = "<cmd>ClaudeCodeSend<cr>";
        mode = "v";
        options.desc = "Send selection";
      }
    ];

    extraConfigLua = ''
      require("claudecode").setup({
        terminal = {
          split_side = "right",
          split_width_percentage = 0.35,
          provider = "external",
          provider_opts = {
            external_terminal_cmd = "ghostty -e %s",
          },
          auto_close = true,
        },
        auto_start = true,
        track_selection = true,
        focus_after_send = false,
      })
    '';
  };
}
