#!/system/bin/sh
# Development component installer: not yet an end-user entry point.
# Requires vetted pinned payloads; never touches GameHub's existing runtimes.
case "$0" in */*) TF_DIR=${0%/*} ;; *) exit 2 ;; esac
[ "${1-}" = --install-components ] || {
    print -r -- 'Development installer. Not enabled by Check-Setup.cmd.'; exit 2;
}
TF_USR=/data/user/0/com.ludashi.aibench/files/usr
case "${WINEPREFIX-}" in
    /data/user/*/com.ludashi.aibench/files/usr/*) TF_USR=${WINEPREFIX%%/files/usr/*}/files/usr ;;
esac
case "$TF_USR" in *'/../'*|*'/./'*|*/..|*/.) exit 3 ;; esac
[ ! -L "$TF_USR/home" ] || exit 3
[ -d "$TF_USR/home/virtual_containers" ] || exit 3
TF_PARENT="$TF_USR/home/thor-forever"
TF_INSTALL="$TF_PARENT/release-v1"
case "${2-}" in
    '') ;;
    --test-attempt-02) TF_INSTALL="$TF_PARENT/install-v2" ;;
    *) print -r -- 'Unknown test attempt. Nothing changed.'; exit 2 ;;
esac
[ ! -L "$TF_PARENT" ] && [ ! -e "$TF_INSTALL" ] && [ ! -L "$TF_INSTALL" ] || {
    print -r -- 'An installation or unfinished attempt already exists. Nothing overwritten.'; exit 4;
}
. "$TF_DIR/verify-payload.sh" || exit 5
. "$TF_DIR/discover-game.sh" || exit 5
. "$TF_DIR/create-prefix.sh" || exit 5
. "$TF_DIR/stage-game.sh" || exit 5
. "$TF_DIR/install-report.sh" || exit 5
[ -s "$TF_DIR/Config-Thor-Forever.wtf" ] && [ ! -L "$TF_DIR/Config-Thor-Forever.wtf" ] || exit 5
if ! tf_discover_game "$TF_USR"; then
    if [ "$TF_DISCOVERY_STATUS" = multiple ]; then
        print -r -- 'The game is installed in more than one GameHub container. Keep one and delete the other (or its World of Warcraft folder):'
        print -rn -- "$TF_GAME_LIST"
    else
        print -r -- 'The game was not found under C:\Program Files (x86) or C:\Program Files\World of Warcraft\_classic_beta_ in any GameHub container.'
    fi
    exit 6
fi
# Checksum scratch lives in a new directory, so previous reports are preserved.
mkdir -p "$TF_PARENT" || exit 7
mkdir "$TF_INSTALL" || exit 8
exec >"$TF_INSTALL/install.log" 2>&1 </dev/null
TF_PHASE=payload
trap 'tf_exit=$?; tf_install_report "$tf_exit"; exit "$tf_exit"' EXIT
print -r -- 'Thor Forever component installation. Existing GameHub components are not replaced.'
tf_verify_payload "$TF_DIR/../payload" "$TF_INSTALL/checksum.tmp" || exit 9
TF_PHASE=storage
# Parse df with shell builtins: require 3 GiB available for extraction + prefix.
/system/bin/toybox df -Pk "$TF_PARENT" >"$TF_INSTALL/space.txt" || exit 10
tf_space_ok=0
while read -r tf_fs tf_blocks tf_used tf_available tf_percent tf_mount; do
    case "$tf_available" in ''|*[!0-9]*) continue ;; esac
    [ "$tf_available" -lt 3145728 ] || tf_space_ok=1
done <"$TF_INSTALL/space.txt"
[ "$tf_space_ok" = 1 ] || { print -r -- 'At least 3 GiB of free internal storage is required.'; exit 11; }
mkdir "$TF_INSTALL/runtime" "$TF_INSTALL/graphics" "$TF_INSTALL/driver" || exit 12
TF_PHASE=extraction
# Only the archive pinned above is accepted. Its member paths are audited by
# tools/audit-runtime-archive.py before updating a payload hash for a release.
/system/bin/toybox tar -xf "$TF_DIR/../payload/wine-runtime.tar" -C "$TF_INSTALL/runtime" || exit 13
[ ! -e "$TF_INSTALL/runtime/lib/libandroid-sysvshm.so" ] && [ ! -L "$TF_INSTALL/runtime/lib/libandroid-sysvshm.so" ] || exit 14
TF_PHASE=components
cp "$TF_DIR/../payload/libandroid-sysvshm.so" "$TF_INSTALL/runtime/lib/libandroid-sysvshm.so" || exit 15
cp "$TF_DIR/../payload/libGL.so.1" "$TF_INSTALL/graphics/libGL.so.1" || exit 15
cp "$TF_DIR/../payload/trace.so" "$TF_INSTALL/graphics/trace.so" || exit 15
cp "$TF_DIR/../payload/libvulkan_freedreno.so" "$TF_INSTALL/driver/libvulkan_freedreno.so" || exit 15
cmp -s "$TF_DIR/../payload/libandroid-sysvshm.so" "$TF_INSTALL/runtime/lib/libandroid-sysvshm.so" || exit 15
cmp -s "$TF_DIR/../payload/libGL.so.1" "$TF_INSTALL/graphics/libGL.so.1" || exit 15
cmp -s "$TF_DIR/../payload/trace.so" "$TF_INSTALL/graphics/trace.so" || exit 15
cmp -s "$TF_DIR/../payload/libvulkan_freedreno.so" "$TF_INSTALL/driver/libvulkan_freedreno.so" || exit 15
TF_PHASE=prefix
tf_create_prefix "$TF_INSTALL/runtime" "$TF_INSTALL/prefix" "$TF_INSTALL/graphics" || exit 16
TF_PHASE=dxvk
for tf_dll in dxgi.dll d3d11.dll; do
    tf_dest="$TF_INSTALL/prefix/drive_c/windows/system32/$tf_dll"
    [ ! -L "$tf_dest" ] || exit 17
    if [ -e "$tf_dest" ]; then
        cp "$tf_dest" "$TF_INSTALL/builtin-$tf_dll" || exit 18
        cmp -s "$tf_dest" "$TF_INSTALL/builtin-$tf_dll" || exit 18
    fi
    cp "$TF_DIR/../payload/$tf_dll" "$tf_dest" || exit 19
    cmp -s "$TF_DIR/../payload/$tf_dll" "$tf_dest" || exit 19
done
print -r -- 'COMPONENTS_READY' >"$TF_INSTALL/components-ready" || exit 20
TF_PHASE=game
tf_stage_game "$TF_GAME_DIR" "$TF_INSTALL" "$TF_DIR/Config-Thor-Forever.wtf" || exit 21
TF_PHASE=prepared
print -r -- 'Components and separate game layout prepared. Launcher and acceptance tests are still required.'
exit 0
