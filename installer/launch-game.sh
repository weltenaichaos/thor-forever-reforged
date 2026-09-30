#!/system/bin/sh
# Thor Forever launcher. No Battle.net/update invocation.
KIT=/sdcard/Download/Thor-Forever
USR=/data/user/0/com.ludashi.aibench/files/usr
case "${WINEPREFIX-}" in
    /data/user/*/com.ludashi.aibench/files/usr/*) USR=${WINEPREFIX%%/files/usr/*}/files/usr ;;
esac
case "$USR" in *'/../'*|*'/./'*|*/..|*/.) exit 3 ;; esac
ROOT="$USR/home/thor-forever/release-v1"
RUNTIME="$ROOT/runtime"
GL_DIR="$ROOT/graphics"
DRIVER="$ROOT/driver"
PREFIX="$ROOT/prefix"
STAGE="$ROOT/game"
GAME="$STAGE/_classic_beta_"
n=1
while [ "$n" -le 10000 ]; do
    OUT="$KIT/INSTALLED-WOW-$n"
    if mkdir "$OUT" 2>/dev/null; then break; fi
    n=$((n + 1))
done
[ "$n" -le 10000 ] || exit 2
exec >"$OUT/result.txt" 2>&1 </dev/null
tf_stage=preflight
trap 'tf_status=$?; print -r -- "SCRIPT_EXIT=$tf_status STAGE=$tf_stage"' EXIT
[ -f "$KIT/installer/discover-game.sh" ] || exit 3
. "$KIT/installer/discover-game.sh"
tf_discover_game "$USR" || { print -r -- 'STOP: a unique standard game installation was not found.'; exit 4; }
SOURCE=$TF_GAME_DIR
[ -s "$ROOT/components-ready" ] && [ -s "$ROOT/game-ready" ] || exit 5
[ -s "$PREFIX/system.reg" ] && [ ! -L "$ROOT" ] && [ ! -L "$PREFIX" ] || exit 6
# Refuse a copied executable that has become stale after a Battle.net update.
cmp -s "$SOURCE/WowB-ARM64.exe" "$GAME/WowB-ARM64.exe" || exit 7
cmp -s "$RUNTIME/lib/wine/aarch64-windows/ntdll.dll" "$PREFIX/drive_c/windows/system32/ntdll.dll" || exit 8
[ -s "$GAME/WowB-ARM64.exe" ] || exit 9
[ -s "$GAME/WTF/Config-Thor-Forever.wtf" ] || exit 10
for dll in dxgi.dll d3d11.dll; do
    cmp -s "$KIT/payload/$dll" "$PREFIX/drive_c/windows/system32/$dll" || exit 11
done
fail() { print -r -- "STOP: $1"; exit 12; }
# GameHub's process wrapper drops inherited fd9, so external flock cannot use it.
# Atomic directory lock with shell PID/start-time/boot identity instead.
LOCK="$USR/home/wow-private-launch.lockdir"
IFS= read -r boot_id </proc/sys/kernel/random/boot_id || fail 'Cannot identify the current device boot.'
get_stamp()
{
    proc_stamp=
    case "$1" in ''|*[!0-9]*) return 1 ;; esac
    [ -r "/proc/$1/stat" ] || return 1
    IFS= read -r proc_stat <"/proc/$1/stat" || return 1
    proc_tail=${proc_stat##*) }
    set -f
    set -- $proc_tail
    set +f
    [ "$#" -ge 20 ] || return 1
    shift 19
    proc_stamp="$boot_id:$1"
}
get_stamp "$$" || fail 'Cannot identify this launcher process.'
self_stamp="$proc_stamp"
if ! mkdir "$LOCK" 2>/dev/null; then
    [ -f "$LOCK/owner" ] && [ ! -L "$LOCK" ] && [ ! -L "$LOCK/owner" ] || fail 'Launch lock needs inspection; its owner could not be verified.'
    read -r owner_pid owner_stamp <"$LOCK/owner" || fail 'Cannot read the launch lock.'
    if get_stamp "$owner_pid" && [ "$proc_stamp" = "$owner_stamp" ]; then
        fail 'Another WoW launch is already active.'
    fi
    # Remove only our stale owner marker and then its empty lock directory.
    rm "$LOCK/owner" && rmdir "$LOCK" || fail 'Cannot release the old launch lock.'
    mkdir "$LOCK" || fail 'Another launch acquired the lock.'
fi
print -r -- "$$ $self_stamp" >"$LOCK/owner" || exit 4
cleanup_lock()
{
    read -r owner_pid owner_stamp <"$LOCK/owner" || return
    if [ "$owner_pid" = "$$" ] && [ "$owner_stamp" = "$self_stamp" ]; then
        rm "$LOCK/owner"
        rmdir "$LOCK"
    fi
}
trap cleanup_lock EXIT
trap 'exit 130' INT TERM HUP

# Performance settings from $KIT/tuning.conf. Only known keys with
# validated values are accepted; the file is never executed.
tf_fps=60 tf_hud=fps,frametimes,compiler tf_logs=off tf_gpl=off tf_esync=off
tf_driver=installed tf_cache=on
if [ -f "$KIT/tuning.conf" ] && [ ! -L "$KIT/tuning.conf" ]; then
    while IFS= read -r tf_line || [ -n "$tf_line" ]; do
        tf_line=${tf_line%%#*}
        tf_line=$(print -r -- "$tf_line" | tr -d ' \t\r')
        case "$tf_line" in *=*) ;; *) continue ;; esac
        tf_key=${tf_line%%=*} tf_value=${tf_line#*=}
        case "$tf_key" in
            FPS_CAP) case "$tf_value" in ''|*[!0-9]*) ;; *) [ "${#tf_value}" -le 3 ] && tf_fps=$tf_value ;; esac ;;
            HUD) case "$tf_value" in ''|*[!a-z0-9,=.]*) ;; *) tf_hud=$tf_value ;; esac ;;
            LOGS) case "$tf_value" in on|off) tf_logs=$tf_value ;; esac ;;
            GPL) case "$tf_value" in on|off) tf_gpl=$tf_value ;; esac ;;
            ESYNC) case "$tf_value" in on|off) tf_esync=$tf_value ;; esac ;;
            DRIVER) case "$tf_value" in installed|test) tf_driver=$tf_value ;; esac ;;
            SHADER_CACHE) case "$tf_value" in on|off) tf_cache=$tf_value ;; esac ;;
        esac
    done <"$KIT/tuning.conf"
