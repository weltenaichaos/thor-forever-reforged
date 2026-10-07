#!/system/bin/sh
# Installs (or repairs) Thor Forever for the start screen, from the waiting
# bridge in installer/entry.sh. Usage: start-install.sh install|repair OUT
# While it runs, OUT.phase holds the installer's current phase. At the end
# OUT holds the result code, then lines for the start screen to show.
# Repair never deletes anything: the damaged installation is renamed to
# release-v1.old-<n> (it can be deleted by hand later), a fresh one is made,
# and the game settings (WTF) are copied over from the old one.
KIT=/sdcard/Download/Thor-Forever
mode=$1
out=$2
case "$mode" in install|repair) ;; *) exit 2 ;; esac
case "$out" in "$KIT/logs/"*) ;; *) exit 2 ;; esac
USR=/data/user/0/com.ludashi.aibench/files/usr
case "${WINEPREFIX-}" in
    /data/user/*/com.ludashi.aibench/files/usr/*) USR=${WINEPREFIX%%/files/usr/*}/files/usr ;;
esac
case "$USR" in *'/../'*|*'/./'*|*/..|*/.) exit 3 ;; esac
INSTALL="$USR/home/thor-forever/release-v1"
finish()
{
    tf_code=$1
    {
        print -r -- "$tf_code"
        shift
        for tf_line in "$@"; do print -r -- "$tf_line"; done
        # On failure, the installer's own short report, when it got that far.
        if [ "$tf_code" != 0 ] && [ -f "$INSTALL/result.txt" ] && [ ! -L "$INSTALL/result.txt" ]; then
            while IFS= read -r tf_line; do print -r -- "$tf_line"; done <"$INSTALL/result.txt"
        fi
    } >"$out.tmp" && mv -f "$out.tmp" "$out"
    exit "$tf_code"
}
old=
if [ "$mode" = repair ] && { [ -e "$INSTALL" ] || [ -L "$INSTALL" ]; }; then
    [ ! -L "$INSTALL" ] || finish 4 'The installation folder is a link; not touched.'
    n=1
    while [ -e "$INSTALL.old-$n" ] || [ -L "$INSTALL.old-$n" ]; do
        n=$((n + 1))
        [ "$n" -le 99 ] || finish 4 'Too many old installations are set aside already.'
    done
    mv "$INSTALL" "$INSTALL.old-$n" || finish 4 'Could not set the damaged installation aside.'
    old="$INSTALL.old-$n"
    print -r -- "Set the old installation aside as ${old##*/}."
fi
if [ -e "$INSTALL" ] || [ -L "$INSTALL" ]; then
    finish 4 'Thor Forever is already installed. Use Repair if it does not start.'
fi
TF_PROGRESS_FILE="$out.phase" /system/bin/sh "$KIT/installer/install-components.sh" --install-components \
    >"$out.why" 2>&1 </dev/null
result=$?
why=
while IFS= read -r tf_line; do why="$why$tf_line "; done <"$out.why"
rm -f "$out.why" "$out.phase"
[ "$result" = 0 ] || finish "$result" "$why"
# Keep the player's game settings, key bindings and macros from before.
if [ -n "$old" ] && [ -d "$old/game/_classic_beta_/WTF" ] && [ ! -L "$old/game/_classic_beta_/WTF" ]; then
    cp -R "$old/game/_classic_beta_/WTF/." "$INSTALL/game/_classic_beta_/WTF/" ||
        finish 0 'Installed, but the old game settings could not be copied over.'
    finish 0 "Repaired. Your game settings were copied over; the old installation is kept as ${old##*/}."
fi
finish 0 'Installed.'
