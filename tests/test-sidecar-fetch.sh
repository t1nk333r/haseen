# shellcheck shell=bash
# haseen:covers tools/build-sidecar.sh
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# Plan 127: a machine without a toolchain gets haseen-sidecar and
# haseen-palette (both Rust since plan 167) from the sidecar release instead
# of building them, and only when SHA256SUMS agrees. The "release" here is a
# directory reached over file://, and cargo is rustup's proxy without a
# toolchain (on PATH, but it does not run), as on a fresh machine.
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

capture env HASEEN_SIDECAR_URL="file://$rel" HASEEN_BUILD_WOOTINGD=0 "$BUILD" "$SANDBOX/out/haseen-sidecar"
assert_status "the release is fetched without a toolchain" 0 "$STATUS"
assert_contains "and says what it fetched" "$OUTPUT" "fetched linux-$arch"
assert_eq "the daemon is installed" "fake-sidecar" "$("$SANDBOX/out/haseen-sidecar")"
assert_eq "the palette lands beside it" "fake-palette" "$("$SANDBOX/out/haseen-palette")"

# --- a checksum that does not match installs nothing ------------------------
printf '#!/bin/sh\necho tampered\n' >"$rel/haseen-sidecar-linux-$arch"
capture env HASEEN_SIDECAR_URL="file://$rel" HASEEN_BUILD_WOOTINGD=0 "$BUILD" "$SANDBOX/out2/haseen-sidecar"
assert_status "a tampered asset fails" 1 "$STATUS"
assert_contains "and says why" "$OUTPUT" "does not match its SHA256SUMS"
assert_eq "with nothing installed" "no" "$([[ -e $SANDBOX/out2/haseen-sidecar ]] && echo yes || echo no)"

# --- a sums file that names neither asset verifies nothing ------------------
# --ignore-missing would otherwise pass the check with nothing checked, so the
# names have to be found first (plan 127).
assets
printf '%s\n' "$(printf 'a%.0s' {1..64})  haseen-sidecar-linux-other" \
    "$(printf 'b%.0s' {1..64})  haseen-palette-linux-other" >"$rel/SHA256SUMS"
capture env HASEEN_SIDECAR_URL="file://$rel" HASEEN_BUILD_WOOTINGD=0 "$BUILD" "$SANDBOX/out4/haseen-sidecar"
assert_status "sums that name neither asset fail" 1 "$STATUS"
assert_contains "and say so" "$OUTPUT" "SHA256SUMS does not name haseen-sidecar-linux-$arch"
assert_eq "with nothing installed" "no" "$([[ -e $SANDBOX/out4/haseen-sidecar ]] && echo yes || echo no)"

# --- a destination that cannot be written is an error, not a fetch ----------
# The fetch runs where bash suspends errexit, so a failed install used to be
# reported as fetched and exit 0 (plan 167's review). A file where the
# directory should be stops root as well.
assets
: >"$SANDBOX/blocker"
capture env HASEEN_SIDECAR_URL="file://$rel" HASEEN_BUILD_WOOTINGD=0 "$BUILD" "$SANDBOX/blocker/haseen-sidecar"
assert_status "an unwritable destination fails" 1 "$STATUS"
assert_contains "and says what could not be installed" "$OUTPUT" "haseen-sidecar could not be installed in $SANDBOX/blocker"
assert_not_contains "with nothing reported as fetched" "$OUTPUT" "fetched linux-$arch"

# --- a toolchain shim that does not run counts as none ----------------------
# A mise shim with no version set is a command that exists and then fails;
# the install has to fetch, not stop (IO, 2026-10-26; plan 130).
stub cargo 'echo "mise ERROR No version is set for shim: cargo" >&2
exit 1'
assets
capture env HASEEN_SIDECAR_URL="file://$rel" HASEEN_BUILD_WOOTINGD=0 "$BUILD" "$SANDBOX/out5/haseen-sidecar"
assert_status "a cargo that does not run is not a toolchain" 0 "$STATUS"
assert_contains "so the release is fetched" "$OUTPUT" "fetched linux-$arch"
assert_eq "and installed" "fake-sidecar" "$("$SANDBOX/out5/haseen-sidecar")"
assert_eq "the palette with it" "fake-palette" "$("$SANDBOX/out5/haseen-palette")"
stub cargo 'exit 1'

