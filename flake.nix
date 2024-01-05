{
  description = "My Machines";
  # printf 'run\tprivate/var/run\n' | sudo tee -a /etc/synthetic.conf
  # /System/Library/Filesystems/apfs.fs/Contents/Resources/apfs.util -t
  # nix --experimental-features "nix-command flakes" build ".#darwinConfigurations.eve.system"
  # ./result/sw/bin/darwin-rebuild switch --flake ".#eve"

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    darwin = {
      url = "github:lnl7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    mkAlias = {
      url = "github:reckenrode/mkalias";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-homebrew.url = "github:gshpychka/nix-homebrew";

    homebrew-core = {
      url = "github:homebrew/homebrew-core";
      flake = false;
    };
    homebrew-cask = {
      url = "github:homebrew/homebrew-cask";
      flake = false;
    };
    homebrew-services = {
      url = "github:homebrew/homebrew-services";
      flake = false;
    };
    homebrew-bundle = {
      url = "github:homebrew/homebrew-bundle";
      flake = false;
    };
  };

  outputs = {
    self,
    nixpkgs,
    darwin,
    home-manager,
    nix-homebrew,
    homebrew-core,
    homebrew-cask,
    homebrew-services,
    homebrew-bundle,
    ...
  } @ inputs: let
    shared = import ./machines/harbor/variables.nix;
    nixpkgsConfig = {
      allowUnfree = true;
      allowUnsupportedSystem = false;
    };
    overlays = with inputs; [];
    stateVersion = "22.11";
    user = "gshpychka";
  in {
    # nix-darwin with home-manager for macOS
    darwinConfigurations.eve = darwin.lib.darwinSystem {
      system = "aarch64-darwin";
      # makes all inputs availble in imported files
      specialArgs = {inherit inputs;};
      modules = [
        ./machines/eve/configuration.nix
        ./machines/eve/homebrew.nix
        ({pkgs, ...}: {
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
              allowed-users = [user];
              trusted-users = ["root" user];
              experimental-features = ["nix-command" "flakes"];
              auto-optimise-store = true;
              # needed for devenv to enable cachix
              accept-flake-config = true;
            };
            gc = {
              automatic = true;
              interval = {
                Hour = 12;
              };
              options = "--delete-old";
            };
          };
        })
        home-manager.darwinModule
        {
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            # makes all inputs available in imported files for hm
            extraSpecialArgs = {inherit inputs;};
            users.${user} = {...}: {
              imports = [shared ./home-manager/common ./home-manager/eve];
              home.file.".hushlogin".text = "";
              home.stateVersion = stateVersion;
            };
          };
        }
        nix-homebrew.darwinModules.nix-homebrew
        {
          nix-homebrew = {
            # Install Homebrew under the default prefix
            enable = true;

            enableRosetta = false;

            # User owning the Homebrew prefix
            user = user;

            taps = {
              "homebrew/homebrew-core" = homebrew-core;
              "homebrew/homebrew-cask" = homebrew-cask;
              "homebrew/homebrew-services" = homebrew-services;
              "homebrew/homebrew-bundle" = homebrew-bundle;
            };
            mutableTaps = false;
          };
        }
      ];
    };

    # NixOS configuration for my Raspberry Pi
    nixosConfigurations.harbor = nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";
      # makes all inputs availble in imported files
      specialArgs = {inherit inputs;};
      modules = [
        shared
        ./machines/harbor/configuration.nix
        ({pkgs, ...}: {
          nixpkgs.config = nixpkgsConfig;
          nixpkgs.overlays = overlays;
          nix = {
            package = pkgs.nixVersions.nix_2_15;
            settings = {
              allowed-users = ["pi"];
              experimental-features = ["nix-command" "flakes"];
              accept-flake-config = true;
            };
          };
        })
        home-manager.nixosModules.home-manager
        {
          home-manager.users.pi = {...}: {
            imports = [./home-manager/common ./home-manager/harbor];
            home.stateVersion = stateVersion;
          };
        }
      ];
    };
  };
}
