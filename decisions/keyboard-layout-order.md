# keyboard-layout-order: fleet default on every host

**Ruling** [USER 2026-11-25]: every host uses the `host.keyboard` default
`gb,de_ccedilla,us(dvorak)` (uk → de → dvorak, uk active at start). hestia no
longer overrides it. gb stays first, so the Wine reasoning below still holds.

## History

**Ruling** [USER 2026-11-15]: hestia's sway layout list is `gb,us(dvorak),de_ccedilla`
(was `us(dvorak),gb,de_ccedilla`). Sway starts on gb; dvorak is selected by hand
with Win+Space each session — no startup auto-switch.

**Why**: XWayland under sway receives sway's keymap, and Wine detects the layout
from its first group, not the active one. With dvorak first, Wine games (a Unity
game under Proton) got dvorak key bindings, and switching layouts in sway before
or during the game changed nothing. `services.xserver.xkb` already held plain
`us`; it does not reach XWayland in a sway session.

**Rejected**:
- gb first plus a sway startup `xkb_switch_layout` to dvorak — a re-plugged
  keyboard (e.g. the Wooting reconnecting) comes back on gb anyway.
- Leave the order, wrap each such game in `swaymsg` layout switches before
  launch and after exit.

**Side effect**: the console keymap (first entry) is now gb instead of plain us.

*Revisit if*: Wine/Proton starts mapping keys from the active xkb group (e.g. the
winewayland driver becomes the default for these games), or a startup switch
proves robust across keyboard re-plugs.
