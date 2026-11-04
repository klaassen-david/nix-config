# nvim: editor defaults

**Ruling** [USER 2026-11-04]: guess-indent is the one indent detector; sleuth
did the same job alongside it. comment.nvim is out: nvim's builtin `gc`/`gcc`
replace it, so its `gb` block-comment maps are gone too.

**Revisit if**: guess-indent misdetects a filetype sleuth handled, or block
comments turn out to be missed.
