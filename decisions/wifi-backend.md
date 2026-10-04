# hermes drives wifi through wpa_supplicant, not iwd

**Ruling** [USER 2026-10-04]: NetworkManager's wifi backend on hermes is
**wpa_supplicant** (`common/modules/wifi/default.nix`), and the MT7922 runs with
`disable_aspm=1` (`hermes/configuration.nix`). Both were prompted by frequent
drops on a weak Bouygues Bbox; only the first is a fix for them.

**The drops were an iwd defect, not signal or roaming.** The Bbox requires MFP
(PMF) on `Bbox-B8B9B5CB-Plus` — every BSS — so on re-association it still holds
a security association and answers `status 30` with an association-comeback time
of **1953 TU**. iwd 3.12 `src/netdev.c`:

    #define MAX_COMEBACK_DELAY 1200
    if (timeout <= MAX_COMEBACK_DELAY) { l_debug(...); return; }
    l_debug("Comeback delay of %u exceeded maximum of %u, deauthenticating", ...);
    netdev_deauth_and_fail_connection(...);

1953 > 1200, so iwd deauthenticated instead of waiting ~2 s. One boot logged 50
`rejected association temporarily`, 50 kernel `comeback` events and 50
`aborting association ... by local choice` — 1:1:1. The constant is compile-time;
no iwd setting reaches it. wpa_supplicant 2.12 `sme.c` accepts up to 60000 TU and
registers a retry timer (`sme_try_assoc_comeback`), so the same AP works.

**Rejected**: *RSSI roam thresholds* (`RoamThreshold*` at -85/-88,
`RoamRetryInterval=300`) — tested live for 20 min and it got **worse**, 10 roam
attempts and 8 failed, while roaming at -73 dBm, which disproved the
weak-signal-roaming theory outright. *`ManagementFrameProtection=0`* — `-Plus`
sets MFP-required on all four BSSes, so disabling MFP makes it unconnectable.
*`[Scan] DisableRoamingScan=true`* — suppresses the trigger, not the bug, and is
global, so hermes would stop roaming on eduroam and every other multi-AP site.
*Patching `MAX_COMEBACK_DELAY` through an overlay* — works and keeps iwd, but
carries a patch across nixpkgs bumps for a backend we have no measured reason to
prefer.

**The original iwd choice was never recorded.** Commit 6d1d8c2 "better wifi"
(2026-04-07) moved hermes off standalone `networking.wireless` onto
NetworkManager and picked iwd in the same commit, with no rationale and bundled
with unrelated changes. The Framework/MT7922 case for iwd in the wild is an
anecdotal throughput claim for the 13" AMD, explicitly unconfirmed for the 16";
the most specific MT7921 report runs the other way (iwd 4-way handshake timeout
on 5 GHz where wpa_supplicant works).

**ASPM is unrelated to the drops** and was set on its own merits: it is the
most-cited mt7921e remedy for latency spikes and link loss, and it was off
(`disable_aspm = N`, no modprobe config). It fixes nothing diagnosed here.

**Cost**: `Bbox-B8B9B5CB-Plus` existed only as `/var/lib/iwd/*.psk`, never as an
NM keyfile, so its password had to be re-entered. The five real NM keyfiles
(`/etc/NetworkManager/system-connections`) carried over untouched. Networks that
live only in iwd's store are invisible to NM's store and are lost with it — that
asymmetry is also why ten profiles disappeared during this investigation.
Dropping iwd also renames the interface — iwd forces `wlan0`, predictable naming
gives `wlp1s0` — which silently invalidates any NM profile carrying
`connection.interface-name = wlan0`; NM reports it as "Wi-Fi network could not be
found". The status bar's middle click now runs `nmtui`, since `iwgtk` only ever
spoke to iwd.

**Revisit if**: hermes shows MT7922-specific faults under wpa_supplicant (the
5 GHz handshake and 3-second signal-change reports are the ones to watch), or a
measured throughput regression against iwd turns up — in which case the overlay
patch above is the way back, not a plain backend flip.
