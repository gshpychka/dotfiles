{
  description = "My Machines";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    # source for reaper's whisper CUDA closure (cache.nixos-cuda.org builds these
    # on the 25.11 channel; see machines/reaper/whisper.nix), and an escape hatch
    # for packages broken on unstable
    nixos-stable.url = "github:nixos/nixpkgs/nixos-25.11";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-index-database = {
      url = "github:nix-community/nix-index-database";
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
      # not following our nixpkgs: more cache hits that way
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
    nixos-hardware = {
      url = "github:NixOS/nixos-hardware/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # auto-imports a directory tree of modules
    import-tree.url = "github:vic/import-tree";
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
      # formatter packages shared by `nix fmt` and the treefmt check
      treefmtTools =
        pkgs: with pkgs; [
          treefmt
          nixfmt
          stylua
          shfmt
          taplo
          ruff
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
          # sops-nix is needed for evaluation: the (disabled) modules in
          # modules/system/nixos define sops.secrets values behind mkIf
          inputs.sops-nix.nixosModules.sops

          ./modules/system/nixos
          ./machines/iso
        ];
      };

      # expose the ISO for easy building: `nix build .#iso`
      packages.x86_64-linux.iso = self.nixosConfigurations.iso.config.system.build.isoImage;

      # bootable SD image for harbor: `nix build .#harbor-sd-image`
      packages.aarch64-linux.harbor-sd-image =
        (self.nixosConfigurations.harbor.extendModules {
          modules = [ "${nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64.nix" ];
        }).config.system.build.sdImage;

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
          machines = removeAttrs self.nixosConfigurations [
            "iso"
            "buoy-bootstrap"
          ];
          nixosChecks = lib.foldlAttrs (
            acc: name: machine:
            lib.recursiveUpdate acc {
              ${machine.config.nixpkgs.hostPlatform.system}.${name} = machine.config.system.build.toplevel;
            }
          ) { } machines;
          # statix + deadnix lint the flake source per system; statix.toml at the
          # repo root disables repeated_keys, deadnix runs strict (no exceptions)
          lintChecks = lib.genAttrs systems (
            system:
            let
              pkgs = nixpkgs.legacyPackages.${system};
            in
            {
              statix = pkgs.runCommand "check-statix" { nativeBuildInputs = [ pkgs.statix ]; } ''
                statix check ${self} -c ${self}
                touch $out
              '';
              deadnix = pkgs.runCommand "check-deadnix" { nativeBuildInputs = [ pkgs.deadnix ]; } ''
                deadnix --fail ${self}
                touch $out
              '';
              # whole-tree format check; copy out of the read-only store so
              # treefmt can rewrite in place, then fail if anything changed
              treefmt = pkgs.runCommand "check-treefmt" { nativeBuildInputs = treefmtTools pkgs; } ''
                cp -r --no-preserve=mode,ownership ${self} src
                cd src
                HOME=$TMPDIR treefmt --no-cache --fail-on-change --tree-root .
                touch $out
              '';
              ruff = pkgs.runCommand "check-ruff" { nativeBuildInputs = [ pkgs.ruff ]; } ''
                ruff check --config ${self}/ruff.toml ${self}
                touch $out
              '';
            }
          );
        in
        lib.recursiveUpdate (lib.recursiveUpdate nixosChecks lintChecks) {
          aarch64-darwin.eve = self.darwinConfigurations.eve.config.system.build.toplevel;
          x86_64-linux.iso = self.nixosConfigurations.iso.config.system.build.isoImage;
        };

      # `nix fmt` — treefmt drives the per-language formatters (see treefmt.toml)
      formatter = lib.genAttrs systems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        pkgs.writeShellApplication {
          name = "treefmt";
          runtimeInputs = treefmtTools pkgs;
          text = ''exec treefmt "$@"'';
        }
      );

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
