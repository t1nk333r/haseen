# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# Uploader, annotation wiring, OCR invocation and circle-to-search.
# Every network call goes to a scripted curl that records its argv AND its
# stdin, so the request shape is asserted exactly and a credential that leaked
# into the command line would be visible in the recording.

TOKEN="xbb-fixture-token-0000"
IMGUR_ID="imgur-fixture-id-0000"

# cap_sandbox NAME — sandbox with every capture/upload tool faked.
cap_sandbox() {
    sandbox "$1"
    export XDG_RUNTIME_DIR="$SANDBOX/run"
    mkdir -p "$XDG_RUNTIME_DIR" && chmod 700 "$XDG_RUNTIME_DIR"
    CALLS="$SANDBOX/calls"
    CALLS_STDIN="$SANDBOX/calls.stdin"
    : >"$CALLS"
    : >"$CALLS_STDIN"
    export CALLS CALLS_STDIN
    export CURL_BODY="" CURL_HEADERS="" CURL_RC=0 CURL_PROBE_CODE=404 CURL_PROBE_RC=0
    stub notify-send 'echo "notify-send $*" >>"$CALLS"'
    stub wl-copy 'printf "wl-copy %s: " "$*" >>"$CALLS"; cat >>"$CALLS"; echo >>"$CALLS"'
    stub xdg-user-dir 'echo "$HOME/$1"'
    stub xdg-open 'echo "xdg-open $*" >>"$CALLS"'
    # GRIM_DELAY holds the picture back, so the OCR consumer is already
    # waiting on the pipe before anything is written to it.
    stub grim 'echo "grim $*" >>"$CALLS"
[ -n "${GRIM_DELAY:-}" ] && sleep "$GRIM_DELAY"
out=""; prev=""
for a in "$@"; do prev2=$prev; prev=$a; done
[ -n "$prev" ] && [ "$prev" != "-" ] && out=$prev
if [ -n "$out" ]; then printf PNG >"$out"; else printf PNG; fi'
    stub slurp 'echo "0,0 100x100"'
    stub hyprpicker 'echo "hyprpicker $*" >>"$CALLS"; sleep 2'
    stub satty 'echo "satty $*" >>"$CALLS"'
    stub rclone 'echo "rclone $*" >>"$CALLS"; [ "$1" = link ] && echo "https://r2.example.com/shot.png"; exit 0'
    # Like the real one, it reads the whole picture before it answers when
    # the picture comes on stdin, so grim never writes into a closed pipe.
    stub tesseract 'echo "tesseract $*" >>"$CALLS"; [ "$1" = stdin ] && cat >/dev/null; printf "%s" "${TESS_TEXT:-recognised text}"'
    # Records argv and the curl config read on stdin; answers with $CURL_BODY
    # and $CURL_HEADERS. -w (used only by the XBackBone probe) answers a code.
    stub curl 'echo "curl $*" >>"$CALLS"
probe=0; prev=""; dump=""
for a in "$@"; do
  [ "$prev" = "-D" ] && dump=$a
  [ "$a" = "-w" ] && probe=1
  prev=$a
done
if [ "$probe" = 1 ]; then printf "%s" "${CURL_PROBE_CODE:-404}"; exit "${CURL_PROBE_RC:-0}"; fi
cat >>"$CALLS_STDIN"
if [ "$dump" = "-" ]; then printf "%s" "$CURL_HEADERS"
elif [ -n "$dump" ]; then printf "%s" "$CURL_HEADERS" >"$dump"; fi
printf "%s" "$CURL_BODY"
exit "${CURL_RC:-0}"'
    SHOT="$SANDBOX/shot.png"
    printf 'PNG' >"$SHOT"
    export HASEEN_UPLOAD_CONFIG="$SANDBOX/upload.toml"
}

calls() { cat "$CALLS"; }
curl_stdin() { cat "$CALLS_STDIN"; }

write_upload_config() { # BODY
    printf '%s\n' "$1" >"$HASEEN_UPLOAD_CONFIG"
    chmod 600 "$HASEEN_UPLOAD_CONFIG"
}

# --- help and metadata -------------------------------------------------------
cap_sandbox upload-help
for c in upload search-screen capture-screenshot capture-text; do
    capture "$REPO/bin/haseen-$c" --help
    assert_status "$c --help" 0 "$STATUS"
done
# `haseen commands` builds its listing from the summary and args headers.
capture haseen commands upload
assert_contains "haseen commands lists upload with its args and summary" "$OUTPUT" \
    "haseen upload [FILE] [--backend NAME]"
assert_contains "and its summary" "$OUTPUT" "Upload a file to a share host"
capture haseen commands search
assert_contains "haseen commands lists search screen with its args" "$OUTPUT" "haseen search screen [text|image]"
assert_contains "and its summary" "$OUTPUT" "Circle to search"
capture haseen upload --help
assert_contains "help says imgur registration is closed" "$OUTPUT" "closed new client"
assert_contains "help says 0x0 is disabled" "$OUTPUT" "DISABLED uploads"
assert_contains "help names the credentials file" "$OUTPUT" "upload.toml"
capture haseen upload
assert_status "upload with no file is a usage error" 2 "$STATUS"
capture haseen upload "$SHOT" --backend nope
assert_status "an unknown backend fails" 1 "$STATUS"
capture haseen upload "$SHOT" --expires abc
assert_status "a non-numeric --expires is a usage error" 2 "$STATUS"

# --- backend list ------------------------------------------------------------
capture haseen upload --list
assert_status "--list exits 0" 0 "$STATUS"
assert_contains "catbox is the keyless default" "$OUTPUT" "catbox     catbox.moe"
assert_contains "the default is marked" "$OUTPUT" "[default]"
assert_eq "catbox carries the default marker" "catbox" \
    "$(awk '/\[default\]/{print $1}' <<<"$OUTPUT")"
write_upload_config '[xbackbone]
url = "https://share.example.com"
token = "'"$TOKEN"'"'
capture haseen upload --list
assert_eq "a configured instance becomes the default" "xbackbone" \
    "$(awk '/\[default\]/{print $1}' <<<"$OUTPUT")"
