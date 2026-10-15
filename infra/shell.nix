{
  nixpkgs,
  system,
  rolesanywhere,
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
    p.hashicorp_aws
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
    pkgs.awscli2
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
    # AWS profiles live under infra/.home, apart from any other AWS profiles
    # on the machine; sign in once with `aws configure sso` against the
    # personal account infra/aws manages. Only the profile files move: the
    # CLI and Terraform's AWS SDK keep the SSO token and credential caches in
    # ~/.aws/{sso,cli}/cache, so give the SSO session a name no other config
    # uses. (Moving HOME instead would also move sops' keys.) What keeps
    # Terraform off any other account is infra/aws's allowed_account_ids.
    export AWS_CONFIG_FILE=$REPO_ROOT/infra/.home/.aws/config
    export AWS_SHARED_CREDENTIALS_FILE=$REPO_ROOT/infra/.home/.aws/credentials
    export TF_VAR_user="${values.user}"
    # the rolesanywhere revision flake.lock pins, whose Terraform infra/aws
    # fetches with git: a copy from the read-only store leaves terragrunt
    # unable to write its manifest into it
    export ROLESANYWHERE_REV="${rolesanywhere.rev}"
  '';
}
