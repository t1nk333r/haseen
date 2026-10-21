#!/usr/bin/env bash
# A fake curl for tests/test-syncthing.sh: a Syncthing REST API with two
# folders, two devices and one invitation of each kind. Every request is
# logged to $FAKE_LOG as "METHOD PATH[ BODY]"; a request whose X-API-Key
# header (read from the -H @file curl is given) is not "fixture-key" fails
# with 403. $FAKE_ST_DOWN makes Syncthing absent.
method=GET url="" body="" key=""
while (($#)); do
    case $1 in
    -X) method=$2; shift ;;
    --data-binary) body=$2; shift ;;
    -H)
        [[ $2 == @* ]] && key="$(sed -n 's/^X-API-Key: //p' "${2#@}")"
        shift
        ;;
    --max-time) shift ;;
    http*) url=$1 ;;
    esac
    shift
done
path=${url#http://127.0.0.1:8384}
echo "$method $path${body:+ $body}" >>"${FAKE_LOG:-/dev/null}"
[[ -z ${FAKE_ST_DOWN:-} ]] || { echo "curl: (7) Failed to connect" >&2; exit 7; }
[[ $key == fixture-key ]] || { echo "curl: (22) 403" >&2; exit 22; }
me=AAAAAAA-AAAAAAA-AAAAAAA-AAAAAAA-AAAAAAA-AAAAAAA-AAAAAAA-AAAAAAA
peer=BBBBBBB-BBBBBBB-BBBBBBB-BBBBBBB-BBBBBBB-BBBBBBB-BBBBBBB-BBBBBBB
new=CCCCCCC-CCCCCCC-CCCCCCC-CCCCCCC-CCCCCCC-CCCCCCC-CCCCCCC-CCCCCCC
case "$method $path" in
"GET /rest/system/version") echo '{"version":"v2.1.3"}' ;;
"GET /rest/system/status") echo "{\"myID\":\"$me\"}" ;;
"GET /rest/config/folders") echo "[{\"id\":\"docs-1\",\"label\":\"Docs\",\"path\":\"/srv/sync/docs\",\"paused\":false,\"devices\":[{\"deviceID\":\"$me\"},{\"deviceID\":\"$peer\"}]},{\"id\":\"pics\",\"label\":\"\",\"path\":\"/srv/sync/pics\",\"paused\":true,\"devices\":[{\"deviceID\":\"$me\"}]}]" ;;
"GET /rest/config/folders/docs-1") echo "{\"id\":\"docs-1\",\"devices\":[{\"deviceID\":\"$me\"},{\"deviceID\":\"$peer\"}]}" ;;
"GET /rest/config/folders/pics") echo "{\"id\":\"pics\",\"devices\":[{\"deviceID\":\"$me\"}]}" ;;
"GET /rest/config/folders/"*) echo "curl: (22) 404" >&2; exit 22 ;;
"GET /rest/config/devices") echo "[{\"deviceID\":\"$me\",\"name\":\"this\"},{\"deviceID\":\"$peer\",\"name\":\"Phone\"}]" ;;
"GET /rest/system/connections") echo "{\"connections\":{\"$peer\":{\"connected\":true}}}" ;;
"GET /rest/cluster/pending/devices") echo "{\"$new\":{\"name\":\"Laptop\",\"address\":\"192.0.2.4:22000\"}}" ;;
"GET /rest/cluster/pending/folders") echo "{\"music\":{\"offeredBy\":{\"$peer\":{\"label\":\"Music\"}}}}" ;;
"GET /rest/db/status?folder=docs-1") echo '{"state":"syncing","globalBytes":1000,"needBytes":250,"needFiles":3}' ;;
"GET /rest/db/status?folder=pics") echo '{"state":"idle","globalBytes":0}' ;;
"GET /rest/events?since=0&"* | "GET /rest/events?since="[1-7]"&"*) echo '[{"id":7,"type":"ItemFinished","time":"2026-10-20T10:00:00Z","data":{"folder":"docs-1","item":"notes.md","action":"update","error":null}},{"id":8,"type":"StateChanged","data":{"folder":"docs-1","to":"idle"}}]' ;;
# A long poll after the last event waits, as Syncthing does, then has none.
"GET /rest/events?"*) sleep 2; echo '[]' ;;
POST* | PATCH* | DELETE*) echo '{}' ;;
*) echo "curl: (22) 404 $path" >&2; exit 22 ;;
esac
