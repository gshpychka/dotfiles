{ lib, ... }:
{
  # Headless machines have no console to answer the emergency-mode root prompt,
  # so a failed mount or fsck would otherwise hang boot indefinitely. Boot on
  # regardless, keeping the machine reachable over the network.
  systemd.enableEmergencyMode = lib.mkDefault false;
}
