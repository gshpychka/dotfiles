{
  description = "My Machines";
  # printf 'run\tprivate/var/run\n' | sudo tee -a /etc/synthetic.conf
  # /System/Library/Filesystems/apfs.fs/Contents/Resources/apfs.util -t
  # nix --experimental-features "nix-command flakes" build ".#darwinConfigurations.eve.system"
  # ./result/sw/bin/darwin-rebuild switch --flake ".#eve"

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    nixos-stable.url = "github:nixos/nixpkgs/nixos-24.11";
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
    nix-homebrew = {
      url = "github:zhaofengli/nix-homebrew";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.nix-darwin.follows = "darwin";
    };
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
    # neovim-nightly-overlay = {
    #   url = "github:nix-community/neovim-nightly-overlay";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };
  };

  outputs = {
    self,
    nixpkgs,
    nixos-stable,
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
    };
    overlays = [
      (final: prev: let
        nixosStablePkgs = import nixos-stable {system = final.system;};
      in {
        # overrides from nixpkgs stable go here
        # pkgname = nixosStablePkgs.pkgname;
      })
    ];
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
            channel.enable = false;
            settings = {
              # originally motivated by https://github.com/NixOS/nixpkgs/pull/369588?new_mergebox=true#issuecomment-2566272567
              sandbox = "relaxed";
              allowed-users = [user];
              trusted-users = ["root" user];
              experimental-features = ["nix-command" "flakes"];

              # https://github.com/NixOS/nix/issues/7273
              auto-optimise-store = false;

              # needed for devenv to enable cachix
              accept-flake-config = true;
              http-connections = 0; # no limit
              download-buffer-size = 500000000; # 500MB
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
            users.${user} = {...}: {
              imports = [shared ./home-manager/eve];
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
          nixpkgs.config =
            {
              permittedInsecurePackages = ["openssl-1.1.1w"];
            }
            // nixpkgsConfig;
          nixpkgs.overlays = overlays;
          nix = {
            channel.enable = false;
            settings = {
              allowed-users = ["pi"];
              trusted-users = ["root" "pi"];
              experimental-features = ["nix-command" "flakes"];
              accept-flake-config = true;
            };
            gc = {
              dates = "weekly";
              automatic = true;
              options = "--delete-older-than 7d";
            };
          };
        })
        home-manager.nixosModules.home-manager
        {
          home-manager = {
            useGlobalPkgs = true;
            users.pi = {...}: {
              imports = [./home-manager/harbor];
              home.stateVersion = stateVersion;
            };
          };
        }
      ];
    };

    # NixOS configuration for reaper
    nixosConfigurations.reaper = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {inherit inputs;};
      modules = [
        ./machines/reaper/configuration.nix
        ({pkgs, ...}: {
          nixpkgs.config =
            {
              cudaSupport = true;
            }
            // nixpkgsConfig;
          nixpkgs.overlays = overlays;
          nix = {
            channel.enable = false;
            settings = {
              allowed-users = [user];
              trusted-users = ["root" user];
              experimental-features = ["nix-command" "flakes"];
              auto-optimise-store = true;
              accept-flake-config = true;
              http-connections = 0; # no limit
              download-buffer-size = 500000000; # 500MB
            };
            gc = {
              dates = "weekly";
              automatic = true;
              options = "--delete-older-than 7d";
            };
          };
        })
        home-manager.nixosModules.home-manager
        {
          home-manager = {
            useGlobalPkgs = true;
            users.${user} = {...}: {
              imports = [./home-manager/reaper];
              home.stateVersion = "24.05";
            };
          };
        }
      ];
    };

    nixosConfigurations.hoard = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {inherit inputs;};
      modules = [
        ./machines/hoard/configuration.nix
        ({pkgs, ...}: {
          nixpkgs.config =
            {
              permittedInsecurePackages = [
                # required for sonarr
                "aspnetcore-runtime-6.0.36"
                "aspnetcore-runtime-wrapped-6.0.36"
                "dotnet-sdk-6.0.428"
                "dotnet-sdk-wrapped-6.0.428"
              ];
            }
            // nixpkgsConfig;
          nixpkgs.overlays = overlays;
          nix = {
            channel.enable = false;
            settings = {
              allowed-users = [user];
              trusted-users = ["root" user];
              experimental-features = ["nix-command" "flakes"];
              auto-optimise-store = true;
              accept-flake-config = true;
              http-connections = 0; # no limit
            };
            gc = {
              dates = "weekly";
              automatic = true;
              options = "--delete-older-than 7d";
            };
          };
        })
        home-manager.nixosModules.home-manager
        {
          home-manager = {
            useGlobalPkgs = true;
            users.${user} = {...}: {
              imports = [./home-manager/hoard];
              home.stateVersion = "24.11";
            };
          };
        }
      ];
    };
  };
}
