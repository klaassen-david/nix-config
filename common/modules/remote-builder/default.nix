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
{ config, lib, ... }:

let
  hestia = config.vpn.nodes.hestia;
  # The mesh's v4 addressing, as common/modules/wireguard derives it from `octet`.
  hestiaIp = "10.100.0.${toString hestia.octet}";
  hestiaHostKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPIuarjxJW72kpLAPnfnU5lGbxGQBSKot8aimJiaGTIe";
in
lib.mkMerge [
  (lib.mkIf (config.host.hostName == "hermes") {
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
  (lib.mkIf (config.host.hostName == "hestia") {
    nix.settings.trusted-users = [ "dk" ];
    # Builds for hermes fill the store with paths nothing references once their results went
    # back (2026-10-05: / reached 98 % in a day). Nix collects them itself while it builds:
    # below 30 GiB free it deletes dead paths until 80 GiB are free. Only dead paths; every
    # generation and gcroot stays.
    nix.settings.min-free = 30 * 1024 * 1024 * 1024;
    nix.settings.max-free = 80 * 1024 * 1024 * 1024;
  })
]
