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
# Each launch logs into its own Download/Thor-Forever/logs/run-<n> folder,
# numbered one above the newest existing one. Only the newest TF_KEEP_RUNS
# folders are kept; older ones are deleted once this launch holds the lock.
LOGS="$KIT/logs"
TF_KEEP_RUNS=3
[ -d "$LOGS" ] && [ ! -L "$LOGS" ] || { [ ! -e "$LOGS" ] && mkdir "$LOGS"; } || exit 2
n=0
for tf_run in "$LOGS"/run-*; do
    tf_rn=${tf_run##*/run-}
    case "$tf_rn" in ''|*[!0-9]*) continue ;; esac
    [ "${#tf_rn}" -le 9 ] && [ "$tf_rn" -gt "$n" ] && n=$tf_rn
done
n=$((n + 1))
tf_end=$((n + 100))
while [ "$n" -le "$tf_end" ]; do
    OUT="$LOGS/run-$n"
    if mkdir "$OUT" 2>/dev/null; then break; fi
    n=$((n + 1))
done
[ "$n" -le "$tf_end" ] || exit 2
exec >"$OUT/result.txt" 2>&1 </dev/null
tf_stage=preflight
trap 'tf_status=$?; print -r -- "SCRIPT_EXIT=$tf_status STAGE=$tf_stage"' EXIT
[ -f "$KIT/installer/discover-game.sh" ] || exit 3
. "$KIT/installer/discover-game.sh"
tf_discover_game "$USR" || { print -r -- 'STOP: a unique standard game installation was not found.'; exit 4; }
SOURCE=$TF_GAME_DIR
[ -s "$ROOT/components-ready" ] && [ -s "$ROOT/game-ready" ] || exit 5
[ -s "$PREFIX/system.reg" ] && [ ! -L "$ROOT" ] && [ ! -L "$PREFIX" ] || exit 6
# After a Battle.net update the staged executable is stale: copy the new one
# (and the other executable files) over from the original installation.
if ! cmp -s "$SOURCE/WowB-ARM64.exe" "$GAME/WowB-ARM64.exe"; then
    [ -f "$KIT/installer/stage-game.sh" ] && . "$KIT/installer/stage-game.sh" || exit 7
    tf_refresh_game "$SOURCE" "$GAME" || { print -r -- "STOP: the game was updated, but copying the new game files failed (code $?)."; exit 7; }
    print -r -- 'GAME UPDATED: copied the new game files from the original installation.'
fi
# While a WINE=test swap is active the check runs after the swap instead.
[ -e "$ROOT/wine-test-active" ] ||
    cmp -s "$RUNTIME/lib/wine/aarch64-windows/ntdll.dll" "$PREFIX/drive_c/windows/system32/ntdll.dll" || exit 8
[ -s "$GAME/WowB-ARM64.exe" ] || exit 9
[ -s "$GAME/WTF/Config-Thor-Forever.wtf" ] || exit 10
# Addons live in the original installation's Interface\AddOns. Not fatal:
# the game still starts without addons if the link cannot be made.
if [ -f "$KIT/installer/stage-game.sh" ] && . "$KIT/installer/stage-game.sh"; then
    tf_link_interface "$SOURCE" "$GAME"
    tf_link=$?
    case "$tf_link" in
        0) print -r -- 'ADDONS: using the original Interface\AddOns folder.' ;;
        72) print -r -- 'ADDONS: the staged game has its own Interface folder with files in it; left unchanged. Move its addons to the original Interface\AddOns and delete it.' ;;
        *) print -r -- "ADDONS: Interface folder not linked (code $tf_link); starting without it." ;;
    esac
    # Addons dropped into Download/Thor-Forever/AddOns are installed now, so no
    # file browser inside GameHub is needed. They go where the game loads them
    # from: through the link (the original folder), or into the staged game's
    # own Interface folder when it has one.
    case "$tf_link" in
        0|72) tf_addons="$GAME/Interface/AddOns" ;;
        *) tf_addons="$SOURCE/Interface/AddOns" ;;
    esac
    tf_sync_addons "$KIT/AddOns" "$tf_addons" ||
        print -r -- "ADDONS: could not copy from Download/Thor-Forever/AddOns (code $?)."
