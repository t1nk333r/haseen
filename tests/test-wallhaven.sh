# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# Plan 072: `haseen wallhaven search|get|random` and haseen.themegen's
# Wallhaven source. curl is tests/fixtures/wallhaven/curl.sh, which serves a
# listing recorded from the API (two pages, one entry turned sketchy), a
# wallpaper record, a generated thumbnail and image, and logs every argv. No
# network. Checked: the query and its defaults, SFW unless a key exists (and
# the key only ever in a header file), paging and the random seed, the rate
# limit, get's refusals, the thumbnail cache's bounds, dry runs, and the
# panel's model from search to the `haseen theme generate` call.

FIX="$FIXTURES/wallhaven"
PLUGIN="$HASEEN_PATH/shell/plugins/haseen.themegen"
QML_BIN=${QML_BIN:-/usr/lib/qt6/bin/qml}

sandbox wallhaven
export CURL_LOG="$SANDBOX/curl.log"
stub curl "exec bash '$FIX/curl.sh' \"\$@\""
# The focused monitor is the second one, rotated: atleast is its portrait size.
stub hyprctl "printf '%s' '[{\"name\":\"A\",\"width\":1920,\"height\":1080,\"focused\":false,\"transform\":0},{\"name\":\"B\",\"width\":2560,\"height\":1440,\"focused\":true,\"transform\":1}]'"
CACHE="$XDG_CACHE_HOME/haseen/wallhaven"
THUMBS="$CACHE/thumbs"
KEY="$XDG_CONFIG_HOME/haseen/wallhaven.key"
DEST="$XDG_CONFIG_HOME/haseen/backgrounds/wallhaven"
log() { cat "$CURL_LOG" 2>/dev/null || true; }
reset_log() {
    : >"$CURL_LOG"
    rm -f "$CACHE/calls"
}
reset_log

# --- help and argument checks ----------------------------------------------------
capture haseen wallhaven search --help
assert_status "search --help" 0 "$STATUS"
assert_contains "--help names the sorts" "$OUTPUT" "toplist date_added random relevance views favorites"
assert_contains "--help names the key file" "$OUTPUT" "wallhaven.key"
capture haseen wallhaven get --help
assert_status "get --help" 0 "$STATUS"
capture haseen wallhaven random --help
assert_status "random --help" 0 "$STATUS"
capture haseen commands wallhaven
assert_contains "the router lists the group" "$OUTPUT" "haseen wallhaven search"

for bad in "--sort hot" "--sort date_added --top-range 1w" "--top-range 2d" "--ratio wide" "--atleast big" \
    "--color red" "--page 0" "--seed toolongseed" "--categories 000" "-x"; do
    # shellcheck disable=SC2086 # the cases are words
    capture haseen wallhaven search $bad
    assert_status "search refuses $bad" 1 "$STATUS"
done
for bad in "../x" "UPPER" "https://example.com/w/abc"; do
    capture haseen wallhaven get "$bad"
    assert_status "get refuses the id $bad" 1 "$STATUS"
done
assert_eq "argument errors never ran curl" "" "$(log)"

# --- dry runs -----------------------------------------------------------------------
capture haseen wallhaven search "blue hour" --dry-run
assert_status "search --dry-run" 0 "$STATUS"
assert_dry_pure "search --dry-run" "$OUTPUT"
assert_contains "the exact URL, with the defaults" "$OUTPUT" \
    "DRYRUN: GET https://wallhaven.cc/api/v1/search?categories=111&purity=100&sorting=toplist&order=desc&page=1&atleast=1440x2560&q=blue%20hour"
assert_contains "and the thumbnail cache" "$OUTPUT" "DRYRUN: cache thumbnails in $THUMBS"
capture haseen wallhaven search --sort toplist --top-range 1w --ratio 16x9,21x9 --atleast 3840x2160 --color '#336600' --page 3 --dry-run
assert_contains "every filter reaches the URL" "$OUTPUT" \
    "categories=111&purity=100&sorting=toplist&order=desc&page=3&atleast=3840x2160&topRange=1w&ratios=16x9%2C21x9&colors=336600"
