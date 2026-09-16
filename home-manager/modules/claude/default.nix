{
  config,
  pkgs,
  inputs,
  ...
}:

# Tooling for claude-code sessions. Everything here is on PATH for dk on every
# host, so an agent invocation finds the same toolbox regardless of machine.
#
# Only what the *base* HM bundle lacks: ripgrep/fd/fzf/curl/wget/bat/gcc/nodejs
# come from home.nix, nixfmt from modules/nvim/plugins/lsp.nix.
#
# Caveat: home.nix installs uutils-coreutils-noprefix, so GNU-only flags
# (`date -d`, `stat -c`, `sort -V`) may not behave as a script expects.

let
  cswap = inputs.claude-swap.packages.${pkgs.stdenv.hostPlatform.system}.claude-swap;
in
{
  home.packages = with pkgs; [
    claude-code
    cswap

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

  # Auto-switch loop. Policy (threshold, drainAccount) lives in cswap's own
  # settings.json, edited with `cswap config set`. Only starts on hosts where
  # accounts were added; after the first `cswap add`, run
  # `systemctl --user start cswap-auto` once.
  systemd.user.services.cswap-auto = {
    Unit = {
      Description = "claude-swap auto-switch between Claude accounts";
      ConditionPathExists = "${config.xdg.dataHome}/claude-swap/sequence.json";
      StartLimitIntervalSec = 0;
    };
    Service = {
      ExecStart = "${cswap}/bin/cswap auto";
      Environment = [ "PYTHONUNBUFFERED=1" ];
      Restart = "on-failure";
      RestartSec = "60s";
    };
    Install.WantedBy = [ "default.target" ];
  };
}
