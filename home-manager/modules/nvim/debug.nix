{ pkgs, ... }:
let
  codelldb = "${pkgs.vscode-extensions.vadimcn.vscode-lldb}/share/vscode/extensions/vadimcn.vscode-lldb";
in
{
  programs.nixvim = {
    # from the project's devshell, decisions/nvim-lsp-closure.md
    dependencies.rust-analyzer.enable = false;

    plugins = {
      dap.enable = true;
      dap-lldb = {
        enable = true;
        settings.codelldb_path = "${codelldb}/adapter/codelldb";
      };
      dap-ui.enable = true;
      rustaceanvim = {
        enable = true;
        # autodetection only looks on PATH and in mason; codelldb is neither here
        settings.dap.adapter.__raw = ''
          require('rustaceanvim.config').get_codelldb_adapter(
            "${codelldb}/adapter/codelldb",
            "${codelldb}/lldb/lib/liblldb.so"
          )
        '';
      };
    };

    extraConfigLuaPost = ''
      -- dapui auto setup on dap events
      local dap, dapui = require("dap"), require("dapui")
      dap.listeners.before.attach.dapui_config = function()
        dapui.open()
      end
      dap.listeners.before.launch.dapui_config = function()
        dapui.open()
      end
      dap.listeners.before.event_terminated.dapui_config = function()
        dapui.close()
      end
      dap.listeners.before.event_exited.dapui_config = function()
        dapui.close()
      end
    '';
  };
}