capture haseen wallhaven search --query "-anime +sky" --dry-run
assert_contains "a query may start with - through --query" "$OUTPUT" "q=-anime%20%2Bsky"
capture haseen wallhaven get 3q797y --dry-run
assert_status "get --dry-run" 0 "$STATUS"
assert_contains "get's plan: the record" "$OUTPUT" "DRYRUN: GET https://wallhaven.cc/api/v1/w/3q797y"
assert_contains "then the image, bounded" "$OUTPUT" "at most 50 MiB) to $DEST/3q797y.<ext>"
capture haseen wallhaven get https://wallhaven.cc/w/3q797y --to "$SANDBOX/elsewhere" --dry-run
assert_contains "a page URL and --to" "$OUTPUT" "$SANDBOX/elsewhere/3q797y.<ext>"
capture haseen wallhaven random --dry-run
assert_contains "random's plan: a random search" "$OUTPUT" "sorting=random"
assert_contains "then get" "$OUTPUT" "DRYRUN: haseen wallhaven get <the first result>"
assert_dry_pure "random --dry-run" "$OUTPUT"
assert_eq "dry runs never ran curl" "" "$(log)"
assert_eq "and wrote nothing" "" "$(find "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" -type f 2>/dev/null)"

# --- search -----------------------------------------------------------------------------
capture haseen wallhaven search mountains --json
assert_status "search --json" 0 "$STATUS"
S1="$OUTPUT"
assert_eq "page 1 of 2, 5 in all" "1 2 5" "$(jq -r '"\(.page) \(.last_page) \(.total)"' <<<"$S1")"
assert_eq "the sketchy entry is dropped without a key" "3q797y lygg6r 216y9y" "$(jq -r '[.results[].id] | join(" ")' <<<"$S1")"
assert_eq "an entry carries what the panel uses" "3840x2160 sfw https://w.wallhaven.cc/full/3q/wallhaven-3q797y.jpg" \
    "$(jq -r '.results[0] | "\(.resolution) \(.purity) \(.path)"' <<<"$S1")"
assert_eq "each thumbnail is cached" "$THUMBS/3q797y.jpg" "$(jq -r '.results[0].thumb' <<<"$S1")"
assert_eq "as an image" "image/jpeg" "$(file --brief --mime-type "$THUMBS/3q797y.jpg")"
assert_eq "no partial files remain" "" "$(find "$THUMBS" -name '.*' 2>/dev/null)"
assert_contains "API calls are https only" "$(log)" "--proto =https"
assert_contains "with a timeout" "$(log)" "--max-time 20"
assert_contains "and haseen's User-Agent" "$(log)" "--user-agent haseen/"
assert_contains "the search asked purity 100" "$(log)" "purity=100&"
assert_not_contains "no key header without a key" "$(log)" "header X-API-Key"
assert_eq "the thumbnails came in one parallel run" 1 "$(grep -c -- '--parallel' "$CURL_LOG")"
reset_log
capture haseen wallhaven search mountains --json
assert_eq "cached thumbnails are not fetched again" "" "$(grep '^thumb ' "$CURL_LOG" || true)"
capture haseen wallhaven search mountains
assert_contains "plain output: the page" "$OUTPUT" "page 1 of 2, 5 wallpapers"
assert_contains "and one line a wallpaper" "$OUTPUT" "3q797y	3840x2160	general	https://wallhaven.cc/w/3q797y"

# --- paging and the random seed ---------------------------------------------------------
reset_log
capture haseen wallhaven search mountains --page 2 --json
assert_eq "page 2" "2 2 216zzg" "$(jq -r '"\(.page) \(.last_page) \(.results[0].id)"' <<<"$OUTPUT")"
assert_contains "asked for page 2" "$(log)" "page=2&"
capture haseen wallhaven search --sort random --seed abc123 --page 2 --json
assert_contains "a random page carries its seed" "$(log)" "seed=abc123"