assert_not_contains "--list never prints the token" "$OUTPUT" "$TOKEN"
rm -f "$HASEEN_UPLOAD_CONFIG"

# --- dry-run plans and purity ------------------------------------------------
cap_sandbox upload-dry
write_upload_config '[xbackbone]
url = "https://share.example.com/"
token = "'"$TOKEN"'"
api = "form"

[imgur]
client_id = "'"$IMGUR_ID"'"

[rclone]
remote = "r2:bucket/shots"'
before="$(find "$HOME" -mindepth 1 | LC_ALL=C sort)"
for b in catbox uguu temp.sh 0x0 xbackbone imgur rclone; do
    capture haseen upload "$SHOT" --backend "$b" --dry-run
    assert_status "$b dry run exits 0" 0 "$STATUS"
    assert_dry_pure "$b dry run" "$OUTPUT"
    assert_not_contains "$b dry run hides the token" "$OUTPUT" "$TOKEN"
    assert_not_contains "$b dry run hides the imgur id" "$OUTPUT" "$IMGUR_ID"
done
capture haseen upload "$SHOT" --backend catbox --dry-run
assert_contains "catbox endpoint planned" "$OUTPUT" "-F reqtype=fileupload -F fileToUpload=@\"$SHOT\" https://catbox.moe/user/api.php"
capture haseen upload "$SHOT" --backend uguu --dry-run
assert_contains "uguu endpoint planned" "$OUTPUT" "-F files[]=@\"$SHOT\" https://uguu.se/upload?output=text"
capture haseen upload "$SHOT" --backend temp.sh --dry-run
assert_contains "temp.sh endpoint planned" "$OUTPUT" "-F file=@\"$SHOT\" https://temp.sh/upload"
capture haseen upload "$SHOT" --backend 0x0 --expires 2 --dry-run
assert_contains "0x0 endpoint planned" "$OUTPUT" "-F file=@\"$SHOT\" -F expires=2 https://0x0.st"
capture haseen upload "$SHOT" --backend xbackbone --dry-run
assert_contains "xbackbone endpoint planned" "$OUTPUT" "-F upload=@\"$SHOT\" https://share.example.com/upload"
assert_contains "the plan says where the token comes from" "$OUTPUT" "read from $HASEEN_UPLOAD_CONFIG and passed on stdin (never shown)"
capture haseen upload "$SHOT" --backend imgur --dry-run
assert_contains "imgur endpoint planned" "$OUTPUT" "-F image=@\"$SHOT\" https://api.imgur.com/3/image"
capture haseen upload "$SHOT" --backend rclone --dry-run
assert_contains "rclone copy planned" "$OUTPUT" "DRYRUN: rclone copyto $SHOT r2:bucket/shots/shot.png"
assert_contains "rclone link planned" "$OUTPUT" "DRYRUN: rclone link r2:bucket/shots/shot.png"
assert_eq "dry runs leave HOME untouched" "$before" "$(find "$HOME" -mindepth 1 | LC_ALL=C sort)"
assert_eq "dry runs call nothing" "" "$(calls)"

# --- real runs: anonymous hosts ---------------------------------------------
cap_sandbox upload-anon
export CURL_BODY="https://files.catbox.moe/abc123.png"
capture haseen upload "$SHOT"
assert_status "catbox upload succeeds" 0 "$STATUS"
assert_eq "catbox returns the link on stdout" "https://files.catbox.moe/abc123.png" "$OUTPUT"
assert_contains "catbox request shape" "$(calls)" "-F reqtype=fileupload -F fileToUpload=@\"$SHOT\" https://catbox.moe/user/api.php"
assert_contains "catbox sends a haseen user agent" "$(calls)" "-A haseen-upload/"
assert_contains "the link lands on the clipboard" "$(calls)" "wl-copy : https://files.catbox.moe/abc123.png"
assert_contains "the upload is notified" "$(calls)" "notify-send -a haseen"
assert_eq "no credential is ever sent for an anonymous host" "" "$(curl_stdin)"

cap_sandbox upload-uguu
export CURL_BODY="https://d.uguu.se/bTPPlbJd.png"
capture haseen upload "$SHOT" --backend uguu --no-copy --quiet
assert_eq "uguu returns the link" "https://d.uguu.se/bTPPlbJd.png" "$OUTPUT"
assert_contains "uguu request shape" "$(calls)" "-F files[]=@\"$SHOT\" https://uguu.se/upload?output=text"
assert_not_contains "--no-copy keeps the clipboard alone" "$(calls)" "wl-copy"
assert_not_contains "--quiet sends no notification" "$(calls)" "notify-send"

cap_sandbox upload-temp
export CURL_BODY="https://temp.sh/aBcDe/shot.png"
capture haseen upload "$SHOT" --backend temp.sh
assert_eq "temp.sh returns the link" "https://temp.sh/aBcDe/shot.png" "$OUTPUT"
assert_contains "temp.sh request shape" "$(calls)" "-F file=@\"$SHOT\" https://temp.sh/upload"

cap_sandbox upload-0x0
export CURL_BODY="https://0x0.st/aB.png"
export CURL_HEADERS="HTTP/2 200
x-token: 0x0-fixture-management-token
"
capture haseen upload "$SHOT" --backend 0x0 --expires 1
assert_eq "0x0 returns the link" "https://0x0.st/aB.png" "$OUTPUT"
assert_contains "0x0 request shape" "$(calls)" "-F file=@\"$SHOT\" -F expires=1 https://0x0.st"
assert_not_contains "the management token is never printed" "$OUTPUT" "0x0-fixture-management-token"
assert_eq "the management token is kept out of the clipboard too" "" \
    "$(grep -c '0x0-fixture-management-token' "$CALLS" | tr -d '0')"
assert_eq "the management token is kept for a delete" "0x0-fixture-management-token" \
    "$(cat "$XDG_RUNTIME_DIR/haseen-upload.delete-token" 2>/dev/null)"

