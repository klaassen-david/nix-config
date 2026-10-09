{
  config,
  lib,
  pkgs,
  host,
  inputs,
  osConfig,
  ...
}:

# The orchestrator (~/code/orchestrator, its docs/deploy-worker.md) on hermes and hestia: the
# worker (orch-worker.{socket,service}, orch.slice with its task slices) and `orch` on PATH. The
# development host (`orchDevHost` below) also runs agentd (orch-agentd.*, runner units in
# orch-runners.slice, the local dashboard on 127.0.0.1:7468, `orch dashboard` prints its login
# URL); agentd reads the harness's own logins from ~/.config/orch/accounts.toml (`orch
# accounts`), never cswap. hestia's worker keeps its bulky data on /mnt/games
# (decisions/orchestrator-worker.md).
#
# Hand-over (orchestrator DECISIONS 136, 137): change `orchDevHost`; pause every agent (runner
# units outlive agentd) and switch the old host, which stops agentd; move ~/.local/state/orch/
# agentd.db* and accounts/, ~/.local/share/orch (clones without their target/ dirs, merges,
# records), ~/.config/orch/accounts.toml with its logins and the checkout ~/code/orchestrator to
# the same paths on the new host; then switch the new host. Same paths on either host, so
# agents' sessions resume by their cwd. The other host supervises over ssh (the API socket, the
# dashboard port forwarded).
#
# The input is pinned to a commit `orch deployable <rev>` accepts (gate `full` passed on that
# tree). To update: pick a newer deployable commit, change `rev` in flake.nix, then
# `nix flake update orchestrator`.
#
# Needs lingering (common/modules/orch); the module's build fails without it, so a logout can't
# end running tasks.

let
  orch = inputs.orchestrator.packages.${pkgs.stdenv.hostPlatform.system};
  # The host that runs agentd: the hand-over switch.
  orchDevHost = "hestia";
  isDev = host.hostName == orchDevHost;
in
{
  imports = [ inputs.orchestrator.homeManagerModules.default ];

  services.orch = lib.mkMerge [
    {
      enable = true;
      host = host.hostName; # task ids T-<host>-…
      roles = [ "worker" ] ++ lib.optional isDev "agentd";
      # 100 GiB absolute per filesystem: 15 % of hermes's 1.8 TiB / or of hestia's 1.4 TiB
      # /mnt/games would hold most tasks back.
      diskFloor = lib.mkDefault {
        gib = 100;
        percent = 0;
      };
      plugins = [ orch.orch-plugin-rust ];
      # Agents' and tasks' sandboxes can't reach the VPN (orchestrator DECISIONS 144): the
      # development host's dashboard answers on the mesh without a login, and every process of
      # an agent's or a task's runs as dk. Every worker host blocks, not only the development
      # host: agentd's guard vouches only for its own host, and an owner leases a task only to
      # an executor that blocks what it blocks. The mesh's /16 (phones' 10.100.1.0/24 inside),
      # its /48 and the phones' v6 range (common/modules/wireguard's header).
      sandbox.blockedNets = [
        "10.100.0.0/16"
        "fdaa:e184:83f::/48"
        "fdcc:ad94:bacf:61a4::cafe:0/112"
      ];
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
    (lib.mkIf isDev {
      # Not the worker's dataRoot (hestia: /mnt/games/orch): agentd's clones, merges and records
      # stay at the path every host gives them, where `orch merge` and endpointAllow look.
      agentd.settings.data_root = "${config.xdg.dataHome}/orch";
      # The dashboard on the host's mesh addresses too, for every VPN device with host access,
      # phones included; no login, VPN access is the gate (orchestrator DECISIONS 144). agentd
      # serves the mesh only while every live agent and task runs behind the VPN block above;
      # common/modules/orch opens the port on the mesh interface only.
      agentd.dashboard.listen =
        let
          octet = toString osConfig.vpn.nodes.${host.hostName}.octet;
        in
        [
          "127.0.0.1"
          "10.100.0.${octet}"
          "fdaa:e184:83f::${octet}"
        ];
      projects.orchestrator = {
        path = "/home/dk/code/orchestrator";
        flake = "git+file:///home/dk/code/orchestrator?ref=main";
      };
    })
    (lib.mkIf (host.hostName == "hermes") {
      # With nix-daemon's budget beside it (5 GiB with hestia, 10 without;
      # common/modules/remote-builder), ~11 GiB of MemTotal (30.6) stay for the desktop, zram's
      # own pages and the system: 26 with hestia froze hermes on 2026-10-07 22:07, and 19 + 6
      # most likely on 2026-10-08 08:54 (Zen alone takes 3-5 GiB).
      ceilingGiB = if osConfig.remoteBuilder.useHestia then 14 else 12;
      # Merge jobs' gates build their Nix checks in hestia's store: only status and errors come
      # back over hermes's usually slow link, no outputs (orchestrator ruling 117).
      agentd.gateNixStore = lib.mkIf (
        isDev && osConfig.remoteBuilder.useHestia
      ) "ssh-ng://nix-ssh@hestia";
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
      # hermes keeps both checkouts, the user's, whichever host develops.
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
      # orch.slice 16 GiB beside nix-daemon's 14 (common/modules/remote-builder): together under
      # hestia's 31 GiB, so builds for hermes, `full`'s VM tests and orch's tasks can't freeze it
      # (hermes froze three times from exactly that oversubscription; the user's go, 2026-10-09).
      ceilingGiB = 16;
      # As the development host, the ledger leaves 6 GiB of the ceiling to agentd (MemoryMax 2G)
      # and its runners (orch-runners.slice is inside orch.slice, outside the ledger); a warm
      # slot gate (8 GiB learned at most) still fits the 10.
      worker.memoryGiB = if isDev then 10 else 15;
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
      # its dev shell from the leased tree. As the development host, the checkout is here too
      # (above); no ostt3 checkout here, so agentd leaves ostt3 out.
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
