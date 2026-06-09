{
  pkgs,
  config,
  ...
}:
{
  imports = [
    ./hardware.nix
    ./boot.nix
    ./nix.nix
    ./networking.nix
    ./filesystems.nix
    ./users.nix
    ./frontend.nix
    ./monitoring.nix
    ./downloaders.nix
    ./media.nix
    ./smb.nix
    ./arr-stack
    ./io-scheduling.nix
    ./docker.nix
    ./home.nix
  ];

  nixpkgs.hostPlatform = "x86_64-linux";
  system.stateVersion = "24.11";

  services.openssh.enable = true;

  environment.systemPackages = with pkgs; [
    cryptsetup
  ];

  sops = {
    defaultSopsFile = ../../secrets/hoard/secrets.yaml;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  };

  my.acme.enable = true;

  my.terminfo.enable = true;

  programs = {
    gnupg.agent = {
      enable = true;
      enableSSHSupport = true;
    };
    zsh = {
      enable = true;
      enableCompletion = false;
      enableBashCompletion = false;
      enableLsColors = false;
    };
  };

  networking.firewall.allowedTCPPorts = [
    config.services.nginx.defaultHTTPListenPort
    config.services.nginx.defaultSSLListenPort
  ];
}
