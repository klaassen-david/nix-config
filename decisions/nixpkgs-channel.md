# One nixpkgs channel for the fleet

**Ruling** [USER 2026-08-31]: olympus tracks `nixpkgs-unstable` like the
desktops. Pinning the server to a stable release (`nixos-25.05`) was
considered and dropped — one channel for three hosts is the point. The
commented `nixpkgs.url` line this referred to was deleted in the 2026-09-07
hygiene sweep.

**Revisit if**: an unstable regression actually takes olympus down, or the
server and the desktops start needing different upgrade cadences.
