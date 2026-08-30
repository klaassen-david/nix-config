{ pkgs, ... }:

# Tooling for claude-code sessions. Everything here is on PATH for dk on every
# host, so an agent invocation finds the same toolbox regardless of machine.
#
# Only what the *base* HM bundle lacks: ripgrep/fd/fzf/curl/wget/bat/gcc/nodejs
# come from home.nix, nixfmt from modules/nvim/plugins/lsp.nix.
#
# Caveat: home.nix installs uutils-coreutils-noprefix, so GNU-only flags
# (`date -d`, `stat -c`, `sort -V`) may not behave as a script expects.

{
  home.packages = with pkgs; [
    claude-code

    python3
    jq
    gh
    tree
    file

    # nix linting; nixfmt already ships with the nvim LSP setup
    statix
    deadnix
    nix-tree
  ];
}
