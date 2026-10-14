{
  pkgs,
  ...
}:
{
  vimPlugins = pkgs.vimPlugins // {
    ts-error-translator-nvim = pkgs.callPackage ./ts-error-translator-nvim.nix { };
  };
  piPackages = pkgs.callPackage ./pi-packages { };
  voice-broker = pkgs.callPackage ./voice-broker { };
  oidc-issuer = pkgs.callPackage ./oidc-issuer { };
  datameter = pkgs.callPackage ./datameter.nix { };
}
