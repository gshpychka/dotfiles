{
  config,
  lib,
  pkgs,
  ...
}:
{
  # home-manager configuration defaults
  home.preferXdgDirectories = lib.mkDefault true;
  programs.home-manager.enable = lib.mkDefault true;

  xdg.enable = true;

  home.sessionVariables = {
    BOTO_CONFIG = "${config.xdg.configHome}/gcloud/boto";
    DOCKER_CONFIG = "${config.xdg.configHome}/docker";
    GOPATH = "${config.xdg.dataHome}/go";
    HISTFILE = "${config.xdg.stateHome}/bash/history";
    LESSHISTFILE = "${config.xdg.stateHome}/lesshst";
    NODE_REPL_HISTORY = "${config.xdg.stateHome}/node_repl_history";
    PSQL_HISTORY = "${config.xdg.stateHome}/psql_history";
    TERMINFO = "${config.xdg.dataHome}/terminfo";
    TERMINFO_DIRS = "${config.xdg.dataHome}/terminfo:/usr/share/terminfo";
  }
  // lib.optionalAttrs pkgs.stdenv.isDarwin {
    XDG_RUNTIME_DIR = "/tmp";
  };
}
