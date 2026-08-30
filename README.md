# Bugs & review findings (2026-06)
## minor / cosmetic
- `wg-easy/default.nix` comments call the host hub interface "wg0"; it's actually named `olympus` (the container-internal `-i wg0` rules are correct)
- `nixvim.inputs.nixpkgs.follows` in `flake.nix` triggers the "Nixvim's inputs pin Nixpkgs to..." eval warning twice per host — drop the follows or set `programs.nixvim.nixpkgs.source`
- `users.extraUsers` in `common.nix` is a deprecated alias of `users.users`; the `networkmanager`/`gamemode` groups are also granted on olympus where neither exists
- add common tools for claude invocation
- middle mouse button should paste selected text in the terminal
- make notifications disappear after focusing their origin window (except firefox)
- notification dismissal with right-click only works with the mouse

# Priorities (review 2026-06)
ranked take on the ideas below, by value-to-effort:
- **1. backup for olympus** — the standout: mail + nextcloud data is the only irreplaceable state in the fleet (everything else rebuilds from the flake); a VPS disk failure currently loses it permanently
- **2. cert-expiry / health alerting** — the SSL cert is a manually rotated agenix secret with no renewal automation, and it backs all vhosts *and* stalwart's SMTP/IMAP TLS; expiry would take down mail silently. even a cron + `openssl x509 -checkend` that emails is most of the value
- **3. stable channel for olympus** — mail server on unstable means stalwart/nextcloud major bumps land whenever a rebuild happens; tradeoff is a second nixpkgs input and slightly divergent module behavior vs. the desktops
- **cheap one-liners, do anytime**: `documentation.nixos.enable = false` on olympus, remove (or actually wire up) the inert ccache config
- **worth it when motivated**: stylix (the `host.theme` struct is already scaffolded for it), vaultwarden over keepassxc+sync (real sync semantics beat `.kdbx` conflict copies; olympus already has the nginx/SSO/agenix plumbing)
- **deprioritize**: attic (cachix works today, VPS disk caveat is real), shared shell history (low payoff), `allowUnfreePredicate` (documentation value only)

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
## secrets-managed wifi / known networks
- declaratively manage networkmanager connections so a fresh install has wifi without manual setup

# Performance
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
## hestia: drop nvidia from the initrd to shrink boot generations
- `hestia/configuration.nix` lists `boot.initrd.kernelModules = [ "nvidia" "nvidia_modeset" "nvidia_uvm" "nvidia_drm" ]`, forcing the proprietary nvidia driver into the initrd (early KMS). The 595 module embeds GSP firmware → `nvidia.ko.xz` is 82M compressed, so every generation's initrd is ~199M. The 510M ESP (`/boot/efi`) then fits only ~2 generations, which is why `host.keepGenerations` had to be dropped to 2 (otherwise the systemd-boot install fails with "No space left on device")
- future change: remove the `boot.initrd.kernelModules` nvidia line. The driver loads in stage-2 instead, shrinking each initrd to ~30M so ~15 generations fit again — then `keepGenerations` can be raised back up
- trade-off: loss of early KMS = one console mode-switch flicker during boot; cosmetic here since hestia has no encrypted root needing an early graphical prompt

