# Isolated build/test environment only. No module/service/activation changes.
let
  root = ../..;
  flake = builtins.getFlake (toString root);
  pkgs = import flake.inputs.nixpkgs { system = builtins.currentSystem; };
in pkgs.mkShell {
  packages = [ pkgs.python313 pkgs.gcc pkgs.pkg-config pkgs.webrtc-audio-processing ];
  LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath [ pkgs.stdenv.cc.cc.lib pkgs.zlib ];
}
