{
  config,
  lib,
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
# - Leases (fleet L3): this worker's ssh key (orch-fleet-<host>.age) fetches leased tasks' trees
#   from the peer; the peer's public key (common/keys/orch-fleet-<peer>.pub) gets dk's
#   authorized_keys line with the forced command `orch git-endpoint`, which serves snapshot refs
#   and nothing else. The line is added only once the .pub file is in git (`git add -N`);
#   until then the build warns.
# - olympus's ssh host key, pinned for its mesh address: on the development host the user and
#   the supervisor fetch and push olympus:git/orchestrator.git (~/.ssh/config.local maps `olympus`
#   there), never trust-on-first-use. The key common/modules/mail-backup pins for dklaassen.de.
let
  name = config.host.hostName;
  # The hosts that run a worker; each one's peers are the others.
  workers = [
    "hermes"
    "hestia"
  ];
  peers = lib.filter (h: h != name) workers;
  # The mesh's v4 addressing, as common/modules/wireguard derives it from `octet`.
  olympusIp = "10.100.0.${toString config.vpn.nodes.olympus.octet}";
  pubKey = peer: ../../keys + "/orch-fleet-${peer}.pub";
  havePub = peer: builtins.pathExists (pubKey peer);
  inherit (config.home-manager.users.dk.services.orch.fleet) gitEndpoint;
in
{
  users.users.dk.linger = true;
  # home-manager's activation finishes before dk's lingering user manager starts at boot. Without
  # the ordering, a boot into a new generation can start the manager on the previous generation's
  # unit links; home-manager then skips its reload ("User systemd daemon not running") and the
  # orch daemons run the old build until the next switch (orchestrator vm-hot-update, 2026-10-08,
  # nix/tests/hm-before-linger.nix). Only boot order changes; a switch is unaffected.
  systemd.services.home-manager-dk.before = [ "user@1000.service" ];

  age.secrets = {
    "orch-link-${name}" = {
      file = "${secretsPath}/orch-link-${name}.age";
      owner = "dk";
      mode = "0400";
    };
    "orch-fleet-${name}" = {
      file = "${secretsPath}/orch-fleet-${name}.age";
      owner = "dk";
      mode = "0400";
    };
  };

  networking.hosts.${olympusIp} = [ "orch.dklaassen.de" ];

  programs.ssh.knownHosts.olympus = {
    hostNames = [
      "olympus"
      olympusIp
    ];
    publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICC2ITqo7NHmJIn8Cgd3O5ezGJAmLSE/Srlq9l8Ix9io";
  };

  # Adds to common.nix's keyFiles; the forced command binds only the peers' fleet keys.
  users.users.dk.openssh.authorizedKeys.keys = map (
    peer: ''restrict,command="${gitEndpoint}" ${lib.removeSuffix "\n" (builtins.readFile (pubKey peer))}''
  ) (lib.filter havePub peers);

  warnings = map (
    peer:
    "orch: common/keys/orch-fleet-${peer}.pub is missing (or not in git); ${peer}'s worker can't fetch trees from ${name} yet."
  ) (lib.filter (p: !havePub p) peers);
}
