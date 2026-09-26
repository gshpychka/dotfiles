# Kodi runbook

CoreELEC box, reached as `ssh kodi`. Skin is Bingie (`skin.bingie`), library
comes from Plex on hoard through PlexKodiConnect (PKC). `/storage/.config`
survives CoreELEC updates; `/storage/.config/system.d` holds user systemd
units.

## Customizations

Kodi overwrites an addon's directory on every update, so `kodi-customize.sh`
reapplies these at boot and after each Bingie or PKC update:

- subtitles at a fixed spot in the bottom letterbox bar, the same in every
  display mode (applied at boot only, while Kodi is stopped)
- hides the Bingie profile switcher at the top of the side menu
- installs every file in `skin-overrides/` into the skin, currently a
  Netflix-style PKC skip intro/credits button
- shows the Dolby Vision profile and HDR10+ from Plex in Bingie's HDR badge,
  e.g. "DV P8.1 · HDR10+" (`snippets/`)

Deploy from eve:

```sh
scripts/kodi/deploy.sh
```

Settings changes land at the next boot (`ssh kodi reboot`). After a PKC patch
change, restart Kodi so PKC loads it (`ssh kodi systemctl restart kodi`).
Library items get new HDR details when PKC next syncs them; to rewrite all of
them, run PKC's repair sync:
`ssh kodi 'kodi-send --action="RunPlugin(plugin://plugin.video.plexkodiconnect/?mode=repair)"'`.

Removing a file from `skin-overrides/` does not remove the installed copy from
the skin; delete it from `skin.bingie/1080i` as well.

If an addon release moves something a patch anchors on, the script logs
`anchor not found` and leaves that file untouched:
`ssh kodi journalctl -t kodi-customize`.

To undo: disable both units, delete them and `/storage/.config/kodi-customize`,
then reinstall Bingie and PKC from their repositories to restore the original
files. The settings stay until changed in Kodi.
