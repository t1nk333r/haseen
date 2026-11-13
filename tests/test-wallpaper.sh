# shellcheck shell=bash
# haseen:covers bin/haseen-theme-set bin/haseen-theme-wallpaper core/palette/**
# haseen:covers share/haseen/VERSION share/haseen/default/nvim/**
# haseen:covers share/haseen/default/shell.json share/haseen/layers/theme/theme-lib.sh
# haseen:covers share/haseen/themed/** tools/build-sidecar.sh
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# `haseen theme wallpaper`: a wallpaper becomes an ordinary haseen theme, the
# palette is cached on the image's content, and an unchanged palette rewrites
# nothing. haseen-palette is Rust since plan 167 (core/palette/): its own
# tests come first, among them every palette of the corpus against the Go
# generator's recorded answers (core/palette/tests/golden/). Without cargo
# the file skips, which is the state of a machine without it and without the
# release; under HASEEN_REQUIRE_ENGINE=1 (CI) a missing cargo fails instead.
rustup_home="${RUSTUP_HOME:-$HOME/.rustup}"
sandbox wallpaper
[[ ! -d $rustup_home ]] || export RUSTUP_HOME="$rustup_home"
CRATE="$REPO/core/palette"

if ! command -v cargo >/dev/null; then
    echo "  skip: cargo missing; haseen-palette not built or tested" >&2
    [[ ${HASEEN_REQUIRE_ENGINE:-0} != 1 ]] || assert_eq "wallpaper: required cargo prerequisite" available unavailable
    return 0 2>/dev/null || exit 0
fi

# A private cargo home and target dir under tests/.out (ignored), kept between
# runs; build-sidecar.sh reads CARGO_TARGET_DIR too, so it reuses the build.
# The crate has no dependencies, so nothing is fetched.
export CARGO_HOME="$OUT/cargo-home" CARGO_TARGET_DIR="$OUT/palette-target"
VERSION="$(cat "$HASEEN_PATH/VERSION")"

capture env HASEEN_VERSION="$VERSION" cargo test --locked --quiet --manifest-path "$CRATE/Cargo.toml"
assert_status "cargo test --locked passes" 0 "$STATUS"
assert_not_contains "no failed Rust test" "$OUTPUT" "FAILED"
assert_contains "the unit tests ran" "$OUTPUT" "test result: ok. 29 passed; 0 failed"
assert_contains "the command-line tests ran" "$OUTPUT" "test result: ok. 5 passed; 0 failed"
assert_contains "the Go generator's answers were compared" "$OUTPUT" "test result: ok. 3 passed; 0 failed"
if cargo clippy --version >/dev/null 2>&1; then
    capture cargo clippy --locked --quiet --all-targets --manifest-path "$CRATE/Cargo.toml" -- -D warnings
    assert_status "clippy finds nothing" 0 "$STATUS"
fi
if cargo fmt --version >/dev/null 2>&1; then
    capture cargo fmt --check --manifest-path "$CRATE/Cargo.toml"
    assert_status "the crate is rustfmt-clean" 0 "$STATUS"
fi
# Decoders, SHA-256, inflate and JSON are written in the crate (plan 167).
assert_eq "the crate has no dependency" "" \
    "$(sed -n '/^\[dependencies\]/,/^\[/p' "$CRATE/Cargo.toml" | sed -n 's/^\([a-z_-]*\) = .*/\1/p')"
assert_eq "and its lock file only the crate" "haseen-palette" \
    "$(sed -n 's/^name = "\(.*\)"/\1/p' "$CRATE/Cargo.lock" | paste -sd' ')"
crate_files() { (cd "$CRATE" && find . -not -path "./src/*" -not -path "./tests/*" -not -name . | LC_ALL=C sort | paste -sd" "); }
assert_eq "no build output in the tracked crate" "./Cargo.lock ./Cargo.toml ./src ./tests" "$(crate_files)"

capture env HASEEN_BUILD_WOOTINGD=0 HASEEN_BUILD_DAEMON=0 HASEEN_FETCH_SIDECAR=0 "$REPO/tools/build-sidecar.sh" "$SANDBOX/haseen-sidecar"
assert_status "the generator builds" 0 "$STATUS"
export HASEEN_PALETTE_BIN="$SANDBOX/haseen-palette"
assert_eq "haseen-palette landed beside the sidecar" 0 "$([[ -x $HASEEN_PALETTE_BIN ]] && echo 0 || echo 1)"