# --- SFW unless a key exists ------------------------------------------------------------
reset_log
capture haseen wallhaven search --purity 111
assert_status "more than SFW is refused without a key" 1 "$STATUS"
assert_contains "and says why" "$OUTPUT" "needs a Wallhaven API key"
capture haseen wallhaven get sk1tch
assert_status "a sketchy wallpaper is refused without a key" 1 "$STATUS"
assert_contains "named as such" "$OUTPUT" "sk1tch is sketchy"
assert_eq "and not downloaded" "" "$(ls "$DEST" 2>/dev/null || true)"
mkdir -p "$(dirname "$KEY")"
printf 'Abc123SecretKey\n' >"$KEY"
chmod 644 "$KEY"
capture haseen wallhaven search --purity 111 --no-thumbs
assert_status "a key others can read is not used" 1 "$STATUS"
assert_contains "with the chmod hint" "$OUTPUT" "chmod 600"
chmod 600 "$KEY"
reset_log
capture haseen wallhaven search --purity 110 --json --no-thumbs
assert_status "with a key, sketchy may be asked for" 0 "$STATUS"
assert_contains "purity 110 sent" "$(log)" "purity=110&"
assert_contains "and the sketchy entry kept" "$(jq -r '[.results[].id] | join(" ")' <<<"$OUTPUT")" "sk1tch"
assert_contains "the key travels in a header file" "$(log)" "header X-API-Key: Abc123SecretKey"
assert_not_contains "never in an argv or a URL" "$(grep '^argv' "$CURL_LOG")" "Abc123SecretKey"
assert_eq "--no-thumbs fetched none" "" "$(grep '^thumb ' "$CURL_LOG" || true)"
capture haseen wallhaven search --dry-run
assert_not_contains "a dry run never prints the key" "$OUTPUT" "Abc123SecretKey"
assert_contains "a key alone keeps the default SFW" "$OUTPUT" "purity=100&"
assert_eq "no header file is left behind" "" "$(find /tmp -maxdepth 1 -user "$(id -u)" -newer "$KEY" -type f -exec grep -l Abc123SecretKey {} + 2>/dev/null || true)"
rm -f "$KEY"

# --- errors and the rate limit ----------------------------------------------------------
reset_log
CURL_HTTP=429 capture haseen wallhaven search
assert_status "a 429 is an error" 1 "$STATUS"
assert_contains "said plainly" "$OUTPUT" "too many requests"
CURL_HTTP=401 capture haseen wallhaven search
assert_contains "a 401 points at the key" "$OUTPUT" "wallhaven.key"
reset_log
mkdir -p "$CACHE"
now="$(date +%s)"
for ((n = 0; n < 45; n++)); do echo "$now"; done >"$CACHE/calls"
capture haseen wallhaven search
assert_status "the 46th call in a minute is refused" 1 "$STATUS"
assert_contains "with the wait" "$OUTPUT" "45 calls a minute"
assert_eq "before curl runs" "" "$(log)"
for ((n = 0; n < 45; n++)); do echo "$((now - 61))"; done >"$CACHE/calls"
capture haseen wallhaven search --no-thumbs
assert_status "calls older than a minute do not count" 0 "$STATUS"
assert_eq "and are forgotten" 1 "$(wc -l <"$CACHE/calls")"

# --- get --------------------------------------------------------------------------------
reset_log
set +e
got="$(haseen wallhaven get 3q797y 2>"$SANDBOX/get.err")"
STATUS=$?
set -e
assert_status "get" 0 "$STATUS"
assert_eq "prints the saved path" "$DEST/3q797y.jpg" "$got"
assert_eq "the fixture's bytes" "$(sha256sum <"$FIX/full-3q797y.jpg")" "$(sha256sum <"$DEST/3q797y.jpg")"
assert_contains "progress lines for the panel" "$(cat "$SANDBOX/get.err")" "progress 42"
assert_contains "ending at 100" "$(cat "$SANDBOX/get.err")" "progress 100"
assert_contains "the image is fetched bounded" "$(log)" "--max-filesize 52428800"
assert_contains "from wallhaven's image host" "$(log)" "https://w.wallhaven.cc/full/3q/wallhaven-3q797y.jpg"
assert_eq "no partial file remains" "" "$(find "$DEST" -name '.*')"
reset_log
capture haseen wallhaven get 3q797y
assert_contains "a second get keeps the file" "$OUTPUT" "already downloaded"
assert_eq "without curl" "" "$(log)"
capture haseen wallhaven get badimg
assert_status "content that is not an image is refused" 1 "$STATUS"
assert_contains "said so" "$OUTPUT" "is not an image; nothing kept"
assert_eq "nothing kept" "" "$(find "$DEST" -name '*badimg*')"
CURL_CTYPE=text/html CURL_BODY="$FIX/full-3q797y.jpg" capture haseen wallhaven get 3q797y --to "$SANDBOX/ct"
assert_status "image bytes sent as text/html are refused" 1 "$STATUS"
assert_contains "by content type" "$OUTPUT" "was not sent as an image (text/html)"
assert_eq "nothing kept there" "" "$(ls -A "$SANDBOX/ct")"
CURL_BODY="$FIX/thumb.jpg" capture haseen wallhaven get 3q797y --to "$SANDBOX/sz"
assert_status "a size other than the API's is refused" 1 "$STATUS"
assert_contains "with both sizes" "$OUTPUT" "wallhaven said $(stat -c %s "$FIX/full-3q797y.jpg")"
capture haseen wallhaven get evil01
assert_status "an image address off wallhaven is refused" 1 "$STATUS"
assert_not_contains "and never fetched" "$(log)" "example.com"
capture haseen wallhaven get huge01
assert_status "a record over 50 MiB is refused" 1 "$STATUS"
assert_contains "with its size" "$OUTPUT" "60 MiB, more than 50 MiB"
capture haseen wallhaven get gif001
assert_status "a type haseen cannot use is refused" 1 "$STATUS"
assert_contains "named" "$OUTPUT" "(image/gif)"
assert_not_contains "neither was fetched" "$(log)" "w.wallhaven.cc/full/hu/"
capture haseen wallhaven get nosuch
assert_status "an unknown id" 1 "$STATUS"
assert_contains "is a plain error" "$OUTPUT" "no such wallpaper"

