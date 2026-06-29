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
      samba = mkOption {
        type = types.bool;
        default = false;
        description = "run the LAN Samba file share (smbd + wsdd discovery) for Windows interop";
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
