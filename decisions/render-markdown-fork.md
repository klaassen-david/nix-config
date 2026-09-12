# render-markdown comes from a fork, for wrapped tables

**Ruling** [USER 2026-09-12]: `plugins.render-markdown.package` is built from
`inputs.render-markdown-nvim` (`github:klaassen-david/render-markdown.nvim`,
branch `wrapped-cells`, `flake = false`) rather than nixpkgs, because that
branch adds `pipe_table.cell = "wrapped"`: columns sized to the window with
cell contents wrapped over several lines, and the row under the cursor showing
its source in place at the rendered row's height. Wide tables in this repo's own
docs (`CLAUDE.md`, `DECISIONS.md`) are the motivating case.

The mode forces `win_options.wrap = false` and `render.scrolled = true` itself —
a concealed line still wraps by the width of the text it hides, and a cursor
column past the window edge would otherwise clear the buffer. `render_modes`
includes `i` by choice in `markdown.nix`: without it the whole buffer un-renders
on insert and every table row jumps.

Considered and dropped: glow and browser previews (`markdown-preview`, `peek`)
reflow wide tables but only outside the buffer; a standalone plugin
(`~/code/mdtable-wrap.nvim`, the first prototype) duplicated render-markdown's
anti-conceal, debounce and mode handling for no gain. See
`decisions/nvim-markdown-stack.md` for the rest of the stack.

**Revisit if**: the mode lands upstream (drop the input, go back to nixpkgs), or
the fork falls far enough behind upstream that rebasing it costs more than the
mode is worth.
