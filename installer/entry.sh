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
    # screen (.copies, see installer/game-copies.sh), which shows a note.
    tf_usr=/data/user/0/com.ludashi.aibench/files/usr
    case "${WINEPREFIX-}" in
        /data/user/*/com.ludashi.aibench/files/usr/*) tf_usr=${WINEPREFIX%%/files/usr/*}/files/usr ;;
    esac
    tf_here=
    case "${WINEPREFIX-}" in "$tf_usr/home/virtual_containers/"*) tf_here=${WINEPREFIX%/} ;; esac
    tf_state=0
    if . "$KIT/installer/discover-game.sh" && . "$KIT/installer/game-copies.sh"; then
        tf_scan_copies "$tf_usr" "$tf_here" "$tf_at.copies"
        # Whether Thor Forever is installed (.state), for Play, Install or
        # Repair on the start screen. See installer/install-state.sh.
        if . "$KIT/installer/install-state.sh"; then
            tf_state=1
            tf_install_state "$tf_usr" "$tf_here" "$KIT" >"$tf_at.state.tmp" &&
                mv -f "$tf_at.state.tmp" "$tf_at.state"
        fi
    fi
    print -r -- 'READY' >"$tf_at.ready" || exit 3
    read -r tf_up _ </proc/uptime
    tf_end=$((${tf_up%%.*} + 43200))
    while [ ! -e "$tf_at.go" ]; do
        read -r tf_up _ </proc/uptime
        if [ -e "$tf_at.quit" ] || [ "${tf_up%%.*}" -ge "$tf_end" ]; then
            # The .log stays for diagnosis; the next launch cleans it up.
            for tf_file in "$tf_at".*; do
                [ "$tf_file" = "$tf_at.log" ] || rm -f "$tf_file"
            done
            exit 0
        fi
        # Install or Repair pressed (.install / .repair): runs
        # installer/start-install.sh in the background and writes
        # "<uptime> <phase>" to .progress every 2 seconds, so the start screen
        # can show the phase and see that this is alive. The result is in
        # .installed; .state is updated afterwards.
        for tf_mode in install repair; do
            [ "$tf_state" = 1 ] && [ -e "$tf_at.$tf_mode" ] || continue
            rm -f "$tf_at.$tf_mode" "$tf_at.installed"
            print -r -- "$tf_mode requested."
            /system/bin/sh "$KIT/installer/start-install.sh" "$tf_mode" "$tf_at.installed" </dev/null &
            tf_job=$!
            while [ ! -e "$tf_at.installed" ]; do
                if ! kill -0 "$tf_job" 2>/dev/null && [ ! -e "$tf_at.installed" ]; then
                    { print -r -- 9; print -r -- 'The installer ended without a result.'; } >"$tf_at.installed"
                    break
                fi
                read -r tf_up _ </proc/uptime
                tf_phase=starting
                [ ! -s "$tf_at.installed.phase" ] || read -r tf_phase <"$tf_at.installed.phase"
                print -r -- "${tf_up%%.*} $tf_phase" >"$tf_at.progress"
                /system/bin/toybox sleep 2 >/dev/null 2>&1 </dev/null
            done
            wait
            rm -f "$tf_at.progress"
            read -r tf_result <"$tf_at.installed"
            print -r -- "$tf_mode finished with code $tf_result."
            tf_install_state "$tf_usr" "$tf_here" "$KIT" >"$tf_at.state.tmp" &&
                mv -f "$tf_at.state.tmp" "$tf_at.state"
        done
        /system/bin/toybox sleep 0.5 >/dev/null 2>&1 </dev/null
    done
    rm -f "$tf_at.go" "$tf_at.ready" "$tf_at.copies" "$tf_at.state"
fi
print -r -- 'STARTED' >"$KIT/logs/ENTRY-$token.started" || exit 3
/system/bin/sh "$KIT/installer/launch-game.sh"
result=$?
print -r -- "$result" >"$KIT/logs/ENTRY-$token.tmp" || exit 4
mv "$KIT/logs/ENTRY-$token.tmp" "$KIT/logs/ENTRY-$token.done" || exit 4
exit "$result"
