{
  # Installs the Command Line Tools and selects them as the active developer
  # directory.
  system.activationScripts.preActivation.text = ''
    developerDir=/Library/Developer/CommandLineTools
    # The in-progress file makes softwareupdate list and install the
    # Command Line Tools labels, which it hides otherwise.
    installOnDemand=/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress

    if [ ! -d "$developerDir" ]; then
      touch "$installOnDemand"
      label=$(/usr/sbin/softwareupdate --list \
        | sed -n 's/^\* Label: \(Command Line Tools for Xcode[ -].*\)$/\1/p' \
        | sort -V | tail -1)

      if [ -z "$label" ]; then
        rm -f "$installOnDemand"
        echo >&2 "error: softwareupdate offers no Command Line Tools"
        exit 1
      fi

      echo >&2 "installing $label..."
      /usr/sbin/softwareupdate --install "$label"
      rm -f "$installOnDemand"

      if [ ! -d "$developerDir" ]; then
        echo >&2 "error: $label did not install $developerDir"
        exit 1
      fi
    fi

    if [ "$(/usr/bin/xcode-select --print-path)" != "$developerDir" ]; then
      echo >&2 "selecting $developerDir..."
      /usr/bin/xcode-select --switch "$developerDir"
    fi
  '';
}
