rec {
  domain = "glib.sh";
  user = "gshpychka";
  gcpProjectId = "status-glibsh";
  gcpTfStateBucket = "${gcpProjectId}-tf-state";
  sshKeys.main = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB737o9Ltm1K3w9XX9SBHNW1JT4NpCPP5qg9R+SB18dG";
  # Google account email authorized for opkssh SSH login (see
  # modules/system/nixos/opkssh.nix). Set to your Gmail/Workspace address to
  # grant access; null leaves opkssh wired up but authorizing no one.
  googleEmail = null;
}
