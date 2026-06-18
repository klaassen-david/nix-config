# Improvement Ideas
## shared shell history
for all 3 configs, maybe via nextcloud.dklaassen.de
## keyring
- two layers usually conflated: (1) the OS **Secret Service** (`org.freedesktop.secrets` over D-Bus) that apps read/write tokens from, and (2) the **password manager** you interact with. decide each separately.
- Secret Service layer — pick a provider and auto-unlock it at login:
  - `gnome-keyring` is the path of least resistance on sway: `services.gnome.gnome-keyring.enable`, run as a session daemon (`--components=secrets,ssh`), unlocked by the login password via `pam_gnome_keyring` in the **greetd** PAM service (`security.pam.services.greetd.enableGnomeKeyring = true`). stays open for the rest of the session.
  - alternative: let **KeePassXC** be the Secret Service provider (its "Secret Service Integration" setting), collapsing layers (1) and (2) into one app — at the cost of KeePassXC having to be unlocked before *anything* can fetch a secret.
- password-manager layer — three coherent options:
  - **KeePassXC + nextcloud-client**: the `.kdbx` lives in the synced nextcloud folder, opened locally. matches the original "syncs via nextcloud" note. risk: editing on two hosts at once → sync-conflict copies of the db.
  - **Vaultwarden on olympus**: self-host (olympus already runs nextcloud + stalwart behind nginx), use Bitwarden clients. real multi-device sync, no file-conflict risk; costs one more service + an agenix-managed admin token.
  - the desktop module currently ships **Proton Pass**, which syncs via Proton's servers (not nextcloud) — so it doesn't fit the "via nextcloud" goal; keep it or replace it.
- browser integration:
  - KeePassXC → `keepassxc-browser` over native messaging (enable the native-messaging host + the zen/firefox extension); Vaultwarden → the Bitwarden extension pointed at olympus.
  - the "unlock for the plugin" worry: the extension can only talk to KeePassXC while the db is **unlocked**. options: unlock manually per session, keep the db keyfile inside the gnome-keyring that PAM already unlocked at login, or KeePassXC Quick-Unlock. on hermes the `fprintd` fingerprint could gate that unlock.
## nextcloud mail
- show preview of attachments
- stop marking every mail as important
## switching terminal CTRL+SHIFT+F2 makes sway bar disappear
## nvim in ghostty as default editor
- xdg-open should open .txt files and similar in nvim.
## zathura text copying does not work
## hestia sway crashes due to libseat crashing
- triggers an automatic restart and everything works fine after that

# Quality of Life
## self-hosted binary cache (attic on olympus)
- goal: keep local-first builds (every host builds itself) but stop recompiling artifacts another host already built
- run `attic` on olympus (only always-on host, already terminates TLS via nginx) behind the existing reverse proxy
- hermes/hestia push built paths to it (post-build-hook / `attic push`); olympus dedups and runs attic's own retention/GC
- add the cache URL + signing public key to substituters on all three hosts; signing key managed via agenix
- replaces the public `klaassen-david.cachix.org` dependency with something fully self-owned
- caveat: VPS disk is limited — rely on attic's retention policy so the cache doesn't grow unbounded
- not a remote *builder* — hosts still build themselves; this only shares the *binary cache* (no cross-host build dependency, immune to hestia being unreachable)
## stylix for unified theming
- single source of truth for colorscheme/fonts/wallpaper across sway, ghostty, nvim, zathura, gtk
- ties in with the "host struct" idea (per-host color scheme + opacity)
## `nh` (nix-helper) as the rebuild front-end
- nicer diff output (shows what packages change), `nh os switch`, `nh clean` for GC
- replaces remembering long `nixos-rebuild` invocations
## secrets-managed wifi / known networks
- declaratively manage networkmanager connections so a fresh install has wifi without manual setup

