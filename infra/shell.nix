{ nixpkgs, system }:
let
  pkgs = import nixpkgs {
    inherit system;
    config.allowUnfree = true;
  };
in
pkgs.mkShell {
  buildInputs = [
    pkgs.terraform
    pkgs.google-cloud-sdk
    pkgs.sops
    pkgs.age
    (pkgs.writeShellScriptBin "tf" ''
      eval "$(${pkgs.sops}/bin/sops -d "$PRJ_ROOT/../secrets/infra/cloudflare.yaml" | sed 's/: /=/g' | sed 's/^/export TF_VAR_/')"
      ${pkgs.terraform}/bin/terraform "$@"
    '')
  ];
  shellHook = ''
    export PRJ_ROOT=$(pwd)
    export CLOUDSDK_CONFIG=$PRJ_ROOT/.home/.config/gcloud
    export GOOGLE_CLOUD_PROJECT="status-glibsh"
    export CLOUDSDK_COMPUTE_REGION="us-central1"
    export CLOUDSDK_COMPUTE_ZONE="$CLOUDSDK_COMPUTE_REGION-a"
  '';
}