# Energy usage (hermes)
status quo: `powerManagement.enable = true` is the *only* power tuning on hermes — no platform-profile daemon, no idle management, bluetooth radio powered at boot, wifi powersave explicitly off. Roughly in order of impact:
## platform power profiles
- `services.power-profiles-daemon.enable = true` — switches amd-pstate EPP hints + ACPI `platform_profile` between power-saver/balanced/performance; the 7040 already runs amd-pstate in active mode (kernel ≥ 6.5 default), what's missing is anything *driving* it on AC↔battery transitions
- alternative: TLP — more knobs (PCIe ASPM, USB autosuspend, NVMe runtime PM, battery charge thresholds) but conflicts with power-profiles-daemon; pick exactly one. ppd is what Framework recommends and is the lower-maintenance default
## panel: amdgpu adaptive backlight (ABM)
- `boot.kernelParams = [ "amdgpu.abmlevel=1" ]` (levels 0–4): panel-side backlight reduction with compensating contrast shift — real backlight savings for a minor color-accuracy cost; runtime-togglable via the connector's `panel_power_savings` sysfs attribute, so it can be flipped on battery only
## radios
- `hardware.bluetooth.powerOnBoot = false` — hermes powers the BT radio at every boot whether or not anything pairs; blueman toggles it on demand anyway
- wifi powersave is deliberately `false` in `common/modules/wifi` (latency-spike avoidance) — worth re-measuring under iwd, or enabling it on battery only via an NM dispatcher script, instead of paying the radio cost 100% of the time
## suspend depth: s2idle drains — consider suspend-then-hibernate
- the 7040 Framework has no S3; suspend is s2idle, which still burns ~1%/h — the lid-close module (`common/modules/wifi`) ends in `systemctl suspend`, so a forgotten closed laptop drains for days
- switch it to `systemctl suspend-then-hibernate` + `HibernateDelaySec` (e.g. 2h); prereqs: `boot.resumeDevice` pointed at the existing swap partition and swap ≥ RAM for the hibernation image — check the partition size first
## measurement + housekeeping
- `powertop` for auditing (per-device tunables, wakeup offenders); `powerManagement.powertop.enable = true` auto-applies its tunables at boot, but that includes USB autosuspend which bites input devices / BT dongles — prefer cherry-picking the tunables it suggests
- `services.fwupd.enable = true` — Framework BIOS/EC updates regularly ship power fixes and land via LVFS; hermes has `framework-tool` but no fwupd today
- consider importing `nixos-hardware`'s `framework-16-7040-amd` module instead of hand-rolling hardware quirks (bundles fwupd, AMD defaults, known Framework fixes) — new flake input, overlaps with existing manual settings, so diff what it sets before adopting

# Nix-specific optimizations
## use `lib.mkDefault` for overridable defaults
- hestia already needs `lib.mkForce` for networkmanager.dns — set defaults with `mkDefault` so hosts override cleanly without force
## narrow allowUnfree
- replace global `allowUnfree = true` with `allowUnfreePredicate` listing the specific unfree pkgs (nvidia, steam, etc.) — documents *why* unfree is needed
## stable channel for the server
- olympus (mail + nextcloud) tracks nixpkgs-unstable like the desktops; consider pinning it to nixos-25.05 for fewer surprise breakages (the commented-out `nixpkgs.url` in flake.nix is a start)

# Reliability & reproducibility
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

# Code review findings (2026-07)

