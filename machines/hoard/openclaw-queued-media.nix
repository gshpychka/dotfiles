# Reviewed e178c39e source fixes; preserve the host tool PATH and plugin configuration.
{ inputs, ... }:
let
  repo = inputs.nix-openclaw;
  pkgs = import repo.inputs.nixpkgs { system = "x86_64-linux"; };
  sourceInfo = import (repo + "/nix/sources/openclaw-source.nix");
  source = pkgs.fetchFromGitHub (
    builtins.removeAttrs sourceInfo [
      "pnpmMajor"
      "applyPublicSurfaceHardlinksPatch"
      "applySkipPluginAutoEnableNixModePatch"
      "applyNixStorePluginOwnershipPatch"
      "releaseTag"
      "releaseVersion"
      "runtimePluginVersion"
      "gatewayNpmDepsHash"
    ]
  );
  patched = pkgs.applyPatches {
    name = "openclaw-e178c39e-queued-media-source";
    src = source;
    patches = [
      (repo + "/nix/patches/queued-source-adoption-e178c39e.patch.gz")
      (repo + "/nix/patches/completion-local-media-e178c39e.patch.gz")
    ];
  };
  buildPlugin = pkgs.callPackage (repo + "/nix/lib/openclaw-runtime-plugin.nix") {
    linkOpenClawPeer = false;
  };
  locks = import (repo + "/nix/generated/openclaw-runtime-plugins");
  gateway = pkgs.callPackage (repo + "/nix/packages/openclaw-gateway.nix") {
    inherit sourceInfo;
    gatewaySrc = patched;
    pnpmDepsHash = "sha256-CO2ykEZhdyCVCgQQlNyFZl274VfGzgNl7TbJ6/gMRp8=";
    bundledAcpx = buildPlugin locks.acpx;
  };
in
{
  nixpkgs.overlays = [
    (_final: _prev: {
      openclaw-gateway = gateway;
      # This host aliases openclaw to the component Gateway, not the batteries bundle.
      openclaw = gateway;
    })
  ];
}
