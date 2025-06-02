{
  description = "My Machines";
  # printf 'run\tprivate/var/run\n' | sudo tee -a /etc/synthetic.conf
  # /System/Library/Filesystems/apfs.fs/Contents/Resources/apfs.util -t
  # nix --experimental-features "nix-command flakes" build ".#darwinConfigurations.eve.system"
  # ./result/sw/bin/darwin-rebuild switch --flake ".#eve"

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    nixos-stable.url = "github:nixos/nixpkgs/nixos-25.05";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    darwin = {
      url = "github:nix-darwin/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-homebrew = {
      url = "github:zhaofengli/nix-homebrew";
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
    sops-nix.url = "github:Mic92/sops-nix";
    # neovim-nightly-overlay = {
    #   url = "github:nix-community/neovim-nightly-overlay";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };
    overseerr-nixpkgs.url = "github:jf-uu/nixpkgs/overseerr";
  };

  outputs =
    {
      self,
      nixpkgs,
      nixos-stable,
      overseerr-nixpkgs,
      darwin,
      home-manager,
      nix-homebrew,
      homebrew-core,
      homebrew-cask,
      homebrew-services,
      ...
    }@inputs:
    let
      # allow unfree packages across all builds
      nixpkgsConfig = {
        allowUnfree = true;
      };

      globalNixModule = {
        nix = {
          channel.enable = false;
          settings = {
            extra-substituters = [ "https://nix-community.cachix.org" ];
            extra-trusted-public-keys = [
              "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
            ];
            experimental-features = [
              "nix-command"
              "flakes"
            ];
          };
        };
      };

      overlays = [
        (
          final: prev:
          let
            nixosStablePkgs = import nixos-stable { system = final.system; };
          in
          {
            # overrides from stable pkgs
            # pkgname = nixosStablePkgs.pkgname;
          }
        )
      ];

      stateVersion = "22.11";
      user = "gshpychka";
    in
    {
      darwinConfigurations.eve = darwin.lib.darwinSystem {
        system = "aarch64-darwin";
        specialArgs = { inherit inputs; };
        modules = [
          inputs.sops-nix.darwinModules.sops
          ./machines/eve/configuration.nix
          ./machines/eve/homebrew.nix

          globalNixModule

          (
            { pkgs, ... }:
            {
              nixpkgs.config = nixpkgsConfig;
              nixpkgs.overlays = overlays;
              system.stateVersion = 4;

              users.users.${user} = {
                home = "/Users/${user}";
                shell = pkgs.zsh;
              };

              nix.settings = {
                # originally motivated by https://github.com/NixOS/nixpkgs/pull/369588?new_mergebox=true#issuecomment-2566272567
                sandbox = "relaxed";
                allowed-users = [ user ];
                trusted-users = [ user ];
                # https://github.com/NixOS/nix/issues/7273
                auto-optimise-store = false;
                accept-flake-config = true;
                http-connections = 0;
                download-buffer-size = 500000000;
              };
              nix.gc = {
                automatic = true;
                interval = {
                  Hour = 12;
                };
              };
            }
          )

          home-manager.darwinModules.home-manager
          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              users.${user} =
                { ... }:
                {
                  imports = [ ./home-manager/eve ];
                  home.file.".hushlogin".text = "";
                  home.stateVersion = stateVersion;
                };
            };
          }

          nix-homebrew.darwinModules.nix-homebrew
          {
            nix-homebrew = {
              enable = true;
              enableRosetta = false;
              user = user;
              taps = {
                "homebrew/homebrew-core" = homebrew-core;
                "homebrew/homebrew-cask" = homebrew-cask;
                "homebrew/homebrew-services" = homebrew-services;
              };
              mutableTaps = false;
            };
          }
        ];
      };

      nixosConfigurations.harbor = nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        specialArgs = { inherit inputs; };
        modules = [
          inputs.sops-nix.nixosModules.sops
          ./machines/harbor/configuration.nix

          globalNixModule

          (
            { pkgs, ... }:
            {
              nixpkgs.config = {
                permittedInsecurePackages = [ "openssl-1.1.1w" ];
              } // nixpkgsConfig;
              nixpkgs.overlays = overlays;

              nix.settings = {
                allowed-users = [ "pi" ];
                trusted-users = [ "pi" ];

                auto-optimise-store = true;
              };
              nix.gc = {
                dates = "weekly";
                automatic = true;
                options = "--delete-older-than 7d";
              };
            }
          )

          home-manager.nixosModules.home-manager
          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              users.pi =
                { ... }:
                {
                  imports = [ ./home-manager/harbor ];
                  home.stateVersion = stateVersion;
                };
            };
          }
        ];
      };

      nixosConfigurations.reaper = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit inputs; };
        modules = [
          inputs.sops-nix.nixosModules.sops
          ./machines/reaper/configuration.nix

          globalNixModule

          (
            { pkgs, ... }:
            {
              nixpkgs.config = {
                # We shouldn't set cudaSupport = true here, because it will lead to
                # building e.g. pytorch from source
                # Omitting it does NOT prevent CUDA support
                # If a package requires this flag, use an override

                # Keeping this here to be explicit
                # cudaSupport = true;

                # https://en.wikipedia.org/wiki/CUDA#GPUs_supported
                cudaCapabilities = [ "8.9" ];
                cudaForwardCompat = true;
                nvidia.acceptLicense = true;
              } // nixpkgsConfig;
              nixpkgs.overlays = [
                # Since we don't set cudaSupport = true globally, we need to enable CUDA
                # for each package that requires it
                (self: super: {
                  ctranslate2 = super.ctranslate2.override {
                    withCUDA = true;
                    withCuDNN = true;
                  };
                  btop = super.btop.override { cudaSupport = true; };
                })
              ] ++ overlays;

              nix.settings = {
                allowed-users = [ user ];
                trusted-users = [ user ];

                auto-optimise-store = true;
                accept-flake-config = true;
                http-connections = 0;
                download-buffer-size = 500000000;
                extra-substituters = [ "https://cuda-maintainers.cachix.org" ];
                extra-trusted-public-keys = [
                  "cuda-maintainers.cachix.org-1:0dq3bujKpuEPMCX6U4WylrUDZ9JyUG0VpVZa7CNfq5E="
                ];
              };
              nix.gc = {
                dates = "weekly";
                automatic = true;
                options = "--delete-older-than 7d";
              };
            }
          )

          home-manager.nixosModules.home-manager
          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              users.${user} =
                { ... }:
                {
                  imports = [ ./home-manager/reaper ];
                  home.stateVersion = "24.05";
                };
            };
          }
        ];
      };

      nixosConfigurations.hoard = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit inputs; };
        modules = [
          inputs.sops-nix.nixosModules.sops
          ./machines/hoard/configuration.nix

          globalNixModule

          (
            { pkgs, ... }:
            {
              nixpkgs.config = {
                permittedInsecurePackages = [
                  # required for Sonarr
                  "aspnetcore-runtime-6.0.36"
                  "aspnetcore-runtime-wrapped-6.0.36"
                  "dotnet-sdk-6.0.428"
                  "dotnet-sdk-wrapped-6.0.428"
                ];
              } // nixpkgsConfig;
              nixpkgs.overlays = [
                # https://github.com/NixOS/nixpkgs/pull/399266
                (
                  final: prev:
                  let
                    overseerrPkgs = import overseerr-nixpkgs {
                      inherit (final) system config;
                    };
                  in
                  {
                    overseerr = overseerrPkgs.overseerr;
                  }
                )
              ] ++ overlays;

              nix.settings = {
                allowed-users = [ user ];
                trusted-users = [ user ];
                auto-optimise-store = true;
                accept-flake-config = true;
                http-connections = 0;
              };
              nix.gc = {
                dates = "weekly";
                automatic = true;
                options = "--delete-older-than 7d";
              };
            }
          )

          home-manager.nixosModules.home-manager
          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              users.${user} =
                { ... }:
                {
                  imports = [ ./home-manager/hoard ];
                  home.stateVersion = "24.11";
                };
            };
          }
        ];
      };
    };
}
