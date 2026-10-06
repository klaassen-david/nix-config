{
  config,
  inputs,
  secretsPath,
  sslVhost,
  nextcloudSSO,
  ...
}:

# The orchestrator's coordinator on olympus (~/code/orchestrator, docs/deploy-coordinator.md
# there; decisions/orchestrator-fleet.md): `orch coordinator` on 127.0.0.1:7469 as a hardened
# system service (`orch-coordinator.service`, state in /var/lib/orch-coordinator), behind the
# vhost orch.dklaassen.de. The workers on hermes and hestia link to it (wss://…/link/v1, one
# token per host) and it relays leases between them; the fleet view and API sit behind the SSO
# gate.
#
# - VPN only: the orchestrator's module puts `allow 10.100.0.0/24; allow 10.100.1.0/24; deny all`
#   on the vhost. The hosts reach it through the mesh because common/modules/orch points
#   orch.dklaassen.de at olympus's mesh address; nothing in public DNS is needed.
# - The tokens (orch-link-<host>.age) are the same files the hosts' workers read. Root-only is
#   fine here: the service gets them as systemd credentials.
# - Its state is derived from the workers' journals: losing /var/lib/orch-coordinator costs a
#   resend, nothing else. Rollback is a switch back; the workers run local-only meanwhile.
let
  # The hosts that run a worker (common/modules/orch).
  workers = [
    "hermes"
    "hestia"
  ];
  secret = h: "orch-link-${h}";
in
{
  imports = [
    ../nginx
    inputs.orchestrator.nixosModules.coordinator
  ];

  age.secrets = builtins.listToAttrs (
    map (h: {
      name = secret h;
      value.file = "${secretsPath}/${secret h}.age";
    }) workers
  );

  services.orch-coordinator = {
    enable = true;
    hostTokens = builtins.listToAttrs (
      map (h: {
        name = h;
        value = config.age.secrets.${secret h}.path;
      }) workers
    );
    nginx = {
      virtualHost = "orch.dklaassen.de";
      # TLS and the SSO gate; the module merges its locations in with lib.recursiveUpdate.
      vhostBase = sslVhost { } // nextcloudSSO;
    };
  };
}
