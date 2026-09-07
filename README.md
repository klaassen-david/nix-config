# nix-config — open items

Audited against the tree on **2026-08-31** (at `c70ff62`). Every item below was
re-checked; line references are valid at that commit, and the ones pointing into
`common/modules/backup`, `common/modules/mail-backup` and `common/host.nix` were
re-checked again after those files were rewritten later the same day (see
*Closed*). Items that had been fixed in the meantime moved to *Closed* at the
bottom rather than being deleted, so a re-read does not re-propose them.

**Legend** — the marker says whether *Claude can confirm a fix on its own*:

- `[auto]` — verifiable mechanically: `nix flake check`, `nix eval`, a grep for
  the absence of the pattern, `systemctl status`, a file existing. No human in
  the loop.
- `[manual]` — needs eyes or a stopwatch: something rendering on a screen, a
  glyph, a battery drain figure, a server-side setting in someone else's web UI,
  or state that only exists on a host this session cannot reach.

Two hosts are reachable from where these checks run (hestia); **hermes-only**
facts (swap size, panel behaviour, battery drain) are called out where they gate
an item.

---

# Decisions on record

Settled questions, kept here so they stop being re-litigated.

## Nextcloud data is deliberately not backed up
`common/modules/mail-backup` covers the stalwart store only (`--host olympus
--tag mail`); olympus's `/var/lib/nextcloud` and its database are in **no**
backup. That is intentional: the Nextcloud content is itself continuously synced
down to the desktops (`home-manager/modules/nextcloud-sync` → `~/sync`), so the
irreplaceable-state argument that justified the mail backup does not apply. Mail
is different — it exists nowhere but olympus.

The residual exposure, accepted: server-side-only state (share links, app
config, calendars/contacts beyond the vdir mirror, anything never synced to a
desktop) is lost with the VPS disk, and a sync-propagated deletion has no
history to roll back to.

## One nixpkgs channel for the fleet
olympus tracks `nixpkgs-unstable` like the desktops. Pinning the server to
`nixos-25.05` (the commented `nixpkgs.url` in `flake.nix:6`) was considered and
**dropped** — one channel for three hosts is the point. Leave the commented line
or delete it; it is not a to-do.

## Password manager: Vaultwarden on olympus
Decided 2026-08-31 — see *Passwords & keyring* below. KeePassXC-over-nextcloud
and keeping Proton Pass are both off the table.

## Theming: adopt stylix
Decided 2026-08-31 — `host.theme.*` stays and gets wired up rather than deleted.
See *Theming*.

---

# Priorities

Ranked by value-to-effort. Everything here is expanded in its own section.

1. **Vaultwarden** — olympus already has the nginx/SSO/agenix plumbing; real
   sync semantics beat `.kdbx` conflict copies.
2. **stylix** — `host.theme` is already scaffolded for it and currently dead.
3. **offsite copy of the restic repo** — the repository is now verified and
   alerts on failure, but it is still a single copy on one desktop.

---

# Reliability & alerting

## the backup is a single copy on one desktop
`/var/backup/restic` lives only on hestia. A house fire, a disk failure, or a
mistaken `rm` takes olympus's mail *and* its only backup. The repo password is
already documented as needing to survive losing hestia
(`backup/default.nix:54-59`) — the repo itself deserves the same. Options: a
second `restic copy` target (external disk, or a rented S3/B2 bucket), or a
`restic-repo copy` cron to a drive that is normally unplugged. `[manual]` (the
copy job is `[auto]`-checkable; "is the offsite copy actually offsite" is not).

## host/disk alerting
No uptime, disk-usage, or service-failure alerting on olympus at all. The
backup jobs now have a pattern to copy (`backup-alert@` + the stamp directory
the bar polls, `common/modules/backup`), but it lives on hestia and covers
backup units only. olympus needs the same `OnFailure=` on the important units
(stalwart, nextcloud, nginx, oauth2-proxy) plus a disk-usage timer, and — being
headless — a transport that is not a desktop notification. `[auto]` for the
units existing; `[manual]` for the notification arriving.

