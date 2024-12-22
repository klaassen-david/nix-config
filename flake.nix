{
  description = "wsl system configuration";

  inputs = {
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixos-wsl.url = "github:nix-community/NixOS-WSL/main";
    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
  };

  outputs = { self, nixpkgs-unstable, nixos-wsl, home-manager, ...}@inputs: {
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
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.users.dk = import ./home;
        }
      ];
    };
  };
}
