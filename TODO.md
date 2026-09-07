# TODO — tactical backlog

Audited against the tree on **2026-08-31** (at `c70ff62`); line references are
valid at that commit. Restructured 2026-09-07: split out of the old README —
settled questions moved to [DECISIONS.md](DECISIONS.md) → `decisions/`.

**Markers**

- `[auto]` — Claude can confirm the fix mechanically: `nix flake check`,
  `nix eval`, a grep for the absence of the pattern, `systemctl status`, a
  file existing. No human in the loop.
- `[manual]` — needs eyes or a stopwatch: something rendering on a screen, a
  glyph, a battery drain figure, a server-side setting in someone else's web
  UI, or state that only exists on a host this session cannot reach.
- `[USER]` / `[AGENT]` — who ruled or verified.

Two hosts are reachable from where these checks run (hestia); **hermes-only**
facts (swap size, panel behaviour, battery drain) are called out where they
gate an item.

**Closing an item**: check it off in place with date, commit, and the command
that proved it — don't delete it. Longer closed-arc narratives sit in *Closed*
at the bottom.

---

## Priorities

Ranked by value-to-effort. Each expands in its own section below.

1. **Vaultwarden** — olympus already has the nginx/SSO/agenix plumbing; real
   sync semantics beat `.kdbx` conflict copies.
2. **stylix** — `host.theme` is already scaffolded for it and currently dead.
3. **offsite copy of the restic repo** — the repository is now verified and
   alerts on failure, but it is still a single copy on one desktop.

---

## Reliability & alerting

- [ ] **the backup is a single copy on one desktop** `[manual]`
  `/var/backup/restic` lives only on hestia. A house fire, a disk failure, or
  a mistaken `rm` takes olympus's mail *and* its only backup. The repo
  password is already documented as needing to survive losing hestia
  (`backup/default.nix:54-59`) — the repo itself deserves the same. Options: a
  second `restic copy` target (external disk, or a rented S3/B2 bucket), or a
  `restic-repo copy` cron to a drive that is normally unplugged. The copy job
  is `[auto]`-checkable; "is the offsite copy actually offsite" is not.
  [USER to pick target]

- [ ] **host/disk alerting** `[auto]` units / `[manual]` delivery
  No uptime, disk-usage, or service-failure alerting on olympus at all. The
  backup jobs have a pattern to copy (`backup-alert@` + the stamp directory
  the bar polls, `common/modules/backup`), but it lives on hestia and covers
  backup units only. olympus needs the same `OnFailure=` on the important
  units (stalwart, nextcloud, nginx, oauth2-proxy) plus a disk-usage timer,
  and — being headless — a transport that is not a desktop notification.

## Security

- [ ] **extend the sshd hardening** `[auto]`
  `headless.nix:40-49` already restricts users and disables password/root
  login. Not set anywhere: `KexAlgorithms`, `Ciphers`, `MACs` allowlists,
  `AllowAgentForwarding no`, `AllowTcpForwarding` scoping, `MaxAuthTries`.
  Apply the same block to the desktops' on-demand sshd rather than only
  olympus. Verify: `nix eval` the rendered `sshd_config`.

- [ ] **desktops disable reverse-path filtering** `[auto]` eval / `[manual]` VPN
  `common/desktop.nix:47` sets `checkReversePath = false`; `headless.nix:37`
  keeps it `true`. Usually a workaround for a VPN/multi-homing edge — the
  wg-quick clients are full-tunnel, which is precisely the case that *doesn't*
  need it. Try `"loose"` (or removing the line) and check the tunnels still
  come up.

## Bugs

- [ ] **the wallpaper path is hand-placed and hardcoded** (confirmed in tree)
  `sway/default.nix:132`: `exec mpvpaper ${host.display.primary}
  /home/dk/wallpaper/current` depends on a file no module puts there, and
  hardcodes a path while `host.theme.wallpaper` (`host.nix:146-149`) exists
  and is read by nothing. Folded into the stylix item. `[auto]` for the
  option being read; `[manual]` for "a wallpaper is actually on screen".

- [ ] **Ctrl+Shift+F2 (VT switch) makes the sway bar disappear** `[manual]`
  Reported from use, not reproducible by reading the config — the bar is a
  swaybar with `hidden_state hide` / `mode dock` (`sway/kanshi.nix:57-60`), so
  a suspect is the mode being lost across a VT switch rather than the bar
  dying. Next step: `swaymsg -t get_bar_config` before and after, plus the
  sway log.

