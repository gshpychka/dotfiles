{ config, lib, osConfig, ... }:
let
  cfg = config.my.git;
in
{
  options.my.git = {
    enable = lib.mkEnableOption "Git version control";
  };

  config = lib.mkIf cfg.enable {
    programs = {
      lazygit = {
        enable = true;
      };
      delta = {
        enable = true;
        enableGitIntegration = true;
      };
      git = {
        enable = true;
        signing = {
          format = "ssh";
          key = osConfig.my.sshKeys.main;
          signByDefault = true;
        };

        settings = {
          user = {
            email = "23005347+gshpychka@users.noreply.github.com";
            name = "Glib Shpychka";
          };
          alias = {
            cm = "commit";
            ca = "commit --amend --no-edit";
            di = "diff";
            dh = "diff HEAD";
            pu = "pull";
            ps = "push";
            pf = "push -f";
            st = "status -sb";
            co = "checkout";
            fe = "fetch";
            gr = "grep -in";
            re = "rebase -i";
          };
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
              user.signingkey = osConfig.my.sshKeys.gitlab;
              user.email = "20539359-gshpychka@users.noreply.gitlab.com";
              init.defaultBranch = "master";
            };
          }
        ];
      };
    };
  };
}