fi
# While DXVK=test DLLs are in the prefix, $ROOT/dxvk-test-active exists and
# the installed DLLs are restored from payload/ further below.
if [ ! -e "$ROOT/dxvk-test-active" ]; then
    for dll in dxgi.dll d3d11.dll; do
        cmp -s "$KIT/payload/$dll" "$PREFIX/drive_c/windows/system32/$dll" || exit 11
    done
fi
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

# Holding the lock means every earlier launch has ended, so their log folders
# are closed: delete all but the newest TF_KEEP_RUNS.
for tf_run in "$LOGS"/run-*; do
    tf_rn=${tf_run##*/run-}
    case "$tf_rn" in ''|*[!0-9]*) continue ;; esac
    [ "${#tf_rn}" -le 9 ] && [ "$tf_rn" -le $((n - TF_KEEP_RUNS)) ] || continue
    [ -d "$tf_run" ] && [ ! -L "$tf_run" ] || continue
    /system/bin/toybox rm -rf "$tf_run" >/dev/null 2>&1 </dev/null
done

# Each launch leaves ENTRY-<token>.log/.started/.done in logs/: the
# handshake Thor-Forever.exe waits on. Holding the lock means every earlier
# launch has ended, so only this launch's set is kept. .tmp files are left
# alone because a finishing launch renames its .tmp into .done. Sets that
# older versions left in the kit folder itself are removed as well.
case "${TF_ENTRY_TOKEN-}" in
    ''|*[!0-9-]*) ;;
    *)
        for tf_entry in "$LOGS"/ENTRY-*.log "$LOGS"/ENTRY-*.started "$LOGS"/ENTRY-*.done \
            "$KIT"/ENTRY-*.log "$KIT"/ENTRY-*.started "$KIT"/ENTRY-*.done; do
            [ -f "$tf_entry" ] && [ ! -L "$tf_entry" ] || continue
            [ "$tf_entry" = "$LOGS/${tf_entry##*/}" ] &&
                case "${tf_entry##*/}" in "ENTRY-$TF_ENTRY_TOKEN".*) continue ;; esac
            rm -f "$tf_entry"
        done
        ;;
esac

# Performance settings from $KIT/tuning.conf. Only known keys with
# validated values are accepted; the file is never executed.
tf_fps=60 tf_hud=fps,frametimes,compiler tf_logs=off tf_gpl=off tf_esync=off
tf_driver=installed tf_cache=on tf_dxvk=installed tf_tiler=auto
tf_profile=off tf_affinity=all tf_tumode=auto tf_wine=installed
tf_ws=$' \t\r'
if [ -f "$KIT/tuning.conf" ] && [ ! -L "$KIT/tuning.conf" ]; then
    while IFS= read -r tf_line || [ -n "$tf_line" ]; do
        tf_line=${tf_line%%#*}
        # Strip whitespace in the shell itself: GameHub's process wrapper
        # adds its own text to the output of any external command.
        tf_line=${tf_line//[$tf_ws]/}
        case "$tf_line" in *=*) ;; *) continue ;; esac
        tf_key=${tf_line%%=*} tf_value=${tf_line#*=}
        case "$tf_key" in
            FPS_CAP) case "$tf_value" in ''|*[!0-9]*) ;; *) [ "${#tf_value}" -le 3 ] && tf_fps=$tf_value ;; esac ;;
            HUD) case "$tf_value" in ''|*[!a-z0-9,=.]*) ;; *) tf_hud=$tf_value ;; esac ;;
            LOGS) case "$tf_value" in on|off|trace) tf_logs=$tf_value ;; esac ;;
            GPL) case "$tf_value" in on|off) tf_gpl=$tf_value ;; esac ;;
            ESYNC) case "$tf_value" in on|off) tf_esync=$tf_value ;; esac ;;
            DRIVER) case "$tf_value" in installed|test) tf_driver=$tf_value ;; esac ;;
            SHADER_CACHE) case "$tf_value" in on|off) tf_cache=$tf_value ;; esac ;;
            DXVK) case "$tf_value" in installed|test) tf_dxvk=$tf_value ;; esac ;;
            DXVK_TILER) case "$tf_value" in auto|on|off) tf_tiler=$tf_value ;; esac ;;
            PROFILE) case "$tf_value" in on|off) tf_profile=$tf_value ;; esac ;;
            AFFINITY) case "$tf_value" in all|big|prime3|one|one-then-all|one-then-split) tf_affinity=$tf_value ;; esac ;;
            TURNIP_MODE) case "$tf_value" in auto|gmem|sysmem) tf_tumode=$tf_value ;; esac ;;
            WINE) case "$tf_value" in installed|test) tf_wine=$tf_value ;; esac ;;
        esac
    done <"$KIT/tuning.conf"