## Desktop & UX

- [x] **nvim as the default editor for text files** `[auto]`
  *Closed 2026-09-07 (`cb7f930`, `desktop/default.nix`):
  `xdg.desktopEntries.nvim-ghostty` (`ghostty -e nvim %F`; not named
  `nvim.desktop` to avoid colliding with neovim's own entry in the profile)
  mapped from the five types. Verified after switch: `xdg-mime query default
  text/plain` → `nvim-ghostty.desktop` (all five types), and `xdg-open` on a
  .txt opened nvim in ghostty.*
  `$EDITOR` is already nvim (`nvim/default.nix` sets
  `programs.nixvim.defaultEditor = true`). Missing is the *graphical* half:
  `desktop/default.nix:44-67` maps `xdg.mimeApps` for mail, LibreOffice and
  PDFs, but nothing for `text/plain`, so `xdg-open foo.txt` falls through.
  nvim ships a terminal-only `.desktop` entry, so this wants a small
  `ghostty -e nvim %f` wrapper entry (`xdg.desktopEntries.nvim`) mapped from
  `text/plain` and the handful that follow it (`text/markdown`,
  `application/json`, `text/x-shellscript`, `text/x-nix`). Verify:
  `xdg-mime query default text/plain` and an actual `xdg-open` after a switch.

- [ ] **bar: pin ghostty's font to the bar's** `[auto]`
  The bar renders with `pango:FiraCode Nerd Font Propo` (`sway/kanshi.nix:57`);
  ghostty sets no `font-family`, so the terminal falls back to its bundled
  JetBrains Mono plus *Symbols Nerd Font* for the icon range. Both cover the
  Material Design glyphs the bar uses — verified with `ghostty +show-face`
  against the TTF cmap — so today they agree only by coincidence of that
  fallback. Setting `font-family = "FiraCode Nerd Font Mono"` (already
  installed via `home-manager/modules/desktop` + fontconfig) makes bar and
  terminal the same face. Verify: `ghostty +show-face` reports the resolved
  face.

- [ ] **bar: reuse the status viewer for the wg-quick tunnels** `[auto]`
  `unit-status-view` takes the unit as an argument — its own header says the
  tunnels can reuse it verbatim (`unit-status-view.nix:29-30`) — and the
  tunnels are hand-toggled units in `host.userManagedUnits`
  (`wireguard/default.nix:152`) exactly like `sshd`. A `service_status` block
  per client interface, modelled on the sshd one
  (`i3status-rust.nix:309-347`), is a few lines each and makes "is the VPN up"
  answerable from the bar.

## Theming — stylix

Decided: [decisions/theming-stylix.md](decisions/theming-stylix.md).

- [ ] **wire up stylix from `host.theme`** `[auto]` consumers / `[manual]` looks
  Single source of truth for colorscheme/fonts/wallpaper across sway, ghostty,
  nvim, zathura and gtk, driven from `host.theme` (`host.nix:136-150`). State
  today: `host.theme.{base16,opacity,wallpaper}` are declared and read by
  **nothing** (`grep -rn 'host.theme' --include='*.nix' .` shows no
  consumers) — pure scaffolding. Absorbs two other items: the hardcoded
  wallpaper path (`sway/default.nix:132`) and ghostty's `background-opacity`.
  Verify: the same grep must show consumers, and `nix flake check` must build
  all three hosts.

## Passwords & keyring

Decided: [decisions/password-manager.md](decisions/password-manager.md). Two
layers usually conflated; they stay separate items.

- [ ] **Secret Service provider** `[auto]`
  (`org.freedesktop.secrets` over D-Bus) — what apps read and write tokens
  from. Nothing provides it today. Path of least resistance on sway:
  `services.gnome.gnome-keyring.enable`, run as a session daemon
  (`--components=secrets,ssh`), unlocked by the login password via
  `pam_gnome_keyring` in the **greetd** PAM service
  (`security.pam.services.greetd.enableGnomeKeyring = true`, alongside the
  existing `security.pam.services.swaylock` at `desktop.nix:96`). Verify:
  `busctl --user list | grep secrets` plus the PAM stack in the built config.

- [ ] **Vaultwarden on olympus** `[auto]` wiring / `[manual]` clients syncing
  Build notes:
  - vhost shape is `sslVhost { }` from `common/modules/nginx` — but **do not**
    put it behind `nextcloudSSO`: the mobile/browser clients speak the
    Bitwarden API and cannot pass an `auth_request` gate. Gate `/admin` only,
    or leave `/admin` disabled and set no admin token at all.
  - new agenix secret for the admin token; remember `git add -N`.
  - the desktop module currently ships **Proton Pass** — [USER] decides at
    cutover whether it goes or stays as a second, unrelated vault.
  - fingerprint unlock: hermes has `fprintd` (`common/modules/fingerprint`),
    which the Bitwarden desktop client can use.
  Verify: `systemctl status vaultwarden` + vhost + secret wiring.

## Energy (hermes)

`nixos-hardware`'s `framework-16-7040-amd` is imported (`flake.nix:101`),
bringing `amd_pstate=active` and `power-profiles-daemon` — and
`sway/i3status-rust.nix:78-96` drives it, reconciling the profile on lid/AC
transitions. What is left, roughly by impact:

- [ ] **panel: amdgpu adaptive backlight (ABM)** `[auto]` param / `[manual]` colour
  `amdgpu.abmlevel` is absent from hermes's evaluated `kernelParams`.
  `boot.kernelParams = [ "amdgpu.abmlevel=1" ]` (levels 0–4) is panel-side
  backlight reduction with a compensating contrast shift: real savings for a
  minor colour-accuracy cost, runtime-togglable via the connector's
  `panel_power_savings` sysfs attribute, so it can be flipped on battery only
  — the existing AC/lid reconcile script is the natural place.

- [ ] **bluetooth radio is powered at every boot** `[auto]`
  `hermes/configuration.nix` sets `powerOnBoot = true` (confirmed by eval)
  whether or not anything ever pairs; blueman toggles it on demand anyway.
  Flip to `false`. Verify: `bluetoothctl show` / `rfkill list` after a reboot.

- [ ] **wifi powersave is off fleet-wide** `[auto]` setting / `[manual]` latency
  `common/modules/wifi/default.nix:32` sets `powersave = false` deliberately,
  to avoid latency spikes (`:11`). A 100%-of-the-time radio cost for a
  sometimes-problem. Re-measure under the current stack, or enable it on
  battery only via a NetworkManager dispatcher script — the lid/AC machinery
  for "on battery" already exists.

- [ ] **suspend depth: s2idle drains** `[auto]` once run on hermes
  The 7040 Framework has no S3, so suspend is s2idle and still burns ~1%/h;
  the lid path ends in `systemctl suspend` (`common/modules/wifi/default.nix:88`),
  so a forgotten closed laptop drains for days. Switch to
  `systemctl suspend-then-hibernate` with `HibernateDelaySec` ~2h.
  **Blocker to check first, on hermes**: hibernation needs `boot.resumeDevice`
  and a swap device ≥ RAM. hermes has exactly one swap partition
  (`hermes/hardware-configuration.nix:43-45`, by-uuid `cf70f01c…`) and no
  `resumeDevice` anywhere in the flake; its size could not be checked from
  hestia. `lsblk -b -o NAME,SIZE
  /dev/disk/by-uuid/cf70f01c-2bcc-49f3-bdea-5584615d4e91` against `free -b`
  decides whether this is a two-line change or a repartition.

- [ ] **measurement & housekeeping** `[manual]`
  `powertop` for auditing (per-device tunables, wakeup offenders).
  `powerManagement.powertop.enable = true` auto-applies its tunables at boot,
  but that includes USB autosuspend, which bites input devices and BT dongles
  — prefer cherry-picking what it suggests.

## Performance & build

- [ ] **per-host `max-jobs` / `cores`** `[auto]` settings / `[manual]` faster
  Neither is set anywhere, so both take nix's defaults. `max-jobs` is how many
  derivations build concurrently; `cores` is `NIX_BUILD_CORES`, the `-j`
  *inside* one build. Their product can oversubscribe the CPU, so tune per
  host (hermes 16c, olympus 8c EPYC). Natural home is a
  `host.build.{maxJobs,cores}` pair on the struct rather than per-host
  literals.

- [ ] **build in RAM where memory allows** `[auto]`
  `boot.tmp.useTmpfs = true` puts `/tmp` (nix's build dir) on tmpfs → faster
  build IO, no SSD wear. Caveat: a big build can OOM, so **not** on the
  RAM-limited olympus VPS. Gate it on the host struct, not a per-host line.
  Verify: `findmnt /tmp` after a switch.

- [ ] **inputs that do not follow nixpkgs** `[auto]`
  `nixvim` and `zen-browser` deliberately do not follow `nixpkgs-unstable`
  (see the prose note in `flake.nix`; zen-browser historically needed `libgbm`
  from unstable). Each unfollowed input pulls a second nixpkgs into the lock —
  duplicate evals and cache misses. Since the flake *is* on unstable,
  re-testing the `follows` for both is cheap. Verify: `nix flake metadata`
  shows how many nixpkgs are in the lock; `nix flake check` proves it builds.

- [ ] **hestia: drop nvidia from the initrd** `[auto]` sizes / `[manual]` flicker
  `hestia/configuration.nix` forces the proprietary driver into the initrd for
  early KMS. The 595 module embeds GSP firmware → `nvidia.ko.xz` is 82M
  compressed, every generation's initrd ~199M; the 510M ESP then fits ~2
  generations, which is why `host.keepGenerations` is pinned to `2` on hestia
  against the struct default of 10 — otherwise the systemd-boot install fails
  with "No space left on device". Removing the line loads the driver in stage
  2 instead: initrd ~30M, ~15 generations fit, `keepGenerations` can go back
  up. Trade-off: one console mode-switch flicker during boot, cosmetic here
  (no encrypted root needing an early graphical prompt). Verify: initrd size
  and `du /boot/efi`.

## Code hygiene

Swept 2026-09-07 — everything `[auto]`-fixable landed as small commits (see
*Closed*); what remains survived the sweep.

- [ ] **`"dk"` / `/home/dk` hardcoded** in ~10 spots `[auto]`
  (`common.nix`, `home.nix`, `samba`, `calendar`, `nextcloud-sync`, `sway`).
  Acceptable for a single-user fleet, but there is no shared constant;
  `host.user` would be the obvious one, and it is what the wallpaper/logs
  paths in sway would consume too.

- [ ] **fish shadows real binaries** — `cat`→`bat` and `ls`→`eza`
  (`home-manager/modules/fish/default.nix`) are *functions*, so they shadow
  the binaries in every interactive shell, including in scripts sourced from
  one. Every fix changes daily UX (abbrs expand visibly, `command` guards
  complicate the bodies). [USER to rule: keep as-is, or which fix]

- [ ] **`udiskie.tray = "auto"; # FIXME does not show`** `[manual]`
  (`desktop/default.nix:74`) — an unresolved FIXME shipped as config. `"auto"`
  hides the icon when nothing is mounted; if the intent is always-visible it
  wants `"always"`, and if the tray itself is missing it wants a
  status-notifier host in the bar.

---

## Closed

Pre-split history, kept so a re-read does not re-propose it. New closures
check off in place above instead.

- [x] **code-hygiene sweep** — 2026-09-07, `6b403f5..bf32d81`, `nix flake
  check` green throughout. Commented-out code deleted (tmux/zellij imports,
  pactl keybinds, dvorak variant, ghostty leftovers, the 25.05 flake input) or
  turned into prose (sway's nvidia env fallbacks, the unfollowed-inputs note
  in `flake.nix`); `# lutris` resolved by installing lutris on hestia; unused
  module args dropped; `programs.i3status.enable` dropped; `home.stateVersion`
  divergence commented; fish `l`/`ll` dedup and a multi-arg-safe `mkcd`;
  `hardware.enableAllFirmware` dropped on hermes (redistributable set already
  on via nixos-hardware; the delta was only broadcom/b43/facetimehd/xone
  blobs); hestia's misplaced `vulkan-tools` removed; trailing whitespace gone.
  Two audit claims were overturned and became decisions:
  [hestia-dns-mkforce](decisions/hestia-dns-mkforce.md),
  [sway-checkconfig](decisions/sway-checkconfig.md).
- [x] **keyboard layout single-sourced** — 2026-09-07, `9124fc1` + `5ac03db`.
  `host.keyboard.{layout,variant,options}` holds sway's comma lists;
  console/XWayland and `home.keyboard` derive the first entry, so the extra
  layouts (and dvorak) exist only inside sway. hestia overrides to `us,gb,de`
  / `dvorak,,`: dvorak active once sway starts, console plain us.
- [x] **`allowUnfree` narrowed** — 2026-09-07, `a1e5b4a` + `5e34684`. The
  global `true` is now an `allowUnfreePredicate` listing the nine names
  actually consulted (traced with a temporary `builtins.trace` predicate
  across all three hosts' evals): nvidia-x11 / nvidia-kernel-modules /
  nvidia-settings, steam / steam-unwrapped / steamcmd, unrar, claude-code,
  corefonts. nixvim's own nixpkgs instance is narrowed to `barbar.nvim` (JSON
  license).
- [x] **sway execs wrote to a directory nothing creates** —
  `wl-gammarelay-rs`'s `2>> /home/dk/logs/...` redirect is gone; nothing
  declarative ever created `/home/dk/logs`, so on a host where it is absent
  the exec fails and the `Ctrl/Shift+XF86MonBrightness*` bindings die with it.
  stderr now lands in the sway log like every other exec.
- [x] **backup verification & alerting** (was priority 1) — done 2026-08-31.
  `restic-check.service` + weekly timer (`Persistent`, 30 min jitter, idle
  I/O) runs on the repository owner and fails on either way a backup lies:
  `restic check --read-data-subset=10%` for rot (deliberately *not*
  `--with-cache` — trusting the local metadata cache is what would hide a
  damaged index; the whole repo is re-read over ~10 runs), and a snapshot-age
  test for abandonment, since a repo nothing writes to any more passes `check`
  forever. Every backup unit carries the module's `alertHook`: a failure runs
  `backup-alert@%n.service` (journal + critical desktop notification + a
  stamp under `/var/lib/backup-alerts`) and the unit's next success clears
  the stamp; a `custom` block in `sway/i3status-rust.nix` shows standing
  failures and middle-clicks into the failing unit's journal. No off switch.
  `restic backup`/`forget` gained `--retry-lock=30m`. Verified: both
  freshness branches against a scratch repo, the notification path on
  hestia's session. *Remaining follow-up: the repo is still a single copy —
  see Reliability.*
- [x] **`host.backup` was configuring the module** — the struct is down to
  `backup.pull = [ "mail" ]` (non-empty ⇒ this host owns the repository).
  Repository path, cache dir, retention, check schedule, alert directory and
  each source's snapshot flags/max age live in `common/modules/backup`,
  exported as the `backupRepo` module arg. `backup.serve` is gone: the serving
  end keys on `services.stalwart.enable`. The channel's verbs are
  `stalwart-export` / `stalwart-import` (`<service>-<verb>`) — a wire protocol
  between the hosts, so **switch olympus before hestia**.
- [x] **backup for olympus** (was priority 1) — `common/modules/backup` owns
  the restic repo on hestia and `common/modules/mail-backup` pulls the
  stalwart store into it over a forced-command ssh channel, with
  `mail-restore` for the way back.
- [x] **`nixos-hardware`'s `framework-16-7040-amd`** — adopted (`flake.nix:101`).
- [x] **`services.power-profiles-daemon`** — enabled (via that module) *and*
  driven: `sway/i3status-rust.nix` reconciles the profile across AC and lid
  transitions and remembers a manual override.
- [x] **hestia sway crashing via libseat** — no longer reported.
- [x] **`chargeLimit` polling every second** — now `interval = 60`
  (`i3status-rust/blocks/charge-limit.nix:31`).
- [x] **`powerProfiles` polling every second** — now signal-driven: the block
  subscribes with `signal` and `power-profile-reconcile` raises SIGRTMIN+4
  after it changes the profile; the click repaints itself via `sync` +
  `update`. `interval = 60` stays only as a backstop for a bare
  `powerprofilesctl set`. The `cpu` block's `interval = 1` is a genuine meter
  and stays.
- [x] **setuid `framework_tool`** — replaced by `common/modules/charge-limit`,
  a udev rule that group-owns the battery's `charge_control_end_threshold`.
- [x] **cert-expiry alerting** (was priority 1) — superseded by the real fix,
  live since 2026-08-30: `common/modules/acme` renews the wildcard with lego
  over dns-01, gated by `host.tls.acme` (true on olympus). `*.dklaassen.de` +
  apex, served by every vhost and by stalwart's SMTP/IMAP, which the cert's
  `reloadServices` restarts on renewal.
  `systemctl status acme-order-renew-dklaassen.de.service` is the health
  check. The CA is Let's Encrypt, not IONOS: their endpoint is DV-only and
  issues solely against a purchased, unassigned certificate — the module
  header records both refusal strings and the single-use EAB behaviour so it
  is not retried. The IONOS API key remains as the *zone* credential lego
  needs for the challenge TXT. *Open follow-up: `ssl-fullchain.age` /
  `ssl-key.age` are dead weight kept only as the `host.tls.acme = false`
  rollback; drop from `secrets.nix` and `common/modules/nginx` once a renewal
  has run unattended.*
- [x] **`documentation.nixos.enable = false` on olympus** — dropped from the
  list.
