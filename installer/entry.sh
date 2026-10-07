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
            [ -z "$tf_sizer" ] || tf_kill_tree "$tf_sizer"
            # The .log stays for diagnosis; the next launch cleans it up.
            for tf_file in "$tf_at".*; do
                [ "$tf_file" = "$tf_at.log" ] || rm -f "$tf_file"
            done
            exit 0
        fi
        if [ "$tf_copies" = 1 ] && [ -e "$tf_at.remove" ]; then
            IFS= read -r tf_name <"$tf_at.remove"
            rm -f "$tf_at.remove" "$tf_at.stop" "$tf_at.rc"
            [ -z "$tf_sizer" ] || tf_kill_tree "$tf_sizer"
            tf_sizer=
            # Deletes in the background. Meanwhile .progress says "<uptime>
            # <KiB freed so far>" every 2 seconds, so the start screen can
            # show progress and see that this is still alive; .stop ends it.
            tf_free0=$(tf_free_kb "$tf_usr/home" "$tf_at.df")
            (
                tf_remove_copy "$tf_usr" "$tf_here" "$tf_name" "$tf_usr/home/thor-forever/release-v1/game/_classic_beta_"
                print -r -- "$?" >"$tf_at.rc"
            ) >"$tf_at.why" 2>&1 &
            tf_remover=$!
            while [ ! -s "$tf_at.rc" ]; do
                if [ -e "$tf_at.stop" ]; then
                    tf_kill_tree "$tf_remover"
                    print -r -- 'Stopped on the start screen. What is left can be removed next time.' >>"$tf_at.why"
                    print -r -- 130 >"$tf_at.rc"
                    break
                fi
                read -r tf_up _ </proc/uptime
                tf_free=$(tf_free_kb "$tf_usr/home" "$tf_at.df")
                print -r -- "${tf_up%%.*} $((tf_free - tf_free0))" >"$tf_at.progress.tmp" &&
                    mv -f "$tf_at.progress.tmp" "$tf_at.progress"
                /system/bin/toybox sleep 2 >/dev/null 2>&1 </dev/null
            done
            read -r tf_result <"$tf_at.rc"
            rm -f "$tf_at.rc" "$tf_at.stop" "$tf_at.progress"
            tf_scan_copies "$tf_usr" "$tf_here" "$tf_at.copies"
            # .removed: the result code, then (on failure) the first and last
            # lines of what happened, which the start screen shows.
            tf_lines=0
            while IFS= read -r tf_line; do
                print -r -- "$tf_line"
                tf_lines=$((tf_lines + 1))
            done <"$tf_at.why"
            {
                print -r -- "$tf_result"
                if [ "$tf_result" != 0 ]; then
                    tf_n=0
                    while IFS= read -r tf_line; do
                        tf_n=$((tf_n + 1))
                        if [ "$tf_n" -le 8 ] || [ "$tf_n" -gt $((tf_lines - 16)) ]; then
                            print -r -- "$tf_line"
                        elif [ "$tf_n" = 9 ]; then
                            print -r -- '...'
                        fi
                    done <"$tf_at.why"
                fi
            } >"$tf_at.removed.tmp" && mv -f "$tf_at.removed.tmp" "$tf_at.removed"
            rm -f "$tf_at.why"
        fi
        /system/bin/toybox sleep 0.5 >/dev/null 2>&1 </dev/null
    done
    [ -z "$tf_sizer" ] || tf_kill_tree "$tf_sizer"
    rm -f "$tf_at.go" "$tf_at.ready" "$tf_at.copies" "$tf_at.sizes"
fi
print -r -- 'STARTED' >"$KIT/logs/ENTRY-$token.started" || exit 3
/system/bin/sh "$KIT/installer/launch-game.sh"
result=$?
print -r -- "$result" >"$KIT/logs/ENTRY-$token.tmp" || exit 4
mv "$KIT/logs/ENTRY-$token.tmp" "$KIT/logs/ENTRY-$token.done" || exit 4
exit "$result"
