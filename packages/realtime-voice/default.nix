{
  lib,
  python3Packages,
  pkg-config,
  webrtc-audio-processing,
  fetchurl,
  fetchPypi,
}:
let
  # The Live API client (gpt-live-1) starts at openai 3.x.
  openai = python3Packages.buildPythonPackage rec {
    pname = "openai";
    version = "3.16.2";
    format = "wheel";
    src = fetchPypi {
      inherit pname version format;
      dist = "py3";
      python = "py3";
      hash = "sha256-Zgp/gwfmYFNCroT/RCVBLnzRnl6bKY+XVQLfKhqaXV8=";
    };
    dependencies = with python3Packages; [
      anyio
      httpx2
      jiter
      pydantic
      sniffio
      typing-extensions
    ];
    # openai calls only jiter.from_json, which nixpkgs' jiter provides.
    pythonRelaxDeps = [ "jiter" ];
    pythonImportsCheck = [
      "openai"
      "openai.resources.live"
    ];
  };

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

  dependencies = [
    openai
  ]
  ++ (with python3Packages; [
    mcp
    numpy
    onnxruntime
    soxr
    websockets
  ]);

  nativeCheckInputs = [ python3Packages.pytestCheckHook ];
  # Tests run the real VAD model.
  env.REALTIME_VOICE_VAD_MODEL = vadModel;

  passthru = { inherit vadModel; };

  meta.mainProgram = "realtime-voice";
}
