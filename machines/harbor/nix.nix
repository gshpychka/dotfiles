{
  ...
}:
{
  nix.settings = {
    auto-optimise-store = true;
  };
  nix.gc = {
    dates = "weekly";
    automatic = true;
    options = "--delete-older-than 7d";
  };
}