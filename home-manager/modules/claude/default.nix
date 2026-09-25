{
  config,
  lib,
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

  # `claude` runs the latest upstream release rather than the nixpkgs pin: the
  # version + checksum are fetched at launch and fed to nixpkgs-unstable's
  # claude-code via its `manifest` override. A binary on PATH, so sh, nvim's
  # claudecode and every other caller get it too. If the lookup or build fails
  # (offline, bad release), it falls back to the flake-pinned claude-code.
  claude = pkgs.writeShellApplication {
    name = "claude";
    runtimeInputs = [
      pkgs.curl
      pkgs.jq
    ];
    text = ''
      fallback() {
        echo "claude: $1; using pinned ${pkgs.claude-code.version}" >&2
        shift
        exec ${lib.getExe pkgs.claude-code} "$@"
      }
      base=https://downloads.claude.ai/claude-code-releases
      v=$(curl -fsS "$base/latest") || fallback "version lookup failed" "$@"
      c=$(curl -fsS "$base/$v/manifest.zst.json" | jq -er '.platforms."linux-x64".checksum') ||
        fallback "manifest lookup for $v failed" "$@"
      out=$(NIXPKGS_ALLOW_UNFREE=1 nix build --no-link --print-out-paths --impure --expr "
        (builtins.getFlake \"github:NixOS/nixpkgs/nixos-unstable\").legacyPackages.x86_64-linux.claude-code.override {
          manifest = { version = \"$v\"; platforms.\"linux-x64\" = { binary = \"claude.zst\"; checksum = \"$c\"; }; };
        }") || fallback "building $v failed" "$@"
      exec "$out/bin/claude" "$@"
    '';
  };
in
{
  home.packages = with pkgs; [
    claude
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