---

# Security

## extend the sshd hardening
`headless.nix:40-49` already restricts users and disables password/root login.
Not set anywhere: `KexAlgorithms`, `Ciphers`, `MACs` allowlists,
`AllowAgentForwarding no`, `AllowTcpForwarding` scoping, `MaxAuthTries`.
Apply the same block to the desktops' on-demand sshd rather than only olympus.
`[auto]` (`nix eval` the rendered `sshd_config`).

## desktops disable reverse-path filtering
`common/desktop.nix:47` sets `checkReversePath = false`; `headless.nix:37`
keeps it `true`. This is usually a workaround for a VPN/multi-homing edge —
the wg-quick clients are full-tunnel, which is precisely the case that *doesn't*
need it. Try `"loose"` (or removing the line) and see whether the tunnels still
come up. `[auto]` for it evaluating; `[manual]` for "the VPN still works".

# Bugs

## confirmed in the tree

### the wallpaper path is hand-placed and hardcoded
`sway/default.nix:132`: `exec mpvpaper ${host.display.primary} /home/dk/wallpaper/current`
depends on a file no module puts there, and hardcodes a path while
`host.theme.wallpaper` (`host.nix:146-149`) exists and is read by nothing.
Folded into the stylix work below. `[auto]` for the option being read;
`[manual]` for "a wallpaper is actually on screen".

## reported from use, not visible in the config

### Ctrl+Shift+F2 (VT switch) makes the sway bar disappear
Not reproducible by reading the config — the bar is a swaybar with
`hidden_state hide` / `mode dock` (`sway/kanshi.nix:57-60`), so a suspect is the
mode being lost across a VT switch rather than the bar dying. Next step is
`swaymsg -t get_bar_config` before and after, plus the sway log.
`[manual]` 

# Desktop & UX

## nvim as the default editor for text files
`$EDITOR` is already nvim — `home-manager/modules/nvim/default.nix:18` sets
`programs.nixvim.defaultEditor = true`. What is missing is the *graphical*
half: `home-manager/modules/desktop/default.nix:44-67` maps `xdg.mimeApps` for
mail, LibreOffice documents and PDFs, but nothing for `text/plain`, so
`xdg-open foo.txt` falls through to whatever happens to be registered.

nvim ships a terminal-only `.desktop` entry, so this wants a small
`ghostty -e nvim %f` wrapper entry (`xdg.desktopEntries.nvim`) mapped from
`text/plain` and the handful that follow it (`text/markdown`, `application/json`,
`text/x-shellscript`, `text/x-nix`). `[auto]` — `xdg-mime query default
text/plain` and an actual `xdg-open` after a switch.

## bar: pin ghostty's font to the bar's
The bar renders with `pango:FiraCode Nerd Font Propo` (`sway/kanshi.nix:57`);
`ghostty/default.nix:10` leaves `font-family` commented out, so the terminal
falls back to its bundled JetBrains Mono plus *Symbols Nerd Font* for the icon
range. Both cover the Material Design glyphs the bar uses — verified with
`ghostty +show-face` against the TTF cmap — so today they agree only by
coincidence of that fallback. Setting
`font-family = "FiraCode Nerd Font Mono"` (already installed via
`home-manager/modules/desktop` + fontconfig) makes bar and terminal the same
face, and any glyph that renders in one is then guaranteed in the other.
`[auto]` — `ghostty +show-face` reports the resolved face.

## bar: `powerProfiles` still polls once a second
`i3status-rust.nix:278` runs `interval = 1`, spawning a shell pipeline every
second forever — on the laptop, on battery — to read a value that only changes
when something explicitly sets it. Use i3status-rust's `signal = N`: raise the
interval to 30s+ and end the click handler (and
`power-profile-reconcile`, `:78`) with `pkill -SIGRTMIN+N i3status-rs` so the
block repaints immediately after the only events that change it.
`[auto]` — the interval is in the generated TOML, and the repaint-on-signal is
observable from the block's own output.

