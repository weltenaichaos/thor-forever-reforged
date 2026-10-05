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
    print -r -- 'READY' >"$KIT/logs/ENTRY-$token.ready" || exit 3
    read -r tf_up _ </proc/uptime
    tf_end=$((${tf_up%%.*} + 43200))
    while [ ! -e "$KIT/logs/ENTRY-$token.go" ]; do
        read -r tf_up _ </proc/uptime
        if [ -e "$KIT/logs/ENTRY-$token.quit" ] || [ "${tf_up%%.*}" -ge "$tf_end" ]; then
            rm -f "$KIT/logs/ENTRY-$token".*
            exit 0
        fi
        /system/bin/toybox sleep 0.5 >/dev/null 2>&1 </dev/null
    done
    rm -f "$KIT/logs/ENTRY-$token.go" "$KIT/logs/ENTRY-$token.ready"
fi
print -r -- 'STARTED' >"$KIT/logs/ENTRY-$token.started" || exit 3
/system/bin/sh "$KIT/installer/launch-game.sh"
result=$?
print -r -- "$result" >"$KIT/logs/ENTRY-$token.tmp" || exit 4
mv "$KIT/logs/ENTRY-$token.tmp" "$KIT/logs/ENTRY-$token.done" || exit 4
exit "$result"