## Correctness / latent bugs
### `--unsupported-gpu ` flag has a trailing space
- `home-manager/modules/sway/default.nix:19`: `extraOptions = [ "--unsupported-gpu " ]`. The
argv token becomes `--unsupported-gpu ` (trailing space) and won't match sway's exact flag
string — a latent break on the **nvidia tower where the flag is actually required**.
- Also unconditional: it's applied to both desktops, yet the nvidia-specific env vars right
below it (`default.nix:30-42`) are gated on `host.gpu == "nvidia"`. Gate the flag the same way
(it's pointless on hermes/amdgpu).

### sway execs write to dirs nothing creates
- `sway/default.nix:134`: `exec wl-gammarelay-rs run 2>> /home/dk/logs/wl-gammarelay-rs` — no
tmpfiles/`home.file` rule creates `/home/dk/logs`; if absent the `2>>` redirect fails and
gammarelay (the `Ctrl/Shift+XF86MonBrightness*` keybindings) silently never starts.
- `sway/default.nix:132`: `mpvpaper … /home/dk/wallpaper/current` depends on a hand-placed
file and hardcodes the path (see dead `host.theme.wallpaper` below).

### `initialHashedPassword` hash is committed to the repo
- `common/common.nix:53` stores the yescrypt hash for `dk` in version control (all hosts). A
hash is offline-crackable; if this repo is ever public that's a real exposure. Consider
`hashedPasswordFile` via agenix.

### framework_tool is setuid-root
- `hermes/configuration.nix:110-115`: `security.wrappers.framework_tool { setuid = true;
owner/group = root; }` grants every session full root via the EC tool. A dedicated group + udev
rule on the EC device is the tighter grant.

## Dead code & unused scaffolding
- **`host.theme.{base16,opacity,wallpaper}`** (`host.nix:99-113`) are defined but **never
read** anywhere; the wallpaper path is hardcoded in `sway`. Pure stylix-scaffolding — keep only
if stylix is imminent, else it's dead surface.
- **Unimported module dirs**: `home-manager/modules/tmux` and `home-manager/modules/zellij`
exist but their imports are commented out in `home.nix:13,15`. Dead files.
- **Commented-out code** scattered: `home.nix:13,15` (tmux/zellij), `desktop/default.nix:26`
(`# lutris`), `sway/default.nix:37-39` (nvidia env), `sway/default.nix:86-88` (old pactl
keybinds), `common.nix:73` (`# xkb.variant`), plus the hestia/desktop network lines from the
prior review. Decide keep-vs-delete.

## Duplication & single-source-of-truth violations
- **Keyboard layout defined in three places, two disagreeing**: `common.nix:72` `xkb.layout =
"gb"`, `home.nix:25` `home.keyboard.layout = "gb"`, and `sway/default.nix:60` `xkb_layout =
"gb,de,us"`. No single source.
- **`"dk"` / `/home/dk`** hardcoded in ~10 spots (common, home, samba, calendar,
nextcloud-sync). Acceptable for single-user, but there's no shared constant.

## Cosmetic / minor
- **Unused module arguments**: `olympus/configuration.nix` declares `lib`/`pkgs` (uses
neither), `hermes/configuration.nix` declares unused `lib`, `common.nix` declares unused
`config`. Tidy the headers.
- **Redundant explicit defaults**: `sway/default.nix:194` `programs.i3status.enable = false`
(already false); `checkConfig = false` (`sway:20`) has no comment explaining why validation is
off.
- **`home.stateVersion = "24.11"`** (`home.nix:20`) trails the hosts' `25.05` — independent by
design, but worth a comment since the whole point elsewhere is one authoritative version.
- **fish nits** (`fish/default.nix`): `l` and `ll` are byte-identical (`eza -l $argv`,
`:39-44`); `mkcd` (`:50`) breaks on multiple args (`cd $argv`); `cat`→`bat`/`ls`→`eza` are
functions that shadow the real binaries in every interactive shell.
- **`hardware.enableAllFirmware = true`** (`hermes:54`) pulls the full unfree firmware set;
`enableRedistributableFirmware` (already implied by the nixos-hardware framework module) is
usually enough — diff before keeping both.
- **`vulkan-tools`** sits in `hardware.graphics.extraPackages` (`hestia:61`) — that list is
for driver libs, not CLI tools; belongs in `systemPackages`.
- **`udiskie.tray = "auto"; # FIXME does not show`** (`desktop/default.nix:69`) — unresolved
FIXME shipped as config.
- **Trailing whitespace**: `sway/default.nix:132`, `nvim/plugins/lsp.nix:168`.

# Bar follow-ups (2026-08-30)

Suggestions raised alongside the `sshd` bar toggle (`sway/i3status-rust.nix`) and
`sway/unit-status-view.nix`, deliberately *not* implemented there:

- **Pin ghostty's font to the bar's**: the bar renders with `pango:FiraCode Nerd Font Propo`
(`sway/kanshi.nix:57`), while `ghostty/default.nix:10` leaves `font-family` commented out, so
the terminal falls back to its bundled JetBrains Mono plus *Symbols Nerd Font* for the icon
range. Both cover the Material-Design glyphs the bar uses (verified with `ghostty +show-face`
and against the TTF's cmap), so today they agree only by coincidence of that fallback.
Setting `font-family = "FiraCode Nerd Font Mono"` — already installed via
`home-manager/modules/desktop` + fontconfig — makes bar and terminal the same face, and any
glyph that renders in one is then guaranteed in the other.
- **Stop polling once a second**: `chargeLimit` and `powerProfiles` (`i3status-rust.nix`) run
`interval = 1`, so each spawns a shell pipeline every second forever — on the laptop, on
battery. i3status-rust's common `signal = N` option covers the case they actually need: raise
`interval` to something lazy (30s+) and have the click handler end with
`pkill -SIGRTMIN+N i3status-rs`, which repaints the block immediately after the only event
that ever changes it. The `sshd` block avoids the issue entirely — `service_status` is D-Bus
driven and has no interval at all.
- **Reuse the status viewer for the wg-quick tunnels**: `unit-status-view` takes the unit as
an argument, and the tunnels are hand-toggled units in `host.userManagedUnits` exactly like
`sshd` (`common/modules/wireguard`, `common/modules/polkit-units`). A `service_status` block
per client interface — same right-click toggle, same middle-click status window — is a few
lines each, and would make "is the VPN actually up" answerable from the bar instead of from
`systemctl`.
