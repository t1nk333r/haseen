#!/usr/bin/env bash
# A stand-in for curl in tests/test-wallhaven.sh: serves this directory's
# fixtures for the URLs haseen asks wallhaven for, and logs each argv (and the
# header file's contents, to prove the key travels only there) to $CURL_LOG.
#   CURL_HTTP    the API's status code (default 200)
#   CURL_CTYPE   the content type an image is sent with (default image/jpeg)
#   CURL_BODY    a file served instead of any image
set -u
fix="$(dirname "$(readlink -f "$0")")"
printf 'argv %s\n' "$*" >>"$CURL_LOG"
out="" fmt="" cfg="" urls=()
while (($#)); do
    case $1 in
    --output) out=$2 && shift ;;
    --write-out) fmt=$2 && shift ;;
    --config) cfg=$2 && shift ;;
    --header)
        [[ $2 == @* && -s ${2#@} ]] && printf 'header %s\n' "$(cat "${2#@}")" >>"$CURL_LOG"
        shift
        ;;
    --user-agent | --proto | --max-time | --connect-timeout | --max-filesize | --parallel-max) shift ;;
    --) shift && urls+=("$@") && break ;;
    -*) ;;
    *) urls+=("$1") ;;
    esac
    shift
done

# serve URL FILE — copy the fixture for URL to FILE; prints the content type.
serve() {
    local url=$1 file=$2 id
    case $url in
    https://wallhaven.cc/api/v1/search\?*)
        local page=1
        [[ $url =~ [?\&]page=([0-9]+) ]] && page=${BASH_REMATCH[1]}
        cp "$fix/search-$page.json" "$file" && echo application/json
        ;;
    https://wallhaven.cc/api/v1/w/*)
        id=${url##*/}
        cp "$fix/w-$id.json" "$file" 2>/dev/null && echo application/json
        ;;
    https://th.wallhaven.cc/*)
        cp "${CURL_BODY:-$fix/thumb.jpg}" "$file" && echo image/jpeg
        ;;
    https://w.wallhaven.cc/full/*)
        id=${url##*/wallhaven-}
        id=${id%.*}
        if [[ -n ${CURL_BODY:-} ]]; then cp "$CURL_BODY" "$file"
        elif [[ -f $fix/full-$id.jpg ]]; then cp "$fix/full-$id.jpg" "$file"
        else cp "$fix/not-an-image.html" "$file"; fi
        echo "${CURL_CTYPE:-image/jpeg}"
        ;;
    *) return 1 ;;
    esac
}

if [[ -n $cfg ]]; then
    url=""
    while IFS= read -r line; do
        case $line in
        url\ =\ *) url=${line#url = } && url=${url//\"/} ;;
        output\ =\ *)
            o=${line#output = }
            o=${o//\"/}
            printf 'thumb %s\n' "$url" >>"$CURL_LOG"
            serve "$url" "$o" >/dev/null
            ;;
        esac
    done <"$cfg"
    exit 0
fi

url=${urls[0]:-}
code=${CURL_HTTP:-200}
ctype="$(serve "$url" "${out:-/dev/stdout}")" || code=404
if [[ $url == https://wallhaven.cc/api/* && $code != 200 ]]; then
    printf '{"error":"x"}' >"$out"
fi
# The download's progress bar, as curl draws it.
[[ $url == https://w.wallhaven.cc/* ]] && printf '##########       42.0%%\r##################### 100.0%%\n' >&2
size=0
[[ -n $out && -f $out ]] && size=$(stat -c %s "$out")
fmt=${fmt//%\{http_code\}/$code}
fmt=${fmt//%\{content_type\}/$ctype}
fmt=${fmt//%\{size_download\}/$size}
printf '%b' "$fmt"
exit 0
