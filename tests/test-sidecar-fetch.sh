# shellcheck shell=bash
# haseen:covers tools/build-sidecar.sh
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# Plan 127: a machine without a Go toolchain gets haseen-sidecar and
# haseen-palette from the sidecar release instead of building them, and only
# when SHA256SUMS agrees. The "release" here is a directory reached over
# file://, and PATH has no go, as on a fresh machine.
sandbox sidecar-fetch
# The sandbox stubs curl (plan 094); this one hands the call to the real
# binary, which only ever reads the fixture below (file://).
stub curl 'exec /usr/bin/curl "$@"'
BUILD="$REPO/tools/build-sidecar.sh"
rel="$SANDBOX/release"
mkdir -p "$rel"
case "$(uname -m)" in
aarch64 | arm64) arch=arm64 ;;
*) arch=amd64 ;;
esac

assets() {
    printf '#!/bin/sh\necho fake-sidecar\n' >"$rel/haseen-sidecar-linux-$arch"
    printf '#!/bin/sh\necho fake-palette\n' >"$rel/haseen-palette-linux-$arch"
    chmod +x "$rel/haseen-sidecar-linux-$arch" "$rel/haseen-palette-linux-$arch"
    (cd "$rel" && sha256sum "haseen-sidecar-linux-$arch" "haseen-palette-linux-$arch" >SHA256SUMS)
}
assets

capture env GO="$SANDBOX/no-go" HASEEN_SIDECAR_URL="file://$rel" HASEEN_BUILD_WOOTINGD=0 "$BUILD" "$SANDBOX/out/haseen-sidecar"
assert_status "the release is fetched without a toolchain" 0 "$STATUS"
assert_contains "and says what it fetched" "$OUTPUT" "fetched linux-$arch"
assert_eq "the daemon is installed" "fake-sidecar" "$("$SANDBOX/out/haseen-sidecar")"
assert_eq "the palette lands beside it" "fake-palette" "$("$SANDBOX/out/haseen-palette")"

# --- a checksum that does not match installs nothing ------------------------
printf '#!/bin/sh\necho tampered\n' >"$rel/haseen-sidecar-linux-$arch"
capture env GO="$SANDBOX/no-go" HASEEN_SIDECAR_URL="file://$rel" HASEEN_BUILD_WOOTINGD=0 "$BUILD" "$SANDBOX/out2/haseen-sidecar"
assert_status "a tampered asset fails" 1 "$STATUS"
assert_contains "and says why" "$OUTPUT" "does not match its SHA256SUMS"
assert_eq "with nothing installed" "no" "$([[ -e $SANDBOX/out2/haseen-sidecar ]] && echo yes || echo no)"

# --- a sums file that names neither asset verifies nothing ------------------
# --ignore-missing would otherwise pass the check with nothing checked, so the
# names have to be found first (plan 127).
assets
printf '%s\n' "$(printf 'a%.0s' {1..64})  haseen-sidecar-linux-other" \
    "$(printf 'b%.0s' {1..64})  haseen-palette-linux-other" >"$rel/SHA256SUMS"
capture env GO="$SANDBOX/no-go" HASEEN_SIDECAR_URL="file://$rel" HASEEN_BUILD_WOOTINGD=0 "$BUILD" "$SANDBOX/out4/haseen-sidecar"
assert_status "sums that name neither asset fail" 1 "$STATUS"
assert_contains "and say so" "$OUTPUT" "SHA256SUMS does not name haseen-sidecar-linux-$arch"
assert_eq "with nothing installed" "no" "$([[ -e $SANDBOX/out4/haseen-sidecar ]] && echo yes || echo no)"

# --- the download can be turned off ----------------------------------------
assets
capture env GO="$SANDBOX/no-go" HASEEN_FETCH_SIDECAR=0 HASEEN_SIDECAR_URL="file://$rel" HASEEN_BUILD_WOOTINGD=0 "$BUILD" "$SANDBOX/out3/haseen-sidecar"
assert_status "HASEEN_FETCH_SIDECAR=0 is not an error" 0 "$STATUS"
assert_contains "it keeps the old message" "$OUTPUT" "no go toolchain; haseen-sidecar not built"
assert_eq "and installs nothing" "no" "$([[ -e $SANDBOX/out3/haseen-sidecar ]] && echo yes || echo no)"
