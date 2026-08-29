{ config, lib, ... }:

let
  inherit (lib) mkOption types;
in
{
  options.host = {
    hostName = mkOption {
      type = types.str;
      description = "host's hostname; source of truth for networking.hostName, mirrors the flake output name";
    };

    role = mkOption {
      type = types.enum [
        "vps"
        "laptop"
        "tower"
      ];
      description = "coarse host class; seeds capability defaults and anchors assertions";
    };

    stateVersion = mkOption {
      type = types.str;
      description = "NixOS state version; defaults to system.stateVersion";
    };

    keepGenerations = mkOption {
      type = types.ints.positive;
      default = 10;
      description = "system generations to retain; caps bootloader entries and the nh clean keep-policy";
    };

    capabilities = {
      wifi = mkOption {
        type = types.bool;
        default = false;
      };
      bluetooth = mkOption {
        type = types.bool;
        default = false;
      };
      battery = mkOption {
        type = types.bool;
        default = false;
        description = "has a battery; gates powerctl widgets, charge-limit, power-profiles";
      };
      fingerprint = mkOption {
        type = types.bool;
        default = false;
      };
      lid = mkOption {
        type = types.bool;
        default = false;
        description = "has a laptop lid; gates lid-close handling (e.g. wifi-keepalive suspend delay in modules/wifi)";
      };
      samba = mkOption {
        type = types.bool;
        default = false;
        description = "run the LAN Samba file share (smbd + wsdd discovery) for Windows interop";
      };
      onDemandSshServer = mkOption {
        type = types.bool;
        default = config.host.role != "vps";
        description = "configure sshd but leave it stopped at boot, toggled by hand with `sudo systemctl start|stop sshd` (common/modules/ssh-on-demand); desktops only — headless.nix runs a permanent sshd instead";
      };
      binaryCachePush = mkOption {
        type = types.bool;
        default = config.host.role != "vps";
        description = "push every freshly built store path to the self-hosted attic cache (common/modules/attic); defaults on for non-server hosts, off for the vps that hosts the cache";
      };
    };

    gpu = mkOption {
      type = types.enum [
        "nvidia"
        "amdgpu"
        "intel"
        "none"
      ];
      default = "none";
      description = "primary GPU vendor; selects videoDrivers, graphics extraPackages, kernel modules";
    };

    # Units that dk may start/stop without sudo or a password. Unlike the rest of
    # the struct this is not set per host: each module appends the units it owns
    # (wireguard its wg-quick clients, ssh-on-demand its sshd), and
    # common/modules/polkit-units turns the merged list into one polkit rule.
    userManagedUnits = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "sshd.service" ];
      description = "systemd units wheel may start/stop unprivileged (see common/modules/polkit-units)";
    };

    # single source of truth for reading the lid state. The /proc button path and
    # its token format are hardware-dependent, so the check lives per-host (set in
    # <host>/configuration.nix) rather than in shared code. Forwarded to
    # home-manager with the rest of the struct, so both the system lid handling
    # (modules/wifi) and user-session consumers (power-profile reconcile) call the
    # same script instead of re-deriving the grep.
    lid_state = mkOption {
      type = types.nullOr types.package;
      default = null;
      description = "executable that prints the lid state (open|closed)";
    };

    # only the primary connector ("mainDisplay") lives in the struct; the full monitor
    # topology stays in kanshi.nix, keyed by EDID, and drives tray/workspace via exec
    display.primary = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''primary output connector ("mainDisplay"), e.g. "DP-3" or "eDP-1"; null on headless hosts'';
    };

    theme = {
      base16 = mkOption {
        type = types.str;
        default = "nord";
        description = "base16 scheme name; feeds the stylix idea + bar colors";
      };
      opacity = mkOption {
        type = types.numbers.between 0.0 1.0;
        default = 1.0;
      };
      wallpaper = mkOption {
        type = types.nullOr types.path;
        default = null;
      };
    };

    firewall = {
      tcpPorts = mkOption {
        type = types.listOf types.port;
        default = [ ];
      };
      tcpRanges = mkOption {
        default = [ ];
        type = types.listOf (
          types.submodule {
            options = {
              from = mkOption { type = types.port; };
              to = mkOption { type = types.port; };
            };
          }
        );
      };
    };

    # opt-in diagnostics for hard lockups: a GPU/kernel freeze flushes nothing to
    # the journal, so this turns the hang into a panic that dumps dmesg to pstore
    # (EFI NVRAM, survives a power-cycle) and arms the hardware watchdog. See
    # common/modules/crash-capture.
    debug.crashCapture = mkOption {
      type = types.bool;
      default = false;
      description = "capture kernel dmesg to pstore on a hard lockup (panic-on-hang) and arm the hardware watchdog; for diagnosing GPU/kernel freezes";
    };
  };

  config = {
    # the struct is the source of truth: hostName mirrors the flake output name and
    # stateVersion replaces the duplicated per-host block, so derive both downstream
    networking.hostName = config.host.hostName;
    system.stateVersion = config.host.stateVersion;

    assertions = [
      {
        assertion = config.host.capabilities.battery -> config.host.role == "laptop";
        message = ''host.capabilities.battery only makes sense when host.role = "laptop"'';
      }
      {
        assertion = config.host.capabilities.lid -> config.host.role == "laptop";
        message = ''host.capabilities.lid only makes sense when host.role = "laptop"'';
      }
      {
        assertion = config.host.capabilities.lid -> config.host.lid_state != null;
        message = "host.lid_state must be set when host.capabilities.lid is true";
      }
      {
        # headless.nix already runs a permanent, key-only sshd; the module's
        # `wantedBy = mkForce []` would disarm it without a word
        assertion = config.host.capabilities.onDemandSshServer -> config.host.role != "vps";
        message = ''host.capabilities.onDemandSshServer is incompatible with host.role = "vps" (headless.nix runs a permanent sshd)'';
      }
      {
        assertion = !(config.host.role == "vps" && config.host.gpu != "none");
        message = ''host.role = "vps" implies host.gpu = "none"'';
      }
      {
        assertion =
          (config.host.role == "laptop" || config.host.role == "tower")
          -> config.host.display.primary != null;
        message = "host.display.primary must be set for laptop/tower roles";
      }
    ];

    # forward the evaluated struct to home-manager modules as the `host` arg
    # (the flake no longer passes the hostname string, so this is the sole `host`)
    home-manager.extraSpecialArgs = {
      host = config.host;
    };
  };
}
