# The CA, certificate issuer and client behind my.rolesAnywhere
# (modules/system/nixos/rolesanywhere.nix).
{
  lib,
  python3Packages,
}:
python3Packages.buildPythonApplication {
  pname = "rolesanywhere";
  version = "0.1.0";
  pyproject = true;

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./pyproject.toml
      ./src
      ./tests
    ];
  };

  build-system = [ python3Packages.setuptools ];

  dependencies = [ python3Packages.cryptography ];

  nativeCheckInputs = [ python3Packages.pytestCheckHook ];

  meta.mainProgram = "rolesanywhere";
}
