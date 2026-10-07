# shellcheck shell=bash disable=SC2034  # the WH_* settings are read by bin/haseen-wallhaven-*
# wallhaven.sh — the Wallhaven API v1 client shared by bin/haseen-wallhaven-*
# (plan 072). Sourced after common.sh.
#
# https://wallhaven.cc/help/api: GET /api/v1/search and /api/v1/w/<id>, 24
# results a page, 45 API calls a minute (429 beyond). Guests see SFW only; an
# API key (the X-API-Key header) unlocks sketchy/NSFW and the user's own
# filters. haseen sends purity 100 (SFW) unless the user has put a key in
# ~/.config/haseen/wallhaven.key (mode 600) and asks for more.
#
# The search defaults follow Aether's wallhaven client (bjarneo/aether
# internal/wallhaven/client.go: categories 111, purity 100, order desc;
# frontend store: atleast 1920x1080), except the sorting: toplist instead of
# date_added, and atleast is the focused monitor's own size.

WH_API="https://wallhaven.cc/api/v1"
WH_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/haseen/wallhaven"
WH_THUMBS="$WH_CACHE/thumbs"
WH_KEY_FILE="$HASEEN_USER_CONFIG/wallhaven.key"
WH_DEST="$HASEEN_USER_CONFIG/backgrounds/wallhaven"
WH_UA="haseen/$(cat "$HASEEN_PATH/VERSION" 2>/dev/null || echo dev) (+https://github.com/t1nk333r/haseen)"
WH_SORTS=(toplist date_added random relevance views favorites)
WH_RANGES=(1d 3d 1w 1M 3M 6M 1y)
WH_RATE=45
# Aether's limits: 50 MiB for a wallpaper, 5 MiB for a thumbnail.
WH_MAX_IMAGE=$((50 << 20))
WH_MAX_THUMB=$((5 << 20))
# The thumbnail cache: files unused for a week go, and never more than this.
WH_THUMB_DAYS=7
WH_THUMB_MAX=600

# wh_key — REPLY = the API key, or empty. A key readable by others is not
# used (it would leak to every local user), and the key itself is never
# printed.
wh_key() {
    REPLY=""
    [[ -f $WH_KEY_FILE ]] || return 0
    local mode key
    mode="$(stat -c %a -- "$WH_KEY_FILE")"
    if [[ $mode != 600 && $mode != 400 ]]; then
        warn "ignoring $WH_KEY_FILE: mode $mode, it must be 600 (chmod 600 $WH_KEY_FILE)"
        return 0
    fi
    key="$(tr -d '[:space:]' <"$WH_KEY_FILE")"
    if [[ ! $key =~ ^[A-Za-z0-9]+$ ]]; then
        warn "ignoring $WH_KEY_FILE: not an API key"
        return 0
    fi
    REPLY=$key
}

# wh_rate — refuse a call that would pass 45 API calls in the last minute,
# counted in a log of timestamps under the cache. The panel pages on scroll,
# so a fast scroll could otherwise earn a 429 for every later call.
wh_rate() {
    local log="$WH_CACHE/calls" now kept=() t
    mkdir -p -- "$WH_CACHE"
    now="$(date +%s)"
    exec 8>>"$log.lock"
    flock 8
    if [[ -f $log ]]; then
        while read -r t; do
            [[ $t =~ ^[0-9]+$ ]] && ((t > now - 60)) && kept+=("$t")
        done <"$log"
    fi
    if ((${#kept[@]} >= WH_RATE)); then
        exec 8>&-
        die "wallhaven allows $WH_RATE calls a minute; try again in $((kept[0] + 60 - now)) s"
    fi
    kept+=("$now")
    printf '%s\n' "${kept[@]}" >"$log"
    exec 8>&-
}

# wh_api PATH_AND_QUERY — print the API's JSON body. The key goes in a
# header read from a private file, so it is on no command line and in no URL.
wh_api() {
    local url="$WH_API/$1" hdr body status=0
    wh_rate
    hdr="$(mktemp)"
    body="$(mktemp)"
    wh_key
    [[ -z $REPLY ]] || printf 'X-API-Key: %s\n' "$REPLY" >"$hdr"
    local code
    code="$(curl --silent --show-error --proto '=https' --max-time 20 --connect-timeout 10 \
        --user-agent "$WH_UA" --header "@$hdr" --max-filesize $((4 << 20)) \
        --output "$body" --write-out '%{http_code}' -- "$url")" || status=$?
    rm -f -- "$hdr"
    if ((status != 0)); then
        rm -f -- "$body"
        die "wallhaven did not answer (curl exit $status)"
    fi
    case $code in
    200) ;;
    429) rm -f -- "$body" && die "wallhaven: too many requests (45 a minute); try again shortly" ;;
    401) rm -f -- "$body" && die "wallhaven refused the request (401): sketchy and NSFW need a valid key in $WH_KEY_FILE" ;;
    404) rm -f -- "$body" && die "wallhaven has no such wallpaper" ;;
    *) rm -f -- "$body" && die "wallhaven answered HTTP $code" ;;
    esac
    jq -e . "$body" >/dev/null 2>&1 || {
        rm -f -- "$body"
        die "wallhaven sent something that is not JSON"
    }
    cat -- "$body"
    rm -f -- "$body"
}

