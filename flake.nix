{
  description = "My Machines";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
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
    sops-nix.url = "github:Mic92/sops-nix";
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
      ...
    }@inputs:
    {
      darwinConfigurations.eve = darwin.lib.darwinSystem {
        system = "aarch64-darwin";
        specialArgs = { inherit inputs; };
        modules = [
          inputs.sops-nix.darwinModules.sops
          home-manager.darwinModules.home-manager
          nix-homebrew.darwinModules.nix-homebrew

          ./modules/globals.nix
          ./machines/eve
          ./home-manager/eve
        ];
      };

      nixosConfigurations.harbor = nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        specialArgs = { inherit inputs; };
        modules = [
          inputs.sops-nix.nixosModules.sops
          home-manager.nixosModules.home-manager

          ./modules/globals.nix
          ./machines/harbor/configuration.nix
          ./home-manager/harbor
        ];
      };

      nixosConfigurations.reaper = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit inputs; };
        modules = [
          inputs.sops-nix.nixosModules.sops
          home-manager.nixosModules.home-manager

          ./modules/globals.nix
          ./machines/reaper
          ./home-manager/reaper
        ];
      };

      nixosConfigurations.hoard = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit inputs; };
        modules = [
          inputs.sops-nix.nixosModules.sops
          home-manager.nixosModules.home-manager

          ./machines/hoard/configuration.nix
          ./home-manager/hoard
          ./modules/globals.nix
        ];
      };

      checks = {
        aarch64-darwin.eve = self.darwinConfigurations.eve.config.system.build.toplevel;
        aarch64-linux.harbor = self.nixosConfigurations.harbor.config.system.build.toplevel;
        x86_64-linux.reaper = self.nixosConfigurations.reaper.config.system.build.toplevel;
        x86_64-linux.hoard = self.nixosConfigurations.hoard.config.system.build.toplevel;
      };
    };
}
