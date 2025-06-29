# Nix Dotfiles Configuration

## Overview
Personal dotfiles managed with Nix flakes for multiple machines (eve, harbor, reaper, hoard).

## Architecture
- `machines/` - Machine-specific NixOS configurations
- `modules/` - Shared modules (darwin/nixos/common)
- `home-manager/` - User environment configs
- `overlays/` - Package overlays
- `secrets/` - SOPS encrypted secrets

## Standards
- As much as possible should be declarative
- Imperative steps should be recorded in comments close to where they are relevant
- Not too much abstraction and/or layers of indirection
- Type safety is important, magic strings should be avoided where possible
- Weird / non-obvious things should be explained clearly in comments
- Refactoring should not be feared
- Assumptions about functionality should be avoided, or at least documented explicitly

## Machines
- eve: M2 Pro MacBook (aarch64-darwin)
    - Acts as the entry point - the only machine that is used directly
    - nix-darwin for system setup, homebrew for GUI apps
- harbor: Raspberry Pi 4 DNS/DHCP server (aarch64-linux)
    - dnsmasq for DHCP and local DNS, Adgurd Home upstream ad blocking
- reaper: Desktop with Intel 14900k, RTX 4090, 96GB RAM (x86_64-linux)
    - Headless
    - AI server: ollama, whisper, kokoro
    - Work environment: SSH from eve, coding in neovim
- hoard: Beelink S12 Pro Intel N100 mini PC media server with external HDD enclosure (x86_64-linux)
    - Media server running the arr stack and Plex

## Notes
- Nix only sees files that are tracked by git - run `git add` before checking config
- Check config after making non-trivial changes: `nix flake check --all-systems --no-build`
- Perform a full build if on the relevant machine: `nix flake check`
