# nvim: heavy language servers come from the project

**Ruling** [USER 2026-11-04]: clangd, omnisharp, ocamlformat and rust-analyzer
are not bundled with nvim. Like ocamllsp, they come from the project's devshell,
so nvim has to start inside it (`nd`, then `nvim`). They accounted for 3.3 GiB
of the 5.0 GiB nvim closure on hermes.

tinymist, pyright, nixd, elp, lua_ls and texlab stay bundled: together about
0.5 GiB, and needed outside any project. tinymist sets `packageFallback` because
the wrapper otherwise puts its own copy ahead of a project's on `PATH`.

Every host keeps the same nvim. A smaller olympus (core editor in `home.nix`,
language tooling in the desktop bundle) was rejected: the removal above takes
most of what made it heavy.

direnv was rejected: entering a directory would wait for the flake to load, and
`nd` already does the job on demand.

A missing server is silent: it only shows in `lsp.log` and `:checkhealth vim.lsp`.

**Revisit if**: starting nvim outside a devshell becomes the common case for C,
C#, OCaml or Rust work, or olympus's closure becomes a problem again.
