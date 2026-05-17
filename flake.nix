{
  description = "system configuration";

  nixConfig = {
    extra-substituters = [
      "https://nix-gaming.cachix.org"
      "https://nix-community.cachix.org"
      "https://devenv.cachix.org"
      "https://klaassen-david.cachix.org"
    ];
    extra-trusted-public-keys = [
      "nix-gaming.cachix.org-1:nbjlureqMbRAxR1gJ/f3hxemL9svXaZF/Ees8vCUUs4="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
      "klaassen-david.cachix.org-1:JSXHnsFehuyyhJ+JZSRhJNlx1gCudEBCTMXLd4y1Tn8="
    ];
  };

  inputs = {
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    # nixpks.url = "github:NixOS/nixpkgs/nixos-25.05";
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
          sharedArgs = {
            inherit inputs host;
            secretsPath = ./secrets;
          };
        in
        nixpkgs-unstable.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = sharedArgs;
          modules = [
            ./${host}/configuration.nix
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
            agenix.nixosModules.default
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
    };
}
