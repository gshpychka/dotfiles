{
  description = "My Machines";
  # printf 'run\tprivate/var/run\n' | sudo tee -a /etc/synthetic.conf
  # /System/Library/Filesystems/apfs.fs/Contents/Resources/apfs.util -t
  # nix --experimental-features "nix-command flakes" build ".#darwinConfigurations.eve.system"
  # ./result/sw/bin/darwin-rebuild switch --flake ".#eve"



  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    darwin = {
      url = "github:lnl7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };


  outputs = { self, nixpkgs, darwin, home-manager, ... }@inputs:
    let
      shared = import ./machines/harbor/variables.nix;
      nixpkgsConfig = {
        allowUnfree = true;
        allowUnsupportedSystem = false;
      };
      overlays = [
        import ./overlays/tree-sitter.nix
      ];
      stateVersion = "22.11";
      user = "gshpychka";
    in
    {
      # nix-darwin with home-manager for macOS
      darwinConfigurations.eve = darwin.lib.darwinSystem {
        system = "aarch64-darwin";
        # makes all inputs availble in imported files
        specialArgs = {
          inherit inputs;
        };
        modules = [
          ./machines/eve/configuration.nix
          ./machines/eve/homebrew.nix
          ({ pkgs, ... }: {
            nixpkgs.config = nixpkgsConfig;
            nixpkgs.overlays = overlays;

            system.stateVersion = 4;

            users.users.${user} = {
              home = "/Users/${user}";
              shell = pkgs.zsh;
            };

            nix = {
              package = pkgs.nixVersions.nix_2_15;
              settings = {
                allowed-users = [ user ];
                experimental-features = [ "nix-command" "flakes" ];
              };
            };
          })
          home-manager.darwinModule
          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              # makes all inputs available in imported files for hm
              extraSpecialArgs = {
                inherit inputs;
              };
              users.${user} = { ... }: {
                imports = [
                  shared
                  ./home-manager/common
                  ./home-manager/eve
                ];
                home.file.".hushlogin".text = "";
                home.stateVersion = stateVersion;
              };
            };
          }
        ];
      };

      # NixOS configuration for my Raspberry Pi
      nixosConfigurations.harbor = nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        # makes all inputs availble in imported files
        specialArgs = { inherit inputs; };
        modules = [
          shared
          ./machines/harbor/configuration.nix
          ({ pkgs, ... }: {
            nixpkgs.config = nixpkgsConfig;
            nixpkgs.overlays = overlays;
          })
          home-manager.nixosModules.home-manager
          {
            home-manager.users.pi = { ... }:
              {
                imports = [
                  ./home-manager/common
                  ./home-manager/harbor
                ];
                home.stateVersion = stateVersion;
              };
          }
        ];
      };
    };
}   
