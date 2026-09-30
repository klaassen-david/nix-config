# Power logger scope

**Ruling** [USER 2026-09-30]: the power logger (`common/modules/power-log`)
runs on hermes only, opted into by importing it in `hermes/configuration.nix`.

**Why**: the point is battery life. Only hermes has a battery, the context
fields (AC, lid, panel power savings) are laptop concepts, and hermes is where
the energy backlog in `TODO.md` lives.

**Rejected**: hestia as well (RAPL + `nvidia-smi` GPU power, no battery).

**Revisit if**: a hestia question needs power data — e.g. judging the
`gpuPowerLimitWatts` cap by energy rather than stability.
