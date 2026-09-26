# Kodi runbook

CoreELEC box, reached as `ssh kodi`. Skin is Bingie (`skin.bingie`).
`/storage/.config` survives CoreELEC updates; `/storage/.config/system.d` holds
user systemd units.

## Bingie customizations

Kodi overwrites the skin directory on every Bingie update, so
`kodi-bingie-customize.sh` reapplies these at boot and after each update:

- hides the profile switcher at the top of the side menu
- installs every file in `skin-overrides/` into the skin, currently a
  Netflix-style PlexKodiConnect skip intro/credits button

From the repo root:

```sh
ssh kodi 'mkdir -p /storage/.config/kodi-bingie && rm -f /storage/.config/kodi-bingie/*'
for f in scripts/kodi/skin-overrides/*; do
  ssh kodi "cat > /storage/.config/kodi-bingie/$(basename "$f")" < "$f"
done
ssh kodi 'cat > /storage/.config/kodi-bingie-customize.sh' < scripts/kodi/kodi-bingie-customize.sh
for f in kodi-bingie-customize.service kodi-bingie-customize.path; do
  ssh kodi "cat > /storage/.config/system.d/$f" < "scripts/kodi/$f"
done
ssh kodi 'systemctl daemon-reload
  systemctl enable kodi-bingie-customize.service
  systemctl enable --now kodi-bingie-customize.path
  systemctl start kodi-bingie-customize.service'
```

Removing a file from `skin-overrides/` does not remove the installed copy from the
skin; delete it from `skin.bingie/1080i` as well.

If a Bingie release moves the profile switcher, the script logs
`anchor not found` and leaves that file untouched:
`ssh kodi journalctl -t kodi-bingie-customize`.

To undo: disable both units, delete them, the script and
`/storage/.config/kodi-bingie`, then reinstall Bingie from its repository to
restore the original files.
