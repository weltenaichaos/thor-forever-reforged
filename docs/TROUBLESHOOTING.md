# Troubleshooting

| Symptom | First check |
| --- | --- |
| Settings/account name forgotten | Use the bare custom configuration filename after `-config`; exit through the game menu. Never reset that file on each launch. |
| WoW closes at once (`WOW_EXIT=1`, wine.log says `taskset: failed to set ... affinity: Invalid argument`), or the start screen says the fastest CPU core is not available | Android has taken the prime core cpu7 away from GameHub (seen once with a full battery and a cool device). The launch log's `CPUS online=... allowed=...` line shows which cores were usable. Thor Forever then starts WoW on the next big core, which may be slower. Restarting the Thor brings cpu7 back. |
| Battle.net opens instead of the dedicated launcher | Verify Startup File Path and close the previous container session before testing. |
| Immediately returns to GameHub | Inspect the bridge completion code and latest launch log. Check that the Windows wrapper remains alive and native child streams are redirected. |
| Bridge returns 141 | The observed setup needed stdout/stderr redirected to a file and stdin to `/dev/null` before launching children. |
| Photosensitivity-stage crash | Verify the exact runtime/driver/shim combination. That visual symptom alone does not prove a shader scheduler fault. |
| No realms | Verify credentials, region/eligibility and client build against the working PC installation; do not assume a Vulkan fault. |
| In-game options cause instability | Return to the tested low-load profile. Preserve the failing log privately before experimenting. |
| Addons not found (`GetNumAddOns()` is 0) | Easiest: put each addon folder in `Thor-Forever/AddOns/` on the Thor; the launcher copies them in at every start, into whichever `Interface\AddOns` the game loads (`ADDON COPIED:` in the launch log). Or install addons in the original game's `_classic_beta_\Interface\AddOns` in the GameHub container. The launcher links that folder into the staged game; the launch log's `ADDONS:` line says whether it did. A real `Interface` folder inside the staged game is left alone and used instead. Fully restart the game after adding an addon. |
| Launcher reports another session | Do not start concurrent clients. Use the launcher's owner-checked lock recovery; never kill all Wine processes globally. |

Do not post raw logs, registry exports or WTF/Account files. They may expose account names, character names, tokens, paths and device identifiers. Share only a reviewed, redacted excerpt relevant to the failure.

Rollback should restore the recorded Startup File Path and leave the original GameHub/Battle.net components untouched. Retain private backups locally; removing the custom launcher is not a reason to delete the game or its settings.
