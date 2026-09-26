# Kodi follow-up

Open items for the customizations in this folder. Delete each one when done.

## Blocked on hoard's media drive

Plex on hoard is down: the external enclosure (label `hoard`) is not detected
on USB, so `/mnt/hoard` never mounts and `plex.service` fails its dependency.
The arr-sync and ACME renewal units hang on the same mount.

- [ ] Power-cycle the enclosure and reseat its USB cable; check it shows up
      with `ssh hoard lsblk -o NAME,LABEL` and that `plex` is active.
      Do not start Plex without the drive: a scan would mark the library as
      missing, and automatic trash emptying would delete it.

## Once Plex is up

- [ ] Check Kodi reaches Plex:
      `ssh kodi grep -c "Server unreachable" /storage/.kodi/temp/kodi.log`
      stops growing. PKC points at the public `plex.direct` address; if it
      keeps failing, point it at `192-168-1-3.<server hash>.plex.direct:32400`,
      which hoard forwards into Plex's `wan2` namespace.
- [ ] Restart Kodi so PKC loads the HDR patch: `ssh kodi systemctl restart kodi`.
- [ ] Run PKC's repair sync so every item gets the DV profile and HDR10+:
      `ssh kodi 'kodi-send --action="RunPlugin(plugin://plugin.video.plexkodiconnect/?mode=repair)"'`
- [ ] Verify the HDR types in Kodi's library match Plex (about 607 P8.1,
      236 P7, 79 P5, 215 streams with HDR10+):
      `ssh kodi "sqlite3 /storage/.kodi/userdata/Database/MyVideos131.db 'select strHdrType, count(*) from streamdetails where iStreamType=0 group by 1'"`.
      No `hdr10plus` values means Plex's API names the field differently from
      its database (`HDR10PlusPresent`); fix `snippets/pkc-hdr.py`.
- [ ] Open a DV movie's info page and check the badge, e.g. "DV P8.1".

## Needs someone at the TV

- [ ] Subtitle position: play a 2.39:1 film with two-line subtitles. Text
      clipped at the bottom → raise Settings > Player > Subtitles > Vertical
      margin; second line over the picture → lower the font size. Carry the
      result into `SUBTITLES_*` in `kodi-customize.sh`, then
      `scripts/kodi/deploy.sh` and reboot the box.
- [ ] Skip intro button: check its look and position over real playback.
- [ ] Reboot the box once and check `ssh kodi journalctl -t kodi-customize -b`
      shows a clean run before Kodi starts.

## Cleanup

- [ ] Delete the pre-customization backups on the box once everything looks
      right: `ssh kodi rm /storage/media.py /storage/IncludesVariables.xml
      /storage/IncludesMediaFlags.xml /storage/guisettings.xml.bak-subs`.