# wh_atleast — REPLY = the focused monitor's size (WxH; a rotated monitor
# swapped), read-only from hyprctl; 1920x1080 (Aether's default) without one.
wh_atleast() {
    REPLY=1920x1080
    local size
    size="$(hyprctl -j monitors 2>/dev/null | jq -r '
        (map(select(.focused)) + .)[0] // empty
        | if (.transform % 2) == 1 then "\(.height)x\(.width)" else "\(.width)x\(.height)" end' 2>/dev/null)" || return 0
    [[ $size =~ ^[1-9][0-9]*x[1-9][0-9]*$ ]] && REPLY=$size
    return 0
}

# wh_is_image FILE — true when FILE's bytes are a JPEG, PNG or WebP.
wh_is_image() {
    case "$(file --brief --mime-type -- "$1" 2>/dev/null)" in
    image/jpeg | image/png | image/webp) return 0 ;;
    *) return 1 ;;
    esac
}

# wh_prune_thumbs — drop thumbnails unused for WH_THUMB_DAYS, then the oldest
# beyond WH_THUMB_MAX. A cache hit is touched, so "unused" is real.
wh_prune_thumbs() {
    [[ -d $WH_THUMBS ]] || return 0
    find "$WH_THUMBS" -maxdepth 1 -type f -mtime +"$((WH_THUMB_DAYS - 1))" -delete
    find "$WH_THUMBS" -maxdepth 1 -type f -printf '%T@ %p\n' | sort -rn | tail -n +$((WH_THUMB_MAX + 1)) |
        cut -d' ' -f2- | while IFS= read -r f; do rm -f -- "$f"; done
}

# wh_thumbs < "ID<TAB>URL" lines — cache each small thumbnail as
# thumbs/<id>.<ext> in one parallel curl; prints "ID<TAB>PATH" for each one
# present afterwards. A file that is not an image is deleted.
wh_thumbs() {
    local id url ext want=() ids=() cfg
    mkdir -p -- "$WH_THUMBS"
    cfg="$(mktemp)"
    while IFS=$'\t' read -r id url; do
        [[ $id =~ ^[a-z0-9]+$ && $url =~ ^https://th\.wallhaven\.cc/[a-z]+/[a-z0-9]+/[a-z0-9]+\.(jpg|png|webp)$ ]] || continue
        ext="${url##*.}"
        ids+=("$id"$'\t'"$WH_THUMBS/$id.$ext")
        if [[ -s $WH_THUMBS/$id.$ext ]]; then
            touch -- "$WH_THUMBS/$id.$ext"
            continue
        fi
        want+=("$id")
        printf 'url = "%s"\noutput = "%s"\n' "$url" "$WH_THUMBS/.$id.$ext.part" >>"$cfg"
    done
    if ((${#want[@]} > 0)); then
        curl --silent --proto '=https' --max-time 30 --connect-timeout 10 --user-agent "$WH_UA" \
            --max-filesize "$WH_MAX_THUMB" --fail --parallel --parallel-max 6 --config "$cfg" || true
    fi
    rm -f -- "$cfg"
    local entry part
    for entry in "${ids[@]+"${ids[@]}"}"; do
        id="${entry%%$'\t'*}"
        part="$WH_THUMBS/.${entry##*/}.part"
        if [[ -f $part ]]; then
            if wh_is_image "$part"; then mv -f -- "$part" "${entry#*$'\t'}"; else rm -f -- "$part"; fi
        fi
        [[ -s ${entry#*$'\t'} ]] && printf '%s\n' "$entry"
    done
    wh_prune_thumbs
}

# The jq filter that keeps the fields haseen uses from a listing entry.
# shellcheck disable=SC2016 # jq, not shell
WH_ENTRY='{id, url, purity, category, resolution, file_type, file_size, path, colors, thumb_url: .thumbs.small}'
