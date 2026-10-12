{ pkgs }:
let
  lock = builtins.fromJSON (builtins.readFile ./python-inputs.lock.json);
  fetch =
    item:
    pkgs.fetchurl {
      inherit (item) url sha256;
      name = item.filename;
    };
in
pkgs.stdenvNoCC.mkDerivation {
  pname = "voice-pe-idf-python";
  version = "5.5.5";
  dontUnpack = true;
  dontBuild = true;
  nativeBuildInputs = [
    pkgs.python3
    pkgs.autoPatchelfHook
    pkgs.gnutar
    pkgs.gzip
  ];
  buildInputs = [
    pkgs.stdenv.cc.cc.lib
    pkgs.libffi
    pkgs.openssl
  ];
  requiredSystemFeatures = [ "big-parallel" ];
  installPhase = ''
    mkdir -p $out
    ${pkgs.lib.concatMapStringsSep "\n" (
      item:
      if item.wheel then
        ''
          python3 -m zipfile -e ${fetch item} $out
        ''
      else
        ''
          mkdir source-${item.name}
          tar -xf ${fetch item} --strip-components=1 -C source-${item.name}
          cp -r source-${item.name}/${item.name} $out/
        ''
    ) lock}
    # Bytecode paths and timestamps are deliberately not part of the module input.
    find $out -name __pycache__ -type d -exec rm -rf {} +
  '';
  doInstallCheck = true;
  installCheckPhase = ''
    PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=$out python3 -c "import esptool, kconfiglib, esp_idf_size, yaml, cryptography"
  '';
}
