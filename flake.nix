{
  description = "wsl system configuration";

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
  };

  outputs = { self, nixpkgs-unstable, nixos-wsl, home-manager, zen-browser, ...}@inputs: {
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

    # main
    nixosConfigurations.hestia = nixpkgs-unstable.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./hestia/configuration.nix

        home-manager.nixosModules.home-manager {
          home-manager.extraSpecialArgs = {
            inherit inputs;
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
