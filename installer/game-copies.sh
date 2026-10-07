#!/bin/sh
# Functions only; needs discover-game.sh loaded first.
# For when the game is installed in more than one GameHub container (GameHub
# can make a new container and keep the old one's folder after a reinstall).
# The start screen shows a note about the extra copies. It never deletes
# them: on the device, a delete aimed at another container from inside
# GameHub removed files elsewhere (Download/Thor-Forever/logs) instead.

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
