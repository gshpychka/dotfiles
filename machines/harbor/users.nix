{
  pkgs,
  config,
  ...
}:
{
  users = {
    users = {
      ${config.my.user} = {
        shell = pkgs.zsh;
        isNormalUser = true;
        extraGroups = [ "wheel" ];
        packages = with pkgs; [
          neovim
        ];
        openssh.authorizedKeys.keys = [
          config.my.sshKeys.main
        ];
        initialHashedPassword = "";
      };
    };
  };
}