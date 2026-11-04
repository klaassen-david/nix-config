{ lib, ... }:
let
  pickerMap = key: picker: desc: {
    mode = "n";
    inherit key;
    action.__raw = "require('telescope.builtin').${picker}";
    options.desc = "LSP: ${desc}";
  };
in
{
  programs.nixvim = {
    plugins.fidget.enable = true;

    plugins.rustaceanvim.enable = true;
    # from the project's devshell, decisions/nvim-lsp-closure.md
    dependencies.rust-analyzer.enable = false;

    plugins.conform-nvim = {
      enable = true;
      settings = {
        format_on_save.lsp_format = "fallback";
        # from the project's devshell; ocamllsp formats when it is missing
        formatters_by_ft.ocaml = [ "ocamlformat" ];
      };
    };

    plugins.lsp = {
      enable = true;
      autoLoad = true;

      servers = {
        pyright.enable = true;
        nixd.enable = true;

        lua_ls = {
          enable = true;
          settings.completion.callSnippet = "Replace";
        };

        # package = null: from the project's devshell, decisions/nvim-lsp-closure.md
        omnisharp = {
          enable = true;
          package = null;
        };

        clangd = {
          enable = true;
          package = null;
        };

        elp.enable = true;

        ocamllsp = {
          enable = true;
          package = null;
        };

        texlab.enable = true;
        texlab.settings = {
          texlab = {
            rootDirectory = null;
            build = {
              executable = "nix";
              args = [ "build" ];
              onSave = true;
              forwardSearchAfter = true;
            };
            forwardSearch = {
              executable = "zathura";
              args = [
                "--synctex-forward"
                "%l:1:%f"
                "%p"
              ];
            };
            chktex = {
              onOpenAndSave = true;
              onEdit = false;
            };
            diagnosticsDelay = 300;
            latexFormatter = "latexindent";
            latexindent = {
              local = null;
              modifyLineBreaks = false;
            };
            bibtexFormatter = "texlab";
            formatterLineLength = 80;
          };
        };
      };

      keymaps = {
        diagnostic."<leader>q" = {
          action = "setloclist";
          desc = "Open diagnostic [Q]uickfix list";
        };

        extra = [
          {
            mode = "n";
            key = "<Right>d";
            action.__raw = ''
              function()
                vim.diagnostic.jump({ count = 1, on_jump = function(_, bufnr)
                  vim.diagnostic.open_float({ bufnr = bufnr, scope = "cursor", focus = false })
                end })
              end
            '';
            options.desc = "[->] [D]iagnostic";
          }
          {
            mode = "n";
            key = "<Left>d";
            action.__raw = ''
              function()
                vim.diagnostic.jump({ count = -1, on_jump = function(_, bufnr)
                  vim.diagnostic.open_float({ bufnr = bufnr, scope = "cursor", focus = false })
                end })
              end
            '';
            options.desc = "[<-] [D]iagnostic";
          }
          (pickerMap "gd" "lsp_definitions" "[G]oto [D]efinition")
          # shadows nvim's gr* defaults in LSP buffers; the maps here cover them
          (lib.recursiveUpdate (pickerMap "gr" "lsp_references" "[G]oto [R]eferences") {
            options.nowait = true;
          })
          (pickerMap "gI" "lsp_implementations" "[G]oto [I]mplementation")
          (pickerMap "<leader>D" "lsp_type_definitions" "Type [D]efinition")
          (pickerMap "<leader>ds" "lsp_document_symbols" "[D]ocument [S]ymbols")
          (pickerMap "<leader>ws" "lsp_dynamic_workspace_symbols" "[W]orkspace [S]ymbols")
        ];

        lspBuf = {
          "<leader>rn" = {
            action = "rename";
            desc = "LSP: [R]e[n]ame";
          };
          "<leader>c" = {
            action = "code_action";
            desc = "LSP: [C]ode Action";
          };
          "gD" = {
            action = "declaration";
            desc = "LSP: [G]oto [D]eclaration";
          };
        };
      };

      onAttach = ''
        if client and client:supports_method(vim.lsp.protocol.Methods.textDocument_documentHighlight) then
          local highlight_augroup = vim.api.nvim_create_augroup('kickstart-lsp-highlight', { clear = false })
          -- nixvim reruns this on every client/registerCapability
          vim.api.nvim_clear_autocmds({ group = highlight_augroup, buf = bufnr })
          vim.api.nvim_create_autocmd({ 'CursorHold', 'CursorHoldI' }, {
            buf = bufnr,
            group = highlight_augroup,
            callback = vim.lsp.buf.document_highlight,
          })

          vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
            buf = bufnr,
            group = highlight_augroup,
            callback = vim.lsp.buf.clear_references,
          })

          vim.api.nvim_create_autocmd('LspDetach', {
            group = vim.api.nvim_create_augroup('kickstart-lsp-detach', { clear = true }),
            callback = function(event2)
              vim.lsp.buf.clear_references()
              vim.api.nvim_clear_autocmds { group = 'kickstart-lsp-highlight', buf = event2.buf }
            end,
          })
        end

        if client and client:supports_method(vim.lsp.protocol.Methods.textDocument_inlayHint) then
          vim.keymap.set('n', '<leader>th', function()
            vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled { bufnr = bufnr })
          end, { buf = bufnr, desc = 'LSP: [T]oggle Inlay [H]ints' })
        end
      '';
    };
  };
}
