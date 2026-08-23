# Lean 4 support — lean.nvim: infoview, unicode abbreviations, and the `leanls`
# client (started by the plugin itself via `vim.lsp.enable`, *not* through
# `plugins.lsp.servers`).
#
# Toolchain: leanls shells out to `lake serve` — or `lean --server` for files
# with no lakefile — picked up from PATH, so something has to provide it.
# nixvim's `dependencies.lean` defaults to `pkgs.lean4`, which pins one Lean
# version editor-wide and breaks the moment a project's `lean-toolchain`
# disagrees (Mathlib pins exact versions). `pkgs.elan` instead ships `lean`/
# `lake` shims that read `lean-toolchain` and fetch the matching toolchain into
# ~/.elan, so one editor config works across projects. Trade-off: toolchains
# are fetched at runtime and live outside the store.
#
# elan is referenced twice on purpose — same store path, so no extra closure:
# as the nixvim dependency it joins the wrapped nvim's PATH, in `home.packages`
# it also serves `lake build` / `elan` from a shell.
#
# Standalone .lean files outside any project need a default toolchain once:
# `elan default stable`.
{ pkgs, ... }:
{
  home.packages = [ pkgs.elan ];

  programs.nixvim = {
    dependencies.lean.package = pkgs.elan;

    plugins.lean = {
      enable = true;
      # Upstream ships its suggested mappings disabled. Enabling binds them
      # buffer-locally in lean buffers: infoview pins/widgets, `K` for the
      # interactive hover, `<LocalLeader>r` to restart a file. No
      # `maplocalleader` is set anywhere, so LocalLeader is `\` — which is also
      # the abbreviation leader, but that only maps in insert mode.
      settings.mappings = true;
    };

    # The suggested mappings already cover these; this mirrors the three
    # infoview actions worth a <leader> chord onto `<leader>l*`. Buffer-local
    # (like tinymist's onAttach maps) so nothing is shadowed outside Lean.
    autoCmd = [
      {
        event = [ "FileType" ];
        pattern = [ "lean" ];
        desc = "Lean infoview keymaps";
        callback.__raw = ''
          function(event)
            local map = function(keys, cmd, desc)
              vim.keymap.set('n', keys, '<cmd>' .. cmd .. '<CR>', {
                buffer = event.buf,
                desc = 'Lean: ' .. desc,
              })
            end
            map('<leader>li', 'LeanInfoviewToggle', 'Toggle [I]nfoview')
            map('<leader>lp', 'LeanInfoviewAddPin', 'Add infoview [P]in')
            map('<leader>lc', 'LeanInfoviewClearPins', '[C]lear infoview pins')
          end
        '';
      }
    ];
  };
}
