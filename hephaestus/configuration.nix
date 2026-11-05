# hephaestus: headless implementer host (decisions/implementer-host.md).
# Imports base.nix, not common.nix: no mesh module, no attic, no id_priv. Its only
# secret is its wg-easy client config, encrypted to id_priv and its own host key.
{
  config,
  lib,
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

  warnings = lib.optional (
    !hasTunnel
  ) "hephaestus: secrets/wg-fleet-hephaestus.age is not in the git tree; building without the fleet tunnel";

  age.identityPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  age.secrets = lib.mkIf hasTunnel { wg-fleet.file = wgSecret; };

  # wg-easy's conf, edited before encrypting: AllowedIPs = 10.100.0.0/16,
  # PersistentKeepalive = 25, no DNS line
  networking.wg-quick.interfaces = lib.mkIf hasTunnel {
    fleet.configFile = config.age.secrets.wg-fleet.path;
  };
  # the unit is a oneshot: without this, one DNS failure at boot leaves no tunnel
  systemd.services = lib.mkIf hasTunnel {
    wg-quick-fleet = {
      unitConfig.StartLimitIntervalSec = 0;
      serviceConfig = {
        Restart = "on-failure";
        RestartSec = "30s";
      };
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
  ];

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
