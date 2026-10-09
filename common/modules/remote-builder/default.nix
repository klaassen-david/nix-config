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
        # hestia's dedicated trusted build user (nix.sshServe below), not dk: dk is an untrusted
        # Nix user there, so tasks running as dk can't register store paths (orchestrator, 2026-10-09).
        sshUser = "nix-ssh";
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
  # throttled a dozen builders for an hour without killing one. The budget and orch.slice's
  # ceiling together stay ~5 GiB under MemTotal (30.6 GiB) for the desktop and the system: at 10 +
  # 26 they didn't, and hermes froze again on 2026-10-07 22:07 before either reached its limit.
  # systemd-oomd kills a builder after 20 s of heavy memory pressure, before the box stalls.
  # With hestia, a build still runs here whenever hestia's slots are full (max-jobs `auto` let a
  # full gate boot five VM tests here at 92 °C on 2026-10-07): one local job per client, and the
  # daemon's CPU capped at 4 of the 16 cores (8 without hestia), beside orch-tasks.slice's 8.
  (lib.mkIf (config.host.hostName == "hermes") {
    nix.settings.max-jobs = lib.mkIf config.remoteBuilder.useHestia 1;
    systemd.services.nix-daemon.serviceConfig = {
      CPUQuota = if config.remoteBuilder.useHestia then "400%" else "800%";
      MemoryMax = if config.remoteBuilder.useHestia then "5G" else "10G";
      MemorySwapMax = "1G";
      OOMPolicy = "continue";
      ManagedOOMMemoryPressure = "kill";
      ManagedOOMMemoryPressureLimit = "50%";
      ManagedOOMMemoryPressureDurationSec = "20s";
    };
  })
  # Without hestia, hermes builds everything itself. `max-jobs` holds per client, not per daemon
  # (every gate step is a client), so only the remote builder's slots bound a gate's builds.
  (lib.mkIf (config.host.hostName == "hermes" && !config.remoteBuilder.useHestia) {
    nix.settings.max-jobs = 2;
    nix.settings.cores = 3;
  })
  (lib.mkIf (config.host.hostName == "hestia") {
    # Remote builds from hermes come in as the dedicated user nix-ssh (forced `nix-daemon --stdio`,
    # trusted, key-only: hermes root's id_priv). dk is no longer a trusted Nix user here: every
    # orchestrator task runs as dk with the daemon socket in its sandbox, and a trusted client can
    # register arbitrary paths as valid (skipping signatures), which would let a leased agent task
    # forge a check's output (orchestrator review, 2026-10-09). Untrusted users still build.
    nix.sshServe = {
      enable = true;
      protocol = "ssh-ng";
      write = true;
      trusted = true;
      keys = [ (builtins.readFile ../../keys/id_priv.pub) ];
    };
    # sshd admits only dk otherwise (common ssh settings).
    services.openssh.settings.AllowUsers = [ "nix-ssh" ];
    # Builds for hermes fill the store with paths nothing references once their results went
    # back (2026-10-05: / reached 98 % in a day). Nix collects them itself while it builds:
    # below 30 GiB free it deletes dead paths until 80 GiB are free. Only dead paths; every
    # generation and gcroot stays.
    nix.settings.min-free = 30 * 1024 * 1024 * 1024;
    nix.settings.max-free = 80 * 1024 * 1024 * 1024;
    # Each build gets 8 of the 24 threads instead of all of them (cores = 0): an orchestrator
    # `full` gate runs up to six Nix builds at once (cargo at -j24 each), and the VM tests beside
    # them timed out under that load on 2026-10-08 (orchestrator's Fable report on `full`, A3).
    nix.settings.cores = 8;
  })
];
}
