# Switching back safely

This is a non-destructive recovery guide, not an uninstaller.

1. Exit WoW through its in-game menu. Do not start two copies together.
2. In GameHub, open the same game's **Game Settings > General > Startup File Path**.
3. Select the previous launcher path that you recorded before changing it.
4. Return to GameHub and launch normally.

Changing the startup path selects a launcher; it does not remove either runtime
or game installation. If you did not record the old path, stop and identify it
before changing files. Do not guess by selecting the Battle.net installer or
the game executable directly: the working profile requires its launcher.

## If a preparation attempt fails

Keep the attempt and its reports. Do not rerun installation over that directory
or delete it just to make an installer proceed. Failed attempts are deliberately
preserved, and the installer refuses existing destinations. Reports can contain
local paths; do not post raw logs without reviewing them for private information.

## Cleanup is a separate step

There is no tested automatic uninstaller yet. Do not remove the shared Data
directory, original game folder, original prefix or any folder currently
referenced by a launcher. Do not run a recursive cleanup that follows links.
Saved preferences and account-related settings in the new prefix/game directory
must be preserved if you want to keep using that installation.

The selected launcher's scripts remain dependencies even after direct GameHub
launch works. Keep your Thor-Forever folder in place. Older test folders may still
be needed by older startup entries; this release does not remove any of them.
