{ ... }:
let
  iceDomain = "com.jordanbaird.Ice";
in
{
  # Ice menu bar manager, used to keep the MDM-managed Rippling and SentinelOne
  # icons out of sight. Their agents keep running; only the status items are hidden.
  #
  # The beta build is used because macOS 26 support landed after the 0.11.12 stable release.
  #
  # Imperative steps (Ice stores item placement in its own state, not in a settable default):
  # 1. Grant Ice Accessibility and Screen Recording permissions on first launch.
  # 2. Ice > Settings > Menu Bar Layout: drag Rippling and SentinelOne into "Always-Hidden".
  homebrew.casks = [ "jordanbaird-ice@beta" ];

  system.defaults.CustomUserPreferences.${iceDomain} = {
    EnableAlwaysHiddenSection = true;
  };

  # Started by launchd rather than Ice's own "Launch at login" toggle so that it is declarative
  launchd.user.agents.ice.serviceConfig = {
    ProgramArguments = [
      "/usr/bin/open"
      "-a"
      "/Applications/Ice.app"
    ];
    RunAtLoad = true;
  };
}
