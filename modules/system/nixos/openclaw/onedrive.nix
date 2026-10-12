# The host's OneDrive sync (my.onedrive) for the agent: membership in its
# group, so the agent's file tools work in the tree, and a skill describing it.
{ config, lib, ... }:
let
  cfg = config.my.openclaw;
  gw = config.services.openclaw-gateway;
  onedrive = config.my.onedrive;
in
{
  options.my.openclaw.onedrive.enable = lib.mkEnableOption ''
    the host's OneDrive sync for the agent: its file tools in the tree, and a
    skill describing it'';

  config = lib.mkIf (cfg.enable && cfg.onedrive.enable) {
    assertions = [
      {
        assertion = onedrive.enable;
        message = "my.openclaw.onedrive gives the agent the tree my.onedrive syncs; enable my.onedrive on this host.";
      }
    ];

    users.users.${gw.user}.extraGroups = [ onedrive.group ];

    my.openclaw.skills.onedrive = {
      description = "The owner's OneDrive, synced both ways at ${onedrive.syncDir}.";
      text = ''
        `${onedrive.syncDir}` is the owner's whole OneDrive, kept in sync both
        ways: what you create, change, move or delete there changes on
        OneDrive within seconds, and changes made elsewhere arrive within
        about 5 minutes. Use the normal file tools.

        A deletion there deletes on OneDrive too, where its recycle bin keeps
        it for 30 days; removing more than 1000 items at once stops the sync
        until the owner confirms.
      '';
    };
  };
}
