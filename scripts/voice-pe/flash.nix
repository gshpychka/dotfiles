{
  esphome,
  python3,
  coreutils,
  writeShellApplication,
  lib,
  writeShellScriptBin,
}:
let
  python = python3.withPackages (p: [
    p.zeroconf
    p.pyserial
    # esphome.helpers resolves a host name through it
    p.aioesphomeapi
  ]);
  modules = "${esphome}/${python.sitePackages}";
  uploader = writeShellScriptBin "voice-pe-upload" ''
    export PYTHONPATH="${modules}"
    exec ${python}/bin/python3 ${./upload.py} "$@"
  '';
in
writeShellApplication {
  name = "flash-voice-pe";
  runtimeInputs = [
    uploader
    coreutils
  ];
  text = lib.removePrefix "#!/usr/bin/env bash\n" (builtins.readFile ./flash.sh);
  meta.description = "Explicitly upload an existing Voice PE OTA image; never compile or decrypt secrets";
}
