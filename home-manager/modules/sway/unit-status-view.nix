# unit-status-view — read-only, live `systemctl status <unit>` in neovim
# =====================================================================
# The bar's service blocks (see ./i3status-rust.nix) can say *whether* a unit is
# running; when it is not, the interesting part is *why*, which is what
# `systemctl status` prints. Middle-clicking such a block opens this in a
# terminal window.
#
# Why a file plus neovim, rather than `ghostty -e systemctl status`:
#   - the output stays navigable (search, yank, scroll) instead of being a dead
#     scrollback dump, and
#   - it keeps refreshing, so the window is still correct a minute later — the
#     usual case is watching a unit while flipping it from the bar.
#
# Shape:
#   - a background loop re-renders the status into a file in $XDG_RUNTIME_DIR
#     every 2s and swaps it in with `mv` (atomic — the buffer can never observe
#     a half-written file). Identical output is *not* swapped in, because every
#     mv bumps mtime and nvim would reload (and flash) for no reason.
#   - neovim opens it with 'autoread' and a 1s timer running :checktime, so the
#     buffer follows the file with no keypress. Reloading works even though the
#     buffer is 'readonly' *and* 'nomodifiable' — :checktime re-reads the file
#     rather than editing the buffer.
#   - closing the buffer quits the editor. This is a throwaway window, and
#     <C-c> (barbar's BufferClose, see ../nvim) would otherwise leave an empty
#     nvim sitting in the terminal.
#   - the EXIT trap kills the refresher and removes the temp dir, so nothing
#     survives the window.
#
# Takes the unit as an argument (`unit-status-view sshd.service`) so the
# wg-quick tunnels — the other hand-toggled units — can reuse it verbatim.
{
  lib,
  writeShellScriptBin,
  writeText,
  coreutils,
  diffutils,
  systemd,
}:

let
  view = writeText "unit-status-view.lua" ''
    vim.opt.autoread = true
    vim.bo.modifiable = false

    -- 'autoread' alone only fires on events nvim already handles (shell out,
    -- focus change); in a window that just sits there nothing would ever
    -- trigger it, hence the timer.
    local timer = vim.uv.new_timer()
    timer:start(1000, 1000, vim.schedule_wrap(function()
      -- not while a prompt or insert is open: :checktime would interrupt it
      if vim.api.nvim_get_mode().mode == "n" then
        vim.cmd("silent! checktime")
      end
    end))

    vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
      buffer = 0,
      callback = function()
        timer:stop()
        -- scheduled: quitting from inside the autocmd that is deleting the
        -- buffer is not allowed
        vim.schedule(function()
          vim.cmd("qa!")
        end)
      end,
    })
  '';
in
writeShellScriptBin "unit-status-view" ''
  set -eu
  export PATH=${
    lib.makeBinPath [
      coreutils
      diffutils
      systemd
    ]
  }:$PATH

  unit=''${1:-}
  [ -n "$unit" ] || {
    echo "usage: unit-status-view <unit>" >&2
    exit 2
  }

  dir=$(mktemp -d "''${XDG_RUNTIME_DIR:-/tmp}/unit-status.XXXXXX")
  file="$dir/$unit"

  render() {
    # `status` exits non-zero for an inactive unit — that output is exactly what
    # we want to show, so the exit code is not an error here
    systemctl status --no-pager --lines=30 "$unit" >"$file.new" 2>&1 || true
    if cmp -s "$file.new" "$file" 2>/dev/null; then
      rm -f "$file.new"
    else
      mv "$file.new" "$file"
    fi
  }

  render
  while :; do
    sleep 2
    render
  done &
  refresher=$!
  trap 'kill "$refresher" 2>/dev/null || true; rm -rf "$dir"' EXIT INT TERM

  # bare `nvim`, deliberately not a store path: this has to be the user's own
  # nixvim (colours, keymaps, barbar), not a second neovim closure.
  # -R readonly, -n no swapfile (the file is a transient in $XDG_RUNTIME_DIR).
  nvim -R -n "$file" -c "luafile ${view}"
''
