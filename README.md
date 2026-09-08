# nix-config

Multi-host NixOS flake (x86_64-linux): one shared base, three hosts —
**olympus** (headless VPS: nginx/SSO, Nextcloud, stalwart mail, wireguard
hub), **hermes** (Framework 16 laptop, sway), **hestia** (nvidia tower, sway).
Inputs track `nixpkgs-unstable`; secrets are agenix; per-host facts live in
the `host` struct (`common/host.nix`) and everything downstream derives from
it.

- [CLAUDE.md](CLAUDE.md) — the working reference: layout, conventions,
  secrets/backup/deploy protocols, style.
- [TODO.md](TODO.md) — tactical backlog, `[auto]`/`[manual]`-marked.
- [DECISIONS.md](DECISIONS.md) — index of settled questions; rationale and
  revisit-conditions in `decisions/`.

```sh
nix flake check   # eval + build every host's toplevel, statix lint
sudo nixos-rebuild switch --flake .#<host>   # rebuild + switch
```
