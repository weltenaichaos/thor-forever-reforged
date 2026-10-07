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

# After a game update (Battle.net patches the original installation), copy the
# new executable files and build metadata into the staged game, the same set
# tf_stage_game copied. Data is shared and already up to date; WTF, Cache and
# Interface are left alone. Each file goes to a temporary name first, so an
# interrupted copy never leaves a half-written executable behind.
tf_refresh_game() (
    tf_source=$1
    tf_game=$2
    tf_stage=${tf_game%/*}
    [ -s "$tf_source/WowB-ARM64.exe" ] && [ ! -L "$tf_source/WowB-ARM64.exe" ] || exit 52
    [ -d "$tf_game" ] && [ ! -L "$tf_game" ] && [ ! -L "$tf_stage" ] || exit 54
    tf_copy() {
        [ ! -L "$1" ] && [ -f "$1" ] && [ ! -L "$2" ] || return 1
        cp "$1" "$2.new" && cmp -s "$1" "$2.new" && mv -f "$2.new" "$2" || { rm -f "$2.new"; return 1; }
    }
    for tf_file in "$tf_source/"*.exe "$tf_source/"*.dll "$tf_source/"*.sig "$tf_source/.flavor.info"; do
        [ -e "$tf_file" ] || [ -L "$tf_file" ] || continue
        tf_copy "$tf_file" "$tf_game/${tf_file##*/}" || exit 59
    done
    for tf_file in .build.info .flavor.info; do
        [ -e "$tf_source/../$tf_file" ] || [ -L "$tf_source/../$tf_file" ] || continue
        tf_copy "$tf_source/../$tf_file" "$tf_stage/$tf_file" || exit 59
    done
    cmp -s "$tf_source/WowB-ARM64.exe" "$tf_game/WowB-ARM64.exe" || exit 59
)

# After the game was reinstalled into another GameHub container, the staged
# game's links to Data and Interface still point into the old container
# (or nowhere, once it is deleted). Point them at the installation found
# now. Only links are changed; real folders are never touched. Prints what
# it changed.
tf_follow_install() (
    tf_source=$1
    tf_game=$2
    tf_stage=${tf_game%/*}
    tf_relink() {
        # $1 = link in the staged game, $2 = folder it should point to
        [ -L "$1" ] || return 0
        [ "$1" -ef "$2" ] && return 0
        [ -d "$2" ] && [ ! -L "$2" ] || return 1
        rm -f "$1" && ln -s "$2" "$1" || return 1
        print -r -- "RELINKED: ${1##*/} now uses the installation in this container."
    }
    if [ -L "$tf_stage/Data" ]; then
        tf_relink "$tf_stage/Data" "$tf_source/../Data" || exit 90
    elif [ -L "$tf_game/Data" ]; then
        tf_relink "$tf_game/Data" "$tf_source/Data" || exit 90
    fi
    # A fresh installation has no Interface folder yet.
    if [ -L "$tf_game/Interface" ] && [ ! -e "$tf_source/Interface" ] && [ ! -L "$tf_source/Interface" ]; then
        mkdir -p "$tf_source/Interface/AddOns" || exit 91
    fi
    tf_relink "$tf_game/Interface" "$tf_source/Interface" || exit 91
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
        # Compare by file identity, not readlink output: GameHub's process
        # wrapper can add its own text to an external command's output.
        [ "$tf_game/Interface" -ef "$tf_target" ] && exit 0
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

# Copy addons the player dropped into shared storage (Download/Thor-Forever/
# AddOns/<Name>/<Name>.toc) into the game's Interface\AddOns, replacing the
# installed copy of each one. Folders without a matching .toc, and links, are
# skipped. Other installed addons are never touched. Prints one line per addon.
tf_sync_addons() (
    tf_from=$1
    tf_to=$2
    [ -d "$tf_from" ] && [ ! -L "$tf_from" ] || exit 0
    [ ! -L "$tf_to" ] || exit 80
    mkdir -p "$tf_to" || exit 81
    for tf_dir in "$tf_from"/*; do
        [ -d "$tf_dir" ] && [ ! -L "$tf_dir" ] || continue
        tf_name=${tf_dir##*/}
        case "$tf_name" in ''|.*|*[!A-Za-z0-9_.-]*) continue ;; esac
        [ -f "$tf_dir/$tf_name.toc" ] || { print -r -- "ADDON SKIPPED: $tf_name (no $tf_name.toc)"; continue; }
        rm -rf "$tf_to/.$tf_name.new" &&
            cp -R "$tf_dir" "$tf_to/.$tf_name.new" &&
            rm -rf "$tf_to/$tf_name" &&
            mv "$tf_to/.$tf_name.new" "$tf_to/$tf_name" ||
            { print -r -- "ADDON FAILED: $tf_name"; continue; }
        print -r -- "ADDON COPIED: $tf_name"
    done
)