fi
print -r -- "TUNING FPS_CAP=$tf_fps HUD=$tf_hud LOGS=$tf_logs GPL=$tf_gpl ESYNC=$tf_esync DRIVER=$tf_driver SHADER_CACHE=$tf_cache DXVK=$tf_dxvk DXVK_TILER=$tf_tiler PROFILE=$tf_profile AFFINITY=$tf_affinity TURNIP_MODE=$tf_tumode WINE=$tf_wine"
# The shipped tuning.conf picks the test driver and DXVK. Without their
# files, fall back to the installed ones instead of refusing to start.
if [ "$tf_driver" = test ] && { [ ! -s "$KIT/driver-test/libvulkan_freedreno.so" ] || [ -L "$KIT/driver-test/libvulkan_freedreno.so" ]; }; then
    print -r -- 'DRIVER=test, but driver-test/libvulkan_freedreno.so is missing: using the installed driver.'
    tf_driver=installed
fi
if [ "$tf_dxvk" = test ]; then
    for dll in dxgi.dll d3d11.dll; do
        if [ ! -s "$KIT/dxvk-test/$dll" ] || [ -L "$KIT/dxvk-test/$dll" ]; then
            print -r -- "DXVK=test, but dxvk-test/$dll is missing: using the installed DXVK."
            tf_dxvk=installed
            break
        fi
    done
fi
if [ "$tf_wine" = test ] && { [ ! -s "$KIT/wine-test/ntdll.so" ] || [ -L "$KIT/wine-test/ntdll.so" ]; }; then
    print -r -- 'WINE=test, but wine-test/ntdll.so is missing: using the installed Wine.'
    tf_wine=installed
fi
# With the installed driver, esync made WoW's own waits fail and the game
# crashed within minutes (2026-10-02); with the Mesa 26.2.3 test driver it
# ran without errors. So esync is only used together with DRIVER=test.
if [ "$tf_esync" = on ] && [ "$tf_driver" != test ]; then
    print -r -- 'ESYNC=on only works with DRIVER=test: esync stays off.'
    tf_esync=off
fi
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
# GameHub's process wrapper can prepend its own messages, without a newline,
# to a child's output. Take the last 64 characters of each word and keep the
# first one that is a full lowercase hex digest.
tf_sha256()
{
    tf_hash=unknown
    tf_raw=$(/system/bin/toybox sha256sum "$1" 2>/dev/null)
    for tf_word in $tf_raw; do
        [ "${#tf_word}" -ge 64 ] || continue
        tf_tail=${tf_word#"${tf_word%????????????????????????????????????????????????????????????????}"}
        case "$tf_tail" in *[!0-9a-f]*) ;; *) tf_hash=$tf_tail; break ;; esac
    done
}
tf_sha256 "$DRIVER/libvulkan_freedreno.so"
print -r -- "DRIVER_SHA256=$tf_hash"
# DXVK=test puts Download/Thor-Forever/dxvk-test/{dxgi,d3d11}.dll into the
# test prefix. DXVK=installed puts the installed ones from payload/ back.
# The marker is written before the first copy, so an interrupted swap is
# still undone by the next DXVK=installed launch.
tf_sys32="$PREFIX/drive_c/windows/system32"
if [ "$tf_dxvk" = test ]; then
    tf_dxvk_src="$KIT/dxvk-test"
    for dll in dxgi.dll d3d11.dll; do
        [ -s "$tf_dxvk_src/$dll" ] && [ ! -L "$tf_dxvk_src/$dll" ] || fail "DXVK=test, but dxvk-test/$dll is missing."
    done
    : >"$ROOT/dxvk-test-active" || fail 'Cannot mark the test DXVK as active.'
