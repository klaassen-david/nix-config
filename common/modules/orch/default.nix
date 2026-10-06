{
  config,
  secretsPath,
  ...
}:

# The NixOS side of the orchestrator's workers (home-manager/modules/orch; decisions/
# orchestrator-fleet.md): what the user-level module can't set itself.
#
# - Lingering: task units outlive a logout; the module's build fails without it.
# - The link token to the coordinator on olympus (common/modules/orch-coordinator), readable by
#   dk, whose worker reads it at every connect. The same file is olympus's token for this host.
# - orch.dklaassen.de resolves to olympus's mesh address: the vhost admits only the VPN's
#   networks, so the worker must come through the mesh, never through the public address.
let
  name = config.host.hostName;
  # The mesh's v4 addressing, as common/modules/wireguard derives it from `octet`.
  olympusIp = "10.100.0.${toString config.vpn.nodes.olympus.octet}";
in
{
  users.users.dk.linger = true;

  age.secrets."orch-link-${name}" = {
    file = "${secretsPath}/orch-link-${name}.age";
    owner = "dk";
    mode = "0400";
  };

  networking.hosts.${olympusIp} = [ "orch.dklaassen.de" ];
}
