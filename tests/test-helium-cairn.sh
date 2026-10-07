# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# tests/test-helium-cairn.sh — plan 073: the shell layer installs Helium and
# hands Cairn's release .crx to it (lib/cairn.sh, bin/haseen-setup-cairn).
# curl is a stub that serves files from $SANDBOX/srv by URL basename; the
# .crx files are fakes built here, with a test key, never Cairn's code.

CAIRN_REAL_ID=bddeidknhkokohcgdkpgdmlppgfkblig

# hexbytes HEX — the bytes HEX spells.
hexbytes() { printf '%b' "$(sed 's/../\\x&/g' <<<"$1")"; }
tohex() { od -An -tx1 -v | tr -d ' \n'; }
len8() { printf '%02x' "$1"; } # every length here is under 128: a one-byte varint

# fake_crx OUT KEY PAYLOAD [ID_KEY] — a CRX3 file with one RSA proof for KEY
# and a signed header naming the ID of ID_KEY (default KEY), then PAYLOAD.
fake_crx() {
    local out="$1" key="$2" payload="$3" idkey="${4:-$2}" keyhex idhex proof signed header
    keyhex="$(printf '%s' "$key" | tohex)"
    idhex="$(printf '%s' "$idkey" | sha256sum | cut -c1-32)"
    proof="0a$(len8 ${#key})${keyhex}1203736967"
    signed="0a10$idhex"
    header="12$(len8 $((${#proof} / 2)))${proof}82f104$(len8 $((${#signed} / 2)))$signed"
    {
        printf 'Cr24'
        hexbytes "03000000$(len8 $((${#header} / 2)))000000$header"
        printf 'PK\003\004%s' "$payload"
    } >"$out"
}
key_id() { printf '%s' "$1" | sha256sum | cut -c1-32 | tr '0-9a-f' 'a-p'; }
sha() { sha256sum -- "$1" | cut -d' ' -f1; }

serve_curl() {
    mkdir -p "$SANDBOX/srv"
    cat >"$SANDBOX/stubs/curl" <<EOF
#!/bin/sh
out="" url=""
while [ \$# -gt 0 ]; do
    case "\$1" in
    --output | -o) out="\$2"; shift 2 ;;
    --) url="\$2"; shift 2 ;;
    *) shift ;;
    esac
done
echo "\$url" >>"$SANDBOX/curl.log"
f="$SANDBOX/srv/\${url##*/}"
[ -f "\$f" ] || exit 22
if [ -n "\$out" ]; then cp "\$f" "\$out"; else cat "\$f"; fi
EOF
    chmod +x "$SANDBOX/stubs/curl"
}
downloads() { grep -c '\.crx$' "$SANDBOX/curl.log" 2>/dev/null || true; }

# --- the ID a .crx proves --------------------------------------------------
sandbox cairn-id
KEY="haseen-test-key-for-cairn"
TEST_ID="$(key_id "$KEY")"
fake_crx "$SANDBOX/ok.crx" "$KEY" one
fake_crx "$SANDBOX/forged.crx" "$KEY" one "another-key"
printf 'PK\003\004zip' >"$SANDBOX/plain.zip"
id_of() { bash -c 'source "$HASEEN_PATH/lib/cairn.sh"; cairn_crx_id "$1"' _ "$1"; }
capture id_of "$SANDBOX/ok.crx"
assert_eq "crx id: the key's SHA-256, a-p" "0 $TEST_ID" "$STATUS $OUTPUT"
capture id_of "$SANDBOX/forged.crx"
assert_eq "crx id: a header naming another key's id proves nothing" "1 " "$STATUS $OUTPUT"
capture id_of "$SANDBOX/plain.zip"
assert_status "crx id: not a crx" 1 "$STATUS"
assert_eq "the pinned id is Cairn's" "$CAIRN_REAL_ID" "$(bash -c 'source "$HASEEN_PATH/lib/cairn.sh"; echo "$CAIRN_ID"')"
assert_eq "pinned release and sha256" "0.1.1 030d8b3c30c6a739c935ae4ef0815ba72e5efc3cbc887ae8368cebbc6365d6f7" \
    "$(bash -c 'source "$HASEEN_PATH/lib/cairn.sh"; echo "$CAIRN_VERSION $CAIRN_SHA256"')"

# --- haseen setup cairn: dry run ---------------------------------------------
sandbox cairn-dry
JSON="$XDG_CONFIG_HOME/net.imput.helium/External Extensions/$CAIRN_REAL_ID.json"
CRX="$XDG_DATA_HOME/haseen/extensions/cairn/0.1.1/cairn-0.1.1.crx"
capture haseen setup cairn --help
assert_status "--help" 0 "$STATUS"
capture haseen setup cairn bogus
assert_status "unknown verb" 2 "$STATUS"
capture haseen setup cairn --dry-run
assert_status "install --dry-run exits 0" 0 "$STATUS"
assert_dry_pure "install" "$OUTPUT"
assert_contains "the pinned release is downloaded" "$OUTPUT" \
    "--output $XDG_DATA_HOME/haseen/extensions/cairn/0.1.1/.cairn-0.1.1.crx.part -- https://github.com/t1nk333r/cairn/releases/download/v0.1.1/cairn-0.1.1.crx"
