{...}: {
  programs = {
    lazygit = {
      enable = true;
    };
    git = {
      enable = true;
      delta.enable = true;
      userEmail = "23005347+gshpychka@users.noreply.github.com";
      userName = "Glib Shpychka";
      aliases = {
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
      signing = {
        format = "ssh";
        key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB737o9Ltm1K3w9XX9SBHNW1JT4NpCPP5qg9R+SB18dG";
        signByDefault = true;
      };

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
            user.signingkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILo71XBp2p5c7UPaizrAL70I3QkspxLg5zyKsKjAnswr";
            user.email = "20539359-gshpychka@users.noreply.gitlab.com";
            init.defaultBranch = "master";
          };
        }
      ];
    };
  };
}
