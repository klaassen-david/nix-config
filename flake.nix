{
  description = "system configuration";

  inputs = {
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    # nixvim and zen-browser deliberately do not follow nixpkgs-unstable, so
    # each drags its own nixpkgs into the lock (zen-browser needs libgbm from
    # unstable). Re-testing `inputs.nixpkgs.follows` for both is an open README
    # item ("inputs that do not follow nixpkgs").
    nixvim = {
      url = "github:nix-community/nixvim";
    };
    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
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
    # Neovim plugin not in nixpkgs
    claudecode-nvim = {
      url = "github:coder/claudecode.nvim";
      flake = false;
    };
    # Fork of the nixpkgs plugin, for `pipe_table.cell = "wrapped"`
    render-markdown-nvim = {
      url = "github:klaassen-david/render-markdown.nvim/wrapped-cells";
      flake = false;
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
        packages = [
          agenix.packages.x86_64-linux.agenix
          nixpkgs-unstable.legacyPackages.x86_64-linux.statix
        ];
      };

      # `nix flake check` builds every host's toplevel — catches eval/build breakage
      # before deploy — and lints the tree with statix.
      checks.x86_64-linux =
        let
          pkgs = nixpkgs-unstable.legacyPackages.x86_64-linux;
        in
        nixpkgs-unstable.lib.mapAttrs (_: cfg: cfg.config.system.build.toplevel) self.nixosConfigurations
        // {
          # statix exits 1 on any lint; statix.toml (cwd-relative, hence the cd)
          # lists the ones this repo declines to follow.
          statix = pkgs.runCommand "statix-check" { nativeBuildInputs = [ pkgs.statix ]; } ''
            cd ${self}
            statix check
            touch $out
          '';
        };
    };
}
