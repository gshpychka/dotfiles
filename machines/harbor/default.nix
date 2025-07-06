{
  config,
  ...
}:
{
  imports = [
    ./hardware.nix
    ./boot.nix
    ./nix.nix
    ./filesystems.nix
    ./networking.nix
    ./users.nix
    ./nginx.nix
    ./home.nix
  ];

  networking.hostName = "harbor";
  nixpkgs.hostPlatform = "aarch64-linux";
  system.stateVersion = "22.11";

  my.user = "pi";

  nixpkgs.config.permittedInsecurePackages = [ "openssl-1.1.1w" ];

  programs.zsh = {
    enable = true;
    enableCompletion = false;
    enableGlobalCompInit = false;
    enableLsColors = false;
  };

  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

  my.acme = {
    enable = true;
    domain = config.my.domain;
    extraDomainNames = [ "*.${config.networking.fqdn}" ];
  };

  my.tailscale = {
    enable = true;
    ssh = true;
    magicDns = false;
    exitNode = true;
    advertiseRoutes = [ "192.168.1.0/24" ];
  };

  security = {
    sudo.enable = true;
    pam = {
      sshAgentAuth.enable = true;
      services.sudo.sshAgentAuth = true;
    };
  };
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };
}
