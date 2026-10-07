# Thor Forever Reforged

This is a fork of [AeroNico/thor-forever](https://github.com/AeroNico/thor-forever),
continued by [weltenaichaos](https://github.com/weltenaichaos). All credit for the
original investigation, installer and runtime packaging goes to AeroNico; see
"Credits and provenance" below. Changes made in this fork are listed in its
pull requests. Test builds from this fork reuse the upstream payload binaries
unchanged; each published build ships with the upstream source companion and
the `notices/` folder.

## How to install

You need an AYN Thor, the app **GameHub Lite** (`com.ludashi.aibench`) and
your own Battle.net account with access to World of Warcraft: Forever (beta).
No game files are included here: the game comes from Battle.net, as usual.

**Part 1: the game, in GameHub**

1. Install GameHub Lite and open it.
2. Create a new container (a "PC game") for Battle.net and install
   **Battle.net** into it with its normal Windows setup program.
3. Start Battle.net in that container, log in, and install
   **World of Warcraft: Forever** (the beta). Choose the **ARM64** client
   if Battle.net asks.
4. Close the game and Battle.net when the download is done. Keep at least
   3 GB free on the device.

**Part 2: Thor Forever Reforged**

5. Download **Thor-Forever-Reforged-&lt;version&gt;.zip** from the newest
   [release](https://github.com/weltenaichaos/thor-forever-reforged/releases).
   Do not use **Code > Download ZIP**: that is only the source code.
6. Extract the zip into your **Download** folder, so that you get
   **Download/Thor-Forever** with `Thor-Forever.exe` directly inside.
7. In GameHub, open the same container's **Game Settings > General >
   Startup File Path**, select **Download/Thor-Forever/Thor-Forever.exe**
   and press **Play**. Write down the old Startup File Path first, so you
   can switch back.
8. The start screen says Thor Forever is not installed yet. Press
   **Install** and leave it open while it shows its steps (a few minutes).
9. When it says **Installed**, the button changes to **Play**. Press it,
   log in yourself and play.

From then on, pressing **Play** in GameHub opens this start screen. Game
updates go through its **Update with Battle.net** button. If something
breaks, the button offers **Repair**. More details:
[START-HERE.md](START-HERE.md) and [troubleshooting](docs/TROUBLESHOOTING.md).

---

The original README follows.

---

# Thor Forever

**Status: experimental preview — tested on one AYN Thor.**

Download **Thor-Forever-v0.1.0-alpha.1.zip** from the
[release page](https://github.com/AeroNico/thor-forever/releases/tag/v0.1.0-alpha.1),
then follow [START-HERE.md](START-HERE.md). Do not use **Code > Download ZIP**:
that contains source code, not the installer payload.

Installation into a separate environment, gameplay, saved gamepad settings,
direct GameHub launch and restart passed manual testing on the owner's device.
This is an early community preview, not a compatibility guarantee.
See [validation results and known limits](docs/VALIDATION.md).

This project documents a working World of Warcraft: Forever Beta ARM64 setup on one AYN Thor, using GameHub Lite Ludashi, a separate patched Wine runtime, ARM64 DXVK and a locally patched Mesa Turnip driver. It is not affiliated with Blizzard, AYN, GameHub, Wine or Mesa.

The owner reports playable in-world gameplay, direct launch from GameHub, and persistent account-name/gamepad preferences after the final configuration-path correction. This is a single-device report, not a compatibility guarantee or a benchmark. Remembering an account name does not mean storing a password or bypassing authentication.

## Tested combination

| Component | Tested configuration |
| --- | --- |
| Hardware | AYN Thor, Adreno 740 |
| Android app | GameHub Lite Ludashi (`com.ludashi.aibench`) |
| Game | Forever Beta, ARM64 client, build 1.60.1.70009 |
| Runtime | Separate Android Wine 11 build with the fixes described below |
| Direct3D translation | DXVK 2.4.1, native Windows ARM64 DLLs |
| Vulkan | Turnip from Mesa revision `fe067b17d908d8f02e88ef3c4433ec5fbb66b2a9`, with a local scheduler patch |
| Starting profile | 1280×720, low graphics, VSync off, 30 FPS cap |

Versions describe the successful test, not current release recommendations. Later game updates may change compatibility. Obtain the game through authorized distribution and use your own eligible account.

## What made it work

1. Keep the original GameHub/Battle.net container intact. Prepare a separate Wine prefix and runtime; do not replace global components.
2. Use matching ARM64 runtime components, including the Windows-visible `ntdll.dll`, plus the required Android shared-memory support and ARM64 DXVK. A Wine version check alone does not establish that the game can run.
3. Correct an NLS path-allocation bug in the Wine Android patch set.
4. Patch Turnip's kill/demote scheduling check so that it does not wait for varying fetches belonging to another basic block. The captured failing shader compiled after this change.
5. Avoid an independent crash in GameHub's OpenGL/GLX initialization by using an isolated no-OpenGL shim for this launch. WoW uses D3D11 through DXVK/Vulkan. **Do not install this shim globally.**
6. Use the low-load profile. The owner reported much better playability and input responsiveness; we did not establish a single root cause for the earlier input stalls.
7. Use a persistent Windows launcher plus a shell completion marker for direct GameHub launch. Redirect the shell's standard streams before starting child processes.
8. Pass `-config Config-Jugabilidad-01.wtf`, **not** `-config 'WTF\Config-Jugabilidad-01.wtf'`. With the former, the owner confirmed settings and remembered account persisted after a normal exit and restart.

## Read before installing anything

Do not copy historical troubleshooting scripts to another device. The release
installer discovers a single standard game location and creates a fresh prefix.
Keep the existing installation and record its startup path before switching.
No automatic uninstall or game-update migration is provided in this preview.

See [the setup and validation plan](docs/SETUP.md), [technical findings](docs/TECHNICAL-NOTES.md), [troubleshooting](docs/TROUBLESHOOTING.md), and [release checklist](docs/RELEASE-CHECKLIST.md).

The [release](https://github.com/AeroNico/thor-forever/releases/tag/v0.1.0-alpha.1)
also provides a source companion and SHA-256 checksums. Players need only the
installer ZIP. The installer does not download missing payloads automatically.
Developers: see [source distribution](docs/SOURCE-DISTRIBUTION.md).

For safe switching back to the original entry, see [recovery guidance](docs/RECOVERY.md).

The Git repository contains source, documentation and notices. Release assets
contain the separately packaged runtime and source companion. Neither includes
game files, accounts, a personal prefix, captured game shaders or private logs.

## Credits and provenance

- Wine and the Android Proton/Wine work: [upstream fork used](https://github.com/The412Banner/proton-wine), [owner's build fork](https://github.com/AeroNico/proton-wine).
- Mesa/Freedreno/Turnip developers: source revision listed above.
- DXVK developers: ARM64 DXVK 2.4.1 used in the working setup.
- GameHub Lite maintainers, and [u/BryTheGuy06](https://www.reddit.com/user/BryTheGuy06/) for the original community guide/comment that motivated the investigation. This credit is not an endorsement of this project.
- Local investigation and implementation were carried out with assistance from ChatGPT/Codex, with the owner testing on the device.

Original Thor Forever code and documentation are licensed under [MIT](LICENSE).
Third-party work retains its own licenses; see [licensing scope](LICENSING.md).
The MIT license does not by itself authorize redistribution of third-party binaries.
