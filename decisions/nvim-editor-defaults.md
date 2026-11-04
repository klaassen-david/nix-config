# nvim: editor defaults

**Ruling** [USER 2026-11-04]: guess-indent is the one indent detector; sleuth
did the same job alongside it. comment.nvim is out: nvim's builtin `gc`/`gcc`
replace it, so its `gb` block-comment maps are gone too. `updatetime` is 250,
down from the default 4000 that delayed LSP reference highlights by 4 seconds.
The gutter is 3 cells instead of 6 and the sign column only appears when a
buffer has signs. Diagnostics place no sign: they colour the line number's
background by severity, so the text never shifts.

**Revisit if**: guess-indent misdetects a filetype sleuth handled, block
comments turn out to be missed, or swap writes at 250 ms become noticeable.
