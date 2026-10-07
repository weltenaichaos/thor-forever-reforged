#!/system/bin/sh
KIT=/sdcard/Download/Thor-Forever
case "${1-}" in ''|*[!0-9-]*) exit 2 ;; esac
token=$1
[ "${#token}" -le 80 ] || exit 2
export TF_ENTRY_TOKEN="$token"
# Thor-Forever.exe creates logs/ before starting this script.
[ -d "$KIT/logs" ] || mkdir "$KIT/logs" >/dev/null 2>&1 </dev/null
exec >"$KIT/logs/ENTRY-$token.log" 2>&1 </dev/null
# TF_WAIT_FOR_PLAY: with "wait", the start screen starts this script as soon
# as it opens and it waits for Play (ENTRY-<token>.go) or Quit (.quit).
# Once Battle.net has run, GameHub no longer starts this script, so it has
# to be running before then. Gives up after 12 hours.
if [ "${2-}" = wait ]; then
    tf_at="$KIT/logs/ENTRY-$token"
    # With the game in several containers, list the copies for the start
    # screen (.copies, later .sizes), which can ask to remove one (.remove,
    # answered in .removed). See installer/game-copies.sh.
    tf_usr=/data/user/0/com.ludashi.aibench/files/usr
    case "${WINEPREFIX-}" in
        /data/user/*/com.ludashi.aibench/files/usr/*) tf_usr=${WINEPREFIX%%/files/usr/*}/files/usr ;;
    esac
    tf_here=
    case "${WINEPREFIX-}" in "$tf_usr/home/virtual_containers/"*) tf_here=${WINEPREFIX%/} ;; esac
    tf_copies=0
    tf_sizer=
    if . "$KIT/installer/discover-game.sh" && . "$KIT/installer/stage-game.sh" &&
        . "$KIT/installer/game-copies.sh"; then
        tf_copies=1
        tf_scan_copies "$tf_usr" "$tf_here" "$tf_at.copies"
    fi
    print -r -- 'READY' >"$tf_at.ready" || exit 3
    if [ -s "$tf_at.copies" ]; then
        tf_copy_sizes "$tf_usr" "$tf_at.copies" "$tf_at.sizes" &
        tf_sizer=$!
    fi
    read -r tf_up _ </proc/uptime
    tf_end=$((${tf_up%%.*} + 43200))
    while [ ! -e "$tf_at.go" ]; do
        read -r tf_up _ </proc/uptime
        if [ -e "$tf_at.quit" ] || [ "${tf_up%%.*}" -ge "$tf_end" ]; then
            [ -z "$tf_sizer" ] || kill "$tf_sizer" 2>/dev/null
            # The .log stays for diagnosis; the next launch cleans it up.
            for tf_file in "$tf_at".*; do
                [ "$tf_file" = "$tf_at.log" ] || rm -f "$tf_file"
            done
            exit 0
        fi
        if [ "$tf_copies" = 1 ] && [ -e "$tf_at.remove" ]; then
            IFS= read -r tf_name <"$tf_at.remove"
            rm -f "$tf_at.remove"
            [ -z "$tf_sizer" ] || kill "$tf_sizer" 2>/dev/null
            tf_sizer=
            tf_remove_copy "$tf_usr" "$tf_here" "$tf_name" "$tf_usr/home/thor-forever/release-v1/game/_classic_beta_"
            tf_result=$?
            tf_scan_copies "$tf_usr" "$tf_here" "$tf_at.copies"
            print -r -- "$tf_result" >"$tf_at.removed.tmp" && mv -f "$tf_at.removed.tmp" "$tf_at.removed"
        fi
        /system/bin/toybox sleep 0.5 >/dev/null 2>&1 </dev/null
    done
    [ -z "$tf_sizer" ] || kill "$tf_sizer" 2>/dev/null
    rm -f "$tf_at.go" "$tf_at.ready" "$tf_at.copies" "$tf_at.sizes"
fi
print -r -- 'STARTED' >"$KIT/logs/ENTRY-$token.started" || exit 3
/system/bin/sh "$KIT/installer/launch-game.sh"
result=$?
print -r -- "$result" >"$KIT/logs/ENTRY-$token.tmp" || exit 4
mv "$KIT/logs/ENTRY-$token.tmp" "$KIT/logs/ENTRY-$token.done" || exit 4
exit "$result"
