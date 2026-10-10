# trainer: served from olympus, VPN only

**Ruling** [USER 2026-10-11]: nix-config takes the music trainer app as a flake
input `git+ssh://dk@dklaassen.de/home/dk/code/trainer` (the repo has no remote;
it lives on olympus). A new version is a commit there plus
`nix flake update trainer`. Every host evaluating the flake needs ssh to olympus;
root gets dk's key for that in common.nix, since `sudo nixos-rebuild` evaluates
as root.

**Rejected**: pushing to GitHub (a private repo needs an access token in every
host's nix.conf); a hand-built out-link on olympus (not declarative).

**Serving**: the app is a node server with an unauthenticated event log, so a
systemd service on 127.0.0.1:3030 behind an nginx vhost that admits only
10.100.0.0/16 (`common/modules/trainer`).

**Name resolution** [USER 2026-10-11]: for now a public A record
`trainer.dklaassen.de → 10.100.0.1` (the user adds it at IONOS) plus a static
hosts entry on every host. A resolver on olympus for VPN clients (split horizon,
pushed to phones via wg-easy) was explained and deferred: it routes all phone DNS
through olympus, needs every phone config regenerated, and breaks under Android
Private DNS set to a hostname.

**Naming** [USER 2026-10-11]: the repo calls the app `trainer` only — module,
input, service, vhost, state dir; the app's own name never appears here.

**Revisit if**: the repo gets a public remote (switch to a `github:` input).
