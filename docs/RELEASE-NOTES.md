# v0.1.0-alpha.1 — experimental community preview

For AYN Thor / Adreno 740 with GameHub Lite Ludashi (`com.ludashi.aibench`).
Tested game: World of Warcraft: Forever Beta ARM64, build 1.60.1.70009.
This is one-device evidence, not a compatibility guarantee.

## Downloads

- **Thor-Forever-v0.1.0-alpha.1.zip**: the complete player installation kit.
- **Thor-Forever-v0.1.0-alpha.1-Sources.zip**: source snapshots, patches, recipes
  and notices for developers; not needed on the handheld.
- **SHA256SUMS.txt**: checksums of both ZIP files.

Extract the player kit to **Download/Thor-Forever** and follow START-HERE.md.
No terminal typing or personal path editing is required for a single supported
standard-layout installation. Use your own updated, authorized game installation
and eligible account. Neither game files nor personal account data are included.

## Included

- A separate Wine 11 runtime and fresh prefix, without replacing global
  GameHub/Battle.net components.
- Native ARM64 DXVK, patched Turnip and a launch-scoped GL workaround.
- Direct GameHub entry through a persistent Windows launcher.
- A low-load starting profile, with settings preserved between sessions.
- Pinned payload checks, non-overwrite safeguards and local diagnostic reports.

Installation, gameplay, direct entry, full restart and gamepad-setting
persistence passed on the owner's Thor. The distributed Wine tar only omits
two unused upstream prefix-import files; all 2,589 retained members were checked
for equality with the tested runtime. No new game runtime binaries were built
for packaging.

## Important limitations

- Other hardware, GameHub variants and future game builds are unverified.
- Game Data is shared with the original installation; it is not read-only.
  Never update the separate staged layout through Battle.net.
- Game updates make the staged executable stale. When the original
  executable changes, the launcher copies the new executable files and build
  info into the staged game before starting it ("GAME UPDATED" in the log).
- The installer refuses existing/unfinished destinations. It is not a repair
  command, and there is no automatic uninstaller.
- If the shell bridge is interrupted after startup, the wrapper may remain
  open. Exit/restart the container rather than repeatedly starting more copies.
- Remembered account names worked in the older setup but were not separately
  reconfirmed in the final isolated package. Gamepad persistence was confirmed.
- The source companion is supplied; a full independent, bit-identical rebuild
  has not been demonstrated.

Keep logs local unless reviewed/redacted. See docs/RECOVERY.md to switch back
without deleting either installation. Existing successful Thor Forever test
users do not need to reinstall simply to use this packaging release.

Credits: Wine, Mesa/Freedreno/Turnip, DXVK, the Android runtime and GameHub Lite
contributors, and u/BryTheGuy06 for the original community guide/comment.
Investigation and implementation used ChatGPT/Codex with hands-on owner testing.
No affiliation with or endorsement by Blizzard, AYN or those upstream projects.
