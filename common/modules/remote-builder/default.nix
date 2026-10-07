# hestia builds for hermes
# ========================
# hermes's nix-daemon sends builds to hestia (24 cores, 31 GiB, /dev/kvm) over the
# mesh, VM tests included: the orchestrator's gates (Nix checks, NixOS VM tests) are
# most of a gate's time and loaded hermes into flaky tests (orchestrator DECISIONS,
# 2026-10-05 speed-ups). When hestia doesn't answer within the connect timeout,
# hermes builds locally, so roaming without the mesh still works.
#
# - hermes (client): `distributedBuilds`, one ssh-ng build machine at hestia's mesh
#   address, as dk with id_priv (root reads it; hestia authorizes it for dk), and
#   hestia's host key pinned, never trust-on-first-use. `builders-use-substitutes`
#   lets hestia fetch from the caches itself instead of through hermes.
# - hestia (server): dk is a trusted Nix user, which a remote builder's user must
#   be. dk already has sudo there, so this grants nothing new.
#
# The switch: `remoteBuilder.useHestia` (hermes/configuration.nix). Off while hermes reaches
# hestia over Wi-Fi only: a remote build's round trip there costs more than building on hermes
# (orchestrator docs/gate-times.md, 2026-10-07). On again on a fast link (Ethernet).
{ config, lib, ... }:

let
  hestia = config.vpn.nodes.hestia;
  # The mesh's v4 addressing, as common/modules/wireguard derives it from `octet`.
  hestiaIp = "10.100.0.${toString hestia.octet}";
  hestiaHostKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPIuarjxJW72kpLAPnfnU5lGbxGQBSKot8aimJiaGTIe";
in
{
  options.remoteBuilder.useHestia = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Whether hermes sends its builds to hestia (off on a slow link).";
  };

  config = lib.mkMerge [
  (lib.mkIf (config.host.hostName == "hermes" && config.remoteBuilder.useHestia) {
    nix.distributedBuilds = true;
    nix.buildMachines = [
      {
        hostName = hestiaIp;
        protocol = "ssh-ng";
        sshUser = "dk";
        sshKey = "/home/dk/.ssh/id_priv";
        system = "x86_64-linux";
        maxJobs = 8;
        speedFactor = 2;
        supportedFeatures = [
          "nixos-test"
          "benchmark"
          "big-parallel"
          "kvm"
        ];
      }
    ];
    nix.settings.builders-use-substitutes = true;
    programs.ssh.knownHosts.hestia-builder = {
      hostNames = [ hestiaIp ];
      publicKey = hestiaHostKey;
    };
    programs.ssh.extraConfig = ''
      Host ${hestiaIp}
        ConnectTimeout 5
    '';
  })
  # hermes's local Nix builds run outside the orchestrator's memory ledger, beside the agents and
  # their tasks, so the daemon gets a budget of its own beside orch.slice's
  # (home-manager/modules/orch): unbounded, it reached 24 GiB and froze hermes in swap on
  # 2026-10-07. Over it the kernel kills a builder (that build fails), not the box; `OOMPolicy =
  # continue` keeps the daemon and its other builds. No `MemoryHigh`: just under `MemoryMax` it
  # throttled a dozen builders for an hour without killing one.
  (lib.mkIf (config.host.hostName == "hermes") {
    systemd.services.nix-daemon.serviceConfig = {
      MemoryMax = "10G";
      MemorySwapMax = "1G";
      OOMPolicy = "continue";
    };
  })
  # Without hestia, hermes builds everything itself. `max-jobs` holds per client, not per daemon
  # (every gate step is a client), so only the remote builder's slots bound a gate's builds.
  (lib.mkIf (config.host.hostName == "hermes" && !config.remoteBuilder.useHestia) {
    nix.settings.max-jobs = 2;
    nix.settings.cores = 3;
  })
  (lib.mkIf (config.host.hostName == "hestia") {
    nix.settings.trusted-users = [ "dk" ];
    # Builds for hermes fill the store with paths nothing references once their results went
    # back (2026-10-05: / reached 98 % in a day). Nix collects them itself while it builds:
    # below 30 GiB free it deletes dead paths until 80 GiB are free. Only dead paths; every
    # generation and gcroot stays.
    nix.settings.min-free = 30 * 1024 * 1024 * 1024;
    nix.settings.max-free = 80 * 1024 * 1024 * 1024;
  })
];
}