# --- real runs: XBackBone ----------------------------------------------------
cap_sandbox upload-xbb-form
write_upload_config '[xbackbone]
url = "https://share.example.com"
token = "'"$TOKEN"'"
api = "form"'
export CURL_BODY='{"url":"https://share.example.com/abcd.png"}'
capture haseen upload "$SHOT" --backend xbackbone
assert_status "an XBackBone form upload succeeds" 0 "$STATUS"
assert_eq "the instance link is returned" "https://share.example.com/abcd.png" "$OUTPUT"
assert_contains "the tagged release endpoint is used" "$(calls)" "https://share.example.com/upload"
assert_contains "the file part is sent" "$(calls)" "-F upload=@\"$SHOT\""
assert_contains "the token goes to curl on stdin as a literal string" "$(curl_stdin)" "form-string = \"token=$TOKEN\""
assert_not_contains "the token never reaches the command line" "$(calls)" "$TOKEN"
assert_not_contains "the token is never printed" "$OUTPUT" "$TOKEN"
assert_contains "curl reads its credentials from stdin" "$(calls)" "--config -"
assert_contains "curl skips ~/.curlrc (-q first) and speaks https only" "$(calls)" \
    "curl -q --proto =https --proto-redir =https --config -"
assert_not_contains "no redirect is ever followed" "$(calls)" " -L "
: >"$CALLS"
HASEEN_XBACKBONE_URL=http://127.0.0.1:9000 capture haseen upload "$SHOT" --backend xbackbone --no-copy --quiet
assert_contains "a loopback instance gets plain http and no proxy" "$(calls)" \
    "curl -q --proto =http --proto-redir =https --noproxy * --config -"

cap_sandbox upload-xbb-bearer
write_upload_config '[xbackbone]
url = "https://share.example.com"
token = "'"$TOKEN"'"
api = "bearer"'
export CURL_BODY='{"data":{"raw_url":"https://share.example.com/r/abcd.png","deletion_url":"x"}}'
capture haseen upload "$SHOT" --backend xbackbone
assert_eq "the next-gen raw link is returned" "https://share.example.com/r/abcd.png" "$OUTPUT"
assert_contains "the next-gen endpoint is used" "$(calls)" "https://share.example.com/api/v1/upload"
assert_contains "the next-gen file part is file=" "$(calls)" "-F file=@\"$SHOT\""
assert_contains "the bearer header goes on stdin" "$(curl_stdin)" "header = \"Authorization: Bearer $TOKEN\""
assert_not_contains "the bearer token never reaches the command line" "$(calls)" "$TOKEN"

cap_sandbox upload-xbb-auto
write_upload_config '[xbackbone]
url = "https://share.example.com"
token = "'"$TOKEN"'"'
export CURL_BODY='{"url":"https://share.example.com/abcd.png"}' CURL_PROBE_CODE=404
capture haseen upload "$SHOT"
assert_contains "a 404 on the api route means the tagged release" "$(calls)" "https://share.example.com/upload"
assert_not_contains "and the next-gen route is not used" "$(calls)" "api/v1/upload https"
cap_sandbox upload-xbb-auto2
write_upload_config '[xbackbone]
url = "https://share.example.com"
token = "'"$TOKEN"'"'
export CURL_BODY='{"data":{"raw_url":"https://share.example.com/r/abcd.png"}}' CURL_PROBE_CODE=405
capture haseen upload "$SHOT"
assert_eq "a 405 on the api route means next-gen" "https://share.example.com/r/abcd.png" "$OUTPUT"

cap_sandbox upload-xbb-env
export HASEEN_XBACKBONE_URL="https://env.example.com" HASEEN_XBACKBONE_TOKEN="env-token-0000"
export HASEEN_XBACKBONE_API=form CURL_BODY='{"url":"https://env.example.com/x.png"}'
capture haseen upload "$SHOT"
assert_eq "the environment configures a backend with no file at all" "https://env.example.com/x.png" "$OUTPUT"
assert_contains "the env token also goes on stdin" "$(curl_stdin)" 'form-string = "token=env-token-0000"'
assert_not_contains "and never into argv" "$(calls)" "env-token-0000"
unset HASEEN_XBACKBONE_URL HASEEN_XBACKBONE_TOKEN HASEEN_XBACKBONE_API
capture haseen upload "$SHOT" --backend xbackbone
assert_status "XBackBone without a url refuses" 1 "$STATUS"
assert_contains "and says where to configure it" "$OUTPUT" "no XBackBone instance configured"

# --- real runs: imgur and rclone --------------------------------------------
cap_sandbox upload-imgur
capture haseen upload "$SHOT" --backend imgur
assert_status "imgur without a client id refuses" 1 "$STATUS"
assert_contains "and explains that registration is closed" "$OUTPUT" "registration is closed"
write_upload_config '[imgur]
client_id = "'"$IMGUR_ID"'"'
export CURL_BODY='{"data":{"link":"https://i.imgur.com/x.png","deletehash":"dh"},"success":true}'
capture haseen upload "$SHOT" --backend imgur
assert_eq "imgur returns data.link" "https://i.imgur.com/x.png" "$OUTPUT"
assert_contains "imgur uses the v3 image endpoint" "$(calls)" "-F image=@\"$SHOT\" https://api.imgur.com/3/image"
assert_contains "the client id goes on stdin" "$(curl_stdin)" "header = \"Authorization: Client-ID $IMGUR_ID\""
assert_not_contains "the client id never reaches argv" "$(calls)" "$IMGUR_ID"

cap_sandbox upload-rclone
write_upload_config '[rclone]
remote = "r2:bucket/shots"
link_expire = "1d"'
capture haseen upload "$SHOT" --backend rclone
assert_eq "rclone returns the link" "https://r2.example.com/shot.png" "$OUTPUT"
assert_contains "rclone copies first" "$(calls)" "rclone copyto $SHOT r2:bucket/shots/shot.png"
assert_contains "rclone link honours the expiry" "$(calls)" "rclone link r2:bucket/shots/shot.png --expire 1d"
assert_not_contains "rclone needs no curl" "$(calls)" "curl "

