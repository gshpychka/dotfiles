{
  nixpkgs,
  system,
}:
let
  pkgs = import nixpkgs {
    inherit system;
    config.allowUnfree = true;
  };
  inherit (pkgs) lib;
  values = import ../modules/common/values.nix;
in
pkgs.mkShell {
  buildInputs = [
    pkgs.terraform
    pkgs.google-cloud-sdk
    pkgs.sops
    pkgs.age
    pkgs.ssh-to-age
    (pkgs.writeShellScriptBin "tf" ''
      ${lib.getExe pkgs.sops} exec-env ../secrets/infra/terraform.env "${lib.getExe pkgs.terraform} $*"
    '')
  ];
  shellHook = ''
    export PRJ_ROOT=$(pwd)
    export CLOUDSDK_CONFIG=$PRJ_ROOT/.home/.config/gcloud
    export GOOGLE_APPLICATION_CREDENTIALS=$CLOUDSDK_CONFIG/application_default_credentials.json
    export CLOUDSDK_CORE_PROJECT="${values.gcpProjectId}"
    export CLOUDSDK_COMPUTE_REGION="us-central1"
    export CLOUDSDK_COMPUTE_ZONE="$CLOUDSDK_COMPUTE_REGION-a"
    export TF_VAR_gcp_project_id=$CLOUDSDK_CORE_PROJECT
    export TF_VAR_gcp_region=$CLOUDSDK_COMPUTE_REGION
    export TF_VAR_gcp_zone=$CLOUDSDK_COMPUTE_ZONE
    export TF_VAR_domain_name="${values.domain}"
    export TF_VAR_hostname="buoy"

    # decrypt infra with the host key, derived on demand via sudo (reaper);
    # the :- default preserves eve's op-based SOPS_AGE_KEY_CMD when already set
    export SOPS_AGE_KEY_CMD="''${SOPS_AGE_KEY_CMD:-sudo ${pkgs.ssh-to-age}/bin/ssh-to-age -private-key -i /etc/ssh/ssh_host_ed25519_key}"
  '';
}