# --- random -------------------------------------------------------------------------------
reset_log
set +e
got="$(haseen wallhaven random --to "$SANDBOX/random" 2>/dev/null)"
set -e
assert_eq "random downloads the first random result" "$SANDBOX/random/3q797y.jpg" "$got"
assert_contains "after a random search" "$(log)" "sorting=random"
assert_eq "without thumbnails" "" "$(grep '^thumb ' "$CURL_LOG" || true)"

# --- the thumbnail cache's bounds -------------------------------------------------------------
reset_log
rm -rf "$THUMBS"
mkdir -p "$THUMBS"
touch -d '10 days ago' "$THUMBS/old.jpg"
for ((n = 0; n < 610; n++)); do printf 'x' >"$THUMBS/f$n.jpg"; done
touch -d '1 hour ago' "$THUMBS"/f*.jpg
CURL_BODY="$FIX/not-an-image.html" capture haseen wallhaven search mountains --page 2 --json
assert_eq "a thumbnail that is not an image is not cached" "" "$(jq -r '.results[0].thumb' <<<"$OUTPUT")"
assert_eq "nor left as a partial" "" "$(find "$THUMBS" -name '.*')"
capture haseen wallhaven search mountains --json
assert_eq "a week-old thumbnail is pruned" "" "$(find "$THUMBS" -name old.jpg)"
assert_eq "the cache keeps 600 files at most" 600 "$(find "$THUMBS" -type f | wc -l)"
assert_eq "the fresh ones stay" 3 "$(find "$THUMBS" -name '3q797y.jpg' -o -name 'lygg6r.jpg' -o -name '216y9y.jpg' | wc -l)"
S1="$OUTPUT"

# --- the panel model under the Qt JS engine ------------------------------------------------
capture haseen wallhaven search mountains --page 2 --json
S2="$OUTPUT"
if [[ -x $QML_BIN ]]; then
    harness="$SANDBOX/harness"
    mkdir -p "$harness"
    {
        printf 'var page1 = %s;\n' "$(jq -Rs . <<<"$S1")"
        printf 'var page2 = %s;\n' "$(jq -Rs . <<<"$S2")"
        printf 'var getOut = %s;\n' "$(printf '[*] saved %s\n%s\n' "$DEST/3q797y.jpg" "$DEST/3q797y.jpg" | jq -Rs .)"
        printf 'var cliSorts = %s;\n' "$(sed -n 's/^WH_SORTS=(\(.*\))$/\1/p' "$HASEEN_PATH/lib/wallhaven.sh" | jq -Rc 'split(" ")')"
    } >"$harness/data.js"
    cat >"$harness/Harness.qml" <<EOF
