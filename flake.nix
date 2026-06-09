{
  description = "My Machines";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    # currently unused - kept as an escape hatch for packages broken on unstable
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
      # has no nixpkgs input, so there is nothing to `follows`
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
    homebrew-dagger = {
      url = "github:dagger/homebrew-tap";
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
      # deliberately NOT following our nixpkgs: keeps the upstream
      # cache.numtide.com binary cache usable (substituter is configured
      # in modules/system/common/nix-config.nix)
      url = "github:numtide/llm-agents.nix";
    };
    nixified-ai = {
      url = "github:nixified-ai/flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    jovian-nixos = {
      url = "github:Jovian-Experiments/Jovian-NixOS";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
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
    let
      inherit (nixpkgs) lib;
      # every system the fleet spans
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
    in
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
          inputs.nixos-hardware.nixosModules.raspberry-pi-4
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

      # Minimal bootstrap NixOS config for GCE image
      # Full config is deployed separately via nixos-rebuild
      nixosConfigurations.buoy-bootstrap = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [ ./infra/nixos/configuration.nix ];
      };

      # GCE image for buoy VPS: `nix build .#gce-image`
      packages.x86_64-linux.gce-image =
        let
          pkgs = nixpkgs.legacyPackages.x86_64-linux;
          original = self.nixosConfigurations.buoy-bootstrap.config.system.build.googleComputeImage;
        in
        pkgs.runCommand "gce-image.raw.tar.gz" { inherit original; } ''
          cp $original/*.raw.tar.gz $out
        '';

      # One check per machine, grouped by system and derived from the config
      # sets, so new machines are covered automatically.
      checks =
        let
          # iso's build artifact is the ISO image, special-cased below;
          # buoy-bootstrap is only an image-build shim, covered by packages.gce-image
          machines = builtins.removeAttrs self.nixosConfigurations [
            "iso"
            "buoy-bootstrap"
          ];
          nixosChecks = lib.foldlAttrs (
            acc: name: machine:
            lib.recursiveUpdate acc {
              ${machine.config.nixpkgs.hostPlatform.system}.${name} = machine.config.system.build.toplevel;
            }
          ) { } machines;
        in
        lib.recursiveUpdate nixosChecks {
          aarch64-darwin.eve = self.darwinConfigurations.eve.config.system.build.toplevel;
          x86_64-linux.iso = self.nixosConfigurations.iso.config.system.build.isoImage;
        };

      # `nix fmt`
      formatter = lib.genAttrs systems (system: nixpkgs.legacyPackages.${system}.nixfmt-rfc-style);

      devShells =
        let
          mkShell =
            system:
            let
              pkgs = nixpkgs.legacyPackages.${system};
            in
            {
              default = pkgs.mkShell { buildInputs = [ pkgs.sops ]; };
              infra = import ./infra/shell.nix { inherit nixpkgs system; };
            };
        in
        lib.genAttrs systems mkShell;
    };
}
