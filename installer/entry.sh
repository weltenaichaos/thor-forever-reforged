#!/system/bin/sh
KIT=/sdcard/Download/Thor-Forever
case "${1-}" in ''|*[!0-9-]*) exit 2 ;; esac
token=$1
[ "${#token}" -le 80 ] || exit 2
export TF_ENTRY_TOKEN="$token"
# Thor-Forever.exe creates logs/ before starting this script.
[ -d "$KIT/logs" ] || mkdir "$KIT/logs" >/dev/null 2>&1 </dev/null
exec >"$KIT/logs/ENTRY-$token.log" 2>&1 </dev/null
print -r -- 'STARTED' >"$KIT/logs/ENTRY-$token.started" || exit 3
/system/bin/sh "$KIT/installer/launch-game.sh"
result=$?
print -r -- "$result" >"$KIT/logs/ENTRY-$token.tmp" || exit 4
mv "$KIT/logs/ENTRY-$token.tmp" "$KIT/logs/ENTRY-$token.done" || exit 4
exit "$result"
