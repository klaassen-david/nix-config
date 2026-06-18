# nix-config

Multi-host NixOS flake (x86_64-linux only). Three hosts, one shared base:

| Host      | Role     | Machine                       | Notes                                  |
|-----------|----------|-------------------------------|----------------------------------------|
| `olympus` | `vps`    | headless VPS                  | server: nginx/SSO, nextcloud, stalwart, wg-easy, wireguard hub |
| `hermes`  | `laptop` | Framework 16 (7040 AMD)       | desktop (sway), wireguard client       |
| `hestia`  | `tower`  | Nvidia tower                  | desktop (sway), wireguard client       |

Inputs track `nixpkgs-unstable` + `home-manager/master`. Unfree allowed.

## Layout

- `flake.nix` — `mkHost { host, hostModules?, hmModules? }` builds each `nixosConfigurations.<host>`. `specialArgs` passes `inputs` and `secretsPath = ./secrets`. `checks` builds every host's `system.build.toplevel`.
- `common/` — shared base:
  - `host.nix` — defines the `host.*` options struct (see below) and `imports`-ed everywhere via `common.nix`.
  - `common.nix` — base for *all* hosts (nix settings, user `dk`, agenix identity, fish, nh). Imports `host.nix` + `modules/wireguard`.
  - `headless.nix` — server base; imports `common.nix` + `modules/nginx`. Holds `control.dklaassen.de`, sshd, fail2ban.
  - `desktop.nix` — desktop base; imports `common.nix`. Sway/greetd, audio, steam, printing.
  - `modules/{nginx,nextcloud,stalwart,wg-easy,wireguard}/default.nix` — service modules.
- `<host>/configuration.nix` — per-host: imports a base (`headless.nix` or `desktop.nix`) + service modules, sets the `host` struct, hardware/bootloader.
- `home-manager/` — `home.nix` + `modules/*`; wired into every host via `mkHost`. `hmModules` adds the desktop bundle to laptop/tower only.
- `secrets/` — agenix (`secrets.nix` recipient list + `*.age` files).

## The `host` struct (`common/host.nix`)

Single source of truth per host. `hostName` drives `networking.hostName`; `role` (`vps`/`laptop`/`tower`) seeds capability defaults and feeds assertions; also `stateVersion`, `gpu`, `display.primary`, `capabilities.*`, `theme.*`, `firewall.*`. The evaluated struct is forwarded to home-manager as the `host` arg. Assertions enforce invariants (e.g. `vps ⇒ gpu = none`, laptop/tower need `display.primary`). Set it in `<host>/configuration.nix`, derive downstream — don't hardcode hostname/stateVersion elsewhere.

## Module-arg conventions

Beyond `inputs`/`secretsPath` (specialArgs) and `host` (forwarded to HM), the **nginx module exports two `_module.args`** that service vhosts consume:

- `sslVhost` — forceSSL + shared wildcard cert. TLS-only vhost: `"host" = sslVhost // { locations."/" = {...}; };`
- `nextcloudSSO` — the oauth2-proxy `auth_request` gate. SSO-gated vhost **must** use `lib.recursiveUpdate`, not `//`, because both define `locations` and a shallow merge would drop one:
  ```nix
  "host" = lib.recursiveUpdate (sslVhost // nextcloudSSO) { locations."/" = {...}; };
  ```

Any module needing these args (`nginx`, `nextcloud`, `stalwart`, `wg-easy`, `headless.nix`) **imports `../nginx`** (or `./modules/nginx`). NixOS dedups identical import paths, so multiple importers evaluate the module once — olympus importing it explicitly *and* via `headless.nix` is fine.

## SSO

One oauth2-proxy + one Nextcloud OAuth2 client gates all `*.dklaassen.de` vhosts. Login/callback live on the dedicated `auth.dklaassen.de` host; the parent-domain cookie (`cookie.domain = ".dklaassen.de"`) shares one session across `control`, `vpn`, etc. The Nextcloud client is the only non-declarative piece: created in Nextcloud's admin UI, its **redirect URI is immutable** (Nextcloud has no edit — changing it means delete + recreate, yielding a new `clientID` + secret). `clientID` is plaintext in `modules/nginx/default.nix`; the secret is `oauth2-client-secret.age`.

## agenix secrets

