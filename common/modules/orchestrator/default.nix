_:

# The AI agent harness (olympus:~/code/orchestrator, the monorepo) on hestia, where its agents,
# worktrees and builds live; hot-swapped (../hot-swap, decisions/hot-swap.md):
# the binary is not built by nix-config, a new version is
# `systemctl start orchestrator-swap`, never a switch.
#
# The dashboard is orchestrator.dklaassen.de on olympus (../hot-swap/vhosts.nix),
# proxied over the mesh to 0.0.0.0:3040 here; only the hub may connect. The app
# answers GET /healthz with its version, checks Host against ALLOW_HOST
# (DNS-rebinding guard, as with the trainer) and keeps its data (DB, VAPID key)
# in ~/deploy/orchestrator/state. Agents that must outlive a swap run as
# `systemd-run --user` units, not as children of this one.

let
  inherit ((import ../hot-swap/apps.nix).orchestrator) port;
  domain = "orchestrator.dklaassen.de";
in
{
  imports = [ ../hot-swap ];

  hotSwap.apps.orchestrator = {
    inherit port;
    environment = {
      LISTEN = "0.0.0.0:${toString port}";
      ALLOW_HOST = domain;
      PUBLIC_URL = "https://${domain}";
    };
    # an OOM kill inside the unit (the daemon's git work, its `coordinator run`
    # clients) must not stop it; the limits bound its page cache from merges and
    # gates (peaks 2.5-7.1 G, almost all cache) (decisions/orchestrator-oom-policy.md)
    serviceConfig = {
      OOMPolicy = "continue";
      MemoryHigh = "6G";
      MemoryMax = "10G";
    };
  };
}
