{
  pkgs,
  config,
  lib,
  ...
}:
{
  imports = [
    ./hardware.nix
    ./boot.nix
    ./nix.nix
    ./filesystems.nix
    ./users.nix
    ./frontend.nix
    ./monitoring.nix
    ./downloaders.nix
    ./media.nix
    ./smb.nix
    ./arr-stack
    ./io-scheduling.nix
    ./home.nix
  ];

  networking = {
    hostName = "hoard";
    usePredictableInterfaceNames = true;
    enableIPv6 = false;
    interfaces = {
      enp1s0 = {
        wakeOnLan.enable = true;
      };
    };
    useDHCP = lib.mkDefault true;
    firewall = {
      logRefusedConnections = false;
    };
  };

  nixpkgs.hostPlatform = "x86_64-linux";
  system.stateVersion = "24.11";

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

  environment.systemPackages = with pkgs; [
    cryptsetup
  ];

  sops = {
    defaultSopsFile = ../../secrets/hoard/secrets.yaml;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  };

  my.acme = {
    enable = true;
    domain = config.my.domain;
    extraDomainNames = [ "*.${config.networking.fqdn}" ];
  };

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
