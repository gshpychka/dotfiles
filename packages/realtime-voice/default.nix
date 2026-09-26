{
  lib,
  python3Packages,
  pkg-config,
  webrtc-audio-processing,
  fetchurl,
}:
let
  # Only the ONNX graph is needed; the silero-vad Python package would pull
  # torch into the closure.
  vadModel = fetchurl {
    url = "https://raw.githubusercontent.com/snakers4/silero-vad/v6.2.1/src/silero_vad/data/silero_vad.onnx";
    hash = "sha256-GhU6IvRQnikqlOZ9b5uF6N6yW0mIaCt+F0xlJ52HiOM=";
  };
in
python3Packages.buildPythonApplication {
  pname = "realtime-voice";
  version = "0.1.0";
  pyproject = true;

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./pyproject.toml
      ./setup.py
      ./src
      ./tests
    ];
  };

  build-system = with python3Packages; [
    setuptools
    pybind11
  ];
  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ webrtc-audio-processing ];

  dependencies = with python3Packages; [
    mcp
    numpy
    onnxruntime
    openai
    soxr
    websockets
  ];

  nativeCheckInputs = [ python3Packages.pytestCheckHook ];
  # Tests run the real VAD model.
  env.REALTIME_VOICE_VAD_MODEL = vadModel;

  passthru = { inherit vadModel; };

  meta.mainProgram = "realtime-voice";
}
