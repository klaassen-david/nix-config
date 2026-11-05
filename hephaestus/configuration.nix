# hephaestus: headless implementer host (decisions/implementer-host.md).
# Imports base.nix, not common.nix: no mesh module, no attic, no id_priv. Its only
# secret is its wg-easy client config, encrypted to id_priv and its own host key.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  wgSecret = ../secrets/wg-fleet-hephaestus.age;
  # Until the user encrypts the file and `git add -N`s it, the host evaluates
  # without a tunnel, with a warning, and stays reachable by campusSshSources.
  hasTunnel = builtins.pathExists wgSecret;

  # CONFIRM (user): recovery ssh, key-only. The /25 the host's DHCP address is in;
  # widen if hermes must reach it from elsewhere on campus. IPv4 only on purpose:
  # the host also has a global IPv6 address, where port 22 stays closed.
  campusSshSources = [ "131.246.129.0/25" ];
in
{
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
    ../common/base.nix
  ];

  host = {
    hostName = "hephaestus";
    role = "implementer";
    stateVersion = "26.11";
    browser = null;
    sshIdentity = "~/.ssh/id_hephaestus";
    capabilities.sshServer = false; # the module is not imported; sshd below
    capabilities.binaryCachePush = false;
    firewall.mesh.tcpRanges = [ ];
  };

  warnings =
    lib.optional (!hasTunnel)
      "hephaestus: secrets/wg-fleet-hephaestus.age is not in the git tree; building without the fleet tunnel";

  age.identityPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  age.secrets = lib.mkIf hasTunnel { wg-fleet.file = wgSecret; };

  # wg-easy's conf, edited before encrypting: AllowedIPs = 10.100.0.0/16,
  # PersistentKeepalive = 25, no DNS line
  networking.wg-quick.interfaces = lib.mkIf hasTunnel {
    fleet.configFile = config.age.secrets.wg-fleet.path;
  };
  # the unit is a oneshot: without this, one DNS failure at boot leaves no tunnel
  systemd.services.wg-quick-fleet = lib.mkIf hasTunnel {
    unitConfig.StartLimitIntervalSec = 0;
    serviceConfig = {
      Restart = "on-failure";
      RestartSec = "30s";
    };
  };

  services.openssh = {
    enable = true;
    openFirewall = false;
    settings = {
      UseDns = false;
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      AllowUsers = [
        "dk"
        "root"
      ];
      PermitRootLogin = "prohibit-password";
    };
  };
  # deploys from hermes: dk is not a trusted nix user, so `--target-host dk@` would
  # fail on unsigned paths
  users.users.root.openssh.authorizedKeys.keyFiles = [ ../common/keys/id_priv.pub ];

  networking.firewall = {
    enable = true;
    checkReversePath = false;
    interfaces.fleet.allowedTCPPorts = [ 22 ];
    extraCommands = lib.concatMapStrings (
      src: "iptables -A nixos-fw -s ${src} -p tcp --dport 22 -j nixos-fw-accept\n"
    ) campusSshSources;
  };

  # agents keep running without a login
  users.users.dk.linger = true;

  boot.loader = {
    systemd-boot.enable = true;
    systemd-boot.configurationLimit = config.host.keepGenerations;
    efi.canTouchEfiVariables = true;
  };

  systemd.tmpfiles.rules = [
    "d /mnt/dev 0755 dk users -"
    "d /mnt/dev/work 0755 dk users -"
    "d /mnt/scratch 0755 dk users -"
    "d /mnt/scratch/cargo 0755 dk users -"
  ];

  # 100 GiB of root holds /nix only with collection (decisions/implementer-host.md)
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };
  nix.settings = {
    min-free = 20 * 1024 * 1024 * 1024;
    max-free = 40 * 1024 * 1024 * 1024;
  };

  # Compile output goes to the scratch disk, per workspace. Not CARGO_TARGET_DIR:
  # repo scripts read or set that. Final artifacts stay in each worktree's target/.
  home-manager.users.dk.home.file.".cargo/config.toml".text = ''
    [build]
    build-dir = "/mnt/scratch/cargo/{workspace-path-hash}"
  '';

  # Scratch is rebuildable: drop what has been idle 14 days, then oldest first above 85 %.
  systemd.services.scratch-cleanup = {
    description = "Trim idle compile output on /mnt/scratch";
    serviceConfig = {
      Type = "oneshot";
      User = "dk";
      Nice = 19;
      IOSchedulingClass = "idle";
    };
    path = [
      pkgs.coreutils
      pkgs.findutils
      pkgs.gawk
    ];
    script = ''
      root=/mnt/scratch/cargo
      [ -d "$root" ] || exit 0
      newest() { find "$1" -type f -printf '%T@\n' 2>/dev/null | sort -n | tail -1 | cut -d. -f1; }
      now=$(date +%s)
      list=$(find "$root" -mindepth 2 -maxdepth 2 -type d | while read -r d; do
        echo "$(newest "$d" || true) $d"
      done | sort -n)
      echo "$list" | while read -r t d; do
        [ -n "$d" ] || continue
        if [ -z "$t" ] || [ $((now - t)) -gt $((14 * 86400)) ]; then rm -rf -- "$d"; fi
      done
      echo "$list" | while read -r t d; do
        [ -d "$d" ] || continue
        used=$(df --output=pcent /mnt/scratch | tail -1 | tr -dc 0-9)
        [ "$used" -gt 85 ] || break
        [ $((now - t)) -gt 3600 ] && rm -rf -- "$d"
      done
    '';
    startAt = "daily";
  };

  # A build that runs away stays inside dk's slice; root ssh is outside it.
  systemd.slices."user-1000".sliceConfig = {
    MemoryHigh = "26G";
    MemoryMax = "28G";
  };

  # This host has no config.vpn writing ~/.ssh/config.vpn. Mesh addresses from the
  # vpn.nodes registry; git only on olympus and hestia, the hub passes port 22.
  home-manager.users.dk.programs.ssh.settings = {
    olympus.HostName = "10.100.0.1";
    hestia.HostName = "10.100.0.2";
    hermes.HostName = "10.100.0.3";
  };
  programs.ssh.knownHosts.olympus = {
    hostNames = [
      "olympus"
      "10.100.0.1"
      "dklaassen.de"
    ];
    publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICC2ITqo7NHmJIn8Cgd3O5ezGJAmLSE/Srlq9l8Ix9io";
  };
}
