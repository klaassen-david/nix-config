{
  lib,
  pkgs,
  host,
  inputs,
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
      diskFloor = {
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
    }
    (lib.mkIf (host.hostName == "hermes") {
      roles = [
        "worker"
        "agentd"
      ];
      ceilingGiB = 26; # MemTotal 30 GiB less 4, as ostt3's ostt.slice
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
    })
  ];
}
