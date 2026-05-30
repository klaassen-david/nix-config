{
  description = "system configuration";

  inputs = {
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    # nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    nixvim = {
      url = "github:nix-community/nixvim";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      # # IMPORTANT: we're using "libgbm" and is only available in unstable so ensure
      # # to have it up-to-date or simply don't specify the nixpkgs input
      # inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
  };

  outputs =
    {
      self,
      nixpkgs-unstable,
      home-manager,
      zen-browser,
      nixos-hardware,
      disko,
      agenix,
      ...
    }@inputs:
    let
      # ---------------------------------------------------------------------------
      # Helper — builds a NixOS configuration with home-manager wired in
      # ---------------------------------------------------------------------------
      mkHost =
        {
          host, # hostname string e.g. "olympus"
          hostModules ? [ ], # extra NixOS modules for this host
          hmModules ? [ ], # extra home-manager modules for this host
        }:
        let
          # `host` (the hostname string) only selects the per-host config path below;
          # the evaluated `config.host` struct is forwarded to home-manager from
          # common/host.nix, so it is intentionally not passed as a specialArg here.
          sharedArgs = {
            inherit inputs;
            secretsPath = ./secrets;
          };
        in
        nixpkgs-unstable.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = sharedArgs;
          modules = [
            ./${host}/configuration.nix
            agenix.nixosModules.default
            home-manager.nixosModules.home-manager
            {
              home-manager = {
                extraSpecialArgs = sharedArgs;
                useGlobalPkgs = true;
                useUserPackages = true;
                backupFileExtension = "home-manager.bak";
                users.dk.imports = [ ./home-manager/home.nix ] ++ hmModules;
              };
            }
          ]
          ++ hostModules;
        };
    in
    {
      nixosConfigurations = {
        # VPS
        olympus = mkHost {
          host = "olympus";
          hostModules = [
            disko.nixosModules.disko
          ];
          hmModules = [ ];
        };

        # laptop
        hermes = mkHost {
          host = "hermes";
          hostModules = [ nixos-hardware.nixosModules.framework-16-7040-amd ];
          hmModules = [ ./home-manager/modules/desktop ];
        };

        # tower
        hestia = mkHost {
          host = "hestia";
          hmModules = [ ./home-manager/modules/desktop ];
        };
      };
      devShells.x86_64-linux.default = nixpkgs-unstable.legacyPackages.x86_64-linux.mkShell {
        packages = [ agenix.packages.x86_64-linux.agenix ];
      };

      # `nix flake check` builds every host's toplevel — catches eval/build breakage before deploy
      checks.x86_64-linux = nixpkgs-unstable.lib.mapAttrs (
        _: cfg: cfg.config.system.build.toplevel
      ) self.nixosConfigurations;
    };
}