else
    tf_dxvk_src="$KIT/payload"
fi
for dll in dxgi.dll d3d11.dll; do
    [ ! -L "$tf_sys32/$dll" ] || fail "The prefix $dll is a link."
    if ! cmp -s "$tf_dxvk_src/$dll" "$tf_sys32/$dll"; then
        cp "$tf_dxvk_src/$dll" "$tf_sys32/$dll.tmp" && mv "$tf_sys32/$dll.tmp" "$tf_sys32/$dll" ||
            fail "Cannot copy $dll into the prefix."
    fi
    tf_sha256 "$tf_sys32/$dll"
    print -r -- "DXVK_${dll%.dll}_SHA256=$tf_hash"
done
if [ "$tf_dxvk" = installed ] && [ -e "$ROOT/dxvk-test-active" ]; then
    rm "$ROOT/dxvk-test-active" || fail 'Cannot clear the test DXVK marker.'
fi
# WINE=test swaps in Download/Thor-Forever/wine-test/ntdll.so and, when
# present, ntdll.dll (from the "Build Wine" workflow: the same Wine source
# plus this repo's esync fix). The two halves of ntdll must come from the
# same build. Each installed file is kept as <file>.installed and put back
# by the next WINE=installed launch, also after an interrupted swap.
tf_ntdll="$RUNTIME/lib/wine/aarch64-unix/ntdll.so"
tf_ntdll_pe="$RUNTIME/lib/wine/aarch64-windows/ntdll.dll"
tf_ntdll_sys="$PREFIX/drive_c/windows/system32/ntdll.dll"
for tf_file in "$tf_ntdll" "$tf_ntdll_pe" "$tf_ntdll_sys"; do
    [ ! -L "$tf_file" ] || fail "${tf_file##*/} in the runtime or prefix is a link."
done
tf_swap_in()
{
    if [ ! -e "$2.installed" ]; then
        cp "$2" "$2.installed.tmp" && mv "$2.installed.tmp" "$2.installed" ||
            fail "Cannot keep a copy of the installed ${2##*/}."
    fi
    if ! cmp -s "$1" "$2"; then
        cp "$1" "$2.tmp" && mv "$2.tmp" "$2" || fail "Cannot copy the test ${2##*/}."
    fi
}
tf_swap_back()
{
    [ -e "$1.installed" ] || return 0
    cp "$1.installed" "$1.tmp" && mv "$1.tmp" "$1" && rm "$1.installed" ||
        fail "Cannot restore the installed ${1##*/}."
}
if [ "$tf_wine" = test ]; then
    : >"$ROOT/wine-test-active" || fail 'Cannot mark the test Wine as active.'
    tf_swap_in "$KIT/wine-test/ntdll.so" "$tf_ntdll"
    if [ -f "$KIT/wine-test/ntdll.dll" ]; then
        tf_swap_in "$KIT/wine-test/ntdll.dll" "$tf_ntdll_pe"
        tf_swap_in "$KIT/wine-test/ntdll.dll" "$tf_ntdll_sys"
    else
        tf_swap_back "$tf_ntdll_pe"
        tf_swap_back "$tf_ntdll_sys"
    fi
elif [ -e "$ROOT/wine-test-active" ]; then
    for tf_file in "$tf_ntdll" "$tf_ntdll_pe" "$tf_ntdll_sys"; do
        tf_swap_back "$tf_file"
    done
    rm "$ROOT/wine-test-active" || fail 'Cannot clear the test Wine marker.'