assert_contains "and checked" "$OUTPUT" "sha256 030d8b3c30c6a739c935ae4ef0815ba72e5efc3cbc887ae8368cebbc6365d6f7 and be signed for $CAIRN_REAL_ID"
assert_contains "Helium's external extension file" "$OUTPUT" "DRYRUN: write $JSON:"
assert_contains "names the .crx" "$OUTPUT" "|   \"external_crx\": \"$CRX\","
assert_contains "and the version" "$OUTPUT" "|   \"external_version\": \"0.1.1\""
assert_eq "dry run wrote nothing" "" "$(find "$HOME" -mindepth 1 -print -quit)"

# --- install: checksum and id enforced, then idempotent ---------------------
sandbox cairn-install
serve_curl
JSON="$XDG_CONFIG_HOME/net.imput.helium/External Extensions/$CAIRN_REAL_ID.json"
CDIR="$XDG_DATA_HOME/haseen/extensions/cairn"
fake_crx "$SANDBOX/srv/cairn-0.1.1.crx" "$KEY" not-the-release
capture haseen setup cairn
assert_status "a sha256 mismatch refuses" 1 "$STATUS"
assert_contains "and says so" "$OUTPUT" "does not match 030d8b3c30c6a739c935ae4ef0815ba72e5efc3cbc887ae8368cebbc6365d6f7; deleted"
assert_eq "nothing kept after a mismatch" "" "$(find "$CDIR" -type f 2>/dev/null)"
assert_eq "Helium is not pointed at it" "no" "$([[ -e $JSON ]] && echo yes || echo no)"

fake_crx "$SANDBOX/srv/cairn-9.8.7.crx" "$KEY" release-987
SHA987="$(sha "$SANDBOX/srv/cairn-9.8.7.crx")"
export HASEEN_CAIRN_VERSION=9.8.7 HASEEN_CAIRN_SHA256="$SHA987"
capture haseen setup cairn
assert_status "a crx signed for another id refuses" 1 "$STATUS"
assert_contains "and names both ids" "$OUTPUT" "signed for $TEST_ID, not Cairn's $CAIRN_REAL_ID; deleted"
assert_eq "nothing kept after an id mismatch" "" "$(find "$CDIR" -type f 2>/dev/null)"

export HASEEN_CAIRN_ID="$TEST_ID"
JSON="$XDG_CONFIG_HOME/net.imput.helium/External Extensions/$TEST_ID.json"
capture haseen setup cairn
assert_status "install" 0 "$STATUS"
assert_contains "says Helium installs it" "$OUTPUT" "Helium installs Cairn 9.8.7 on its next start"
assert_eq "the .crx is in its version directory" "$SHA987" "$(sha "$CDIR/9.8.7/cairn-9.8.7.crx")"
assert_eq "no .part left" "" "$(find "$CDIR" -name '*.part')"
assert_eq "external extension file: path and version" "$CDIR/9.8.7/cairn-9.8.7.crx 9.8.7" \
    "$(jq -r '"\(.external_crx) \(.external_version)"' "$JSON")"
assert_eq "it is the only key Helium reads" "external_crx,external_version" "$(jq -r 'keys | join(",")' "$JSON")"
before="$(stat -c %Y.%s "$JSON")"
: >"$SANDBOX/curl.log"
capture haseen setup cairn
assert_status "re-install" 0 "$STATUS"
assert_contains "re-install: nothing to do" "$OUTPUT" "Cairn 9.8.7 is already handed to Helium"
assert_eq "re-install downloads nothing" 0 "$(downloads)"
assert_eq "re-install leaves the file" "$before" "$(stat -c %Y.%s "$JSON")"
capture haseen setup cairn --dry-run
assert_not_contains "dry re-install plans no write" "$OUTPUT" "DRYRUN"

capture haseen setup cairn status
assert_contains "status: handed over" "$OUTPUT" "ok: Cairn 9.8.7 handed to Helium (installed on its next start)"
mkdir -p "$XDG_CONFIG_HOME/net.imput.helium/Default/Extensions/$TEST_ID/9.8.7_0"
capture haseen setup cairn status
assert_contains "status: Helium has it" "$OUTPUT" "ok: Cairn 9.8.7 in Helium"

# --- update ------------------------------------------------------------------
fake_crx "$SANDBOX/srv/cairn-9.9.0.crx" "$KEY" release-990
SHA990="$(sha "$SANDBOX/srv/cairn-9.9.0.crx")"
latest() { # TAG DIGEST
    jq -n --arg t "$1" --arg d "$2" '{tag_name: $t, assets: [
        {name: "cairn-\($t | ltrimstr("v"))-chrome.zip", digest: "sha256:00"},
        {name: "cairn-\($t | ltrimstr("v")).crx", digest: $d}]}' >"$SANDBOX/srv/latest"
}
latest v9.9.0 ""
capture haseen setup cairn update
assert_status "update without a published sha256 refuses" 1 "$STATUS"
assert_contains "and says why" "$OUTPUT" "publishes no sha256 for cairn-9.9.0.crx"
latest v9.9.0 "sha256:$SHA987"
capture haseen setup cairn update
assert_status "update with a wrong sha256 refuses" 1 "$STATUS"
assert_eq "the deployed version stays" 9.8.7 "$(jq -r .external_version "$JSON")"