*(The same finding for `chargeLimit` is closed — it is `interval = 60` at
`:254` now. The `cpu` block's `interval = 1` at `:211` is a genuine meter and
should stay.)*

## bar: reuse the status viewer for the wg-quick tunnels
`unit-status-view` takes the unit as an argument — its own header already says
the tunnels can reuse it verbatim (`unit-status-view.nix:29-30`) — and the
tunnels are hand-toggled units in `host.userManagedUnits`
(`wireguard/default.nix:152`) exactly like `sshd`. A `service_status` block per
client interface, modelled on the sshd one (`i3status-rust.nix:309-347`), is a
few lines each and makes "is the VPN up" answerable from the bar instead of from
`systemctl`. `[auto]`

---

# Theming — stylix (decided)

Single source of truth for colorscheme/fonts/wallpaper across sway, ghostty,
nvim, zathura and gtk, driven from the existing `host.theme` struct
(`host.nix:136-150`) so per-host colour/opacity stays a host-struct fact rather
than a per-module literal.

State today: `host.theme.{base16,opacity,wallpaper}` are declared and read by
**nothing** (`grep -rn 'host.theme' --include='*.nix' .` returns no consumers) —
pure scaffolding, dead until this lands. It also absorbs two other items: the
hardcoded wallpaper path (`sway/default.nix:132`) and ghostty's commented-out
`font-family` / `background-opacity = 0.8` (`ghostty/default.nix:10-11`).

`[auto]` — after the change, the same grep must show consumers, and
`nix flake check` must build all three hosts. Whether the result *looks* right
is `[manual]`.

---

# Passwords & keyring — Vaultwarden (decided)

Two layers usually conflated; they stay separate decisions.

**(1) Secret Service** (`org.freedesktop.secrets` over D-Bus) — what apps read
and write tokens from. Nothing provides it today. Path of least resistance on
sway: `services.gnome.gnome-keyring.enable`, run as a session daemon
(`--components=secrets,ssh`), unlocked by the login password via
`pam_gnome_keyring` in the **greetd** PAM service
(`security.pam.services.greetd.enableGnomeKeyring = true`, alongside the
existing `security.pam.services.swaylock` at `desktop.nix:96`). Stays open for
the rest of the session. `[auto]` — `busctl --user list | grep secrets` plus the
PAM stack in the built config.

**(2) Password manager** — **Vaultwarden on olympus**. Self-hosted behind the
existing nginx wildcard vhost and agenix; Bitwarden clients + the browser
extension pointed at it. Real multi-device sync, no `.kdbx` conflict copies.
Costs one service and an admin-token secret.

Notes for when it is built:
- vhost shape is `sslVhost { }` from `common/modules/nginx` — but **do not**
  put it behind `nextcloudSSO`: the mobile/browser clients speak the Bitwarden
  API and cannot pass an `auth_request` gate. Gate `/admin` only, or leave
  `/admin` disabled and set no admin token at all.
- new agenix secret for the admin token; remember `git add -N`.
- the desktop module currently ships **Proton Pass**
  (`home-manager/modules/desktop`) — decide whether it goes at cutover or
  stays as a second, unrelated vault.
- fingerprint unlock: hermes has `fprintd` (`common/modules/fingerprint`), which
  the Bitwarden desktop client can use for unlock.

`[auto]` for the service, vhost, secret wiring and `systemctl status
vaultwarden`; `[manual]` for the clients actually syncing.

---

# Energy (hermes)

Status quo is better than the last review recorded: `nixos-hardware`'s
`framework-16-7040-amd` module is imported (`flake.nix:101`), which brings
`amd_pstate=active` and enables `power-profiles-daemon` — and
`sway/i3status-rust.nix:78-96` now *drives* it, reconciling the profile on
lid/AC transitions. Verified by evaluating hermes: `services.power-profiles-daemon.enable = true`,
`boot.kernelParams = ["amd_pstate=active" "amdgpu.dcdebugmask=0x10" …]`.

