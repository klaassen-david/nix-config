# Wallpaper per host

**Ruling** [USER 2026-09-30]: the mpvpaper wallpaper comes from
`host.theme.wallpaper`; null (the default) starts no mpvpaper at all.
hestia sets `/home/dk/wallpaper/current`; hermes sets nothing.

**Why**: the sway config started `mpvpaper … /home/dk/wallpaper/current` on
every desktop, and on hermes that file does not exist — a resident process
with nothing to play, and a latent full-time video decode on a laptop the day
a file lands there (found in the 2026-09-26 powertop snapshot).

**Rejected**: a fixed path on every desktop with the file simply left absent
on hermes (the status quo).

**Revisit if**: hermes should get a wallpaper — then consider mpvpaper's
`-p`/`-s` (pause/stop while covered) before setting it.
