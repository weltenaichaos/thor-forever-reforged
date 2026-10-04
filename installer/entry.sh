#!/system/bin/sh
KIT=/sdcard/Download/Thor-Forever
case "${1-}" in ''|*[!0-9-]*) exit 2 ;; esac
token=$1
[ "${#token}" -le 80 ] || exit 2
export TF_ENTRY_TOKEN="$token"
exec >"$KIT/ENTRY-$token.log" 2>&1 </dev/null
print -r -- 'STARTED' >"$KIT/ENTRY-$token.started" || exit 3
/system/bin/sh "$KIT/installer/launch-game.sh"
result=$?
print -r -- "$result" >"$KIT/ENTRY-$token.tmp" || exit 4
mv "$KIT/ENTRY-$token.tmp" "$KIT/ENTRY-$token.done" || exit 4
exit "$result"
