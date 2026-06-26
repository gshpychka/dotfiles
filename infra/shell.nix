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
      ${lib.getExe pkgs.sops} exec-env "$REPO_ROOT/secrets/infra/terraform.env" "${lib.getExe pkgs.terraform} $*"
    '')
  ];
  shellHook = ''
    # repo-anchored so tf/gcloud resolve the same from infra/ and infra/buoy/
    export REPO_ROOT=$(git rev-parse --show-toplevel)
    export CLOUDSDK_CONFIG=$REPO_ROOT/infra/.home/.config/gcloud
    export GOOGLE_APPLICATION_CREDENTIALS=$CLOUDSDK_CONFIG/application_default_credentials.json
    export CLOUDSDK_CORE_PROJECT="${values.gcpProjectId}"
    export TF_VAR_gcp_project_id="${values.gcpProjectId}"
    export TF_VAR_domain_name="${values.domain}"

    # decrypt infra with the host key, derived on demand via sudo (reaper);
    # the :- default preserves eve's op-based SOPS_AGE_KEY_CMD when already set
    export SOPS_AGE_KEY_CMD="''${SOPS_AGE_KEY_CMD:-sudo ${pkgs.ssh-to-age}/bin/ssh-to-age -private-key -i /etc/ssh/ssh_host_ed25519_key}"
  '';
}
