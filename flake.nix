{
  description = "My Machines";

  # nix --experimental-features "nix-command flakes" build ".#darwinConfigurations.mbp.system"
  # ./result/sw/bin/darwin-rebuild switch --flake ~/.nixpkgs


  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    darwin = {
      url = "github:lnl7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };


    forgit = {
      url = "github:wfxr/forgit";
      flake = false;
    };
  };


  outputs = { self, nixpkgs, darwin, home-manager, ... }@inputs:
    let
      nixpkgsConfig = {
        allowUnfree = true;
        allowUnsupportedSystem = false;
      };
      overlays = with inputs; [
      ];
      stateVersion = "22.11";
      user = "gshpychka";
    in
    {
      # nix-darwin with home-manager for macOS
      darwinConfigurations.mbp = darwin.lib.darwinSystem {
        system = "x86_64-darwin";
        # makes all inputs availble in imported files
        specialArgs = { inherit inputs; };
        modules = [
          ./modules
          ./machines/mbp.nix
          ./darwin/homebrew.nix
          ({ pkgs, ... }: {
            nixpkgs.config = nixpkgsConfig;
            nixpkgs.overlays = overlays;

            system.stateVersion = 4;

            users.users.${user} = {
              home = "/Users/${user}";
              shell = pkgs.zsh;
            };

            nix = {
              # enable flakes per default
              package = pkgs.nixFlakes;
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
              extraSpecialArgs = { inherit inputs; };
              users.${user} = { ... }: {
                imports = [
                  ./home/mac.nix
                  ./darwin
                  ./shell
                ];
                home.stateVersion = stateVersion;
              };
            };
          }
        ];
      };
    };
}
