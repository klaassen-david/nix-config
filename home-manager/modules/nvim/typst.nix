{ config, ... }:
{
  programs.nixvim = {
    # image.nvim's typst integration (on by default) needs this parser
    plugins.treesitter.grammarPackages = [
      config.programs.nixvim.plugins.treesitter.package.builtGrammars.typst
    ];

    plugins.lsp.servers = {
      tinymist.enable = true;
      # a project's tinymist wins over this one
      tinymist.packageFallback = true;
      tinymist.rootMarkers = [
        "tinymist.lock"
        "Session.vim"
        ".git"
      ];
      tinymist.settings = {
        formatterMode = "typstyle";
        exportPdf = "onType";
        semanticTokens = "disable";
        projectResolution = "lockDatabase";
      };
      # without override, the global onAttach would run twice: here and from LspAttach
      tinymist.onAttach.override = true;
      tinymist.onAttach.function = ''
        vim.keymap.set("n", "<leader>tp", function()
            client:exec_cmd({
                title = "pin",
                command = "tinymist.pinMainToCurrent",
                arguments = { vim.api.nvim_buf_get_name(0) },
            }, { bufnr = bufnr })
        end, { buf = bufnr, desc = "[T]inymist [P]in" })

        vim.keymap.set("n", "<leader>tu", function()
            client:exec_cmd({
                title = "unpin",
                command = "tinymist.pinMain",
                arguments = { vim.v.null },
            }, { bufnr = bufnr })
        end, { buf = bufnr, desc = "[T]inymist [U]npin" })

        vim.keymap.set("n", "<leader>to", "<cmd>OpenPdf<CR>",
          { buf = bufnr, desc = "[T]inymist [O]pen PDF" })
      '';
    };

    userCommands = {
      OpenPdf = {
        command.__raw = ''
          function()
            local filepath = vim.api.nvim_buf_get_name(0)
            if filepath:match("%.typ$") then
              local pdf_path = filepath:gsub("%.typ$", ".pdf")
              vim.system({ "xdg-open", pdf_path })
            end
          end
        '';
      };
    };
  };
}
