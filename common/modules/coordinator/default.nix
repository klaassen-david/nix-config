{ config, ... }:

# The coordinator (built from olympus:~/code/orchestrator, the monorepo): resource scheduling for builds
# and agent commands, on hestia only for now (../hot-swap/apps.nix), hot-swapped
# (../hot-swap, decisions/hot-swap.md): a new version is
# `systemctl start coordinator-swap`, never a switch.
#
# One port for the API and the dashboard, coordinator.dklaassen.de on olympus
# (../hot-swap/vhosts.nix); only the hub may connect. A second node later (hermes)
# adds its mesh address to `sources` here, once the API authenticates its peers.
#
# Tasks are confined two ways, both without sudo:
#   - `systemd-run --user` units (XDG_RUNTIME_DIR from ../hot-swap): MemoryMax,
#     CPUQuota, `systemctl --user freeze`; they live in user@1000.service and
#     outlive the daemon;
#   - its own cgroup subtree: Delegate hands this unit's cgroup to dk (systemd
#     chowns it to User=), the daemon itself sits in `supervisor`, so it may
#     create task cgroups beside it and write memory.max/cpu.max/cgroup.freeze.
#     KillMode=process: a swap restarts only the daemon and the new version
#     adopts the tasks. A real stop leaves them running too.

let
  inherit ((import ../hot-swap/apps.nix).coordinator) port;
in
{
  imports = [ ../hot-swap ];

  hotSwap.apps.coordinator = {
    inherit port;
    environment = {
      LISTEN = "0.0.0.0:${toString port}";
      NODE = config.host.hostName;
      ALLOW_HOST = "coordinator.dklaassen.de";
    };
    serviceConfig = {
      Delegate = true;
      DelegateSubgroup = "supervisor";
      KillMode = "process";
    };
  };
}
