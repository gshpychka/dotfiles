{ config, pkgs, lib, ... }: {
  #file = {
  #  gitSigningKey = {
  #    source = fetchurl https://github.com/gshpychka.keys;
  #    target = ".ssh/id_ed25519.pub";
  #  };
  #};
  programs.git = {
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
    ignores = [
      ".idea" ".vs" ".vsc" ".vscode" # ide
      ".DS_Store" # mac
      "node_modules" "npm-debug.log" # npm
      "__pycache__" "*.pyc" # python
      ".ipynb_checkpoints" # jupyter
      "__sapper__" # svelte
    ];
    extraConfig = {
      #commit.gpgsign = true;
      #gpg.format = "ssh";
      #gpg.ssh.program = "/Applications/1Password.app/Contents/MacOS/op-ssh-sign";
      #user.signingkey = "~/.ssh/id_ed25519.pub";
      init = { defaultBranch = "main"; };
      pull = {
        ff = false;
        commit = false;
        rebase = true;
      };
      push.autoSetupRemote = true;
      #url = {
        #"ssh://git@github.com" = { insteadOf = "https://github.com"; };
      #};
      delta = {
        line-numbers = true;
      };
    };
  };
}
