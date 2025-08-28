inputs: final: prev: {
  open-webui = inputs.nixos-stable.legacyPackages.${prev.stdenv.hostPlatform.system}.open-webui;
}