# Two images: flat colour bands, which is all the extractor needs.
make_image() { # PATH R,G,B R,G,B ...
    local path="$1"
    shift
    python3 - "$path" "$@" <<'PY'
import sys, zlib, struct
path, bands = sys.argv[1], [tuple(int(v) for v in a.split(",")) for a in sys.argv[2:]]
w = h = 120
rows = b""
for y in range(h):
    band = bands[min(y * len(bands) // h, len(bands) - 1)]
    rows += b"\x00" + bytes(band) * w
def chunk(tag, data):
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data))
png = (b"\x89PNG\r\n\x1a\n"
       + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
       + chunk(b"IDAT", zlib.compress(rows))
       + chunk(b"IEND", b""))
open(path, "wb").write(png)
PY
}

wall="$SANDBOX/wall.png"
other="$SANDBOX/other.png"
make_image "$wall" 18,22,40 190,80,70 60,140,120 230,210,150
make_image "$other" 240,240,240 20,60,200 10,10,10 120,200,90

theme_dir="$XDG_CONFIG_HOME/haseen/themes/wallpaper"
colors="$theme_dir/colors.toml"

capture haseen theme wallpaper "$wall" --dry-run
assert_dry_pure "wallpaper dry run" "$OUTPUT"
assert_contains "a dry run plans the generation" "$OUTPUT" "haseen-palette"
assert_eq "a dry run writes no theme" "" "$(ls "$theme_dir" 2>/dev/null || true)"

capture haseen theme wallpaper "$wall" --no-apply
assert_status "a wallpaper becomes a theme" 0 "$STATUS"
assert_contains "it says where the palette landed" "$OUTPUT" "$colors"
toml="$(cat "$colors")"
assert_contains "the theme carries the mode" "$toml" 'mode = "dark"'
assert_eq "it has all 16 ANSI slots" 16 "$(grep -c '^color[0-9]' <<<"$toml")"
assert_contains "and the keys the templates read" "$toml" "accent = "
assert_eq "the wallpaper is the theme's background" 1 \
    "$(ls "$XDG_CONFIG_HOME/haseen/backgrounds/wallpaper" | wc -l)"

# An unchanged seed must not rewrite the file: a theme set, a FileView or a hook
# downstream would otherwise react to a wallpaper that produced the same colours.
before="$(stat -c %Y.%i "$colors")"
capture haseen theme wallpaper "$wall" --no-apply
assert_contains "the same wallpaper reports no change" "$OUTPUT" "palette unchanged"
assert_eq "and leaves the file alone" "$before" "$(stat -c %Y.%i "$colors")"

# A copy under another name is the same seed (the key is the content).
cp "$wall" "$SANDBOX/renamed.png"
capture haseen theme wallpaper "$SANDBOX/renamed.png" --no-apply
assert_contains "a copy of the same image is the same seed" "$OUTPUT" "palette unchanged"

capture haseen theme wallpaper "$other" --no-apply
assert_contains "a different wallpaper is regenerated" "$OUTPUT" "$colors"
assert_eq "and the colours changed" false \
    "$([[ "$toml" == "$(cat "$colors")" ]] && echo true || echo false)"

capture haseen theme wallpaper "$wall" --name my-theme --no-apply
assert_eq "--name writes that theme" 0 \
    "$([[ -f $XDG_CONFIG_HOME/haseen/themes/my-theme/colors.toml ]] && echo 0 || echo 1)"
capture haseen theme wallpaper "$wall" --light --name lighty --no-apply
assert_contains "--light builds a light palette" \
    "$(cat "$XDG_CONFIG_HOME/haseen/themes/lighty/colors.toml")" 'mode = "light"'

capture haseen theme wallpaper "$wall" --name ../escape --no-apply
assert_status "a name that could leave the themes dir is refused" 1 "$STATUS"
capture haseen theme wallpaper "$SANDBOX/missing.png" --no-apply
assert_status "a missing image is an error" 1 "$STATUS"
capture haseen theme wallpaper "$wall" --mode nonsense --no-apply
assert_status "an unknown extraction mode is an error" 1 "$STATUS"

# The generated theme renders like any other: `haseen theme set` fills every
# template from the same colors.toml.
capture env HASEEN_THEME_HEADLESS=1 haseen theme set wallpaper
assert_status "the generated theme applies" 0 "$STATUS"
rendered="$XDG_STATE_HOME/haseen/current/theme"
assert_eq "the shell tokens come from the wallpaper" "$(jq -r .background "$rendered/shell.json")" \
    "$(sed -n 's/^background = "\(.*\)"/\1/p' "$colors")"
assert_eq "the terminal config was rendered too" 0 "$([[ -s $rendered/foot.ini ]] && echo 0 || echo 1)"
