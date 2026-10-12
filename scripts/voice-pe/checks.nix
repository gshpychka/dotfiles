{ pkgs, source }:
pkgs.runCommand "voice-pe-unit-tests"
  {
    nativeBuildInputs = [
      pkgs.python3
      pkgs.gcc
    ];
    requiredSystemFeatures = pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux [ "big-parallel" ];
  }
  ''
    mkdir -p source/scripts/voice-pe/components source/scripts/voice-pe/tests source/packages/voice-broker/src/voice_broker
    cp -r --no-preserve=mode,ownership ${source}/scripts/voice-pe/components/voice_broker source/scripts/voice-pe/components/
    cp ${source}/scripts/voice-pe/voice-pe.yaml source/scripts/voice-pe/
    cp ${source}/scripts/voice-pe/tests/test_startup.py ${source}/scripts/voice-pe/tests/test_provision.py ${source}/scripts/voice-pe/tests/test_inputs.py source/scripts/voice-pe/tests/
    cp ${source}/scripts/voice-pe/public-inputs.lock.json ${source}/scripts/voice-pe/assets.lock.json ${source}/scripts/voice-pe/python-inputs.lock.json source/scripts/voice-pe/
    cp ${source}/scripts/voice-pe/firmware.nix ${source}/scripts/voice-pe/project.nix ${source}/scripts/voice-pe/python-inputs.nix ${source}/scripts/voice-pe/reconstruct.py source/scripts/voice-pe/
    cp ${source}/packages/voice-broker/src/voice_broker/conversation.py source/packages/voice-broker/src/voice_broker/
    cd source
    python3 scripts/voice-pe/tests/test_startup.py
    python3 scripts/voice-pe/tests/test_provision.py
    python3 scripts/voice-pe/tests/test_inputs.py
    touch $out
  ''
