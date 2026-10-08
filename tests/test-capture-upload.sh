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
    mkdir -p "$XDG_RUNTIME_DIR"
    CALLS="$SANDBOX/calls"
    CALLS_STDIN="$SANDBOX/calls.stdin"
    : >"$CALLS"
    : >"$CALLS_STDIN"
    export CALLS CALLS_STDIN
    export CURL_BODY="" CURL_HEADERS="" CURL_RC=0 CURL_PROBE_CODE=404
    stub notify-send 'echo "notify-send $*" >>"$CALLS"'
    stub wl-copy 'printf "wl-copy %s: " "$*" >>"$CALLS"; cat >>"$CALLS"; echo >>"$CALLS"'
    stub xdg-user-dir 'echo "$HOME/$1"'
    stub xdg-open 'echo "xdg-open $*" >>"$CALLS"'
    stub grim 'echo "grim $*" >>"$CALLS"
out=""; prev=""
for a in "$@"; do prev2=$prev; prev=$a; done
[ -n "$prev" ] && [ "$prev" != "-" ] && out=$prev
if [ -n "$out" ]; then printf PNG >"$out"; else printf PNG; fi'
    stub slurp 'echo "0,0 100x100"'
    stub hyprpicker 'echo "hyprpicker $*" >>"$CALLS"; sleep 2'
    stub satty 'echo "satty $*" >>"$CALLS"'
    stub rclone 'echo "rclone $*" >>"$CALLS"; [ "$1" = link ] && echo "https://r2.example.com/shot.png"; exit 0'
    stub tesseract 'echo "tesseract $*" >>"$CALLS"; printf "%s" "${TESS_TEXT:-recognised text}"'
    # Records argv and the curl config read on stdin; answers with $CURL_BODY
    # and $CURL_HEADERS. -w (used only by the XBackBone probe) answers a code.
    stub curl 'echo "curl $*" >>"$CALLS"
probe=0; prev=""; dump=""
for a in "$@"; do
  [ "$prev" = "-D" ] && dump=$a
  [ "$a" = "-w" ] && probe=1
  prev=$a
done
if [ "$probe" = 1 ]; then printf "%s" "${CURL_PROBE_CODE:-404}"; exit 0; fi
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
assert_contains "catbox endpoint planned" "$OUTPUT" "-F reqtype=fileupload -F fileToUpload=@$SHOT https://catbox.moe/user/api.php"
capture haseen upload "$SHOT" --backend uguu --dry-run
assert_contains "uguu endpoint planned" "$OUTPUT" "-F files[]=@$SHOT https://uguu.se/upload?output=text"
capture haseen upload "$SHOT" --backend temp.sh --dry-run
assert_contains "temp.sh endpoint planned" "$OUTPUT" "-F file=@$SHOT https://temp.sh/upload"
capture haseen upload "$SHOT" --backend 0x0 --expires 2 --dry-run
assert_contains "0x0 endpoint planned" "$OUTPUT" "-F file=@$SHOT -F expires=2 https://0x0.st"
capture haseen upload "$SHOT" --backend xbackbone --dry-run
assert_contains "xbackbone endpoint planned" "$OUTPUT" "-F upload=@$SHOT https://share.example.com/upload"
assert_contains "the plan says where the token comes from" "$OUTPUT" "read from $HASEEN_UPLOAD_CONFIG and passed on stdin (never shown)"
capture haseen upload "$SHOT" --backend imgur --dry-run
assert_contains "imgur endpoint planned" "$OUTPUT" "-F image=@$SHOT https://api.imgur.com/3/image"
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
assert_contains "catbox request shape" "$(calls)" "-F reqtype=fileupload -F fileToUpload=@$SHOT https://catbox.moe/user/api.php"
assert_contains "catbox sends a haseen user agent" "$(calls)" "-A haseen-upload/"
assert_contains "the link lands on the clipboard" "$(calls)" "wl-copy : https://files.catbox.moe/abc123.png"
assert_contains "the upload is notified" "$(calls)" "notify-send -a haseen"
assert_eq "no credential is ever sent for an anonymous host" "" "$(curl_stdin)"

cap_sandbox upload-uguu
export CURL_BODY="https://d.uguu.se/bTPPlbJd.png"
capture haseen upload "$SHOT" --backend uguu --no-copy --quiet
assert_eq "uguu returns the link" "https://d.uguu.se/bTPPlbJd.png" "$OUTPUT"
assert_contains "uguu request shape" "$(calls)" "-F files[]=@$SHOT https://uguu.se/upload?output=text"
assert_not_contains "--no-copy keeps the clipboard alone" "$(calls)" "wl-copy"
assert_not_contains "--quiet sends no notification" "$(calls)" "notify-send"

cap_sandbox upload-temp
export CURL_BODY="https://temp.sh/aBcDe/shot.png"
capture haseen upload "$SHOT" --backend temp.sh
assert_eq "temp.sh returns the link" "https://temp.sh/aBcDe/shot.png" "$OUTPUT"
assert_contains "temp.sh request shape" "$(calls)" "-F file=@$SHOT https://temp.sh/upload"

cap_sandbox upload-0x0
export CURL_BODY="https://0x0.st/aB.png"
export CURL_HEADERS="HTTP/2 200
x-token: 0x0-fixture-management-token
"
capture haseen upload "$SHOT" --backend 0x0 --expires 1
assert_eq "0x0 returns the link" "https://0x0.st/aB.png" "$OUTPUT"
assert_contains "0x0 request shape" "$(calls)" "-F file=@$SHOT -F expires=1 https://0x0.st"
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
assert_contains "the file part is sent" "$(calls)" "-F upload=@$SHOT"
assert_contains "the token goes to curl on stdin" "$(curl_stdin)" "form = \"token=$TOKEN\""
assert_not_contains "the token never reaches the command line" "$(calls)" "$TOKEN"
assert_not_contains "the token is never printed" "$OUTPUT" "$TOKEN"
assert_contains "curl reads its credentials from stdin" "$(calls)" "--config -"

cap_sandbox upload-xbb-bearer
write_upload_config '[xbackbone]
url = "https://share.example.com"
token = "'"$TOKEN"'"
api = "bearer"'
export CURL_BODY='{"data":{"raw_url":"https://share.example.com/r/abcd.png","deletion_url":"x"}}'
capture haseen upload "$SHOT" --backend xbackbone
assert_eq "the next-gen raw link is returned" "https://share.example.com/r/abcd.png" "$OUTPUT"
assert_contains "the next-gen endpoint is used" "$(calls)" "https://share.example.com/api/v1/upload"
assert_contains "the next-gen file part is file=" "$(calls)" "-F file=@$SHOT"
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
assert_contains "the env token also goes on stdin" "$(curl_stdin)" 'form = "token=env-token-0000"'
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
assert_contains "imgur uses the v3 image endpoint" "$(calls)" "-F image=@$SHOT https://api.imgur.com/3/image"
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

# --- nothing in the tree carries a credential --------------------------------
assert_eq "no backend bakes in a key" "" \
    "$(grep -nE 'Client-ID [A-Za-z0-9]{8,}|Bearer [A-Za-z0-9]{8,}' "$REPO/bin/haseen-upload" || true)"