# --- a world-readable credentials file is reported ---------------------------
cap_sandbox upload-perms
write_upload_config '[xbackbone]
url = "https://share.example.com"
token = "'"$TOKEN"'"
api = "form"'
chmod 644 "$HASEEN_UPLOAD_CONFIG"
export CURL_BODY='{"url":"https://share.example.com/abcd.png"}'
capture haseen upload "$SHOT"
assert_contains "a readable credentials file is a warning" "$OUTPUT" "readable by others (mode 644)"
assert_not_contains "the warning does not quote the token" "$OUTPUT" "$TOKEN"

# --- the real curl against a local receiver: exactly the selected file -------
# Every file part goes through one encoder. curl's -F grammar splits an
# unquoted @value at ',' (a file list) and ';' (type=/filename=), so a file
# named "shot.png,.env" beside shot.png and .env must upload its own bytes and
# nothing else. The stub curl only rewrites https://HOST to the loopback
# receiver and execs the real curl; the receiver parses the multipart body.
REAL_CURL="$(PATH=/usr/local/bin:/usr/bin:/bin command -v curl || true)"
if [[ -z $REAL_CURL ]]; then
    echo "  (note: curl is not installed; multipart receiver regressions were skipped)"
else
    cap_sandbox upload-multipart
    RECV_LOG="$SANDBOX/received.jsonl"
    python3 "$FIXTURES/multipart-receiver.py" "$SANDBOX/port" "$RECV_LOG" &
    RECV_PID=$!
    for _ in $(seq 100); do [[ -s $SANDBOX/port ]] && break; sleep 0.05; done
    RECV_PORT="$(cat "$SANDBOX/port")"
    export REAL_CURL RECV_PORT
    # The fake https endpoint is the plain-http receiver, so the stub lowers
    # the uploader's --proto =https with it; the real-https cases below use
    # the real curl unchanged.
    cat >"$SANDBOX/stubs/curl" <<'EOF'
