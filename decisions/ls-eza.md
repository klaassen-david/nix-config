# ls-eza: eza in fish, GNU ls in bash

**Ruling** [USER 2026-11-04]: in fish every `ls` goes through eza; bash keeps GNU
`ls`. The short names mean the same in both shells, only the tool differs:
`l` and `ll` are a long listing, `la` is a long listing with hidden files and
`.`/`..` (`eza -laa`, `ls -la`).

**Rejected**: one `home.shellAliases` set pointing both shells at eza. eza is not
a drop-in for GNU flags (`eza -ltr` fails: `-t` takes a time field), and bash is
where commands from docs get pasted.

**Revisit if**: bash becomes an interactive daily shell, or `ll` should differ
from `l` (it duplicates it; hidden files were not asked for).
