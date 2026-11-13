# shellcheck shell=bash
# haseen:covers tools/build-sidecar.sh
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# Plan 127: a machine without the toolchains gets haseen-sidecar (cargo,
# plan 167) and haseen-palette (go) from the sidecar release instead of
# building them, and only when SHA256SUMS agrees. The "release" here is a
# directory reached over file://, GO names no toolchain and cargo is rustup's
# proxy without one (on PATH, but it does not run), as on a fresh machine.
sandbox sidecar-fetch
# The sandbox stubs curl (plan 094); this one hands the call to the real
# binary, which only ever reads the fixture below (file://).
stub curl 'exec /usr/bin/curl "$@"'
stub cargo 'exit 1'
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

# --- a go that is on PATH but does not run counts as none -------------------
# A mise shim with no version set is a `go` that exists and then fails; the
# install has to fetch, not stop (IO, 2026-10-26; plan 130).
printf '#!/bin/sh\necho "mise ERROR No version is set for shim: go" >&2\nexit 1\n' >"$SANDBOX/broken-go"
chmod +x "$SANDBOX/broken-go"
assets
capture env GO="$SANDBOX/broken-go" HASEEN_SIDECAR_URL="file://$rel" HASEEN_BUILD_WOOTINGD=0 "$BUILD" "$SANDBOX/out5/haseen-sidecar"
assert_status "a go that does not run is not a toolchain" 0 "$STATUS"
assert_contains "so the release is fetched" "$OUTPUT" "fetched linux-$arch"
assert_eq "and installed" "fake-sidecar" "$("$SANDBOX/out5/haseen-sidecar")"

# --- a failed download is not reported as a missing asset -------------------
# IO's link took 2m6s for the palette; the old 120 s limit made the install say
# the asset was not in the release (plan 131).
partial="$SANDBOX/release-partial"
mkdir -p "$partial"
cp "$rel/haseen-sidecar-linux-$arch" "$partial/"
(cd "$partial" && sha256sum "haseen-sidecar-linux-$arch" >SHA256SUMS)
capture env GO="$SANDBOX/no-go" HASEEN_SIDECAR_URL="file://$partial" HASEEN_BUILD_WOOTINGD=0 "$BUILD" "$SANDBOX/out6/haseen-sidecar"
assert_status "a download that fails is not an error" 0 "$STATUS"
assert_contains "and says the link, not the release" "$OUTPUT" "haseen-palette-linux-$arch did not download"
assert_eq "with nothing installed" "no" "$([[ -e $SANDBOX/out6/haseen-sidecar ]] && echo yes || echo no)"

# --- the download can be turned off ----------------------------------------
assets
capture env GO="$SANDBOX/no-go" HASEEN_FETCH_SIDECAR=0 HASEEN_SIDECAR_URL="file://$rel" HASEEN_BUILD_WOOTINGD=0 "$BUILD" "$SANDBOX/out3/haseen-sidecar"
assert_status "HASEEN_FETCH_SIDECAR=0 is not an error" 0 "$STATUS"
assert_contains "it says why the daemon is not built" "$OUTPUT" "cargo does not run; haseen-sidecar not built"
assert_contains "and why the palette is not" "$OUTPUT" "no go toolchain; haseen-palette not built"
assert_eq "and installs nothing" "no" "$([[ -e $SANDBOX/out3/haseen-sidecar ]] && echo yes || echo no)"

# --- a cargo that builds the daemon, and no go: only the palette is fetched --
# The stub writes the daemon where cargo would; the release names only the
# palette, which is all this machine needs from it.
stub cargo 'case $1 in
--version) echo "cargo 1.0.0" ;;
build)
    mkdir -p "$CARGO_TARGET_DIR/release"
    printf "#!/bin/sh\necho built-sidecar\n" >"$CARGO_TARGET_DIR/release/haseen-sidecar"
    chmod +x "$CARGO_TARGET_DIR/release/haseen-sidecar"
    ;;
esac'
only="$SANDBOX/release-palette"
mkdir -p "$only"
assets
cp "$rel/haseen-palette-linux-$arch" "$only/"
(cd "$only" && sha256sum "haseen-palette-linux-$arch" >SHA256SUMS)
capture env GO="$SANDBOX/no-go" CARGO_TARGET_DIR="$SANDBOX/target" HASEEN_SIDECAR_URL="file://$only" HASEEN_BUILD_WOOTINGD=0 "$BUILD" "$SANDBOX/out7/haseen-sidecar"
assert_status "a built daemon and a fetched palette" 0 "$STATUS"
assert_eq "the daemon is the one cargo built" "built-sidecar" "$("$SANDBOX/out7/haseen-sidecar")"
assert_eq "the palette came from the release" "fake-palette" "$("$SANDBOX/out7/haseen-palette")"
assert_contains "and says it was fetched" "$OUTPUT" "$SANDBOX/out7/haseen-palette ($(cat "$REPO/share/haseen/VERSION"), fetched linux-$arch)"
assert_not_contains "the daemon was not" "$OUTPUT" "haseen-sidecar-linux-$arch"

# --- a cargo build that fails fetches the daemon ----------------------------
# A compiler too old for the crate is a cargo that runs and then fails.
stub cargo 'case $1 in
--version) echo "cargo 1.0.0" ;;
*) exit 101 ;;
esac'
assets
capture env GO="$SANDBOX/no-go" CARGO_TARGET_DIR="$SANDBOX/target2" HASEEN_SIDECAR_URL="file://$rel" HASEEN_BUILD_WOOTINGD=0 "$BUILD" "$SANDBOX/out8/haseen-sidecar"
assert_status "a failed cargo build is not an error" 0 "$STATUS"
assert_eq "the release's daemon is installed instead" "fake-sidecar" "$("$SANDBOX/out8/haseen-sidecar")"
