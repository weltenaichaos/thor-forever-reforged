#!/bin/sh
# Functions only; needs discover-game.sh and stage-game.sh loaded first.
# For when the game is installed in more than one GameHub container (GameHub
# can make a new container and keep the old one's folder after a reinstall).
# The start screen shows the extra copies and can remove one on request.

# tf_scan_copies USR CONTAINER OUT writes, through OUT.tmp, one line per copy
# when there is more than one, or leftovers (and removes OUT otherwise):
#   HERE <name>       the copy in CONTAINER, the container this launch runs in
#   OTHER <name>      a copy in another container, which could be removed
#   ELSEWHERE <name>  a copy, while CONTAINER itself has none
#   LEFTOVER <name>   a World of Warcraft folder without the game in another
#                     container (a half-removed copy), while CONTAINER has one
# <name> is the container's folder name under home/virtual_containers.
tf_scan_copies()
{
    tf_out=$3
    rm -f "$tf_out" "$tf_out.tmp"
    tf_discover_game "$1" "$2"
    tf_boxes="$1/home/virtual_containers/"
    tf_here_has=0
    [ -n "$2" ] && case "$TF_GAME_DIR" in "${2%/}/"*) tf_here_has=1 ;; esac
    {
        [ "$TF_GAME_COUNT" -ge 2 ] && tf_list_copies "$2"
        [ "$tf_here_has" = 1 ] && tf_list_leftovers "$2"
    } >"$tf_out.tmp"
    if [ -s "$tf_out.tmp" ]; then mv -f "$tf_out.tmp" "$tf_out"; else rm -f "$tf_out.tmp"; fi
    return 0
}

tf_list_leftovers()
{
    for tf_box in "$tf_boxes"*; do
        [ -d "$tf_box" ] && [ ! -L "$tf_box" ] && [ "$tf_box" != "${1%/}" ] || continue
        for tf_programs in 'Program Files (x86)' 'Program Files'; do
            tf_wow="$tf_box/drive_c/$tf_programs/World of Warcraft"
            [ -d "$tf_wow" ] && [ ! -L "$tf_wow" ] || continue
            case "
$TF_GAME_LIST" in *"
$tf_wow/_classic_beta_
"*) continue ;; esac
            print -r -- "LEFTOVER ${tf_box#"$tf_boxes"}"
            break
        done
    done
}

tf_list_copies()
{
    while IFS= read -r tf_copy; do
        [ -n "$tf_copy" ] || continue
        tf_name=${tf_copy#"$tf_boxes"}
        tf_name=${tf_name%%/*}
        if [ "$TF_DISCOVERY_STATUS" != preferred ]; then
            print -r -- "ELSEWHERE $tf_name"
        elif [ "$tf_boxes$tf_name" = "${1%/}" ]; then
            print -r -- "HERE $tf_name"
        else
            print -r -- "OTHER $tf_name"
        fi
    done <<TF_LIST
$TF_GAME_LIST
TF_LIST
}

# tf_remove_copy USR CONTAINER NAME GAME deletes the World of Warcraft folder
# (a copy or leftovers) in container NAME. Only when CONTAINER (this launch's
# container) has a copy of its own, NAME is a different container, and the staged game
# GAME (may be missing) no longer links into the copy being removed. Never
# deletes anything outside <NAME>/drive_c/<Program Files>/World of Warcraft,
# and never the container itself: GameHub manages those.
tf_remove_copy() (
    tf_usr=$1
    tf_here=${2%/}
    tf_name=$3
    tf_game=$4
    case "$tf_name" in ''|.|..|*/*) exit 2 ;; esac
    [ -n "$tf_here" ] || exit 3
    tf_discover_game "$tf_usr" "$tf_here" || exit 3
    case "$TF_GAME_DIR" in "$tf_here/"*) ;; *) exit 3 ;; esac
    tf_box="$tf_usr/home/virtual_containers/$tf_name"
    [ "$tf_box" != "$tf_here" ] || exit 4
    [ -d "$tf_box" ] && [ ! -L "$tf_box" ] || exit 5
    if [ -d "$tf_game" ]; then
        tf_follow_install "$TF_GAME_DIR" "$tf_game" || exit 6
    fi
    tf_found=0
    for tf_programs in 'Program Files (x86)' 'Program Files'; do
        tf_wow="$tf_box/drive_c/$tf_programs/World of Warcraft"
        # Never through a link on the way there.
        [ -d "$tf_wow" ] && [ ! -L "$tf_box/drive_c" ] && [ ! -L "$tf_box/drive_c/$tf_programs" ] &&
            [ ! -L "$tf_wow" ] || continue
        for tf_link in "$tf_game/../Data" "$tf_game/Data" "$tf_game/Interface"; do
            [ -L "$tf_link" ] || continue
            [ "$tf_link" -ef "$tf_wow/Data" ] || [ "$tf_link" -ef "$tf_wow/_classic_beta_/Data" ] ||
                [ "$tf_link" -ef "$tf_wow/_classic_beta_/Interface" ] && exit 7
        done
        # Wine turns the Windows read-only flag into a folder without write
        # permission, and rm cannot delete what is inside such a folder.
        # So if the first try leaves files behind, make everything writable
        # (it is all being deleted anyway) and try again.
        /system/bin/toybox rm -rf "$tf_wow"
        if [ -e "$tf_wow" ]; then
            print -r -- 'Some files were left; making them writable and trying again.'
            /system/bin/toybox chmod -R u+rwx "$tf_wow"
            /system/bin/toybox rm -rf "$tf_wow"
        fi
        if [ -e "$tf_wow" ]; then
            print -r -- "Could not delete everything in $tf_wow. Left over:"
            /system/bin/toybox ls -la "$tf_wow" "$tf_wow/_classic_beta_"
            exit 8
        fi
        tf_found=1
    done
    [ "$tf_found" = 1 ] || exit 9
    print -r -- "REMOVED: the game copy in container $tf_name."
)

# tf_copy_sizes USR OUT writes, through OUT.tmp, "SIZE <KiB> <name>" for each
# OTHER copy listed in the file tf_scan_copies wrote (COPIES). Slow on a full
# game, so the caller runs it in the background. du's output is read with
# shell builtins and only number lines count: GameHub's process wrapper can
# add its own text to an external command's output.
tf_copy_sizes()
{
    tf_usr=$1
    tf_copies=$2
    tf_out=$3
    : >"$tf_out.tmp" || return 1
    while read -r tf_kind tf_name; do
        [ "$tf_kind" = OTHER ] || [ "$tf_kind" = LEFTOVER ] || continue
        tf_kb=0
        for tf_programs in 'Program Files (x86)' 'Program Files'; do
            tf_wow="$tf_usr/home/virtual_containers/$tf_name/drive_c/$tf_programs/World of Warcraft"
            [ -d "$tf_wow" ] && [ ! -L "$tf_wow" ] || continue
            /system/bin/toybox du -sk "$tf_wow" >"$tf_out.du" 2>/dev/null </dev/null
            while read -r tf_size tf_rest; do
                case "$tf_size" in ''|*[!0-9]*) continue ;; esac
                tf_kb=$((tf_kb + tf_size))
            done <"$tf_out.du"
        done
        print -r -- "SIZE $tf_kb $tf_name" >>"$tf_out.tmp"
    done <"$tf_copies"
    rm -f "$tf_out.du"
    mv -f "$tf_out.tmp" "$tf_out"
}
