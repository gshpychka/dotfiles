# Plain attrset, deliberately NOT a module: the single source of truth for
# identity values that are also needed OUTSIDE the module system
# (infra/shell.nix, infra/nixos/configuration.nix, infra/backend.tf).
# Inside machine configs always use the typed `my.*` options from globals.nix,
# which reads its defaults from here.
{
  domain = "glib.sh";
  user = "gshpychka";
  gcpProjectId = "status-glibsh";
  sshKeys.main = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB737o9Ltm1K3w9XX9SBHNW1JT4NpCPP5qg9R+SB18dG";
}
