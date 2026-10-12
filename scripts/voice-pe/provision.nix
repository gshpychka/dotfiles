{ python3, writeShellApplication }:
let
  python = python3.withPackages (p: [ p.aioesphomeapi ]);
in
writeShellApplication {
  name = "provision-voice-pe";
  text = ''exec ${python}/bin/python3 ${./provision.py} "$@"'';
  meta.description = "Provision Voice PE broker credential over authenticated Noise API";
}
