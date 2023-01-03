This repo represents my first steps in the Nix world and is pretty terrible. It will hopefully get better as I get more comfortable with the ecosystem. At this point, I just want to get to a basic dev env and don't dedicate too much effort into making the config nice. I will switch my attention to that as the next priority, though.

Steps when setting up from scratch:

1. Disable SIP (required for yabai)
 - Boot into recovery by holding command + R during boot
 - Utilities -> Terminal
 - `csrutil disable --with kext --with dtrace --with nvram --with basesystem`
2. Install Homebrew (for some reason, nix-darwin doesn't handle this)
 - `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"`
3. Install Nix
 - `sh <(curl -L https://nixos.org/nix/install)`
4. Build the system
 - `nix build .#darwinConfigurations.gshpychka-mbp.system --extra-experimental-features "nix-command flakes"`
5. Something to do with the read-only root partition:
 - `printf 'run\tprivate/var/run\n' | sudo tee -a /etc/synthetic.conf`
 - `/System/Library/Filesystems/apfs.fs/Contents/Resources/apfs.util -t`
6. Switch to the system
 - `./result/sw/bin/darwin-rebuild switch --flake ".#mbp"`