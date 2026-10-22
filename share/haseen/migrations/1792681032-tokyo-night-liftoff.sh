# shellcheck shell=bash
# Plan 106: theme images are pinned at Omarchy v4.5.0-rc1 now, where Liftoff
# leads Tokyo Night and every other background moved up a number
# (0-winding-road.webp became 1-winding-road.webp, Omarchy 097c733fc). The
# cached copies are renamed, since the bytes are the same, so nothing is
# downloaded twice and the picker lists no duplicates; a copy already fetched
# under the new name makes the old one a duplicate, which is removed.
# current/background and the remembered Tokyo Night background follow the
# rename (as Omarchy's b7c60feb1 keeps picks). A file whose bytes are not the
# pinned image stays where it is. Safe to re-run: once renamed, nothing is
# left to move.

# shellcheck source=../lib/common.sh
source "$HASEEN_PATH/lib/common.sh"
# shellcheck source=../layers/theme/theme-lib.sh
source "$HASEEN_PATH/layers/theme/theme-lib.sh"

dir="$THEME_CACHE_DIR/tokyo-night/backgrounds"
[[ -d $dir ]] || exit 0

declare -A renumbered=(
    [0-winding-road.webp]=1-winding-road.webp
    [1-quattro.webp]=2-quattro.webp
    [2-swirl-buck.webp]=3-swirl-buck.webp
    [3-sunset-lake.webp]=4-sunset-lake.webp
    [4-omakub.webp]=5-omakub.webp
    [5-oma-cityscape.jpg]=6-oma-cityscape.jpg
    [6-oma.webp]=7-oma.webp
)
declare -A pinned=()
while read -r sha _ rel; do
    pinned[${rel#backgrounds/}]="$sha"
done < <(theme_assets tokyo-night)

# follow OLD NEW — a link or record naming OLD names NEW from now on.
follow() {
    local link
    link="$(readlink "$THEME_BACKGROUND_LINK" 2>/dev/null || true)"
    if [[ $link == "$1" ]]; then
        theme_set_background_link "$2"
    fi
    if theme_bg_memory_file tokyo-night && [[ -r $REPLY && $(head -n1 -- "$REPLY") == "$1" ]]; then
        printf '%s\n' "$2" | replace_user_file "$REPLY"
    fi
}

for old in "${!renumbered[@]}"; do
    new="${renumbered[$old]}"
    [[ -f $dir/$old && ! -L $dir/$old && -n ${pinned[$new]:-} ]] || continue
    [[ $(sha256sum -- "$dir/$old" | cut -d' ' -f1) == "${pinned[$new]}" ]] || continue
    if [[ ! -e $dir/$new && ! -L $dir/$new ]]; then
        mv -T -- "$dir/$old" "$dir/$new"
    elif [[ -f $dir/$new && ! -L $dir/$new ]] && cmp -s -- "$dir/$old" "$dir/$new"; then
        rm -f -- "$dir/$old"
    else
        continue
    fi
    follow "$dir/$old" "$dir/$new"
done
