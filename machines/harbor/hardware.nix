{
  lib,
  modulesPath,
  ...
}:
{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  powerManagement.cpuFreqGovernor = lib.mkDefault "ondemand";

  # argononed fails to start
  # services.hardware.argonone.enable = true;
}