What is left, roughly by impact:

## panel: amdgpu adaptive backlight (ABM)
Not set — `amdgpu.abmlevel` is absent from hermes's evaluated `kernelParams`.
`boot.kernelParams = [ "amdgpu.abmlevel=1" ]` (levels 0–4) is panel-side
backlight reduction with a compensating contrast shift: real backlight savings
for a minor colour-accuracy cost, and runtime-togglable via the connector's
`panel_power_savings` sysfs attribute, so it can be flipped on battery only —
which the existing AC/lid reconcile script is the natural place for.
`[auto]` for the parameter and the sysfs attribute's value; `[manual]` for
whether the colour shift is acceptable and what it actually saves.

## bluetooth radio is powered at every boot
`hermes/configuration.nix:59` sets `powerOnBoot = true` (confirmed by eval)
whether or not anything ever pairs; blueman toggles it on demand anyway. Flip to
`false`. `[auto]` — `bluetoothctl show` / `rfkill list` after a reboot.

## wifi powersave is off fleet-wide
`common/modules/wifi/default.nix:32` sets `powersave = false` deliberately, to
avoid latency spikes (`:11`). That is a 100%-of-the-time radio cost for a
sometimes-problem. Worth re-measuring under the current stack, or enabling it on
battery only via a NetworkManager dispatcher script — the lid/AC machinery for
"on battery" already exists. `[auto]` for the setting; `[manual]` for the
latency measurement that justifies either answer.

## suspend depth: s2idle drains
The 7040 Framework has no S3, so suspend is s2idle and still burns ~1%/h; the
lid path ends in `systemctl suspend`
(`common/modules/wifi/default.nix:88`), so a forgotten closed laptop drains for
days. Switch to `systemctl suspend-then-hibernate` with a
`HibernateDelaySec` of ~2h.

**Blocker to check first, on hermes:** hibernation needs `boot.resumeDevice`
set and a swap device ≥ RAM. hermes has exactly one swap partition
(`hermes/hardware-configuration.nix:43-45`, by-uuid `cf70f01c…`) and no
`resumeDevice` anywhere in the flake — and its size could not be checked from
here. `lsblk -b -o NAME,SIZE /dev/disk/by-uuid/cf70f01c-2bcc-49f3-bdea-5584615d4e91`
against `free -b` decides whether this item is a two-line change or a
repartition. `[auto]` once run on hermes.

## measurement & housekeeping
`powertop` for auditing (per-device tunables, wakeup offenders).
`powerManagement.powertop.enable = true` auto-applies its tunables at boot, but
that includes USB autosuspend, which bites input devices and BT dongles — prefer
cherry-picking what it suggests. `[manual]`

---

# Performance & build

## per-host `max-jobs` / `cores`
Neither is set anywhere (`grep -rn 'max-jobs\|cores' --include='*.nix' .` is
empty), so both take nix's defaults. `max-jobs` is how many derivations build
concurrently; `cores` is `NIX_BUILD_CORES`, the `-j` *inside* one build. Their
product can oversubscribe the CPU, so tune per host (hermes 16c, olympus 8c
EPYC) to trade build-graph width against per-build parallelism. Natural home is
a `host.build.{maxJobs,cores}` pair on the struct rather than per-host literals.
`[auto]` for the evaluated `nix.settings`; `[manual]` for whether it is faster.

