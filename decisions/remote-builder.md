# hestia builds for hermes

**Ruling** [USER 2026-10-05]: hermes uses hestia as a Nix remote builder
(`common/modules/remote-builder`), over the mesh, VM tests included. Part of the
orchestrator's speed-up list of 2026-10-05: its gates' Nix checks and NixOS VM
tests are most of a gate's time, and parallel agents loaded hermes into flaky tests.

- ssh-ng as dk with `id_priv` to hestia's mesh address; hestia's host key is pinned.
- hestia trusts dk as a Nix user (a remote builder's user must be trusted); dk
  already has sudo there.
- A 5 s connect timeout: without the mesh, hermes builds locally.
- `builders-use-substitutes`: hestia fetches from the caches itself.

**Rejected:** a dedicated `nixremote` user with a forced command (more to maintain
for no gain, as dk is already root-equivalent on hestia); building on olympus (small
VPS, no KVM).

**Revisit if:** hestia's load from builds disturbs its own work or ostt3's
measurements (`measure` lock), or a third build host appears.
