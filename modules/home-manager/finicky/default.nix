{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.finicky;
  filePath = "finicky/config.js";
  # the config is plain JS that finicky parses at runtime, where a syntax error
  # takes out all URL routing; this fails the build instead
  validatedConfig =
    pkgs.runCommand "finicky-config.js" { nativeBuildInputs = [ pkgs.nodejs-slim ]; }
      ''
        # node picks ES module parsing from the .mjs extension
        cp ${./config.js} config.mjs
        node --check config.mjs
        cp config.mjs $out
      '';
in
{
  options.my.finicky = {
    enable = lib.mkEnableOption "Finicky browser chooser";
  };

  config = lib.mkIf cfg.enable {
    xdg.configFile.${filePath} = {
      source = validatedConfig;
      # finicky does not support symlinks
      onChange = "cat ${config.xdg.configHome}/${filePath} > ${config.home.homeDirectory}/.finicky.js";
    };

    # Set finicky as the default browser; this pops a one-time macOS dialog, so
    # only act when it isn't already default ("* " marks it in defaultbrowser).
    home.activation.finickyDefaultBrowser = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if ! ${pkgs.defaultbrowser}/bin/defaultbrowser | ${pkgs.gnugrep}/bin/grep -qx '\* finicky'; then
          $DRY_RUN_CMD ${pkgs.defaultbrowser}/bin/defaultbrowser finicky || true
        fi
      ''
    );
  };
}
