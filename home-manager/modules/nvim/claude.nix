{ pkgs, inputs, ... }:
let
  claudeMap = key: command: desc: {
    inherit key;
    action = "<cmd>${command}<cr>";
    options.desc = desc;
  };
in
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
      (claudeMap "<leader>ac" "ClaudeCode" "Toggle Claude")
      (claudeMap "<leader>af" "ClaudeCodeFocus" "Focus Claude")
      (claudeMap "<leader>ar" "ClaudeCode --resume" "Resume Claude")
      (claudeMap "<leader>aC" "ClaudeCode --continue" "Continue Claude")
      (claudeMap "<leader>ab" "ClaudeCodeAdd %" "Add current buffer")
      (claudeMap "<leader>aa" "ClaudeCodeDiffAccept" "Accept diff")
      (claudeMap "<leader>ad" "ClaudeCodeDiffDeny" "Deny diff")
      (claudeMap "<leader>as" "ClaudeCodeSend" "Send selection" // { mode = "v"; })
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
