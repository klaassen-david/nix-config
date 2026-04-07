{
  description = "wsl system configuration";

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
    nixos-wsl.url = "github:nix-community/NixOS-WSL/main";
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
  };

  # hermes = lib.mkEnableOption "hermes";

  outputs = { self, nixpkgs-unstable, nixos-wsl, home-manager, zen-browser, nixos-hardware, ...}@inputs: {
    hermes = nixpkgs-unstable.lib.mkEnableOption "hermes";

    # wsl
    nixosConfigurations.janus = nixpkgs-unstable.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        nixos-wsl.nixosModules.default {
          system.stateVersion = "24.11";
          wsl.enable = true;
          wsl.defaultUser = "dk";
        }

        ./janus.nix

        home-manager.nixosModules.home-manager {
          home-manager.extraSpecialArgs = {
            inherit inputs;
          };
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.users.dk = {
            imports = [
              ./home.nix
    # inputs.nixvim.homeManagerModules.nixvim

            ];
          };
        }
      ];
    };

    # laptop
    nixosConfigurations.hermes = nixpkgs-unstable.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./hermes/configuration.nix
        nixos-hardware.nixosModules.framework-16-7040-amd

        home-manager.nixosModules.home-manager {
          home-manager.extraSpecialArgs = {
            inherit inputs;
            host = "hermes";
          };
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.backupFileExtension = "home-manager.bak";
          home-manager.users.dk = {
            imports = [
              ./home.nix 
            ];
          };
        }
      ];
    };

    # main
    nixosConfigurations.hestia = nixpkgs-unstable.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./hestia/configuration.nix

        home-manager.nixosModules.home-manager {
          home-manager.extraSpecialArgs = {
            inherit inputs;
            host = "hestia";
          };
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.backupFileExtension = "home-manager.bak";
          home-manager.users.dk = {
            imports = [
              ./home.nix
            ];
          };
        }
      ];
    };
  };
}
