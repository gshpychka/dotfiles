_:
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
  # Ice menu bar manager.
  homebrew.casks = [ "jordanbaird-ice@beta" ];

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

  launchd.user.agents.ice.serviceConfig = {
    ProgramArguments = [
      "/usr/bin/open"
      "-a"
      "/Applications/Ice.app"
    ];
    RunAtLoad = true;
  };
}
