{
  lib,
  stdenv,
  fetchurl,
  nodejs,
  makeWrapper,
}:

stdenv.mkDerivation rec {
  pname = "ccusage";
  version = "16.1.1";

  src = fetchurl {
    url = "https://registry.npmjs.org/ccusage/-/ccusage-${version}.tgz";
    hash = "sha256-IyDjiXEtuqzlJ4k76gl47vTb7JB8lDAJux/45WsTa1M=";
  };

  nativeBuildInputs = [
    nodejs
    makeWrapper
  ];

  # npm tarballs are already built and ready to use
  dontBuild = true;
  dontConfigure = true;

  unpackPhase = ''
    runHook preUnpack

    # Extract the npm package tarball
    mkdir -p source
    cd source
    tar --strip-components=1 -xzf $src

    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall

    # Install the package files
    mkdir -p $out/lib/node_modules/ccusage
    cp -r ./* $out/lib/node_modules/ccusage/

    # Create the binary wrapper
    mkdir -p $out/bin
    makeWrapper ${nodejs}/bin/node $out/bin/ccusage \
      --add-flags "$out/lib/node_modules/ccusage/dist/index.js"

    runHook postInstall
  '';

  # tests
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    # Set up mock Claude configuration directory
    export CLAUDE_CONFIG_DIR="$TMPDIR/mock-claude"
    mkdir -p "$CLAUDE_CONFIG_DIR/projects"

    # Test that ccusage binary exists and is executable
    if [ ! -x "$out/bin/ccusage" ]; then
      echo "ERROR: ccusage binary not found or not executable"
      exit 1
    fi

    # Test version command
    version_output=$($out/bin/ccusage --version)
    if [ "$version_output" != "${version}" ]; then
      echo "ERROR: Expected version ${version}, got: $version_output"
      exit 1
    fi

    # Test help command produces expected output
    $out/bin/ccusage --help > help_output.txt 2>&1
    if ! grep -q "USAGE:" help_output.txt; then
      echo "ERROR: Help output doesn't contain 'USAGE:'"
      exit 1
    fi

    if ! grep -q "daily" help_output.txt; then
      echo "ERROR: Help output doesn't contain 'daily' command"
      exit 1
    fi

    # Test daily command help
    $out/bin/ccusage daily --help > daily_help.txt 2>&1
    if ! grep -q "OPTIONS:" daily_help.txt; then
      echo "ERROR: Daily help doesn't contain OPTIONS"
      exit 1
    fi

    echo "ccusage install check tests passed"

    runHook postInstallCheck
  '';

  meta = with lib; {
    description = "Usage analysis tool for Claude Code";
    longDescription = ''
      ccusage is a CLI tool for analyzing Claude Code token usage and costs 
      from local JSONL files. It provides detailed insights into AI conversation 
      metrics including daily, monthly, and session-based analysis.
    '';
    homepage = "https://github.com/ryoppippi/ccusage";
    license = licenses.mit;
    maintainers = [ ];
    mainProgram = "ccusage";
    platforms = platforms.all;
  };
}
