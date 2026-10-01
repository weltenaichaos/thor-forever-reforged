#!/system/bin/sh
# Internal library: caller supplies its dedicated, initialized installation root.
# Never run Battle.net against this layout: CASC Data is shared, not read-only.
tf_stage_game() (
    tf_source=$1
    tf_install=$2
    tf_template=$3
    tf_stage="$tf_install/game"
    tf_game="$tf_stage/_classic_beta_"
    # Check ancestors, not only the final directory. Platform aliases above the
    # app's home are handled by the component installer, not followed here.
    for tf_path in "$tf_install" "$tf_source"; do
        case "$tf_path" in *'/../'*|*'/./'*|*/..|*/.) exit 50 ;; esac
        while [ -n "$tf_path" ] && [ "$tf_path" != / ]; do
            [ ! -L "$tf_path" ] || exit 50
            case "$tf_path" in */home) break ;; esac
            case "$tf_path" in */*) tf_path=${tf_path%/*} ;; *) break ;; esac
        done
    done
    [ -s "$tf_install/components-ready" ] && [ ! -L "$tf_install/components-ready" ] || exit 51
    [ -s "$tf_source/WowB-ARM64.exe" ] && [ ! -L "$tf_source/WowB-ARM64.exe" ] || exit 52
    [ -s "$tf_template" ] && [ ! -L "$tf_template" ] || exit 53
    [ ! -e "$tf_stage" ] && [ ! -L "$tf_stage" ] || exit 54
    if [ -d "$tf_source/../Data" ] && [ ! -L "$tf_source/../Data" ]; then
        tf_data="$tf_source/../Data"
        tf_data_dest="$tf_stage/Data"
    elif [ -d "$tf_source/Data" ] && [ ! -L "$tf_source/Data" ]; then
        tf_data="$tf_source/Data"
        tf_data_dest="$tf_game/Data"
    else
        exit 55
    fi
    # Refuse suspicious executable/metadata links rather than silently omitting
    # one and producing an incomplete game. Never copy WTF, Account or caches.
    for tf_file in "$tf_source/"*.exe "$tf_source/"*.dll "$tf_source/"*.sig "$tf_source/.flavor.info" "$tf_source/../.build.info" "$tf_source/../.flavor.info"; do
        [ ! -L "$tf_file" ] || exit 56
        [ ! -e "$tf_file" ] || [ -f "$tf_file" ] || exit 56
    done
    mkdir "$tf_stage" || exit 57
    mkdir "$tf_game" "$tf_game/WTF" || exit 58
    for tf_file in "$tf_source/"*.exe "$tf_source/"*.dll "$tf_source/"*.sig "$tf_source/.flavor.info"; do
        [ -f "$tf_file" ] || continue
        cp "$tf_file" "$tf_game/${tf_file##*/}" || exit 59
        cmp -s "$tf_file" "$tf_game/${tf_file##*/}" || exit 59
    done
    for tf_file in .build.info .flavor.info; do
        [ -f "$tf_source/../$tf_file" ] || continue
        cp "$tf_source/../$tf_file" "$tf_stage/$tf_file" || exit 59
        cmp -s "$tf_source/../$tf_file" "$tf_stage/$tf_file" || exit 59
    done
    ln -s "$tf_data" "$tf_data_dest" || exit 60
    tf_link_interface "$tf_source" "$tf_game" || exit 63
    cp "$tf_template" "$tf_game/WTF/Config-Thor-Forever.wtf" || exit 61
    cmp -s "$tf_template" "$tf_game/WTF/Config-Thor-Forever.wtf" || exit 61
    print -r -- 'GAME_STAGED' >"$tf_install/game-ready" || exit 62
    print -r -- 'Separate game settings prepared. Shared Data is not read-only.'
)

# Make the staged game use the original installation's Interface folder, so
# addons installed the normal way (Interface\AddOns next to WowB-ARM64.exe in
# the GameHub container) are the ones the game loads. Creates the original
# Interface\AddOns if missing. A real Interface folder already in the staged
# game is never replaced. Called at staging and again at every launch, so
# installations staged before this existed are linked without reinstalling.
tf_link_interface() (
    tf_source=$1
    tf_game=$2
    tf_target="$tf_source/Interface"
    [ ! -L "$tf_target" ] || exit 70
    if [ -L "$tf_game/Interface" ]; then
        [ "$(readlink "$tf_game/Interface")" = "$tf_target" ] && exit 0
        exit 71
    fi
    # The client can create an empty Interface\AddOns of its own; rmdir only
    # removes empty folders, so anything with content is still left alone.
    if [ -d "$tf_game/Interface" ]; then
        rmdir "$tf_game/Interface/AddOns" 2>/dev/null
        rmdir "$tf_game/Interface" 2>/dev/null
    fi
    [ ! -e "$tf_game/Interface" ] || exit 72
    mkdir -p "$tf_target/AddOns" || exit 73
    ln -s "$tf_target" "$tf_game/Interface" || exit 74
)
