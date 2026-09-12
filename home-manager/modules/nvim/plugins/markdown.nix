{ pkgs, ... }:
# Markdown stack, one concern each:
#   render-markdown  in-buffer prettifying (headings, code blocks, tables, checkboxes)
#   nabla            ASCII-art rendering of the LaTeX equation under the cursor
#   image            real images, via the terminal's graphics protocol
#   mkdnflow         links, tables, lists, to-dos, section folding
#   otter            LSP inside fenced code blocks
#
# Four things are not self-evident:
# - image.nvim's kitty backend needs a terminal that speaks the graphics protocol.
#   ghostty does; zellij does not, so images disappear when nvim runs inside it.
# - render-markdown's latex module shells out to `utftex` or `latex2text`. nixpkgs has
#   only the latter, in python3Packages.pylatexenc. Without it, math is left as source.
# - otter activates from `lsp.onAttach`, which never fires in a markdown buffer (no
#   markdown server), so a FileType autocmd does it instead. It surfaces the servers
#   already configured in ./lsp.nix (nixd, pyright, lua_ls, clangd, …) inside fences.
# - mkdnflow's table-align maps default to <leader>a{l,r,c}, colliding with the Claude
#   maps in ../default.nix; moved under <leader>t. Every other mkdnflow map is
#   buffer-local to markdown, so the rest of the config is unaffected.
{
  programs.nixvim = {
    extraPackages = [ pkgs.python3Packages.pylatexenc ];

    plugins = {
      render-markdown = {
        enable = true;
        settings = {
          heading.border = true;
          code = {
            width = "block";
            left_pad = 2;
            right_pad = 2;
          };
          signs.enabled = false;
        };
      };

      nabla.enable = true;

      image = {
        enable = true;
        settings.backend = "kitty";
      };

      mkdnflow = {
        enable = true;
        settings.mappings = {
          MkdnTableAlignLeft = [
            "n"
            "<leader>tl"
          ];
          MkdnTableAlignRight = [
            "n"
            "<leader>tr"
          ];
          MkdnTableAlignCenter = [
            "n"
            "<leader>tc"
          ];
        };
      };

      otter.enable = true;
    };

    keymaps = [
      {
        key = "<leader>mp";
        action.__raw = "require('nabla').popup";
        options.desc = "Math popup";
      }
      {
        key = "<leader>mv";
        action.__raw = "require('nabla').toggle_virt";
        options.desc = "Toggle math virtual lines";
      }
    ];

    autoCmd = [
      {
        event = [ "FileType" ];
        pattern = [ "markdown" ];
        desc = "Attach otter (no markdown LSP means no LspAttach to hook)";
        callback.__raw = ''
          function()
            require('otter').activate()
          end
        '';
      }
    ];
  };
}
