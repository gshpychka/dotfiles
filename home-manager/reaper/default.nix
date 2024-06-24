{
  config,
  pkgs,
  lib,
  inputs,
  system,
  ...
}: {
  imports = [
    ../common
    ../common/tmux
    ../common/neovim
  ];

  programs = {
    git = {
      enable = true;
      userEmail = "23005347+gshpychka@users.noreply.github.com";
      userName = "Glib Shpychka";
      extraConfig = {
        init.defaultBranch = "main";
        pull = {
          ff = false;
          commit = false;
          rebase = true;
        };
        push.autoSetupRemote = true;
        delta.line-numbers = true;
        rerere.enabled = true;
      };
      includes = [
        {
          condition = "hasconfig:remote.*.url:git@gitlab.com:*/**";
          contents = {
            user.email = "20539359-gshpychka@users.noreply.gitlab.com";
            init.defaultBranch = "master";
          };
        }
      ];
    };
  };
}