# --- a failed download is not reported as a missing asset -------------------
# IO's link took 2m6s for the palette; the old 120 s limit made the install say
# the asset was not in the release (plan 131).
partial="$SANDBOX/release-partial"
mkdir -p "$partial"
cp "$rel/haseen-sidecar-linux-$arch" "$partial/"
(cd "$partial" && sha256sum "haseen-sidecar-linux-$arch" >SHA256SUMS)
capture env HASEEN_SIDECAR_URL="file://$partial" HASEEN_BUILD_WOOTINGD=0 "$BUILD" "$SANDBOX/out6/haseen-sidecar"
assert_status "a download that fails is not an error" 0 "$STATUS"
assert_contains "and says the link, not the release" "$OUTPUT" "haseen-palette-linux-$arch did not download"
assert_eq "with nothing installed" "no" "$([[ -e $SANDBOX/out6/haseen-sidecar ]] && echo yes || echo no)"

# --- the download can be turned off ----------------------------------------
assets
capture env HASEEN_FETCH_SIDECAR=0 HASEEN_SIDECAR_URL="file://$rel" HASEEN_BUILD_WOOTINGD=0 "$BUILD" "$SANDBOX/out3/haseen-sidecar"
assert_status "HASEEN_FETCH_SIDECAR=0 is not an error" 0 "$STATUS"
assert_contains "it says why the daemon is not built" "$OUTPUT" "cargo does not run; haseen-sidecar not built"
assert_contains "and why the palette is not" "$OUTPUT" "cargo does not run; haseen-palette not built"
assert_eq "and installs nothing" "no" "$([[ -e $SANDBOX/out3/haseen-sidecar ]] && echo yes || echo no)"

# --- a cargo that builds both: nothing is fetched ---------------------------
# The stub writes each binary where cargo would, named by the manifest it
# was given. The release URL leads nowhere, so a fetch would show.
stub cargo 'case $1 in
--version) echo "cargo 1.0.0" ;;
build)
    case $* in
    */core/palette/*) name=haseen-palette ;;
    *) name=haseen-sidecar ;;
    esac
    [ "${FAIL_CRATE:-}" != "$name" ] || exit 101
    mkdir -p "$CARGO_TARGET_DIR/release"
    printf "#!/bin/sh\necho built-%s\n" "${name#haseen-}" >"$CARGO_TARGET_DIR/release/$name"
    chmod +x "$CARGO_TARGET_DIR/release/$name"
    ;;
esac'
capture env CARGO_TARGET_DIR="$SANDBOX/target0" HASEEN_SIDECAR_URL="file://$SANDBOX/nowhere" HASEEN_BUILD_WOOTINGD=0 "$BUILD" "$SANDBOX/out9/haseen-sidecar"
assert_status "both helpers build" 0 "$STATUS"
assert_eq "the daemon is the one cargo built" "built-sidecar" "$("$SANDBOX/out9/haseen-sidecar")"
assert_eq "and the palette" "built-palette" "$("$SANDBOX/out9/haseen-palette")"
assert_not_contains "nothing was fetched" "$OUTPUT" "fetched"
assert_not_contains "or tried" "$OUTPUT" "SHA256SUMS"

# --- the daemon builds and the palette does not: only the palette is fetched
# The release names only the palette, which is all this machine needs from it.
only="$SANDBOX/release-palette"
mkdir -p "$only"
assets
cp "$rel/haseen-palette-linux-$arch" "$only/"
(cd "$only" && sha256sum "haseen-palette-linux-$arch" >SHA256SUMS)
capture env FAIL_CRATE=haseen-palette CARGO_TARGET_DIR="$SANDBOX/target" HASEEN_SIDECAR_URL="file://$only" HASEEN_BUILD_WOOTINGD=0 "$BUILD" "$SANDBOX/out7/haseen-sidecar"
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
capture env CARGO_TARGET_DIR="$SANDBOX/target2" HASEEN_SIDECAR_URL="file://$rel" HASEEN_BUILD_WOOTINGD=0 "$BUILD" "$SANDBOX/out8/haseen-sidecar"
assert_status "a failed cargo build is not an error" 0 "$STATUS"
assert_eq "the release's daemon is installed instead" "fake-sidecar" "$("$SANDBOX/out8/haseen-sidecar")"
assert_eq "and the release's palette" "fake-palette" "$("$SANDBOX/out8/haseen-palette")"
