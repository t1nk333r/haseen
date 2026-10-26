# shellcheck shell=bash
# haseen:covers tools/release-sidecar.sh
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# Plan 127: tools/release-sidecar.sh is what the installer's fetch points at,
# so its tag, architectures and asset names have to stay the ones
# tools/build-sidecar.sh asks for. A stub `go` writes the asset path it is asked
# to build, a stub `gh` records the calls and answers view/create, and neither
# a toolchain nor the network is touched.
sandbox sidecar-release
export SANDBOX
stub git 'exec /usr/bin/git "$@"'
stub go 'out=""
while [ $# -gt 0 ]; do
    case $1 in
    -o)
        shift
        out=$1
        ;;
    esac
    shift
done
[[ -n $out ]] || exit 1
printf "fake asset\n" >"$out"
chmod +x "$out"'
stub gh 'printf "%s\n" "$*" >>"$SANDBOX/gh.log"
case "$*" in
*"--json url"*)
    echo "https://example.invalid/sidecar"
    exit 0
    ;;
"release view "*)
    [[ -e $SANDBOX/release-exists ]] && exit 0 || exit 1
    ;;
esac
exit 0'
RELEASE="$REPO/tools/release-sidecar.sh"
VERSION="$(cat "$REPO/share/haseen/VERSION")"
TAG="sidecar-v$VERSION"
HEAD_SHA="$(/usr/bin/git -C "$REPO" rev-parse HEAD)"
LOG="$SANDBOX/gh.log"
: >"$LOG"

# --- the release is created at the given commit, then replaced -------------
capture "$RELEASE"
assert_status "publishing succeeds" 0 "$STATUS"
assert_contains "the release is created at HEAD" "$(cat "$LOG")" \
    "release create $TAG --title haseen-sidecar $VERSION --target $HEAD_SHA"
assert_contains "and its URL is reported" "$OUTPUT" "sidecar-v$VERSION updated"
for asset in haseen-sidecar-linux-amd64 haseen-sidecar-linux-arm64 \
    haseen-palette-linux-amd64 haseen-palette-linux-arm64 SHA256SUMS; do
    assert_contains "the upload carries $asset" "$(cat "$LOG")" "$asset"
done
assert_contains "assets are replaced, not added" "$(cat "$LOG")" "--clobber"

# --- an existing release is not created again ------------------------------
: >"$LOG"
touch "$SANDBOX/release-exists"
capture "$RELEASE"
assert_status "an existing release publishes" 0 "$STATUS"
assert_not_contains "without a second create" "$(cat "$LOG")" "release create"
assert_contains "but still uploads" "$(cat "$LOG")" "release upload $TAG"

# --- the dry run builds and prints, and calls no gh ------------------------
: >"$LOG"
capture "$RELEASE" --dry-run --target "$HEAD_SHA"
assert_status "the dry run succeeds" 0 "$STATUS"
assert_contains "it names the tag it would create" "$OUTPUT" \
    "DRYRUN: gh release create '$TAG' --title 'haseen-sidecar $VERSION' --target $HEAD_SHA"
assert_contains "and would upload" "$OUTPUT" "DRYRUN: gh release upload '$TAG'"
assert_eq "with no gh call" "0" "$(grep -c . "$LOG" || true)"

# --- a wrong invocation is refused -----------------------------------------
capture "$RELEASE" --nonsense
assert_status "an unknown argument is refused" 2 "$STATUS"
assert_contains "and named" "$OUTPUT" "unknown argument --nonsense"
capture "$RELEASE" --target
assert_status "--target alone is refused" 2 "$STATUS"
assert_contains "with what it needs" "$OUTPUT" "--target needs a ref"