latest v9.9.0 "sha256:$SHA990"
: >"$SANDBOX/curl.log"
capture haseen setup cairn update --dry-run
assert_status "update --dry-run" 0 "$STATUS"
assert_dry_pure "update" "$OUTPUT"
assert_contains "the plan names the release" "$OUTPUT" "Cairn: latest release 9.9.0 (deployed: 9.8.7)"
assert_contains "and its download" "$OUTPUT" "-- https://github.com/t1nk333r/cairn/releases/download/v9.9.0/cairn-9.9.0.crx"
assert_eq "a dry update downloads nothing" 0 "$(downloads)"
assert_eq "and changes nothing" 9.8.7 "$(jq -r .external_version "$JSON")"
capture haseen setup cairn update
assert_status "update" 0 "$STATUS"
assert_eq "update: Helium is pointed at 9.9.0" "$CDIR/9.9.0/cairn-9.9.0.crx 9.9.0" \
    "$(jq -r '"\(.external_crx) \(.external_version)"' "$JSON")"
assert_eq "update: the old version is gone" "9.9.0" "$(ls "$CDIR")"
capture haseen setup cairn update
assert_contains "update again: nothing to do" "$OUTPUT" "Cairn 9.9.0 is already handed to Helium"
capture haseen setup cairn
assert_contains "the pinned install never downgrades" "$OUTPUT" "Cairn 9.9.0 stays (newer than haseen's pinned 9.8.7)"
assert_eq "still 9.9.0" 9.9.0 "$(jq -r .external_version "$JSON")"

echo "{\"extensions\":{\"external_uninstalls\":[\"$TEST_ID\"]}}" >"$XDG_CONFIG_HOME/net.imput.helium/Default/Preferences"
capture haseen setup cairn status
assert_contains "status: a removal in Helium is respected" "$OUTPUT" "ok: Cairn was removed in Helium; haseen leaves it removed"
unset HASEEN_CAIRN_VERSION HASEEN_CAIRN_SHA256 HASEEN_CAIRN_ID

# --- the shell layer: Helium from Chaotic-AUR, then Cairn ----------------------
sandbox cairn-layer
fx="$SANDBOX/fx"
cp -a "$FIXTURES/cachyos-limine-luks-dualboot/." "$fx/"
mkdir -p "$fx/var/lib/pacman/sync"
printf '[options]\n[cachyos]\nInclude = x\n[core]\nInclude = x\n[extra]\nInclude = x\n[chaotic-aur]\nInclude = /etc/pacman.d/chaotic-mirrorlist\n' >"$fx/etc/pacman.conf"
printf 'helium-browser-bin\nparu\n' >"$fx/var/lib/pacman/sync/chaotic-aur.pkgs"
capture env HASEEN_SYSROOT="$fx" DRY_RUN=true bash -c 'source "$HASEEN_PATH/lib/layers.sh"; layer_run_apply shell'
assert_status "shell layer dry-run" 0 "$STATUS"
assert_dry_pure "shell layer with Helium and Cairn" "$OUTPUT"
assert_contains "Helium comes from Chaotic-AUR" "$OUTPUT" "DRYRUN: sudo pacman -S --needed chaotic-aur/helium-browser-bin"
assert_not_contains "never built from the AUR" "$OUTPUT" "paru -S"
assert_contains "Cairn's release is fetched" "$OUTPUT" "releases/download/v0.1.1/cairn-0.1.1.crx"
assert_contains "and handed to Helium" "$OUTPUT" "DRYRUN: write $XDG_CONFIG_HOME/net.imput.helium/External Extensions/$CAIRN_REAL_ID.json:"
order="$(grep -nE 'helium-browser-bin|External Extensions' <<<"$OUTPUT" | cut -d: -f1 | paste -sd' ')"
read -r helium_line cairn_line <<<"$order"
assert_eq "Helium before Cairn" "yes" "$( ((helium_line < cairn_line)) && echo yes || echo no)"
assert_eq "layer dry-run wrote nothing" "" "$(find "$HOME" -mindepth 1 -print -quit)"
assert_contains "the summary says so" "$(bash -c 'source "$HASEEN_PATH/lib/layers.sh"; layer_field shell LAYER_SUMMARY')" "Helium with Cairn"

# Offline: the shell still applies; status reports Cairn missing.
serve_curl
capture env HASEEN_SYSROOT="$FIXTURES/shell-quickshell-installed" bash -c 'source "$HASEEN_PATH/lib/cairn.sh"; cairn_install || echo FAILED'
assert_contains "offline: the download fails cleanly" "$OUTPUT" "cairn-0.1.1.crx: download failed (curl exit 22)"
assert_eq "offline: nothing left behind" "" "$(find "$XDG_DATA_HOME" -type f 2>/dev/null)"