fi
cmp -s "$tf_ntdll_pe" "$tf_ntdll_sys" || fail 'The runtime and prefix ntdll.dll differ.'
tf_sha256 "$tf_ntdll"
print -r -- "WINE_NTDLL_SHA256=$tf_hash"
tf_sha256 "$tf_ntdll_pe"
print -r -- "WINE_NTDLL_DLL_SHA256=$tf_hash"
# With LOGS=trace, keep one copy of the installed (original) ntdll pair in
# Download/Thor-Forever/wine-installed/, to compare it with a rebuilt one.
if [ "$tf_logs" = trace ] && [ ! -e "$KIT/wine-installed/ntdll.dll" ]; then
    mkdir -p "$KIT/wine-installed" &&
        for tf_file in "$tf_ntdll" "$tf_ntdll_pe"; do
            tf_src=$tf_file
            [ -e "$tf_file.installed" ] && tf_src=$tf_file.installed
            cp "$tf_src" "$KIT/wine-installed/${tf_file##*/}" || break
        done
fi
export WINEMU_REPLACED_DRIVER="$DRIVER"
# Turnip renders either in the GPU's fast on-chip tile memory (gmem) or
# straight to memory (sysmem) and picks per render pass. Forcing one is a
# driver debug option, used here to compare speed.
case "$tf_tumode" in
    gmem|sysmem) export TU_DEBUG="$tf_tumode" ;;
esac
# Mesa's on-disk shader cache is off by default on Android. It only has an
# effect with a driver built with the shader cache enabled.
if [ "$tf_cache" = on ]; then
    mkdir -p "$ROOT/shader-cache" || fail 'Cannot create the shader cache directory.'
    export MESA_SHADER_CACHE_DISABLE=false MESA_SHADER_CACHE_DIR="$ROOT/shader-cache"
else
    export MESA_SHADER_CACHE_DISABLE=true
fi
if [ "$tf_logs" != off ]; then
    export WINEDEBUG='-all,err+all' DXVK_LOG_LEVEL=info MESA_LOG_LEVEL=warning
    # trace also logs every exception and where each DLL was loaded, to tell
    # which code a crash address belongs to. It makes wine.log much bigger.
    [ "$tf_logs" = trace ] && WINEDEBUG='-all,err+all,+seh,+loaddll'
else
    export WINEDEBUG='-all' DXVK_LOG_LEVEL=warn MESA_LOG_LEVEL=error
    # Esync errors are rare but explain its crashes, so keep them.
    [ "$tf_esync" = on ] && WINEDEBUG='-all,err+esync'
fi
# Faster sync options need kernel support: ntsync needs /dev/ntsync.
IFS= read -r tf_kernel </proc/sys/kernel/osrelease 2>/dev/null || tf_kernel=unknown
tf_ntsync=no
[ -e /dev/ntsync ] && tf_ntsync=yes
print -r -- "KERNEL=$tf_kernel NTSYNC_DEVICE=$tf_ntsync"
if [ "$tf_esync" = on ]; then
    # Esync needs one file descriptor per Windows sync object.
    print -r -- "FD_LIMIT soft=$(ulimit -Sn) hard=$(ulimit -Hn)"
fi
export DXVK_LOG_PATH="Z:\\sdcard\\Download\\Thor-Forever\\logs\\run-$n"
# With PROFILE=on, the Thor-tuned DXVK also writes frames.csv: one line per
# frame with its duration and what DXVK did in it, to find stutters. Other
# DXVK builds ignore the variable. Our test Wine (WINE=test) also writes,
# every 5 s, how often and how long threads waited on the wineserver into
# wine.log ("server-stats" lines).
if [ "$tf_profile" = on ]; then
    export DXVK_FRAME_LOG="$DXVK_LOG_PATH\\frames.csv" WINE_SERVER_STATS=1
else
    unset DXVK_FRAME_LOG WINE_SERVER_STATS
fi
tf_gpl_value=False
[ "$tf_gpl" = on ] && tf_gpl_value=True
export DXVK_CONFIG="dxvk.enableGraphicsPipelineLibrary = $tf_gpl_value; dxgi.maxFrameRate = $tf_fps"
# DXVK 2.6+ switches on a tile-based GPU mode for Turnip by itself; older
# versions ignore the option.
case "$tf_tiler" in
    on) DXVK_CONFIG="$DXVK_CONFIG; dxvk.tilerMode = True" ;;
    off) DXVK_CONFIG="$DXVK_CONFIG; dxvk.tilerMode = False" ;;
