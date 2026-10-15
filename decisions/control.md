# control: the phone_controller relay on olympus

**Ruling** [USER 2026-10-15]: `control.dklaassen.de` is served by a
hot-swapped app on olympus (`common/modules/control`, `hot-swap/apps.nix`
entry `control`, port 8080), not by a process started by hand. Releases are
built on a desktop (static musl binary + the phone UI) and pushed to
`~/deploy/control/releases/<v>/`; olympus never builds them. Activation is the
usual `echo <v> > ~/deploy/control/want && systemctl start control-swap`, so an
agent session can deploy without sudo.

**No SSO** [USER 2026-10-15]: the vhost drops the Nextcloud SSO gate it had
in `headless.nix`. Phones must open their join link without a login, and the
desktop clients (games, the mouse agent) have no session cookie; behind the gate
they were redirected, which broke remote use. Access control moves into the
app: games authenticate with API tokens created and revoked only with the
`control token` CLI on olympus, and a phone reaches a game only through a join
link that game requested, one phone per link.

**Hardening** [USER 2026-10-15, after an adversarial review]: control stays
on `control.dklaassen.de`, so it is same-site with every SSO vhost and the
browser sends it the `.dklaassen.de` oauth2-proxy cookie. nginx strips
`Cookie`/`Set-Cookie` there and sends a strict CSP, `nosniff` and
`no-referrer`; join links are secrets in the path, so the TLS vhost has no
access log (the plain-HTTP redirect and nginx's error log can still record a
path; clients are only ever given https links). The unit is sandboxed
(`ProtectHome=tmpfs` with only `~/deploy/control` bound, state writable;
loopback-only IP; no capabilities; `PrivatePIDs` and no `AF_UNIX`, because a
dk process could otherwise open another dk process's `/proc/<pid>/root` or the
user bus and step outside the sandbox): it parses input from anyone holding a
link and would otherwise be dk with dk's home. A dedicated uid would be
stronger; it needs per-app users in hot-swap, not done yet.

**Placement**: olympus is the only public host, and the relay is tiny. It binds
`127.0.0.1:8080`; nginx is the only door, so the app has no mesh `sources` and
no firewall rule. It does not take the orchestrator proxy key
(`hotSwap.apps.<n>.proxyKey = false`): it trusts nobody by proxy header, and
the key has no business in its state directory. `hot-swap/vhosts.nix` skips
apps placed on olympus, since those bring their own vhost.

**Rejected**:
- a flake input built by nix-config — every game change would be an olympus
  switch, and olympus would build or fetch the closure.
- `nixos-rebuild --target-host` from a desktop — olympus trusts only root, so
  store paths copied by dk must be signed, and nothing signs desktop builds.
- a plain dk user service — no health check or rollback, and outside the
  declarative config.

**Revisit if**: the relay gains accounts or anything worth more than a game
session (then a dedicated uid for the unit), or control moves to a different
domain/host (then drop the cookie stripping and reconsider the CSP).
