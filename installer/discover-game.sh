#!/system/bin/sh
# Functions only. No scanning or writes occur when this file is loaded.
# tf_discover_game USR_ROOT checks supported layouts without following directory
# symlinks, executing configuration, or choosing silently between installations.
tf_discover_game()
{
    tf_root=$1
    TF_GAME_DIR=
    TF_GAME_COUNT=0
    # Every installation found, one per line, for the error message.
    TF_GAME_LIST=
    TF_DISCOVERY_STATUS=missing
    [ -d "$tf_root/home/virtual_containers" ] || return 10
    for tf_container in "$tf_root/home/virtual_containers/"*; do
        [ -d "$tf_container" ] && [ ! -L "$tf_container" ] || continue
        for tf_programs in 'Program Files (x86)' 'Program Files'; do
            tf_candidate="$tf_container/drive_c/$tf_programs/World of Warcraft/_classic_beta_"
            # Never walk a redirected directory outside the inspected container.
            tf_safe=1
            for tf_part in "$tf_container/drive_c" "$tf_container/drive_c/$tf_programs" \
                "$tf_container/drive_c/$tf_programs/World of Warcraft" "$tf_candidate"; do
                [ ! -L "$tf_part" ] || tf_safe=0
            done
            [ "$tf_safe" = 1 ] || continue
            [ -f "$tf_candidate/WowB-ARM64.exe" ] && [ ! -L "$tf_candidate/WowB-ARM64.exe" ] || continue
            [ -s "$tf_candidate/WowB-ARM64.exe" ] || continue
            TF_GAME_COUNT=$((TF_GAME_COUNT + 1))
            TF_GAME_DIR=$tf_candidate
            TF_GAME_LIST="$TF_GAME_LIST$tf_candidate
"
        done
    done
    case "$TF_GAME_COUNT" in
        0) return 10 ;;
        1) TF_DISCOVERY_STATUS=found; return 0 ;;
        *) TF_GAME_DIR=; TF_DISCOVERY_STATUS=multiple; return 11 ;;
    esac
}