#!/usr/bin/env bash
args=()
for a in "$@"; do
    if [[ $a == https://* ]]; then
        rest=${a#https://}
        [[ $rest == */* ]] && a="http://127.0.0.1:$RECV_PORT/${rest#*/}" || a="http://127.0.0.1:$RECV_PORT/"
    elif [[ $a == =https ]]; then
        a==http
    fi
    args+=("$a")
done
exec "$REAL_CURL" "${args[@]}"
EOF
    chmod +x "$SANDBOX/stubs/curl"
    files="$SANDBOX/files"
    mkdir -p "$files"
    printf 'sibling shot bytes' >"$files/shot.png"
    printf 'SECRET=do-not-upload\n' >"$files/.env"
    received_file_parts() { # → "sha256" per file part of the last request
        tail -n1 "$RECV_LOG" | jq -r '.parts[] | select(.filename != null) | .sha256'
    }
    export HASEEN_IMGUR_CLIENT_ID="$IMGUR_ID" HASEEN_0X0_URL="http://127.0.0.1:$RECV_PORT"
    for name in 'shot.png,.env' 'semi;filename=evil.png' 'q"uote.png' 'back\slash.png'; do
        printf 'selected file: %s' "$name" >"$files/$name"
        want="$(sha256sum <"$files/$name" | cut -d' ' -f1)"
        for b in catbox uguu temp.sh 0x0 imgur xbackbone:form xbackbone:bearer; do
            unset HASEEN_XBACKBONE_URL HASEEN_XBACKBONE_TOKEN HASEEN_XBACKBONE_API
            if [[ $b == xbackbone:* ]]; then
                export HASEEN_XBACKBONE_URL="http://127.0.0.1:$RECV_PORT" HASEEN_XBACKBONE_TOKEN="$TOKEN"
                export HASEEN_XBACKBONE_API=${b#*:}
            fi
            : >"$RECV_LOG"
            capture haseen upload "$files/$name" --backend "${b%%:*}" --no-copy --quiet
            assert_status "$b uploads '$name'" 0 "$STATUS"
            assert_eq "$b sends exactly the bytes of '$name', one file part" "$want" "$(received_file_parts)"
        done
    done
    unset HASEEN_XBACKBONE_URL HASEEN_XBACKBONE_TOKEN HASEEN_XBACKBONE_API
    # A token is a literal form string: "@path" is never read as a file.
    export HASEEN_XBACKBONE_URL="http://127.0.0.1:$RECV_PORT" HASEEN_XBACKBONE_API=form
    export HASEEN_XBACKBONE_TOKEN="@$files/.env"
    : >"$RECV_LOG"
    capture haseen upload "$files/shot.png" --backend xbackbone --no-copy --quiet
    assert_status "an @-leading token uploads" 0 "$STATUS"
    assert_eq "the token field is the literal token, not a file" "@$files/.env" \
        "$(tail -n1 "$RECV_LOG" | jq -r '.parts[] | select(.name == "token") | .value')"
    assert_not_contains "the token's named file is never sent" "$(cat "$RECV_LOG")" \
        "$(sha256sum <"$files/.env" | cut -d' ' -f1)"

    # --- curl's own configuration never widens the transport (SEC-6) ---------
    # start_receiver NAME ARGS… — another receiver: NAME_port, NAME.jsonl.
    EXTRA_PIDS=()
    start_receiver() {
        local name=$1
        shift
        python3 "$FIXTURES/multipart-receiver.py" "$SANDBOX/$name.port" "$SANDBOX/$name.jsonl" "$@" &
        EXTRA_PIDS+=($!)
        for _ in $(seq 100); do [[ -s $SANDBOX/$name.port ]] && break; sleep 0.05; done
        : >"$SANDBOX/$name.jsonl"
    }
    # An inherited remote proxy (here a recording receiver) never carries the
    # plaintext loopback request with the token and the file.
    start_receiver proxy
    export HASEEN_XBACKBONE_URL="http://127.0.0.1:$RECV_PORT" HASEEN_XBACKBONE_API=form HASEEN_XBACKBONE_TOKEN="$TOKEN"
    : >"$RECV_LOG"
    proxy="http://127.0.0.1:$(cat "$SANDBOX/proxy.port")"
    capture env -u no_proxy -u NO_PROXY http_proxy="$proxy" all_proxy="$proxy" ALL_PROXY="$proxy" \
        haseen upload "$files/shot.png" --backend xbackbone --no-copy --quiet
    assert_status "a loopback upload with a proxy in the environment succeeds" 0 "$STATUS"
    assert_eq "the proxy never sees the loopback upload" "" "$(cat "$SANDBOX/proxy.jsonl")"
    assert_eq "the loopback instance gets the token directly" "$TOKEN" \
        "$(tail -n1 "$RECV_LOG" | jq -r '.parts[] | select(.name == "token") | .value')"
    # A ~/.curlrc asking to follow redirects never replays the form, token and
    # file from an https instance to the plain-http address its 307 names.
    if command -v openssl >/dev/null; then
        openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 1 \
            -subj /CN=127.0.0.1 -addext subjectAltName=IP:127.0.0.1 \
            -keyout "$SANDBOX/tls.key" -out "$SANDBOX/tls.crt" 2>/dev/null
        start_receiver observer
        start_receiver tls --tls "$SANDBOX/tls.crt" "$SANDBOX/tls.key" \
            --redirect "http://127.0.0.1:$(cat "$SANDBOX/observer.port")/upload"
        printf 'location\n' >"$HOME/.curlrc"
        printf '#!/usr/bin/env bash\nexec "$REAL_CURL" "$@"\n' >"$SANDBOX/stubs/curl"
        capture env CURL_HOME="$HOME" CURL_CA_BUNDLE="$SANDBOX/tls.crt" \
            HASEEN_XBACKBONE_URL="https://127.0.0.1:$(cat "$SANDBOX/tls.port")" \
            haseen upload "$files/shot.png" --backend xbackbone --no-copy --quiet
        assert_eq "the https instance received the upload" 1 "$(grep -c . "$SANDBOX/tls.jsonl")"
        assert_eq "the redirect is not followed: nothing reaches plain http" "" "$(cat "$SANDBOX/observer.jsonl")"
        rm -f "$HOME/.curlrc"
    else
        echo "  (note: openssl is not installed; the https redirect regression was skipped)"
    fi
    kill "${EXTRA_PIDS[@]}" 2>/dev/null || true
    wait "${EXTRA_PIDS[@]}" 2>/dev/null || true
    unset HASEEN_XBACKBONE_URL HASEEN_XBACKBONE_TOKEN HASEEN_XBACKBONE_API HASEEN_IMGUR_CLIENT_ID HASEEN_0X0_URL
    kill "$RECV_PID" 2>/dev/null || true
    wait "$RECV_PID" 2>/dev/null || true
fi

# --- a token or management token never crosses a network in the clear ------
cap_sandbox upload-plaintext
export CURL_BODY='{"url":"https://share.example.com/abcd.png"}' HASEEN_XBACKBONE_TOKEN="$TOKEN"
for url in http://share.example.com share.example.com 'http://localhost@evil.example.com' 'http://127.0.0.1.evil.example'; do
    : >"$CALLS"
    HASEEN_XBACKBONE_URL="$url" capture haseen upload "$SHOT" --backend xbackbone
    assert_status "XBackBone at '$url' is refused" 1 "$STATUS"
    assert_contains "and says to use https" "$OUTPUT" "use an https:// URL"
    assert_not_contains "nothing is sent to '$url'" "$(calls)" "curl"
done
for url in http://localhost:8080 'http://127.0.0.1:9000/xbb' 'http://[::1]:8080' https://share.example.com; do
    HASEEN_XBACKBONE_URL="$url" HASEEN_XBACKBONE_API=form capture haseen upload "$SHOT" --backend xbackbone --dry-run
    assert_status "XBackBone at '$url' is allowed" 0 "$STATUS"
done
: >"$CALLS"
HASEEN_0X0_URL=http://0x0.example.com capture haseen upload "$SHOT" --backend 0x0
assert_status "a plain-http 0x0 (it returns a management token) is refused" 1 "$STATUS"
assert_not_contains "nothing is sent to the plain-http 0x0" "$(calls)" "curl"
unset HASEEN_XBACKBONE_TOKEN

# --- the XBackBone probe: a connection failure is not "next-gen" -------------
cap_sandbox upload-xbb-probe-fail
write_upload_config '[xbackbone]
url = "https://share.example.com"
token = "'"$TOKEN"'"'
export CURL_BODY='{"url":"https://share.example.com/abcd.png"}' CURL_PROBE_CODE=000 CURL_PROBE_RC=7
capture haseen upload "$SHOT"
assert_contains "a failed probe falls back to the tagged release" "$(calls)" "https://share.example.com/upload"
assert_not_contains "and never to the next-gen route" "$(calls)" "api/v1/upload https"

# --- the delete token is private, never a shared /tmp file -------------------
token_file="haseen-upload.delete-token"
for runtime in shared unset; do
    cap_sandbox "upload-token-$runtime"
    export CURL_BODY="https://0x0.st/aB.png" CURL_HEADERS=$'HTTP/2 200\nx-token: 0x0-fixture-management-token\n'
    if [[ $runtime == shared ]]; then chmod 755 "$XDG_RUNTIME_DIR"; else unset XDG_RUNTIME_DIR; fi
    saved_umask="$(umask)"
    umask 022
    capture haseen upload "$SHOT" --backend 0x0 --no-copy --quiet
    umask "$saved_umask"
    assert_status "$runtime runtime dir: the upload succeeds" 0 "$STATUS"
    [[ $runtime == unset ]] || assert_eq "$runtime runtime dir: the token is not left there" no \
        "$([[ -e $SANDBOX/run/$token_file ]] && echo yes || echo no)"
    state="$XDG_STATE_HOME/haseen/upload"
    assert_eq "$runtime runtime dir: the token is kept in the private state dir" "0x0-fixture-management-token" \
        "$(cat "$state/$token_file" 2>/dev/null)"
    assert_eq "$runtime runtime dir: that dir is 0700" 700 "$(stat -c %a "$state" 2>/dev/null)"
    assert_eq "$runtime runtime dir: the token file is 0600" 600 "$(stat -c %a "$state/$token_file" 2>/dev/null)"
done
cap_sandbox upload-token-link
export CURL_BODY="https://0x0.st/aB.png" CURL_HEADERS=$'HTTP/2 200\nx-token: 0x0-fixture-management-token\n'
printf 'victim\n' >"$SANDBOX/victim"
ln -s "$SANDBOX/victim" "$XDG_RUNTIME_DIR/$token_file"
capture haseen upload "$SHOT" --backend 0x0 --no-copy --quiet
assert_eq "a link planted at the token path is never written through" victim "$(cat "$SANDBOX/victim")"
assert_eq "the link is replaced by the private token file" "0x0-fixture-management-token" \
    "$([[ ! -L $XDG_RUNTIME_DIR/$token_file ]] && cat "$XDG_RUNTIME_DIR/$token_file")"
assert_eq "the replaced token file is 0600" 600 "$(stat -c %a "$XDG_RUNTIME_DIR/$token_file")"

# --- OCR: the exact argv -----------------------------------------------------
OCR_ARGV="--oem 1 --psm 6 -l ara+eng -c preserve_interword_spaces=1"
cap_sandbox ocr
capture haseen capture text --geometry "0,0 10x10" --dry-run
assert_status "capture text dry run exits 0" 0 "$STATUS"
assert_eq "the planned OCR argv is exact" \
    "DRYRUN: grim -g 0,0 10x10 - | tesseract stdin stdout $OCR_ARGV | wl-copy" "$OUTPUT"
assert_not_contains "no --dpi 300: it merged words in the measurement" "$OUTPUT" "--dpi"
capture haseen capture text --image "$SHOT" --lang eng --dry-run
assert_eq "an image and a language are planned the same way" \
    "DRYRUN: cat $SHOT | tesseract $SHOT stdout --oem 1 --psm 6 -l eng -c preserve_interword_spaces=1 | wl-copy" "$OUTPUT"
capture haseen capture text --image "$SHOT"
assert_status "capture text on an image succeeds" 0 "$STATUS"
assert_contains "the real OCR argv matches the plan" "$(calls)" \
    "tesseract $SHOT stdout $OCR_ARGV"
assert_contains "the text lands on the clipboard" "$(calls)" "wl-copy : recognised text"
assert_not_contains "the recognised text is never put in a notification" \
    "$(grep notify-send "$CALLS")" "recognised text"
TESS_TEXT="   " capture haseen capture text --image "$SHOT"
assert_status "empty OCR output fails" 1 "$STATUS"

# --- circle to search --------------------------------------------------------
cap_sandbox search-dry
capture haseen search screen --dry-run
assert_status "search screen dry run exits 0" 0 "$STATUS"
assert_dry_pure "search screen dry run" "$OUTPUT"
assert_contains "it freezes the screen first" "$OUTPUT" "DRYRUN: hyprpicker -r -z (freeze the screen)"
assert_contains "the default mode is the same local OCR" "$OUTPUT" \
    "DRYRUN: grim -g <slurp selection> - | tesseract stdin stdout $OCR_ARGV | wl-copy"
assert_not_contains "and nothing is uploaded by default" "$OUTPUT" "lens.google.com"
capture haseen search screen image --dry-run
assert_contains "image mode hands off through the clipboard" "$OUTPUT" "wl-copy --type image/png --sensitive"
assert_not_contains "image mode uploads nothing on its own" "$OUTPUT" "lens.google.com"
capture haseen search screen image --upload --dry-run
assert_contains "the upload path asks first" "$OUTPUT" "DRYRUN: confirm: this uploads the capture to Google"
assert_contains "the upload path posts to Lens" "$OUTPUT" \
    "DRYRUN: curl -X POST -F encoded_image=@<capture> https://lens.google.com/v3/upload"
assert_contains "and opens the Location header" "$OUTPUT" "DRYRUN: xdg-open <the Location: header>"
capture haseen search screen --upload --dry-run
assert_status "--upload outside image mode is a usage error" 2 "$STATUS"
capture haseen search screen --provider nope --dry-run
assert_status "an unknown provider is a usage error" 2 "$STATUS"

cap_sandbox search-text
capture haseen search screen --print
assert_status "the local path succeeds" 0 "$STATUS"
assert_eq "it prints what it read" "recognised text" "$OUTPUT"
assert_contains "it froze the screen" "$(calls)" "hyprpicker -r -z"
assert_contains "the OCR argv is the measured one" "$(calls)" "tesseract stdin stdout $OCR_ARGV"
assert_contains "the text is copied" "$(calls)" "wl-copy : recognised text"
assert_not_contains "nothing was uploaded" "$(calls)" "curl"
assert_not_contains "and no browser was opened" "$(calls)" "xdg-open"
capture haseen search screen --search
assert_status "--search succeeds" 0 "$STATUS"
assert_eq "--search says nothing on stdout" "" "$OUTPUT"
assert_contains "--search opens a text search" "$(calls)" "xdg-open https://www.google.com/search?q=recognised%20text"
# RV-4: the OCR reads the whole picture grim writes, however late it comes; a
# reader that left early would turn a good capture into "OCR failed".
GRIM_DELAY=0.3 capture haseen search screen --geometry "0,0 10x10" --print
assert_status "a slow grim still reaches the OCR" 0 "$STATUS"
assert_eq "and its text is read" "recognised text" "$OUTPUT"

cap_sandbox search-image
capture haseen search screen image
assert_status "image mode succeeds" 0 "$STATUS"
assert_contains "the capture is copied as sensitive" "$(calls)" "wl-copy --type image/png --sensitive"
assert_contains "the hand-off page is opened" "$(calls)" "xdg-open https://imgops.com/"
assert_not_contains "image mode never calls out on its own" "$(calls)" "curl "
assert_eq "the capture is deleted afterwards" "" \
    "$(find "$XDG_RUNTIME_DIR/haseen-search-screen" -type f 2>/dev/null)"

cap_sandbox search-lens
export CURL_HEADERS="HTTP/2 200
location: https://www.google.com/search?vsrid=FIXTURE&udm=26
"
capture haseen search screen image --upload --yes
assert_status "the consented upload succeeds" 0 "$STATUS"
assert_contains "it warns before it sends anything" "$OUTPUT" "sends the captured picture of your screen to Google"
assert_contains "the Lens request shape" "$(calls)" "-F encoded_image=@$XDG_RUNTIME_DIR/haseen-search-screen/capture-"
assert_contains "it posts to the v3 upload endpoint" "$(calls)" "https://lens.google.com/v3/upload"
assert_contains "it follows the Location header" "$(calls)" "xdg-open https://www.google.com/search?vsrid=FIXTURE&udm=26"
assert_eq "the capture is deleted after the upload" "" \
    "$(find "$XDG_RUNTIME_DIR/haseen-search-screen" -type f 2>/dev/null)"
assert_eq "the capture directory is private" "700" \
    "$(stat -c '%a' "$XDG_RUNTIME_DIR/haseen-search-screen")"

cap_sandbox search-lens-refused
capture haseen search screen image --upload </dev/null
assert_status "a declined upload is not a failure" 0 "$STATUS"
assert_contains "and it says nothing was sent" "$OUTPUT" "Nothing was uploaded."
assert_not_contains "no request was made" "$(calls)" "lens.google.com"

# RV-2: --image works on a copy the command makes in its private directory.
# Every way out removes that copy; the user's own file is never touched.
search_copies() { find "$XDG_RUNTIME_DIR/haseen-search-screen" -type f 2>/dev/null; }
cap_sandbox search-image-file
printf 'PNG-original' >"$SHOT"
capture haseen search screen image --image "$SHOT"
assert_status "--image hand-off succeeds" 0 "$STATUS"
assert_contains "--image hand-off: the picture goes on the clipboard" "$(calls)" \
    "wl-copy --type image/png --sensitive: PNG-original"
assert_eq "--image hand-off: the original is unchanged" "PNG-original" "$(cat "$SHOT")"
assert_eq "--image hand-off: the temporary copy is gone" "" "$(search_copies)"
export CURL_HEADERS="HTTP/2 200
location: https://www.google.com/search?vsrid=FIXTURE&udm=26
"
capture haseen search screen image --image "$SHOT" --upload --yes
assert_status "--image upload succeeds" 0 "$STATUS"
assert_contains "--image upload: the copy is what is sent" "$(calls)" \
    "-F encoded_image=@$XDG_RUNTIME_DIR/haseen-search-screen/capture-"
assert_eq "--image upload: the original is unchanged" "PNG-original" "$(cat "$SHOT")"
assert_eq "--image upload: the temporary copy is gone" "" "$(search_copies)"
capture haseen search screen image --image "$SHOT" --upload </dev/null
assert_contains "--image declined: nothing was sent" "$OUTPUT" "Nothing was uploaded."
assert_eq "--image declined: the original is unchanged" "PNG-original" "$(cat "$SHOT")"
assert_eq "--image declined: the temporary copy is gone" "" "$(search_copies)"

# RV-1: a picture of the screen is stored only in a private directory of ours.
# Without XDG_RUNTIME_DIR there is no shared /tmp fallback, and an existing
# capture directory that is a link, someone else's, or open to others is
# refused before anything is swept or captured into it.
# refused_store LABEL — the last run captured nothing and said why.
refused_store() {
    assert_status "$1: refused" 1 "$STATUS"
    assert_contains "$1: it says why" "$OUTPUT" "not a private directory"
    assert_not_contains "$1: nothing was captured" "$(calls)" "grim"
    assert_not_contains "$1: nothing reached the clipboard" "$(calls)" "wl-copy"
}
cap_sandbox search-store-noruntime
capture env -u XDG_RUNTIME_DIR haseen search screen image --geometry "0,0 10x10"
assert_status "no XDG_RUNTIME_DIR: refused" 1 "$STATUS"
assert_contains "no XDG_RUNTIME_DIR: it says why" "$OUTPUT" "XDG_RUNTIME_DIR"
assert_not_contains "no XDG_RUNTIME_DIR: no /tmp fallback, nothing captured" "$(calls)" "grim"

cap_sandbox search-store-runtime-open
chmod 755 "$XDG_RUNTIME_DIR"
capture haseen search screen image --geometry "0,0 10x10"
refused_store "a runtime dir open to others"
assert_eq "a runtime dir open to others: no capture dir is made in it" "absent" \
    "$([[ -e $XDG_RUNTIME_DIR/haseen-search-screen ]] && echo present || echo absent)"

cap_sandbox search-store-link
mkdir -m 700 "$SANDBOX/elsewhere"
printf old >"$SANDBOX/elsewhere/capture-old"
touch -d '-1 hour' "$SANDBOX/elsewhere/capture-old"
ln -s "$SANDBOX/elsewhere" "$XDG_RUNTIME_DIR/haseen-search-screen"
capture haseen search screen image --geometry "0,0 10x10"
refused_store "a symlinked capture dir"
assert_eq "a symlinked capture dir: nothing is swept or written through it" "capture-old" \
    "$(ls -A "$SANDBOX/elsewhere")"
assert_eq "a symlinked capture dir: the link is left alone" "$SANDBOX/elsewhere" \
    "$(readlink "$XDG_RUNTIME_DIR/haseen-search-screen")"

cap_sandbox search-store-open
mkdir -m 755 "$XDG_RUNTIME_DIR/haseen-search-screen"
printf old >"$XDG_RUNTIME_DIR/haseen-search-screen/capture-old"
touch -d '-1 hour' "$XDG_RUNTIME_DIR/haseen-search-screen/capture-old"
capture haseen search screen image --geometry "0,0 10x10"
refused_store "a capture dir open to others"
assert_eq "a capture dir open to others: its mode and contents are not touched" "755|capture-old" \
    "$(stat -c %a "$XDG_RUNTIME_DIR/haseen-search-screen")|$(ls -A "$XDG_RUNTIME_DIR/haseen-search-screen")"

# A directory that is really someone else's needs a second uid: the user's
# subordinate range, through an unprivileged user namespace, chowns a fresh
# 0700 directory to it.
cap_sandbox search-store-foreign
foreign="$XDG_RUNTIME_DIR/haseen-search-screen"
if unshare --map-auto --map-root-user sh -c 'mkdir -m 700 -- "$1" && chown 1:1 -- "$1"' sh "$foreign" 2>/dev/null &&
    [[ -d $foreign && ! -O $foreign ]]; then
    capture haseen search screen image --geometry "0,0 10x10"
    refused_store "someone else's capture dir"
else
    echo "  skip: no subordinate uid to own a foreign capture dir (unshare --map-auto)" >&2
fi

# --- annotate then upload ----------------------------------------------------
cap_sandbox shot-upload
capture haseen capture screenshot --geometry "0,0 10x10" --edit --upload --dry-run
assert_status "the annotate-then-upload plan exits 0" 0 "$STATUS"
assert_dry_pure "annotate-then-upload plan" "$OUTPUT"
assert_contains "the editor is planned" "$OUTPUT" "DRYRUN: satty --filename"
assert_contains "the upload is planned after it" "$OUTPUT" "DRYRUN: haseen-upload"
assert_contains "and the link replaces the image on the clipboard" "$OUTPUT" "the link replaces the image on the clipboard"
export CURL_BODY="https://files.catbox.moe/zz.png"
capture haseen capture screenshot --geometry "0,0 10x10" --edit --upload
assert_status "annotate then upload succeeds" 0 "$STATUS"
assert_contains "satty edited the file in place" "$(calls)" "satty --filename"
assert_contains "satty ran before the upload" "$(calls)" "satty"
assert_contains "the link is returned" "$OUTPUT" "https://files.catbox.moe/zz.png"
assert_contains "the link ends up on the clipboard" "$(calls)" "wl-copy : https://files.catbox.moe/zz.png"
assert_eq "the image is copied first, the link last" "image link" \
    "$(grep -c 'wl-copy -t image/png' "$CALLS" >/dev/null && \
       awk '/wl-copy -t image\/png/{print "image"} /wl-copy : https/{print "link"}' "$CALLS" | tr '\n' ' ' | sed 's/ $//')"
capture haseen capture screenshot --geometry "0,0 10x10" --upload-to uguu --dry-run
assert_contains "--upload-to names the backend" "$OUTPUT" "DRYRUN: haseen-upload $HOME/PICTURES/screenshot-"
assert_contains "--upload-to passes the backend through" "$OUTPUT" "--backend uguu"

# --- the seed ----------------------------------------------------------------
cap_sandbox capture-seed
export HASEEN_SYSROOT="$FIXTURES/seeds-plain"
capture haseen seed user --dry-run
assert_status "the seed dry run succeeds" 0 "$STATUS"
assert_dry_pure "capture seed dry run" "$OUTPUT"
assert_contains "satty's config is planned" "$OUTPUT" "DRYRUN: seed $HOME/.config/satty/config.toml"
assert_contains "satty's colours are linked to the theme pipeline" "$OUTPUT" \
    "DRYRUN: ln -snf $HOME/.local/state/haseen/current/theme/satty.css $HOME/.config/satty/overrides.css"
assert_contains "the uploader's credentials file is planned" "$OUTPUT" \
    "DRYRUN: write $HOME/.config/haseen/upload.toml"
assert_contains "and it is planned as 0600" "$OUTPUT" "DRYRUN: chmod 600 $HOME/.config/haseen/upload.toml"
capture haseen seed user
assert_status "seeding succeeds" 0 "$STATUS"
assert_eq "satty's config landed" "yes" "$([[ -f $HOME/.config/satty/config.toml ]] && echo yes)"
assert_eq "the overrides link points at the theme render" \
    "$HOME/.local/state/haseen/current/theme/satty.css" \
    "$(readlink "$HOME/.config/satty/overrides.css")"
assert_eq "the credentials file is private" "600" "$(stat -c '%a' "$HOME/.config/haseen/upload.toml")"
assert_eq "the credentials file holds no credential" "" \
    "$(grep -vE '^[[:space:]]*(#|$)' "$HOME/.config/haseen/upload.toml")"
assert_contains "satty copies with wl-copy" "$(cat "$HOME/.config/satty/config.toml")" 'copy-command = "wl-copy"'
assert_contains "satty's palette is high contrast, not theme-derived" \
    "$(cat "$HOME/.config/satty/config.toml")" '"#eb4d4bff"'
capture haseen seed user --dry-run
assert_eq "a second plan is empty" "" "$(grep -c DRYRUN <<<"$OUTPUT" | tr -d '0')"
# The file is private from the moment it exists, not only after the chmod:
# with chmod a no-op the mode it was created with shows.
cap_sandbox capture-seed-umask
export HASEEN_SYSROOT="$FIXTURES/seeds-plain"
stub chmod 'exit 0'
saved_umask="$(umask)"
umask 022
capture haseen seed user
umask "$saved_umask"
assert_eq "upload.toml is created 0600, never world-readable first" 600 \
    "$(stat -c '%a' "$HOME/.config/haseen/upload.toml")"

# --- nothing in the tree carries a credential --------------------------------
assert_eq "no backend bakes in a key" "" \
    "$(grep -nE 'Client-ID [A-Za-z0-9]{8,}|Bearer [A-Za-z0-9]{8,}' "$REPO/bin/haseen-upload" || true)"
