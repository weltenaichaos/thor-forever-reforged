#!/bin/sh
# Functions only; needs discover-game.sh loaded first. Read-only.
# tf_install_state USR CONTAINER KIT writes, for the start screen, what it
# needs to offer Play, Install or Repair:
#   STATE installed|missing|broken
#   GAME found|missing|multiple     the game in this GameHub container
#   PAYLOAD ok | PAYLOAD missing <file> ...  install files in KIT/payload
#   OLD <n>                         earlier installations set aside by Repair
# The free storage is left out: df can be slow, and the installer checks it.
tf_install_state()
{
    tf_state_root="$1/home/thor-forever/release-v1"
    if [ ! -e "$tf_state_root" ] && [ ! -L "$tf_state_root" ]; then
        print -r -- 'STATE missing'
    elif [ ! -L "$tf_state_root" ] && [ -s "$tf_state_root/components-ready" ] && [ -s "$tf_state_root/game-ready" ] &&
        [ -s "$tf_state_root/prefix/system.reg" ] && [ -s "$tf_state_root/game/_classic_beta_/WowB-ARM64.exe" ] &&
        [ ! -e "$3/repair" ] && [ ! -e "$3/repair.txt" ]; then
        # A file named "repair" (or repair.txt) in Download/Thor-Forever
        # offers Repair even for a working installation (to redo it, or to
        # test it).
        print -r -- 'STATE installed'
    else
        # An unfinished or damaged installation (the same checks as
        # launch-game.sh makes before starting the game).
        print -r -- 'STATE broken'
    fi
    tf_discover_game "$1" "$2"
    case "$TF_DISCOVERY_STATUS" in
        found|preferred) print -r -- 'GAME found' ;;
        multiple) print -r -- 'GAME multiple' ;;
        *) print -r -- 'GAME missing' ;;
    esac
    tf_missing=
    for tf_file in wine-runtime.tar d3d11.dll dxgi.dll libandroid-sysvshm.so libvulkan_freedreno.so libGL.so.1 trace.so; do
        [ -s "$3/payload/$tf_file" ] || tf_missing="$tf_missing $tf_file"
    done
    if [ -n "$tf_missing" ]; then print -r -- "PAYLOAD missing$tf_missing"; else print -r -- 'PAYLOAD ok'; fi
    tf_old=0
    for tf_dir in "$tf_state_root".old-*; do
        [ -d "$tf_dir" ] && tf_old=$((tf_old + 1))
    done
    print -r -- "OLD $tf_old"
}