esac
if [ "$tf_hud" = off ]; then unset DXVK_HUD; else export DXVK_HUD="$tf_hud"; fi
export MESA_LOG_FILE="$OUT/mesa.log"
unset WINEBUILDDIR LIBGL_ALWAYS_INDIRECT DXVK_SHADER_DUMP_PATH
trap 'tf_status=$?; print -r -- "SCRIPT_EXIT=$tf_status STAGE=$tf_stage"; "$WINESERVER" -k; cleanup_lock' EXIT
tf_stage=restart-test-prefix
"$WINESERVER" -k
/system/bin/toybox timeout -k 2 10 "$WINESERVER" -w || exit 13
tf_stage=game
cd "$GAME" || exit 18
# PROFILE=on samples, every 2 seconds, the CPU time and current core of each
# WoW and wineserver thread, how much WoW has read from storage, how many
# files each has open, every core's clock and the GPU load into perf.csv.
# It only reads /proc and /sys with shell builtins.
# Prints "k,<kind>,<count>" for the open fds of process $1 (for example
# eventfd or sync_file), from the link targets toybox ls shows.
tf_fd_kinds()
{
    tf_ke=0 tf_ks=0 tf_kd=0 tf_ka=0 tf_ko= tf_kn=0 tf_kp=0 tf_kg=0 tf_kv=0 tf_kf=0
    /system/bin/toybox ls -l "$1/fd/" >"$OUT/.fds" 2>/dev/null </dev/null || return
    while IFS= read -r tf_l; do
        case "$tf_l" in *' -> '*) ;; *) continue ;; esac
        case "${tf_l##* -> }" in
            *eventfd*) tf_ke=$((tf_ke + 1)) ;;
            *sync_file*) tf_ks=$((tf_ks + 1)) ;;
            *dmabuf*|/dmabuf*) tf_kd=$((tf_kd + 1)) ;;
            anon_inode:*) tf_ka=$((tf_ka + 1)); tf_ko=${tf_l##* -> } ;;
            socket:*) tf_kn=$((tf_kn + 1)) ;;
            pipe:*) tf_kp=$((tf_kp + 1)) ;;
            /dev/kgsl*) tf_kg=$((tf_kg + 1)) ;;
            /dev/*) tf_kv=$((tf_kv + 1)) ;;
            *) tf_kf=$((tf_kf + 1)) ;;
        esac
    done <"$OUT/.fds"
    rm -f "$OUT/.fds"
    print -r -- "k,eventfd,$tf_ke"
    print -r -- "k,sync_file,$tf_ks"
    print -r -- "k,dmabuf,$tf_kd"
    print -r -- "k,other_anon(${tf_ko//[!A-Za-z0-9_:.]/_}),$tf_ka"
    print -r -- "k,socket,$tf_kn"
    print -r -- "k,pipe,$tf_kp"
    print -r -- "k,kgsl,$tf_kg"
    print -r -- "k,other_dev,$tf_kv"
    print -r -- "k,file,$tf_kf"
}
tf_profile_loop()
{
    tf_tick=0
    while [ -e "$OUT/.profiling" ]; do
        tf_tick=$((tf_tick + 1))
        read -r tf_up _ </proc/uptime || tf_up=0
        print -r -- "T,$tf_up"
        for tf_c in /sys/devices/system/cpu/cpu[0-9]*; do
            IFS= read -r tf_f <"$tf_c/cpufreq/scaling_cur_freq" 2>/dev/null || continue
            IFS= read -r tf_m <"$tf_c/cpufreq/scaling_max_freq" 2>/dev/null || tf_m=
            print -r -- "f,${tf_c##*/cpu},$tf_f,$tf_m"
        done
        tf_g= tf_gf=
        IFS= read -r tf_g </sys/class/kgsl/kgsl-3d0/gpu_busy_percentage 2>/dev/null
        IFS= read -r tf_gf </sys/class/kgsl/kgsl-3d0/devfreq/cur_freq 2>/dev/null
        print -r -- "g,${tf_g%%[!0-9]*},$tf_gf"
        tf_gm= tf_gt= tf_gc=
        IFS= read -r tf_gm </sys/class/kgsl/kgsl-3d0/devfreq/max_freq 2>/dev/null
        IFS= read -r tf_gt </sys/class/kgsl/kgsl-3d0/thermal_pwrlevel 2>/dev/null
        IFS= read -r tf_gc </sys/class/kgsl/kgsl-3d0/temp 2>/dev/null
        print -r -- "L,$tf_gm,$tf_gt,${tf_gc%%[!0-9]*}"
        for tf_p in /proc/[0-9]*; do
            IFS= read -r tf_n <"$tf_p/comm" 2>/dev/null || continue
            case "$tf_n" in WowB-ARM64.exe|wineserver) ;; *) continue ;; esac
            # Open files (fds), to see a leak filling the fd table.
            set -- "$tf_p"/fd/*
            [ "$1" != "$tf_p/fd/*" ] && print -r -- "n,$tf_n,${tf_p##*/},$#"
            # Every 30 s while WoW has many open, count them by kind.
            [ "$tf_n" = WowB-ARM64.exe ] && [ "$#" -gt 1000 ] && [ $((tf_tick % 15)) = 0 ] &&
                tf_fd_kinds "$tf_p"
            # Bytes WoW has read so far, to see loading bursts.
            if [ "$tf_n" = WowB-ARM64.exe ]; then
                tf_rc= tf_rb=
                { while IFS=': ' read -r tf_key tf_val; do
                    case "$tf_key" in rchar) tf_rc=$tf_val ;; read_bytes) tf_rb=$tf_val ;; esac
                done <"$tf_p/io"; } 2>/dev/null
                print -r -- "i,${tf_p##*/},$tf_rc,$tf_rb"
            fi
            for tf_t in "$tf_p"/task/[0-9]*; do
                IFS= read -r tf_tn <"$tf_t/comm" 2>/dev/null || continue
                IFS= read -r tf_st <"$tf_t/stat" 2>/dev/null || continue
                set -f
                set -- ${tf_st##*) }
                set +f
                [ "$#" -ge 37 ] || continue
                print -r -- "t,$tf_n,${tf_t##*/},${tf_tn//[!A-Za-z0-9_.-]/_},${12},${13},${37}"
            done
        done
        /system/bin/toybox sleep 2 >/dev/null 2>&1 </dev/null || break
    done
}
# PROFILE=on also samples WoW's main thread every 50 ms into state.csv:
# whether it runs (R), sleeps (S, waiting for something) or waits on the
# disk (D), the kernel function it waits in, and from schedstat its total
# time on a core and waiting for a free core (ns), to see what stutters are.
tf_state_loop()
{
    tf_pid=
    while [ -e "$OUT/.profiling" ]; do
        if [ -z "$tf_pid" ] || [ ! -e "/proc/$tf_pid/stat" ]; then
            tf_pid=
            for tf_p in /proc/[0-9]*; do
                IFS= read -r tf_n <"$tf_p/comm" 2>/dev/null || continue
                [ "$tf_n" = WowB-ARM64.exe ] && { tf_pid=${tf_p##*/}; break; }
            done
        fi
        if [ -n "$tf_pid" ]; then
            read -r tf_up _ </proc/uptime || tf_up=0
            tf_st= tf_w= tf_run= tf_rq=
            IFS= read -r tf_st <"/proc/$tf_pid/task/$tf_pid/stat" 2>/dev/null
            IFS= read -r tf_w <"/proc/$tf_pid/task/$tf_pid/wchan" 2>/dev/null
            read -r tf_run tf_rq _ <"/proc/$tf_pid/task/$tf_pid/schedstat" 2>/dev/null
            tf_st=${tf_st##*) }
            print -r -- "$tf_up,${tf_st%% *},${tf_w//[!A-Za-z0-9_.]/_},${tf_run//[!0-9]/},${tf_rq//[!0-9]/}"
        fi
        /system/bin/toybox sleep 0.05 >/dev/null 2>&1 </dev/null || break
    done
}
if [ "$tf_profile" = on ]; then
    : >"$OUT/.profiling" && {
        tf_profile_loop >"$OUT/perf.csv" 2>/dev/null &
        tf_state_loop >"$OUT/state.csv" 2>/dev/null &
    }
fi
# AFFINITY keeps WoW, Wine and DXVK threads off the small cores. On the
# Snapdragon 8 Gen 2, cpu0-2 are the small cores and cpu7 is the prime core.
case "$tf_affinity" in
    big) set -- /system/bin/toybox taskset f8 ;;
    prime3) set -- /system/bin/toybox taskset e0 ;;
    # one = the prime core only. Slow; only for testing whether a crash
    # needs threads running at the same time.
    one|one-then-all|one-then-split) set -- /system/bin/toybox taskset 80 ;;
    *) set -- ;;