import QtQuick
import "file://$PLUGIN/Wallhaven.js" as W
import "file://$PLUGIN/Themegen.js" as T
import "data.js" as D
Item {
    function out(k, v) { console.warn("RESULT " + k + " " + JSON.stringify(v)); }
    Component.onCompleted: {
        out("sorts", W.SORTS.join(" ") === D.cliSorts.join(" "));
        out("labels", W.SORTS.map(W.sortLabel));
        // search -> results
        out("search", W.searchArgv("/b/haseen", "  mountains ", "toplist", 1, ""));
        out("searchEmpty", W.searchArgv("/b/haseen", "", "views", 0, "abc123"));
        const p1 = W.parseSearch(D.page1);
        out("page1", [p1.ok, p1.page, p1.lastPage, p1.total, p1.items.map(i => i.id).join(" "), p1.items[0].label, p1.items[0].thumb !== ""]);
        out("more", [W.hasMore(p1.page, p1.lastPage), W.hasMore(2, 2), W.hasMore(0, 0)]);
        out("next", W.searchArgv("/b/haseen", "mountains", "toplist", p1.page + 1, ""));
        const p2 = W.parseSearch(D.page2);
        out("appended", W.append(p1.items, p2.items.concat([p1.items[0]])).map(i => i.id).join(" "));
        out("random", W.searchArgv("/b/haseen", "", "random", 2, "abc123"));
        out("broken", [W.parseSearch("").ok, W.parseSearch("{}").error, W.parseSearch('{"results":[{"id":"../x"}]}').items.length]);
        // select -> get
        out("get", W.getArgv("/b/haseen", p1.items[0].id));
        out("progress", ["progress 42", "progress 100", "[*] saved /x", "progress 420"].map(W.progressOf));
        const path = W.pathOf(D.getOut);
        out("path", [path, W.pathOf("Error: nope\n")]);
        // -> the generate call
        const name = W.themeName(p1.items[0].id);
        out("preview", T.previewArgv("/b/haseen", path, "tonal-spot", "dark", name));
        out("apply", T.writeArgv("/b/haseen", path, "tonal-spot", "dark", name, true));
        Qt.quit();
    }
}
EOF
    qml_out="$(cd "$harness" && QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 timeout 30 "$QML_BIN" Harness.qml 2>&1 | sed -n 's/^.*RESULT //p')"
    r() { sed -n "s/^$1 //p" <<<"$qml_out"; }
    assert_eq "model: the sorts are the CLI's" "true" "$(r sorts)"
    assert_eq "model: sort chips" '["Top","Latest","Random","Relevance","Views","Favourites"]' "$(r labels)"
    assert_eq "model: the search argv" '["/b/haseen","wallhaven","search","--query","mountains","--sort","toplist","--page","1","--json"]' "$(r search)"
    assert_eq "model: no query, a seed only for random" '["/b/haseen","wallhaven","search","--sort","views","--page","1","--json"]' "$(r searchEmpty)"
    assert_eq "model: reads the CLI's page" '[true,1,2,5,"3q797y lygg6r 216y9y","3840x2160",true]' "$(r page1)"
    assert_eq "model: more pages while page < last" '[true,false,false]' "$(r more)"
    assert_eq "model: the next page" '["/b/haseen","wallhaven","search","--query","mountains","--sort","toplist","--page","2","--json"]' "$(r next)"
    assert_eq "model: pages append without repeats" "3q797y lygg6r 216y9y 216zzg" "$(r appended | jq -r .)"
    assert_eq "model: random pages pass the seed" '["/b/haseen","wallhaven","search","--sort","random","--page","2","--seed","abc123","--json"]' "$(r random)"
    assert_eq "model: bad output is no results" '[false,"no results",0]' "$(r broken)"
    assert_eq "model: selecting downloads" '["/b/haseen","wallhaven","get","3q797y"]' "$(r get)"
    assert_eq "model: progress lines" '[42,100,-1,-1]' "$(r progress)"
    assert_eq "model: the downloaded path" "[\"$DEST/3q797y.jpg\",\"\"]" "$(r path)"
    assert_eq "model: the preview of the download" \
        "[\"/b/haseen\",\"theme\",\"generate\",\"$DEST/3q797y.jpg\",\"--scheme\",\"tonal-spot\",\"--mode\",\"dark\",\"--name\",\"wallhaven-3q797y\",\"--json\"]" "$(r preview)"
    assert_eq "model: Apply generates the theme from it" \
        "[\"/b/haseen\",\"theme\",\"generate\",\"$DEST/3q797y.jpg\",\"--scheme\",\"tonal-spot\",\"--mode\",\"dark\",\"--name\",\"wallhaven-3q797y\"]" "$(r apply)"
else
    echo "  skip: $QML_BIN not installed, Wallhaven.js not exercised" >&2
fi

# --- the panel ---------------------------------------------------------------------------------
assert_contains "the grid pages on scroll, not on a timer" "$(cat "$PLUGIN/WallhavenGrid.qml")" "onAtYEndChanged"
assert_contains "the panel offers the Wallhaven source" "$(cat "$PLUGIN/Panel.qml")" '"Wallhaven"'
assert_eq "the source starts at the user's own images" "local" "$(jq -r .settings.source.default "$PLUGIN/manifest.json")"
assert_eq "the panel stays off by default" "false" \
    "$(jq -r '.plugins["haseen.themegen"].enabled' "$HASEEN_PATH/default/shell.json")"
