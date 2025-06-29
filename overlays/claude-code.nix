final: prev: {
  claude-code = prev.claude-code.overrideAttrs (oldAttrs: {
    # https://docs.anthropic.com/en/docs/claude-code/settings#environment-variables
    postInstall = ''
      wrapProgram $out/bin/claude \
        --set DISABLE_TELEMETRY 1 \
        --set DISABLE_ERROR_REPORTING 1 \
        --set DISABLE_AUTOUPDATER 1
    '';
  });
}

