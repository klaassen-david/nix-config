{
  lib,
  pkgs,
  host,
  inputs,
  osConfig,
  ...
}:

# The orchestrator (~/code/orchestrator, its docs/deploy-worker.md) on hermes and hestia: the
# worker (orch-worker.{socket,service}, orch.slice with its task slices) and `orch` on PATH.
# hermes also runs agentd (orch-agentd.*, runner units in orch-runners.slice, the local
# dashboard on 127.0.0.1:7468, `orch dashboard` prints its login URL); agentd reads the
# harness's own logins from ~/.config/orch/accounts.toml (`orch accounts`), never cswap. hestia
# runs the worker only, its bulky data on /mnt/games (decisions/orchestrator-worker.md).
#
# The input is pinned to a commit `orch deployable <rev>` accepts (gate `full` passed on that
# tree). To update: pick a newer deployable commit, change `rev` in flake.nix, then
# `nix flake update orchestrator`.
#
# Needs lingering (common/modules/orch); the module's build fails without it, so a logout can't
# end running tasks.

let
  orch = inputs.orchestrator.packages.${pkgs.stdenv.hostPlatform.system};
in
{
  imports = [ inputs.orchestrator.homeManagerModules.default ];

  services.orch = lib.mkMerge [
    {
      enable = true;
      host = host.hostName; # task ids T-<host>-…
      # 100 GiB absolute per filesystem: 15 % of hermes's 1.8 TiB / or of hestia's 1.4 TiB
      # /mnt/games would hold most tasks back.
      diskFloor = lib.mkDefault {
        gib = 100;
        percent = 0;
      };
      plugins = [ orch.orch-plugin-rust ];
      # The link to the coordinator on olympus (common/modules/orch-coordinator); the token is
      # this host's agenix secret (common/modules/orch).
      coordinator = {
        url = "wss://orch.dklaassen.de/link/v1";
        tokenFile = "/run/agenix/orch-link-${host.hostName}";
      };
      # Accept windows and leases (fleet L3). Trees move over ssh with this worker's own key
      # (common/modules/orch); the peer's endpoint serves snapshots of the repositories under
      # endpointAllow.
      fleet = {
        sshKeyFile = "/run/agenix/orch-fleet-${host.hostName}";
        endpointAllow = [
          "/home/dk/code"
          "/home/dk/.local/share/orch/clones"
        ];
      };
    }
    (lib.mkIf (host.hostName == "hermes") {
      roles = [
        "worker"
        "agentd"
      ];
      # With nix-daemon's budget beside it (5 GiB with hestia, 10 without;
      # common/modules/remote-builder), ~11 GiB of MemTotal (30.6) stay for the desktop, zram's
      # own pages and the system: 26 with hestia froze hermes on 2026-10-07 22:07, and 19 + 6
      # most likely on 2026-10-08 08:54 (Zen alone takes 3-5 GiB).
      ceilingGiB = if osConfig.remoteBuilder.useHestia then 14 else 12;
      # Merge jobs' gates build their Nix checks in hestia's store: only status and errors come
      # back over hermes's usually slow link, no outputs (orchestrator ruling 117).
      agentd.gateNixStore = lib.mkIf osConfig.remoteBuilder.useHestia "ssh-ng://nix-ssh@hestia";
      # Closing the lid ends the accept window and gives idempotent leased tasks back.
      fleet = {
        sleepInhibitor = true;
        peers.hestia = "dk@hestia";
      };
      # Builds go to hestia; hermes's two slots serve only while hestia is out of reach or full
      # (orchestrator incremental-builds IB6, R2, R7; DECISIONS 117).
      worker = {
        offload.enable = true;
        warmSlots = 2;
      };
      projects = {
        ostt3 = {
          path = "/home/dk/code/ostt3";
          flake = "git+file:///home/dk/code/ostt3?ref=main";
        };
        orchestrator = {
          path = "/home/dk/code/orchestrator";
          flake = "git+file:///home/dk/code/orchestrator?ref=main";
        };
      };
    })
    (lib.mkIf (host.hostName == "hestia") {
      roles = [ "worker" ];
      ceilingGiB = 27; # MemTotal 31 GiB less 4
      # clones, trees, warm targets; / has 457 GiB, /mnt/games 1.4 TiB. dk owns /mnt/games, so
      # the worker makes the directory.
      dataRoot = "/mnt/games/orch";
      # The floor holds on every filesystem the worker writes: results, logs and dev shells stay
      # on / (~68 GiB free on 2026-10-06, nix min-free 30 GiB), so 100 GiB would hold every task.
      diskFloor = {
        gib = 20;
        percent = 0;
      };
      # Pulls hermes's waiting tasks whenever it has room, without an accept window.
      fleet = {
        acceptsAlways = true;
        peers.hermes = "dk@hermes";
      };
      worker.warmSlots = 6; # IB6 R7: six warm build slots on hestia
      # Tasks of hermes's projects leased here: the worker knows the project by name and builds
      # its dev shell from the leased tree. No checkout or flake here (hestia has no copy of the
      # repository and can't reach olympus's).
      projects.orchestrator = { };
    })
  ];

  # At its ceiling the kernel kills inside orch.slice instead of thrashing hermes in swap (froze
  # it on 2026-10-07). Under 20 s of heavy memory pressure, systemd-oomd kills a task first.
  # Tasks get 8 of the 16 cores, beside nix-daemon's cap (common/modules/remote-builder), so the
  # desktop and the agents keep some and the laptop stays below its thermal limit.
  # The desktop (app.slice: browser, mail, terminals; session.slice: sway, the bar) is protected
  # up to MemoryLow, so under pressure the kernel reclaims from orch first.
  # keep-old: a switch must never stop these two slices. Without it, the switch that introduced
  # them stopped both, and with them every window and session service (2026-10-08 17:02); a
  # changed MemoryLow applies on the switch's daemon-reload instead.
  systemd.user.slices = lib.mkIf (host.hostName == "hermes") {
    app = {
      Unit = {
        Description = "User Application Slice";
        X-SwitchMethod = "keep-old";
      };
      Slice.MemoryLow = "6G";
    };
    session = {
      Unit = {
        Description = "User Core Session Slice";
        X-SwitchMethod = "keep-old";
      };
      Slice.MemoryLow = "512M";
    };
    orch.Slice.MemorySwapMax = "2G";
    orch-tasks.Slice = {
      CPUQuota = "800%";
      ManagedOOMMemoryPressure = "kill";
      ManagedOOMMemoryPressureLimit = "50%";
      ManagedOOMMemoryPressureDurationSec = "20s";
    };
  };
}