esac
# WoW writes its own crash reports into Errors inside the private game
# folder, where they can't be opened on the device. A crash usually ends
# this script too, so copy new reports to Download/Thor-Forever/wow-errors
# at the next launch. Reports copied before are skipped.
for tf_err in "$GAME/Errors"/*.txt "$GAME/Errors"/*.log; do
    [ -f "$tf_err" ] && [ ! -L "$tf_err" ] || continue
    [ -e "$KIT/wow-errors/${tf_err##*/}" ] && continue
    mkdir -p "$KIT/wow-errors" && cp "$tf_err" "$KIT/wow-errors/" >/dev/null 2>&1 &&
        print -r -- "WOW_ERROR_REPORT=${tf_err##*/}"
done
# one-then-all starts WoW on the prime core only and frees all cores once
# startup is over. With esync, WoW's startup CPU checks sometimes collide
# across threads and the main thread crashes (a blank window); on one core
# that did not happen in testing. Only threads still limited to cpu7 are
# changed, a few times so that late new threads are caught as well.
# one-then-split does the same, but leaves WoW's main thread alone on cpu7
# and moves every other thread to cpu0-6, so no other thread can take the
# prime core from it. Threads the main thread starts later inherit cpu7,
# so it keeps checking every 10 s while WoW runs.
tf_release_once()
{
    for tf_t in /proc/[0-9]*/task/[0-9]*; do
        tf_allowed=
        # Threads can end at any moment, so a failed open is silent.
        { while IFS=$' \t' read -r tf_key tf_val; do
            [ "$tf_key" = Cpus_allowed_list: ] && { tf_allowed=$tf_val; break; }
        done <"$tf_t/status"; } 2>/dev/null
        [ "$tf_allowed" = 7 ] || continue
        tf_mask=ff
        if [ "$tf_affinity" = one-then-split ]; then
            tf_p=${tf_t%/task/*}
            tf_n=
            IFS= read -r tf_n <"$tf_p/comm" 2>/dev/null
            [ "$tf_n" = WowB-ARM64.exe ] && [ "${tf_p##*/}" = "${tf_t##*/}" ] && continue
            tf_mask=7f
        fi
        /system/bin/toybox taskset -p "$tf_mask" "${tf_t##*/}" >/dev/null 2>&1 </dev/null
    done
}
tf_release_cores()
{
    for tf_wait in 30 15 15 30; do
        /system/bin/toybox sleep "$tf_wait" >/dev/null 2>&1 </dev/null
        tf_release_once
    done
    [ "$tf_affinity" = one-then-split ] || return 0
    while :; do
        /system/bin/toybox sleep 10 >/dev/null 2>&1 </dev/null
        tf_seen=
        for tf_p in /proc/[0-9]*; do
            IFS= read -r tf_n <"$tf_p/comm" 2>/dev/null || continue
            [ "$tf_n" = WowB-ARM64.exe ] && { tf_seen=1; break; }
        done
        [ -n "$tf_seen" ] || return 0
        tf_release_once
    done
}
case "$tf_affinity" in one-then-all|one-then-split) tf_release_cores & ;; esac
print -r -- 'Starting WoW in the fresh prefix with separate WTF, Cache and Logs.'
"$@" "$WINELOADER" "$GAME/WowB-ARM64.exe" -d3d11 -config Config-Thor-Forever.wtf >"$OUT/wine.log" 2>&1
tf_result=$?
rm -f "$OUT/.profiling"
print -r -- "WOW_EXIT=$tf_result"
print -r -- 'TEST_FINISHED'
exit "$tf_result"
