{ config, pkgs, lib, ... }: {
  home.file = {
    ".ssh/config" = {
      target = ".ssh/config";
      text = ''
      Host *
	IdentityAgent "~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
      '';
    };
  };
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
      commit.gpgsign = true;
      gpg.format = "ssh";
      gpg.ssh.program = "/Applications/1Password.app/Contents/MacOS/op-ssh-sign";
      user.signingkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB737o9Ltm1K3w9XX9SBHNW1JT4NpCPP5qg9R+SB18dG";
      init = { defaultBranch = "main"; };
      #pull = {
        #ff = false;
        #commit = false;
        #rebase = true;
      #};
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
