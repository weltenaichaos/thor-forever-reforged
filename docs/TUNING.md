# Tuning results

Device tests on the AYN Thor (Adreno 740) in GameHub Lite, 1280x720, low
settings, FPS_CAP=60, installed Turnip driver. FPS is what the DXVK overlay
showed in the starter area, in crowds and in the main hub, so treat it as a
rough range, not a benchmark.

## Recommended profile

```
LOGS=off
GPL=off
ESYNC=on
DRIVER=installed
SHADER_CACHE=on
DXVK=test          # DXVK 2.6.2 in dxvk-test/
DXVK_TILER=off
```

`ESYNC=on` also needs the Android setting below.

## Android settings

Android's "phantom process killer" can kill Wine's child processes. With
esync that shows up as `esync_set_event write: Bad file descriptor` in
wine.log and a crash at the login screen.

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
| Turnip from Mesa 26.2.3 with shader cache | ~30 FPS, small stutters; slower than the installed driver |