## build in RAM where memory allows
`boot.tmp.useTmpfs = true` puts `/tmp` (nix's build dir) on tmpfs → faster build
IO, no SSD wear. Caveat: a big build (chromium, fat closures) can OOM, so **not**
on the RAM-limited olympus VPS. Gate it on the host struct, not a per-host line.
`[auto]` — `findmnt /tmp` after a switch.

## inputs that do not follow nixpkgs
`nixvim` and `zen-browser` both have their `inputs.nixpkgs.follows` commented
out (`flake.nix:13`, `:17-19`) — zen-browser's with a note that it needs
`libgbm` from unstable. Each unfollowed input pulls a second nixpkgs into the
lock, which means duplicate evals and cache misses for anything they build.
Since the flake *is* on unstable, re-testing the `follows` for both is cheap.
`[auto]` — `nix flake metadata` shows how many nixpkgs are in the lock, and
`nix flake check` proves it still builds.

## hestia: drop nvidia from the initrd
`hestia/configuration.nix:56-61` lists
`boot.initrd.kernelModules = [ "nvidia" "nvidia_modeset" "nvidia_uvm" "nvidia_drm" ]`,
forcing the proprietary driver into the initrd for early KMS. The 595 module
embeds GSP firmware → `nvidia.ko.xz` is 82M compressed, so every generation's
initrd is ~199M; the 510M ESP then fits ~2 generations, which is why
`host.keepGenerations` is pinned to `2` on hestia (`:30`) against the struct's
default of 10 (`host.nix:36`) — otherwise the systemd-boot install fails with
"No space left on device".

Removing the line lets the driver load in stage 2 instead, shrinking each initrd
to ~30M so ~15 generations fit and `keepGenerations` can go back up. Trade-off:
loss of early KMS = one console mode-switch flicker during boot, cosmetic here
since hestia has no encrypted root needing an early graphical prompt.
`[auto]` — initrd size and `du /boot/efi` are both measurable, and the flicker
is the only `[manual]` part.

---

# Code hygiene

## dead code & unused scaffolding
- **Commented-out code** scattered: `home.nix:13,15` (tmux/zellij),
  `desktop/default.nix:26` (`# lutris`), `sway/default.nix:37-39` (nvidia env
  vars), `sway/default.nix:86-88` (pre-swayosd `pactl` keybinds),
  `common.nix:85` (`# xkb.variant = "dvorak"`), `ghostty/default.nix:10,14`,
  `flake.nix:6,13,17-19`. Decide keep-vs-delete per site; the nvidia and
  zen-browser ones carry information and are worth converting to prose
  comments rather than deleting. `[auto]`

## duplication & single-source-of-truth
- **Keyboard layout in three places, two disagreeing**: `common.nix:84`
  `xkb.layout = "gb"`, `home.nix:28` `home.keyboard.layout = "gb"`, and
  `sway/default.nix:60` `xkb_layout = "gb,de,us"`. The sway one is the real
  desktop behaviour; the other two are the console/XWayland fallback. A
  `host.keyboard.{layout,variant,options}` triple on the struct, with sway
  deriving its multi-layout list from it, would leave one authority.
  `[auto]` — the three evaluated values can be diffed.
- **`"dk"` / `/home/dk`** hardcoded in ~10 spots (`common.nix`, `home.nix`,
  `samba`, `calendar`, `nextcloud-sync`, `sway`). Acceptable for a single-user
  fleet, but there is no shared constant; `host.user` would be the obvious one,
  and it is what the wallpaper/logs paths in sway would consume too. `[auto]`

## nix idiom
- **`lib.mkForce` where nothing forces**: `hestia/configuration.nix:95` sets
  `networking.networkmanager.dns = lib.mkForce "none"`, but no other module in
  the flake defines that option (`common/modules/wifi/default.nix:28-35` sets
  only `enable` and `wifi.*`), so the `mkForce` overrides nothing but the
  nixpkgs default and a plain assignment would do. The general rule the
  original note was reaching for still holds: set shared values with
  `lib.mkDefault` in the bases so hosts override cleanly without reaching for
  `mkForce`. `[auto]` — drop the `mkForce` and `nix flake check`; a real
  conflict fails loudly with "The option … has conflicting definitions".
- **narrow `allowUnfree`**: `common/common.nix:56` sets
  `nixpkgs.config.allowUnfree = true` for everything, and
  `home-manager/modules/nvim/default.nix:19` sets it again for nixvim's own
  nixpkgs. Replacing the global with an `allowUnfreePredicate` listing the
  actual packages (nvidia, steam, the Framework firmware blob, zen-browser…)
  documents *why* unfree is needed and turns a surprise unfree dependency into
  a build error instead of a silent pull. `[auto]` — `nix flake check` fails on
  anything unfree not in the list, which is precisely the point.

## cosmetic / minor
- **Unused module arguments**: `olympus/configuration.nix:3-4` declares `lib`
  and `pkgs` and uses neither; `hermes/configuration.nix:3` declares an unused
  `lib`; `common/common.nix:2` declares an unused `config` (`nixpkgs.config` at
  `:56` is an attribute path, not the argument). `[auto]`
- **`sway/default.nix:194`** `programs.i3status.enable = false` — already the
  default, and misleading next to `programs.i3status-rust` being the thing
  actually in use. `[auto]`
- **`sway/default.nix:20`** `checkConfig = false` with no comment explaining
  why validation is off. Either restore the check or write the one-line reason.
  `[auto]` — flipping it back either builds or does not.
- **`home.stateVersion = "24.11"`** (`home.nix:23`) trails the hosts' `25.05`.
  Independent by design, but worth a comment saying so, since the whole point
  of the host struct is one authoritative version. `[auto]`
- **fish nits** (`home-manager/modules/fish/default.nix`): `l` (`:39-41`) and
  `ll` (`:42-44`) are byte-identical (`eza -l $argv`); `mkcd` (`:50-52`) breaks
  on multiple args (`mkdir -p $argv && cd $argv`); `cat`→`bat` (`:46`) and
  `ls`→`eza` (`:33`) are *functions*, so they shadow the real binaries in every
  interactive shell, including in scripts sourced from one. `[auto]`
- **`hardware.enableAllFirmware = true`** (`hermes:56`) pulls the full unfree
  firmware set. `enableRedistributableFirmware` — already implied by the
  nixos-hardware framework module now in use — is usually enough; diff the
  closures before keeping both. `[auto]`
- **`vulkan-tools`** sits in `hardware.graphics.extraPackages`
  (`hestia:72`) — that list is for driver libs loaded into every GL/Vulkan
  client, not CLI tools. It is *also* already in
  `home-manager/modules/desktop/default.nix:29`, so the hestia entry is
  redundant as well as misplaced. `[auto]`
- **`udiskie.tray = "auto"; # FIXME does not show`**
  (`desktop/default.nix:74`) — an unresolved FIXME shipped as config. `"auto"`
  hides the icon when nothing is mounted; if the intent is always-visible it
  wants `"always"`, and if the tray itself is missing it wants a status-notifier
  host in the bar. `[manual]` to confirm the icon appears.
- **Trailing whitespace**: `sway/default.nix:132`,
  `nvim/plugins/lsp.nix:167`. `[auto]`

---

# Closed since the 2026-06 / 2026-07 reviews

Kept so they are not re-proposed.

- **sway execs wrote to a directory nothing creates** — `wl-gammarelay-rs`'s
  `2>> /home/dk/logs/...` redirect is gone (`sway/default.nix:134`); nothing
  declarative ever created `/home/dk/logs`, so on a host where it is absent the
  exec fails and the `Ctrl/Shift+XF86MonBrightness*` bindings die with it.
  stderr now lands in the sway log like every other exec.
- **backup verification & alerting** (was priority 1) — done 2026-08-31, the two
  follow-ups left open by **backup for olympus** below. `restic-check.service` +
  weekly timer (`Persistent`, 30 min jitter, idle I/O) runs on the repository
  owner and fails on either way a backup lies: `restic check
  --read-data-subset=10%` for rot (deliberately *not* `--with-cache` — trusting
  the local metadata cache is what would hide a damaged index; the whole repo is
  re-read over ~10 runs), and a snapshot-age test for abandonment, since a repo
  nothing writes to any more passes `check` forever. Every backup unit carries
  the module's `alertHook`, so a failure runs `backup-alert@%n.service`
  (journal + critical desktop notification + a stamp under
  `/var/lib/backup-alerts`) and the unit's next success clears the stamp; a new
  `custom` block in `sway/i3status-rust.nix` shows the standing failures and
  middle-clicks into the failing unit's journal. The stamp is the part that
  survives a failure nobody was logged in for. No off switch — it comes with
  the module. `restic backup`/`forget` gained `--retry-lock=30m` so a long
  check cannot turn into a false backup failure. Verified: both freshness
  branches against a scratch repo, the notification path on hestia's session.
  *Remaining follow-up: the repo is still a single copy — see Reliability.*
- **`host.backup` was configuring the module** — the struct is down to
  `backup.pull = [ "mail" ]` (a list of source names; non-empty ⇒ this host owns
  the repository). Repository path, cache dir, retention, check schedule, alert
  directory and each source's snapshot flags/max age live in
  `common/modules/backup`, which exports them as the `backupRepo` module arg —
  there is one repo in the fleet, so nothing had anything to vary against, and
  `mail-backup` no longer repeats the restic env block or the
  `--host olympus --tag mail` literals. `backup.serve` is gone with it: the
  serving end keys on `services.stalwart.enable`, because only the host with the
  store can dump it. The channel's verbs are now `stalwart-export` /
  `stalwart-import` (`<service>-<verb>`, so a second service can share the key)
  — a wire protocol between the hosts, so **switch olympus before hestia**.
- **backup for olympus** (was priority 1) — done: `common/modules/backup` owns
  the restic repo on hestia and `common/modules/mail-backup` pulls the stalwart
  store into it over a forced-command ssh channel, with `mail-restore` for the
  way back. *Open follow-up: the repository is a single copy on one desktop;
  scheduled `check` and failure alerting landed — see the entry above.*
- **`nixos-hardware`'s `framework-16-7040-amd`** — adopted (`flake.nix:101`).
- **`services.power-profiles-daemon`** — now enabled (via that module) *and*
  driven: `sway/i3status-rust.nix` reconciles the profile across AC and lid
  transitions and remembers a manual override.
- **hestia sway crashing via libseat** — no longer reported.
- **`chargeLimit` polling every second** — now `interval = 60`
  (`i3status-rust.nix:254`).
- **setuid `framework_tool`** — replaced by `common/modules/charge-limit`, a
  udev rule that group-owns the battery's `charge_control_end_threshold`, so no
  setuid EC tool is on the system.
- **cert-expiry alerting** (was priority 1) — superseded by the real fix, live
  since 2026-08-30: `common/modules/acme` renews the wildcard with lego over
  dns-01, gated by `host.tls.acme` (true on olympus). `*.dklaassen.de` + apex,
  served by every vhost and by stalwart's SMTP/IMAP, which the cert's
  `reloadServices` restarts on renewal. Nothing watches an expiry date any more
  because nothing is hand-rotated;
  `systemctl status acme-order-renew-dklaassen.de.service` is the health check.
  The CA is Let's Encrypt, not IONOS: their endpoint is DV-only and issues
  solely against a purchased, unassigned certificate, which this account does
  not have and a panel reissue did not produce — the module header records both
  refusal strings and the single-use EAB behaviour so it is not retried. The
  IONOS API key is still used, as the *zone* credential lego needs to write the
  challenge TXT. *Open follow-up: `ssl-fullchain.age` / `ssl-key.age` are now
  dead weight kept only as the `host.tls.acme = false` rollback, and can be
  dropped from `secrets.nix` and `common/modules/nginx` once a renewal has run
  unattended.*
- **`documentation.nixos.enable = false` on olympus** — dropped from the list.
- **stable channel for olympus** — decided against; see *Decisions on record*.
