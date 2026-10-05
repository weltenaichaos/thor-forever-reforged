# Performance on the AYN Thor

Where WoW's frame time goes on the AYN Thor (Snapdragon 8 Gen 2, Adreno 740)
in GameHub Lite, what was fixed, and how to measure it again. Status as of
2026-10-04, during the beta. Settings and test history are in
[TUNING.md](TUNING.md).

## Summary

- **Busy city: about 20-25 FPS. Open world: 40-45 FPS** (1280x720, low
  settings, Thor in maximum performance mode). Your in-game settings change
  this. View distance and ground clutter gave about 5 FPS in cities. Render
  scale made no difference, because the GPU is not the limit there.
- **The limit in cities is WoW's own main thread.** It runs on the fastest
  core (cpu7, 3187 MHz) and is busy 85-93% of the time. Our layers take
  only a small share of that thread's time:

  | Part | Share of the main thread's frame time | How it was measured |
  | --- | --- | --- |
  | DXVK (D3D11 calls) | about 5% (2.2-2.3 ms of 43-51 ms, ~31-35k calls) | timer inside our DXVK (`api_ms` in frames.csv) |
  | wineserver round trips | under 1% (10-30 ms per 5 s) | counter in our Wine (`server-stats` in wine.log) |
  | Linux kernel (system calls) | about 15% | user/kernel split in perf.csv |
  | WoW's own code | the rest, about 80% | |

  So faster builds of DXVK, Wine or Turnip can only win a few percent in
  cities. Bigger gains have to come from Blizzard's own optimizations.
- **The GPU is not the city bottleneck.** It ran 30-60% busy at 615-680 MHz
  there. In the open world it gets close to its limit (about 90% busy).

## What was fixed or improved

| Change | Effect | Where |
| --- | --- | --- |
| Esync fd leak: Wine dropped a duplicate eventfd whenever two threads looked up the same handle at once | About 95 fds leaked per second until the 32768 limit after about 6 minutes. Then textures (minimap, menus) went missing and WoW crashed. Since the fix, open fds stay flat at about 1,900 and no crash has happened in 10+ minute runs. Stutters during play dropped from about 20 to about 7 per minute. | PR #12, `patches/wine-esync-deferred-close.patch` |
| Esync never caches fd -1 and logs open fds by kind | If the fd table ever fills again, signals aren't lost, and wine.log says what filled it | PR #12 |
| Esync quit crash (cache entry visible before its fd was stored) | Quitting returns to GameHub | PR #9 |
| `AFFINITY=one-then-all` | Avoids blank starts with esync, a WoW startup race on many cores | PR #9 |
| Thor-tuned DXVK 2.6.2 (ARMv8.2, Cortex-X3 tuning, thin LTO) | About 5% less main-thread CPU per frame | PR #11 |
| Turnip from Mesa 26.2.3, esync on, DXVK tiler off | Stable esync, smoother frames | PR #8 |

Tested and not kept: `AFFINITY=one-then-split` (the main thread alone on
cpu7 made no difference, because it waited for a free core only 1.7% of
the time), `TURNIP_MODE=gmem|sysmem`, `DXVK_TILER=on`, `GPL=on` (crashes),
DXVK 2.7.1 (does not start), and lower render scale.

## Recommended setup

Use `tuning.conf` as shipped (see [TUNING.md](TUNING.md)), with
`PROFILE=off` for normal play. Put these files in `Download/Thor-Forever/`:

| Folder | Files | From | Last tested sha256 |
| --- | --- | --- | --- |
| `driver-test/` | `libvulkan_freedreno.so` | "Build Turnip", artifact `turnip-mesa-26.2.3-cache` | `775295d2...` |
| `dxvk-test/` | `dxgi.dll`, `d3d11.dll` | "Build DXVK", artifact `dxvk-2.6.2-thor-arm64` | d3d11 `a5036f0f...`, dxgi `3a9ec524...` |
| `wine-test/` | `ntdll.so`, `ntdll.dll` | "Build Wine", artifact `wine-ntdll-esync-fix` | ntdll.so `4e20b515...` |

The DXVK and Wine builds contain the measuring code, which stays off
unless `PROFILE=on`. Any newer build of these workflows from `main` works
the same, but its sha256 will differ.

Also: put the Thor in maximum performance mode with the fan up. In standard
mode the GPU stays at 401 MHz, and cities drop to about 21 FPS. Follow
the Android settings in [TUNING.md](TUNING.md).

## How to measure

Set `PROFILE=on` in `tuning.conf`, play, quit normally, then collect from
`Download/Thor-Forever/INSTALLED-WOW-<n>/`:

| File | What it holds | Summarize with |
| --- | --- | --- |
| `perf.csv` | every 2 s: CPU per thread (user/kernel) and its core, core clocks, GPU load and clock, WoW's disk reads, WoW's open fds (by kind every 30 s above 1000), WoW's memory use and the device's free memory | `python tools/analyze-perf.py perf.csv [start end]` |
| `frames.csv` | every frame: frame time, draws, new pipelines, DXVK CS/GPU waits, shader and resource creation time, time inside DXVK (`api_ms`) | `python tools/analyze-frames.py frames.csv [start end]` |
| `state.csv` | WoW's main thread every 50 ms: running, sleeping or on disk, what it waits in, and run-queue wait | `python tools/analyze-states.py state.csv [start end]` |
| `wine.log` | esync errors, and `server-stats` lines every 5 s (wineserver round trips) | read directly |
| `result.txt` | settings and sha256 of driver, DXVK and Wine actually used | read directly |

The optional `start end` (seconds) limits a summary to part of the run,
for example the minutes spent in a city. Android does not let apps use
`simpleperf` (`perf_event_paranoid=3`), so the measurements come from
`/proc` and from timers in our own DXVK and Wine. Nothing reads or changes
the game's memory.

How to read the results:
- `analyze-frames`: "none from DXVK" stutters are WoW's own work, Wine or
  storage. "new pipelines" stutters are shader compiles. Those get rarer
  as the shader cache fills.
- `analyze-states`: a main thread that is mostly `R` (running) is
  CPU-bound. Long `S` stalls show what it waited for.
- `analyze-perf`: a WoW open-fd count that climbs steadily means a leak.
  It should level off at about 1,900.

## To check after the game's release

1. Play a few minutes in the same busy city with `PROFILE=on` and compare
   the numbers above: FPS, the main thread's share, DXVK `api_ms`, stutters
   per minute, and open fds.
2. If the main thread's share drops (Blizzard optimized it), the GPU may
   become the limit. Then retest `TURNIP_MODE`, `DXVK_TILER` and render
   scale.
3. If a new DXVK release works with the ARM64 Wine (2.7.1 did not), build
   it with the Thor tuning and compare `api_ms`.
4. Check wine.log for new esync errors and the fd count for leaks.