- **Single recipient**: every `.age` encrypts to the one `id_priv` key in `secrets/secrets.nix`; all hosts set `age.identityPaths = [ "/home/dk/.ssh/id_priv" ]`, so any host decrypts any secret at activation.
- Add a secret = append its filename to the `files` list in `secrets.nix`, then create `secrets/<name>.age`.
- Secret *content* is the raw value, single line (a WireGuard private key is just the base64 string — no `[Interface]`/`PrivateKey =`).
- **The user encrypts secrets themselves** (`cd secrets && agenix -e <name>.age`). Do not run the encryption for them, and **do not read or `cat` private-key material** — model configs around `privateKeyFile`/`configFile` references instead of inlining keys. Public keys (e.g. WireGuard peer pubkeys, oauth2 `clientID`) are not secret and live in plain `.nix`.
- `nix flake check` does **not** decrypt anything — it only evals/builds. It passes even when `.age` files are missing or undecryptable. Test decryption manually with `agenix -d <name>.age`.

## WireGuard

`modules/wireguard` self-selects by `host.role`: `vps` runs the `olympus` server interface (`networking.wireguard.interfaces`) + NAT; clients run on-demand `wg-quick` interfaces (`autostart = false`, full-tunnel). `tukl` is the university VPN on desktops, modeled declaratively with only its private key from agenix. Per-interface keys are `wg-<host>.age`; peer public keys are inlined in the `nodes` registry.

## Calendar & contacts (desktop)

`home-manager/modules/calendar` is a CalDAV/CardDAV pipeline (in the desktop HM bundle only): **pimsync** syncs every Nextcloud calendar/addressbook into a local vdir, **khal** reads the calendars (the i3status next-appointment block + `ikhal`), **khard** the contacts. Built on home-manager's `accounts.{calendar,contact}` registry — one account definition feeds both the sync engine and the CLI clients.

- **Calendar/contacts ≠ files.** This module is calendars/contacts only; arbitrary file sync stays in `../nextcloud-sync` (`nextcloudcmd`, Nextcloud Files/WebDAV). Same server (`nextcloud.dklaassen.de`), different protocols — complementary, both run.
- **Secret reuse.** Auth reuses the `nextcloud-cmd` app password (declared in `../nextcloud-sync` via the **home-manager** agenix module — `inputs.agenix.homeManagerModules.default`, decrypted to `$XDG_RUNTIME_DIR/agenix`, *not* the system `/run/agenix`). No new `.age`. `passwordCommand` wraps `cat` in `sh -c` because that path string contains a literal `$XDG_RUNTIME_DIR`. The module therefore depends on `../nextcloud-sync` being in the same bundle.
- **Multiple calendars under one account:** pimsync `extraPairDirectives = collections all` discovers them; khal `type = "discover"` loads each discovered subdir as its own calendar.
- **`primaryCollection`** sets only khal's `default_calendar` (the target for *new* events) — it must name a real discovered subdir (`ls ~/.local/share/calendars/nextcloud/`), not the account name, and never restricts which collections load.
- **pimsync ships no scheduler** (neither the HM module nor the nixpkgs package; the `interval` directive is daemon-only and inert under one-shot `sync`). Driven by a one-shot `pimsync sync` systemd-user service + timer, ordered after `agenix.service`. First run is manual (`pimsync sync`) to perform collection discovery before the vdir/khal show anything.

## Commands

```sh
nix flake check                        # eval + build every host's toplevel (run before deploy)
nix develop                            # devShell with `agenix` on PATH
nh os switch                           # local rebuild+switch (front-end; programs.nh, auto closure diff)
nixos-rebuild switch --flake .#<host>  # explicit per-host
```

- GC is `nh.clean` (keeps `host.keepGenerations` gens + 30d). Do **not** also enable `nix.gc.automatic` — running both is rejected.

## Deploying — known gotcha

`switch-to-configuration-ng` (the Rust activation tool on current unstable) can **busy-loop at 100% CPU in `block_on_jobs`** (D-Bus job-wait race) during a live `switch`/`test`, hanging the deploy with no systemd jobs pending. Workarounds:

- `nixos-rebuild boot --flake .#<host>` + `reboot` — `boot` only sets the new generation as default and skips live unit reconciliation, so it never spins. Preferred for the headless VPS.
- or set `system.switch.enableNg = false;` to fall back to the Perl implementation (if still packaged).

Verify decryptability and a console/recovery path before rebooting a remote host; nothing in the base touches sshd or the WAN interface, but the SSO/oauth2-proxy units may be degraded until the Nextcloud client is wired up.

## Style

Modules carry substantial header/section comments explaining *why* (trade-offs, manual prereqs, gotchas) — match that when editing. Keep the `host` struct authoritative; prefer deriving from it over per-host literals.
