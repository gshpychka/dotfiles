# Public immutable archives. Kept independent of the generated project cache.
{ pkgs }:
let
  idfArchive = pkgs.fetchurl {
    url = "https://github.com/esphome-libs/esp-idf/releases/download/v5.5.5/esp-idf-v5.5.5.tar.xz";
    hash = "sha256-2Glt8hcxRndaxOXADPY+6Gx+BMIxUw20DzSkNiy+dpo=";
  };
in
{
  toolchain = pkgs.fetchzip {
    url = "https://github.com/espressif/crosstool-NG/releases/download/esp-14.2.0_20260121/xtensa-esp-elf-14.2.0_20260121-x86_64-linux-gnu.tar.xz";
    hash = "sha256-1Eyo43+ueDtb/mSDPDP6RvSSH0Zk4SfnkxWPJ2aWDgw=";
    stripRoot = false;
  };
  rom = pkgs.fetchzip {
    url = "https://github.com/espressif/esp-rom-elfs/releases/download/20241011/esp-rom-elfs-20241011.tar.gz";
    hash = "sha256-OCbYkTblDpKgpFCxOlYxWuc0qonI9dSn/t5SWZ7KYHI=";
    stripRoot = false;
  };
  idf =
    pkgs.runCommand "voice-pe-idf-5.5.5"
      {
        nativeBuildInputs = [
          pkgs.gnutar
          pkgs.xz
        ];
        requiredSystemFeatures = [ "big-parallel" ];
      }
      ''
        mkdir -p $out
        tar -xf ${idfArchive} --strip-components=1 -C $out
      '';
}
