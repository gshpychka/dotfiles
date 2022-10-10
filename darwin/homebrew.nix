{ config, pkgs, lib, ... }: {
  homebrew = {
    enable = true;
    onActivation = {
      # "zap" removes manually installed brews and casks
      cleanup = "zap";
      autoUpdate = true;
    };
    brews = [
      "helm"
      "kubebuilder" # generating k8s controller
      "lima" # docker alternative
      "skhd" # keybinding manager

      # ios development
      "cocoapods"
      "ios-deploy"

      # broken nix builds
      "openstackclient"
      "yabai" # tiling window manager
      "earthly" # makefile alternative

      # gardener
      "openvpn"
      "iproute2mac"
      "parallel"

      # sketchybar
      "sketchybar" # macos bar alternative
      "ifstat" # network
    ];
    casks = [
      # utilities
      "aldente" # battery management
      "bartender" # hides mac bar icons
      "browserosaurus" # choose browser on each link
      "karabiner-elements" # remap keyboard
      "macfuse" # file system utilities
      "hammerspoon" # lua scripting engine

      # virtualization
      "docker" # docker desktop
      "utm" # virtual machines
      "kui" # UI for kubectl

      # communication
      "microsoft-teams"
      "mutify" # one click mute button
      "zoom"
      "slack"
      "mumble" # teamspeak alternative
      "signal" # messenger
      "teamviewer"
      "discord"

      "adobe-creative-cloud"
      "android-studio"
      "balenaetcher"
      "blender"
      "calibre" # ebook management
      "chromium"
      "google-chrome"
      "lens" # visual k9s
      "meld" # folder differ
      "mixxx" # dj software
      "obs" # stream / recoding software
      "postman"
      "bloomrpc"
      "protonmail-bridge"
      "raspberry-pi-imager"
      "shottr" # screenshot tool
      "the-unarchiver"
      "tunnelblick" # vpn client
      "ubersicht"
      "unity-hub"
      "visual-studio-code"
      "vscodium" # unbranded vscode
      "vlc" # media player
      "eul" # mac monitoring
      "qmk-toolbox" # flashing keyboard
      "kindavim" # vim keys for everything
      "kap" # screen recorder software
      "wireshark" # network sniffer
      "sf-symbols" # patched font for sketchybar
    ];
    taps = [
      # default
      "homebrew/bundle"
      "homebrew/cask"
      "homebrew/cask-drivers"
      "homebrew/cask-fonts"
      "homebrew/core"
      "homebrew/services"
      # custom
      "cmacrae/formulae" # spacebar
      "koekeishiya/formulae" # yabai
      "earthly/earthly" # earthly
      "FelixKratz/formulae" # sketchybar
    ];
  };
}