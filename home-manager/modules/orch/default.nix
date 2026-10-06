{
  pkgs,
  host,
  inputs,
  ...
}:

# The orchestrator (~/code/orchestrator, its docs/deploy-worker.md) on hermes: the worker
# (orch-worker.{socket,service}, orch.slice with its task slices) and agentd (orch-agentd.*,
# runner units in orch-runners.slice, the local dashboard on 127.0.0.1:7468, `orch dashboard`
# prints its login URL), and `orch` on PATH. agentd reads the harness's own logins from
# ~/.config/orch/accounts.toml (`orch accounts`); it never uses cswap. hestia once deployed there.
#
# The input is pinned to a commit `orch deployable <rev>` accepts (gate `full` passed on that
# tree). To update: pick a newer deployable commit, change `rev` in flake.nix, then
# `nix flake update orchestrator`.
#
# Needs lingering (`users.users.dk.linger` in the host's configuration.nix); the module's
# build fails without it, so a logout can't end running tasks.

let
  orch = inputs.orchestrator.packages.${pkgs.stdenv.hostPlatform.system};
in
{
  imports = [ inputs.orchestrator.homeManagerModules.default ];

  services.orch = {
    enable = true;
    host = host.hostName; # task ids T-<host>-…
    roles = [
      "worker"
      "agentd"
    ];
    ceilingGiB = 26; # hermes: MemTotal 30 GiB less 4, as ostt3's ostt.slice
    # 100 GiB absolute: 15 % of hermes's 1.8 TiB / would hold every task back.
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
  };
}
