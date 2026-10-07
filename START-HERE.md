# Thor Forever: start here

**Experimental v0.1.0-alpha.1 — tested on one AYN Thor.** Download
`Thor-Forever-v0.1.0-alpha.1.zip` from the GitHub release, not **Code > Download
ZIP**. The source companion is a separate developer download, not required for
playing. The installer ZIP includes `Thor-Forever.exe`, `payload` and notices.

## Before you start

- Supported test device: AYN Thor with Adreno 740.
- Supported app: GameHub Lite Ludashi (`com.ludashi.aibench`). Other variants
  are not automatically supported.
- Install and update Forever Beta through Battle.net first. You need your own
  eligible account and the ARM64 client. No game files are supplied here.
- Keep at least 3 GiB free internally **after** extracting the package.
- Close WoW and Battle.net. Record your current GameHub startup-file path so
  you can switch back later. Keep your existing installation.

## Install once

1. Extract the complete package so that `Thor-Forever.exe` and the `payload`
   and `installer` folders are directly inside **Download/Thor-Forever**. Do
   not leave them inside a second nested folder.
   Download/Thor-Forever is only the suggested place: any folder in the
   device's shared storage works (for example **Games/Thor-Forever**), as long
   as its path has no spaces and only letters, digits, `-`, `_` and `.`. The
   start screen uses the folder it is in. To move it later, close Thor
   Forever and **copy** (not move) the whole folder to the new place. Select
   the copied Thor-Forever.exe as the Startup File Path, check that it
   starts, and only then delete the old folder by hand. GameHub Lite hides
   a game's settings while its Startup File Path points to a missing file,
   so moving first leaves no way to change the path (moving the folder back
   brings the settings back). Nothing needs to be installed again.
2. In GameHub, open the container where you installed the game: **Game
   Settings > General > Startup File Path**, select
   **Download/Thor-Forever/Thor-Forever.exe**, and press **Play**.
3. The start screen says Thor Forever is not installed yet and lists anything
   that is missing (the game in this container, or install files). When
   everything is there, press **Install**. It shows each step while it runs;
   leave it open for the few minutes it takes.
4. When it says **Installed**, the same button says **Play**.

If installing stops halfway, or the installation is damaged later, the
button says **Repair**. Repair renames the old installation to
`release-v1.old-<n>` (nothing is deleted), installs again and copies your
game settings (the WTF folder) over.

To redo a working installation (for example to test Install), create a file
named `repair` or `repair.txt` in Download/Thor-Forever; the start screen then
offers Repair, and removes the file once Repair succeeds.

`Install-Thor-Forever.cmd` (run from the container desktop, result in
`setup-report/result.txt`) still works the same way as before.

The installer prepares a separate environment and game settings. It links the
existing large game Data rather than downloading a second copy. The shared Data
is not read-only. Never point Battle.net or an updater at this separate layout.

## Play and save your settings

1. From the container desktop, open **Thor-Forever.exe**. Its start screen
   shows your installed game version and has these buttons:
   - **Play** starts the game.
   - **Update with Battle.net** opens Battle.net. Press Update there if it
     offers one, close Battle.net when it's done, then press **Play**. The
     launcher copies the updated game files over by itself.
   - **FPS cap**, **Overlay** and **Measuring** change those settings in
     `tuning.conf`. Each tap moves to the next value.
   - **Quit** closes the start screen without playing.
   - If the game is installed in more than one GameHub container (this can
     happen after reinstalling the game or the container), a note at the
     bottom says so. You always play from the copy in the container you
     started from. To free the other copy's storage, delete that container
     in GameHub. Thor Forever does not delete it itself: from inside
     GameHub, such a delete removed other files instead.
2. Log in yourself, choose your controls and play briefly.
3. Exit through **WoW's menu > Exit Game**, then reopen the launcher and check
   that your controls/settings remain selected.
4. Do not open another copy while the first is running.

Each launch writes its logs into **Thor-Forever > logs > run-<number>**
(the highest number is the newest). Only the last 3 runs are kept. Older
`INSTALLED-WOW-<number>` folders from earlier versions can be deleted.

## Open directly from GameHub

With WoW closed, go to the same container's **Game Settings > General > Startup
File Path**. Select **Download/Thor-Forever/Thor-Forever.exe**. Return to GameHub
and press **Play**. Do not choose Battle.net or the bare game executable.

Keep the Thor-Forever folder in place: its scripts are required for direct entry.
To switch back, select the old startup path you recorded. See
[recovery guidance](docs/RECOVERY.md); there is no automatic cleanup yet.

## Limits

Only one standard game installation can be selected automatically. If none or
several are found, the installer stops rather than guessing. Custom-folder
selection is not implemented. Game updates may require a new matching copy of
the executable-side files; the launcher stops when the main executable differs.
Do not solve this by deleting saved settings or rerunning the installer.

The final-folder candidate passed installation, gameplay, direct launch, reboot
and gamepad-settings persistence on one device. The distributed Wine tar removes
only unused prefix-import metadata; all retained members were verified unchanged.
This is experimental, not a promise
of future game compatibility or a guaranteed frame rate.
