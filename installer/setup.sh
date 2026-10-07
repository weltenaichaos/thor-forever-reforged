#!/system/bin/sh
# KIT is the Thor-Forever folder this script was started from (any folder in
# shared storage, Download/Thor-Forever by default).
case "$0" in /*/installer/*.sh) KIT=${0%/installer/*} ;; *) exit 2 ;; esac
case "$KIT" in *[!A-Za-z0-9/._-]*|*/../*|*/./*|*/..|*/.) exit 2 ;; esac
OUT="$KIT/setup-report"
mkdir "$OUT" || exit 2
exec >"$OUT/setup.log" 2>&1 </dev/null
USR=/data/user/0/com.ludashi.aibench/files/usr
case "${WINEPREFIX-}" in
    /data/user/*/com.ludashi.aibench/files/usr/*) USR=${WINEPREFIX%%/files/usr/*}/files/usr ;;
esac
case "$USR" in *'/../'*|*'/./'*|*/..|*/.) exit 3 ;; esac
INSTALL="$USR/home/thor-forever/release-v1"
if [ -e "$INSTALL" ] || [ -L "$INSTALL" ]; then
    print -r -- 'STOPPED: an installation or unfinished attempt already exists. Nothing overwritten.' >"$OUT/result.txt"
    exit 4
fi
print -r -- 'RUNNING: leave the container open.' >"$OUT/result.txt"
/system/bin/sh "$KIT/installer/install-components.sh" --install-components
result=$?
for report in result.txt install.log; do
    [ -f "$INSTALL/$report" ] && [ ! -L "$INSTALL/$report" ] || continue
    cp "$INSTALL/$report" "$OUT/$report"
done
print -r -- "INSTALLER_EXIT=$result" >>"$OUT/result.txt"
if [ "$result" = 0 ]; then
    print -r -- 'Preparation finished. Open Thor-Forever.exe to test the game.' >>"$OUT/result.txt"
else
    print -r -- 'STOPPED. Keep this report. Do not delete or overwrite the attempt.' >>"$OUT/result.txt"
fi
exit "$result"
