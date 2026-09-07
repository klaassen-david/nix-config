# sway checkConfig stays off

**Ruling** [AGENT 2026-09-07]: `wayland.windowManager.sway.checkConfig =
false` stays, with the reason as a comment in the module. Restoring the check
was tried: `sway -C` initializes a renderer, the build sandbox has no DRM FD
to create one, and the sway.conf derivation fails on every desktop host
("Cannot create Vulkan renderer: no DRM FD available").

**Revisit if**: sway's validate mode stops needing a renderer, or home-manager
grows a genuinely headless config check.
