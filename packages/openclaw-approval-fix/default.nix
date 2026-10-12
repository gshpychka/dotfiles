{ inputs, system ? "x86_64-linux", approvalPatch ? null }:
let
  input = inputs.nix-openclaw;
  pkgs = import input.inputs.nixpkgs { inherit system; };
  pnpm12 = (pkgs.callPackage (input + "/nix/packages/pnpm-12.nix") {}).overrideAttrs (old: {
    version = "12.5.1";
    src = pkgs.fetchurl {
      url = "https://registry.npmjs.org/@pnpm/exe.linux-x64/-/exe.linux-x64-12.5.1.tgz";
      hash = "sha512-3PkUBYo5z4dgtlnTNIFj7QGpcDUAuqXz9WGVigPDCeccEnhGiRkWmA5102TmYJHtwJP3LfmE+ZF9PGeWhn8p9Q==";
    };
  });
  sourceInfo = {
    owner = "openclaw"; repo = "openclaw";
    rev = "e178c39e9aae3fa440735217f9aef9574f286677";
    hash = "sha256-KWbh0iUzav08tohNFh76T2vIALfd5un5w3RHDCfe8yw=";
    pnpmMajor = "12"; runtimePluginVersion = "2026.10.1";
    applyPublicSurfaceHardlinksPatch = false;
    applySkipPluginAutoEnableNixModePatch = false;
    # Stable ownership patch needs adaptation for e178 discovery refactor.
    applyNixStorePluginOwnershipPatch = false;
  };
  # Retain the exact deployed ACPX 2026.10.1 payload, not the stable input's 2026.9.5.
  installedGatewayPath = "/nix/store/nmpa9wg7fv0yfbpd6gkgpkc2rzpr4xi4-openclaw-gateway-unstable-e178c39e";
  installedGateway = builtins.appendContext installedGatewayPath {
    "${installedGatewayPath}" = { path = true; };
  };
  bundledAcpx = pkgs.runCommand "openclaw-bundled-acpx-2026.10.1-preserved" {
    passthru.openclawRuntimePlugin = { id = "acpx"; version = "2026.10.1"; };
  } ''
    mkdir -p $out
    cp -R ${installedGateway}/lib/openclaw/dist/extensions/acpx/. $out/
  '';
  gatewayBase = pkgs.callPackage (input + "/nix/packages/openclaw-gateway-source.nix") {
    inherit sourceInfo bundledAcpx;
    pnpm_11 = pkgs.callPackage (input + "/nix/packages/pnpm-11.nix") {};
    pnpm_12 = pnpm12;
    pnpmDepsHash = "sha256-CO2ykEZhdyCVCgQQlNyFZl274VfGzgNl7TbJ6/gMRp8=";
  };
  gateway = gatewayBase.overrideAttrs (old: {
    env = (old.env or { }) // {
      # e178 measures a 4352 MiB heap in a successful 5 GiB cgroup build.
      # Nix sandbox cgroup visibility can prevent automatic budget discovery.
      OPENCLAW_TSDOWN_MAX_OLD_SPACE_MB = "4352";
    };
    patches = (old.patches or []) ++ [ ./allow-nix-store-plugin-ownership-e178.patch ]
      ++ pkgs.lib.optional (approvalPatch != null) approvalPatch;
  });
in gateway
