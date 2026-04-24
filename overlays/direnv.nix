# direnv tests are broken upstream - disable the check phase
# https://github.com/NixOS/nixpkgs/issues/513019
final: prev: {
  direnv = prev.direnv.overrideAttrs (old: {
    doCheck = false;
  });
}
