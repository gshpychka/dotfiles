{
  lib,
  stdenv,
  buildFHSEnv,
  esphome,
  sops,
  git,
  writeShellApplication,
}:
writeShellApplication {
  name = "flash-voice-pe";
  runtimeInputs = [
    # ESPHome downloads ESP-IDF's prebuilt toolchain, whose dynamically linked binaries need an FHS loader
    (
      if stdenv.hostPlatform.isLinux then
        buildFHSEnv {
          name = "esphome";
          runScript = lib.getExe esphome;
        }
      else
        esphome
    )
    sops
    git
  ];
  text = lib.removePrefix "#!/usr/bin/env bash\n" (builtins.readFile ./flash.sh);
  meta.description = "Build the Voice PE firmware and flash it to every Voice PE";
}
