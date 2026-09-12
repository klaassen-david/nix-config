# nvim markdown stack: mkdnflow, no bullets.vim

**Ruling** [USER 2026-09-12]: the markdown stack is render-markdown (in-buffer
prettifying), nabla (LaTeX popup), image.nvim (kitty protocol), mkdnflow
(links/tables/lists/to-dos/folding) and otter (LSP in fences), all in
`home-manager/modules/nvim/plugins/markdown.nix`.

bullets.vim was considered and dropped: mkdnflow already covers list
continuation, promote/demote with renumbering, and checkbox toggling with
parent/child propagation. What bullets would have added — Roman/alphabetic
outline levels, marker alignment padding, bullet line spacing, auto-indent
after a colon, and list behaviour in `text`/`gitcommit` buffers — was not worth
its costs: its default insert-mode `<CR>` map is buffer-local and would shadow
cmp's `<CR>` = confirm in markdown buffers, and its checkbox engine would run
alongside mkdnflow's with a different marker set.

markview.nvim and headlines.nvim were the alternatives to render-markdown;
they occupy the same concealment/highlight groups, so only one may be enabled.

**Revisit if**: outline lists with Roman/alphabetic levels become a real need,
or list editing is wanted outside markdown buffers.
