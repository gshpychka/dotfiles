{
  description = "My Machines";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixos-stable.url = "github:nixos/nixpkgs/nixos-25.11";
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
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    lanzaboote = {
      url = "github:nix-community/lanzaboote";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    mcp-servers-nix = {
      url = "github:natsukium/mcp-servers-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    llm-agents = {
      url = "github:numtide/llm-agents.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixified-ai = {
      url = "github:nixified-ai/flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    jovian-nixos = {
      url = "github:Jovian-Experiments/Jovian-NixOS";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      darwin,
      home-manager,
      nix-homebrew,
      ...
    }@inputs:
    {
      darwinConfigurations.eve = darwin.lib.darwinSystem {
        specialArgs = { inherit inputs; };
        modules = [
          inputs.sops-nix.darwinModules.sops
          home-manager.darwinModules.home-manager
          nix-homebrew.darwinModules.nix-homebrew

          ./modules/system/darwin
          ./machines/eve
        ];
      };

      nixosConfigurations.harbor = nixpkgs.lib.nixosSystem {
        specialArgs = { inherit inputs; };
        modules = [
          inputs.sops-nix.nixosModules.sops
          home-manager.nixosModules.home-manager

          ./modules/system/nixos
          ./machines/harbor
        ];
      };

      nixosConfigurations.reaper = nixpkgs.lib.nixosSystem {
        specialArgs = { inherit inputs; };
        modules = [
          inputs.sops-nix.nixosModules.sops
          inputs.lanzaboote.nixosModules.lanzaboote
          inputs.jovian-nixos.nixosModules.jovian
          home-manager.nixosModules.home-manager

          ./modules/system/nixos
          ./machines/reaper
        ];
      };

      nixosConfigurations.hoard = nixpkgs.lib.nixosSystem {
        specialArgs = { inherit inputs; };
        modules = [
          inputs.sops-nix.nixosModules.sops
          home-manager.nixosModules.home-manager

          ./modules/system/nixos
          ./machines/hoard
        ];
      };

      # vm in gcp
      # nixos-rebuild switch --flake .#buoy --target-host buoy --sudo
      nixosConfigurations.buoy = nixpkgs.lib.nixosSystem {
        specialArgs = { inherit inputs; };
        modules = [
          inputs.sops-nix.nixosModules.sops

          ./modules/system/nixos
          ./machines/buoy
        ];
      };

      # bootable ISO installer image
      nixosConfigurations.iso = nixpkgs.lib.nixosSystem {
        specialArgs = { inherit inputs; };
        modules = [
          ./modules/common
          ./modules/system/common
          ./machines/iso
        ];
      };

      # expose the ISO for easy building: `nix build .#iso`
      packages.x86_64-linux.iso = self.nixosConfigurations.iso.config.system.build.isoImage;

      checks = {
        aarch64-darwin.eve = self.darwinConfigurations.eve.config.system.build.toplevel;
        aarch64-linux.harbor = self.nixosConfigurations.harbor.config.system.build.toplevel;
        x86_64-linux.reaper = self.nixosConfigurations.reaper.config.system.build.toplevel;
        x86_64-linux.hoard = self.nixosConfigurations.hoard.config.system.build.toplevel;
        x86_64-linux.buoy = self.nixosConfigurations.buoy.config.system.build.toplevel;
        x86_64-linux.iso = self.nixosConfigurations.iso.config.system.build.isoImage;
      };
    };
}
