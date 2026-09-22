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

  # tf providers managed by nix
  terraform = pkgs.terraform.withPlugins (p: [
    p.cloudflare_cloudflare
    p.hashicorp_google
    p.clementblaise_age
    p.tailscale_tailscale
  ]);
  # sops exec-env takes one command string, which a shell re-parses, so each
  # argument is requoted with printf %q
  sopsExecEnv =
    name: package:
    pkgs.writeShellScriptBin name ''
      ${lib.getExe pkgs.sops} exec-env "$REPO_ROOT/secrets/infra/terraform.env" \
        "${lib.getExe package} $(printf '%q ' "$@")"
    '';
in
pkgs.mkShell {
  buildInputs = [
    terraform
    pkgs.google-cloud-sdk
    pkgs.sops
    pkgs.age
    pkgs.terragrunt
    (sopsExecEnv "tf" terraform)
    (sopsExecEnv "tg" pkgs.terragrunt)
  ];
  shellHook = ''
    export REPO_ROOT=$(git rev-parse --show-toplevel)
    export CLOUDSDK_CONFIG=$REPO_ROOT/infra/.home/.config/gcloud
    export GOOGLE_APPLICATION_CREDENTIALS=$CLOUDSDK_CONFIG/application_default_credentials.json
    export CLOUDSDK_CORE_PROJECT="${values.gcpProjectId}"
    export TF_VAR_gcp_project_id="${values.gcpProjectId}"
    export TF_VAR_domain_name="${values.domain}"
    export TF_STATE_BUCKET="${values.gcpTfStateBucket}"
  '';
}
