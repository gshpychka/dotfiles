{ ... }:
let
  iceDomain = "com.jordanbaird.Ice";
  # raw values of Ice's RehideStrategy enum (Ice/Utilities/RehideStrategy.swift)
  rehideStrategy = {
    smart = 0;
    timed = 1;
    focusedApp = 2;
  };
in
{
  # Ice menu bar manager, used to keep the MDM-managed Rippling and SentinelOne
  # icons out of sight. Their agents keep running; only the status items are hidden.
  # Item placement per section is not a settable default: macOS stores it as pixel offsets
  # in each owning app's own preferences.
  homebrew.casks = [ "jordanbaird-ice@beta" ];

  # Keys and value types are from Ice's General/AdvancedSettingsManager.swift.
  # Ice reads these at launch, so changes apply after Ice restarts.
  # Hotkeys and appearance are stored as JSON-encoded data blobs and are left to the UI.
  system.defaults.CustomUserPreferences.${iceDomain} = {
    # -- general --
    # control-click on empty menu bar space opens Ice's menu
    ShowIceIcon = false;
    UseIceBar = false;
    # click on empty menu bar space toggles the hidden section
    ShowOnClick = true;
    ShowOnHover = false;
    ShowOnScroll = false;
    ItemSpacingOffset = 0.0;
    AutoRehide = true;
    RehideStrategy = rehideStrategy.smart;
    # seconds, only used by rehideStrategy.timed
    RehideInterval = 15.0;

    # -- advanced --
    # the frontmost app's menus are hidden while hidden items are shown, to make room
    HideApplicationMenus = true;
    ShowSectionDividers = false;
    EnableAlwaysHiddenSection = true;
    # option-click on empty menu bar space toggles the always-hidden section
    CanToggleAlwaysHiddenSection = true;
    ShowOnHoverDelay = 0.2;
    TempShowInterval = 15.0;
    ShowAllSectionsOnUserDrag = true;
    ShowContextMenuOnRightClick = true;
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
