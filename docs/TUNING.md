# Tuning results

Device tests on the AYN Thor (Adreno 740) in GameHub Lite, 1280x720, low
settings, FPS_CAP=60. FPS is what the DXVK overlay
showed in the starter area, in crowds and in the main hub, so treat it as a
rough range, not a benchmark. Where the frame time goes, and how to
measure it, is in [PERFORMANCE.md](PERFORMANCE.md).

## Recommended profile

This is what the shipped `tuning.conf` sets:

```
LOGS=off
GPL=off
ESYNC=on
DRIVER=test        # Turnip from Mesa 26.2.3 in driver-test/
SHADER_CACHE=on
DXVK=test          # DXVK 2.6.2, Thor-tuned build, in dxvk-test/
DXVK_TILER=off
AFFINITY=one-then-all  # one core for the first ~30 s, then all cores
WINE=test          # ntdll with the esync fix in wine-test/
```

With esync, WoW's start sometimes stopped on a blank window: during its
startup CPU checks the main thread resumed at address 0 and Wine's
exception handling then overflowed its stack (seen with `LOGS=trace`).
Starting on one core avoided it (3 of 3 starts, against 1 of 3 on all
cores); the launcher then frees all cores.

With esync, quitting WoW also crashed now and then (WoW's own
`SmallMemAllocator` check), so GameHub never came back. Wine's esync made a
handle's cache entry visible before its file descriptor was stored, and
closed descriptors while other threads still used them.
`patches/wine-esync-deferred-close.patch` fixes both; the "Build Wine"
workflow builds it as `wine-ntdll-esync-fix`. Put its `ntdll.so` and
`ntdll.dll` in `Download/Thor-Forever/wine-test/`. With it, 3 of 3 quits
returned to GameHub.

Put the files in place first:

- `Download/Thor-Forever/driver-test/libvulkan_freedreno.so` from the
  `turnip-mesa-26.2.3-cache` artifact of the "Build Turnip" workflow
  (tested build: sha256 `775295d2...`).
- `Download/Thor-Forever/dxvk-test/dxgi.dll` and `d3d11.dll` from the
  `dxvk-2.6.2-thor-arm64` artifact of the "Build DXVK" workflow (tested
  builds: d3d11.dll sha256 `9cc173ce...`, and `a5036f0f...` with the
  frame log for `PROFILE=on`). It is DXVK 2.6.2 compiled for the
  Thor's CPU (ARMv8.2 atomics, Cortex-X3 tuning, thin LTO). In a busy city
  WoW's main thread dropped from 82% to 77% of the fast core while the GPU
  got busier, about 5% less CPU time per frame. The plain `dxvk-2.6.2-arm64`
  works too.

If they are missing, the launcher falls back to the installed driver and
DXVK and keeps esync off. `ESYNC=on` also needs the Android setting below.

Outside the launcher, put the Thor itself in its maximum performance mode,
with the fan up. In the standard mode the GPU stayed locked at 401 MHz
instead of up to 680 MHz, and city FPS dropped to about 21.

## Android settings

Android's "phantom process killer" can kill Wine's child processes. With
esync that shows up as `esync_set_event write: Bad file descriptor` in
wine.log and a crash at the login screen.

The same error, followed by WoW crash reports such as
`BC_ASSERT(result == WAIT_OBJECT_0)` or `SmallMemAllocator ... head !=
tailNext`, also appeared with the installed driver even with this setting,
usually within a few minutes. With the Mesa 26.2.3 driver it did not, so
the launcher only uses esync with `DRIVER=test`. Later the same crash,
after about 6 minutes with missing minimap and menu textures, turned out to
be an fd leak in Wine's esync. It is fixed in the `wine-ntdll-esync-fix`
build (see [PERFORMANCE.md](PERFORMANCE.md)). WoW's crash reports are
copied to `Download/Thor-Forever/wow-errors` at the next launch.

- Android 14 or newer: Developer options, "Disable child process restrictions".
- Android 12 or 13, with adb:
  ```
  adb shell device_config set_sync_disabled_for_tests persistent
  adb shell device_config put activity_manager max_phantom_processes 2147483647
  adb shell settings put global settings_enable_monitor_phantom_procs false
  ```
- Settings, Apps, GameHub Lite, Battery: Unrestricted.

## What was tested

| Setup | Result |
| --- | --- |
| DXVK 2.4.1 (kit default) | 40-60 FPS, stuttery |
| DXVK 2.5.3 | ~35-50 FPS, a bit rough |
| DXVK 2.6.2, tiler auto | 30-45 FPS, smooth |
| DXVK 2.6.2, `DXVK_TILER=off` | 35-50 FPS, smooth |
| + `ESYNC=on` | a little better |
| + `GPL=on` | crashes after login |
| DXVK 2.7.1 | does not start: surface queries fail with `VK_ERROR_EXTENSION_NOT_PRESENT`, winevulkan asserts in `vkCreateGraphicsPipelines` |
| Turnip from Mesa 26.2.3 with shader cache | ~30 FPS, small stutters; slower than the installed driver (standard performance mode, esync off) |
| Installed driver + `ESYNC=on`, max performance mode | ~45 FPS, but WoW crashes within minutes |
| Mesa 26.2.3 driver + `ESYNC=on` + DXVK 2.6.2, tiler off, max performance mode | 40-45 FPS open world, 35-40 in cities; 45+ min without a crash; GPU ~90% busy at 680 MHz |
