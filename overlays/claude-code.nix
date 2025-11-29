# Apply customizations on top of nix-ai-tools' claude-code
# This overlay must be applied BEFORE the nix-ai-tools overlay
inputs: final: prev: {
  claude-code =
    (inputs.nix-ai-tools.packages.${prev.system}.claude-code).overrideAttrs
      (oldAttrs: {
        # https://docs.anthropic.com/en/docs/claude-code/settings#environment-variables
        # claude-code breaks if DEV happens to be set
        # https://github.com/anthropics/claude-code/issues/2059
        postInstall = ''
          wrapProgram $out/bin/claude \
            --set DISABLE_TELEMETRY 1 \
            --set DISABLE_ERROR_REPORTING 1 \
            --set DISABLE_AUTOUPDATER 1 \
            --unset DEV
        '';
      });
}