# Performance
## automatic store optimisation + GC
- `nix.settings.auto-optimise-store = true` (hardlink dedup) — currently unset on all hosts
- `nix.gc.automatic` with `options = "--delete-older-than 30d"` so stores don't grow unbounded (esp. olympus VPS disk)
## SSD hygiene
- `services.fstrim.enable = true` on all hosts (none enable it today)
- `zramSwap.enable = true` on hermes/olympus to cut swap latency / OOM risk
## faster builds
- set `nix.settings.max-jobs`/`cores` explicitly per host instead of defaults
  - `max-jobs` = how many derivations build concurrently; `cores` = `NIX_BUILD_CORES`, the `-j` *inside* one build. Their product can oversubscribe the CPU, so tune per host (hermes 16c, olympus 8c EPYC) to trade build-graph width against per-build parallelism.
- `boot.tmp.useTmpfs = true` to build in RAM where memory allows
  - puts `/tmp` (nix's build dir) on tmpfs → faster build IO, no SSD wear; caveat: a big build (chromium, fat closures) can OOM, so not on the RAM-limited olympus VPS.
- reconsider `programs.ccache` once **attic** lands (see the binary-cache idea above)
  - attic shares *whole build outputs across hosts*, so it subsumes most of what ccache would save; ccache only helps the narrow case where this host recompiles a *changed* derivation whose object files are still reusable. So attic makes "is ccache worth it" sharper, not softer — measure before keeping a second, compiler-level cache.
  - latent issue: the current `programs.ccache.enable = true` sets no `packageNames`, so it wraps nothing in nixpkgs today — effectively inert until packages opt in.
## trim closure / boot time
- `documentation.nixos.enable = false` on headless olympus
- audit whether zen-browser not following nixpkgs causes duplicate nixpkgs evals / cache misses

# Nix-specific optimizations
## factor out the duplicated firewall block
- the `let ranges/ports in { firewall ... }` pattern is copy-pasted in common/headless.nix and common/desktop.nix
- extract a small module that takes ports/ranges as options
## use `lib.mkDefault` for overridable defaults
- hestia already needs `lib.mkForce` for networkmanager.dns — set defaults with `mkDefault` so hosts override cleanly without force
## `nix flake check` + per-host build checks
- add `checks` to the flake so `nix flake check` actually builds each nixosConfiguration's toplevel
- catches eval/build breakage before deploy
## narrow allowUnfree
- replace global `allowUnfree = true` with `allowUnfreePredicate` listing the specific unfree pkgs (nvidia, steam, etc.) — documents *why* unfree is needed
## stable channel for the server
- olympus (mail + nextcloud) tracks nixpkgs-unstable like the desktops; consider pinning it to nixos-25.05 for fewer surprise breakages (the commented-out `nixpks.url` is a start — note the typo)

# Code quality & maintainability
## de-duplicate 
- `vim` is listed in both common systemPackages and home.packages
## tidy commented-out code
- home.nix has commented imports (tmux, zellij); desktop.nix/hestia have commented network lines — decide keep vs. delete

# Reliability & reproducibility
## generations diff before switch
- print a closure diff (`nvd diff` / `nh os switch`) as part of the rebuild workflow to see what actually changes
## backup story for olympus state
- nextcloud data + stalwart mail are the irreplaceable bits — declarative restic/borg backup with off-site target
## health checks / alerting
- lightweight uptime + cert-expiry + disk-usage alerting for the VPS (the SSL secrets are manually managed — a cert nearing expiry should page you)

# Security
## SSH hardening already good — extend it
- headless restricts users + disables password/root login; consider the same `openssh.settings` hardening (KexAlgorithms, no agent forwarding) on the desktops
## firewall: desktop sets `checkReversePath = false`
- revisit whether it's still needed; headless keeps it strict
## secrets ownership audit
- confirm every agenix secret has the tightest `owner`/`mode` it can (mail/nextcloud passwords)
- check id_priv vs. host key