fi
print -r -- "TUNING FPS_CAP=$tf_fps HUD=$tf_hud LOGS=$tf_logs GPL=$tf_gpl ESYNC=$tf_esync DRIVER=$tf_driver SHADER_CACHE=$tf_cache"
tf_esync_value=0
[ "$tf_esync" = on ] && tf_esync_value=1
export WINEPREFIX="$PREFIX" WINEARCH=win64 WINEESYNC=$tf_esync_value
export WINELOADER="$RUNTIME/bin/wine" WINESERVER="$RUNTIME/bin/wineserver"
export PATH="$RUNTIME/bin:$PATH"
export LD_LIBRARY_PATH="$GL_DIR:$RUNTIME/lib:$RUNTIME/lib/wine/aarch64-unix${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
# The assertion tracer is a driver-debugging aid, not needed for play.
# Opt in by creating $KIT/enable-trace before launching.
if [ -f "$KIT/enable-trace" ]; then
    export LD_PRELOAD="$GL_DIR/trace.so${LD_PRELOAD:+:$LD_PRELOAD}"
fi
export WINEDATADIR="$RUNTIME/share/wine" XDG_DATA_DIRS="$RUNTIME/share" WINEDLLPATH="$RUNTIME/lib/wine"
export WINEDLLOVERRIDES='dxgi,d3d11=n,b'
# DRIVER=test uses Download/Thor-Forever/driver-test/libvulkan_freedreno.so.
# Shared storage cannot hold executable code, so it is copied into the
# app-private install first; the installed driver is never touched.
if [ "$tf_driver" = test ]; then
    tf_test_src="$KIT/driver-test/libvulkan_freedreno.so"
    [ -s "$tf_test_src" ] && [ ! -L "$tf_test_src" ] || fail 'DRIVER=test, but driver-test/libvulkan_freedreno.so is missing.'
    tf_test_dir="$ROOT/driver-test"
    [ ! -L "$tf_test_dir" ] || fail 'The test driver directory is a link.'
    mkdir -p "$tf_test_dir" || fail 'Cannot create the test driver directory.'
    if ! cmp -s "$tf_test_src" "$tf_test_dir/libvulkan_freedreno.so"; then
        cp "$tf_test_src" "$tf_test_dir/libvulkan_freedreno.so.tmp" &&
            mv "$tf_test_dir/libvulkan_freedreno.so.tmp" "$tf_test_dir/libvulkan_freedreno.so" ||
            fail 'Cannot copy the test driver.'
    fi
    DRIVER=$tf_test_dir
fi
print -r -- "DRIVER_SHA256=$(sha256sum "$DRIVER/libvulkan_freedreno.so" 2>/dev/null | cut -d' ' -f1)"
export WINEMU_REPLACED_DRIVER="$DRIVER"
# Mesa's on-disk shader cache is off by default on Android. It only has an
# effect with a driver built with the shader cache enabled.
if [ "$tf_cache" = on ]; then
    mkdir -p "$ROOT/shader-cache" || fail 'Cannot create the shader cache directory.'
    export MESA_SHADER_CACHE_DISABLE=false MESA_SHADER_CACHE_DIR="$ROOT/shader-cache"
else
    export MESA_SHADER_CACHE_DISABLE=true
fi
if [ "$tf_logs" = on ]; then
    export WINEDEBUG='-all,err+all' DXVK_LOG_LEVEL=info MESA_LOG_LEVEL=warn
else
    export WINEDEBUG='-all' DXVK_LOG_LEVEL=warn MESA_LOG_LEVEL=error
fi
export DXVK_LOG_PATH="Z:\\sdcard\\Download\\Thor-Forever\\INSTALLED-WOW-$n"
tf_gpl_value=False
[ "$tf_gpl" = on ] && tf_gpl_value=True
export DXVK_CONFIG="dxvk.enableGraphicsPipelineLibrary = $tf_gpl_value; dxgi.maxFrameRate = $tf_fps"
if [ "$tf_hud" = off ]; then unset DXVK_HUD; else export DXVK_HUD="$tf_hud"; fi
export MESA_LOG_FILE="$OUT/mesa.log"
unset WINEBUILDDIR LIBGL_ALWAYS_INDIRECT DXVK_SHADER_DUMP_PATH
trap 'tf_status=$?; print -r -- "SCRIPT_EXIT=$tf_status STAGE=$tf_stage"; "$WINESERVER" -k; cleanup_lock' EXIT
tf_stage=restart-test-prefix
"$WINESERVER" -k
/system/bin/toybox timeout -k 2 10 "$WINESERVER" -w || exit 13
tf_stage=game
cd "$GAME" || exit 18
print -r -- 'Starting WoW in the fresh prefix with separate WTF, Cache and Logs.'
"$WINELOADER" "$GAME/WowB-ARM64.exe" -d3d11 -config Config-Thor-Forever.wtf >"$OUT/wine.log" 2>&1
tf_result=$?
print -r -- "WOW_EXIT=$tf_result"
print -r -- 'TEST_FINISHED'
exit "$tf_result"
