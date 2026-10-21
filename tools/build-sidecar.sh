#!/usr/bin/env bash
# tools/build-sidecar.sh [DEST] — build haseen's compiled helpers into the tree:
# haseen-sidecar and haseen-palette from core/ (Go), and wootingd from
# core/wootingd/ (Rust, plan 099).
#
# DEST defaults to share/haseen/sidecar/haseen-sidecar, which is where the
# installed tree keeps it and where qs.Haseen.Sidecar looks; the other two
# land beside it. Without a Go toolchain the Go part says so and is skipped:
# the shell then finds no daemon, the capability is absent, and the features
# that need it hide (plan 032). Without a working cargo (none, or a rustup
# with no toolchain) or when its build fails, wootingd is skipped the same way,
# with a message naming what then does not work (haseen.wooting, `haseen setup
# wooting`): it serves one off-by-default plugin, so it never stops an install.
# HASEEN_REQUIRE_CARGO=1 makes that an error instead.
# HASEEN_BUILD_SIDECAR=0 or HASEEN_BUILD_WOOTINGD=0 leaves one part out.
set -Eeuo pipefail

REPO="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
DEST="${1:-$REPO/share/haseen/sidecar/haseen-sidecar}"
VERSION="$(cat "$REPO/share/haseen/VERSION")"
OUT_DIR="$(dirname "$DEST")"

build_go() {
    if ! command -v go >/dev/null; then
        echo "build-sidecar: no go toolchain; haseen-sidecar not built" >&2
        return 0
    fi
    mkdir -p "$OUT_DIR"
    # -trimpath keeps the build reproducible and -buildvcs=false keeps it from
    # shelling out to git; the version is what the hello frame reports, so a
    # stale binary is visible in `haseen sidecar status`.
    (
        cd "$REPO/core"
        go build -trimpath -buildvcs=false -ldflags "-s -w -X main.version=$VERSION" -o "$DEST" ./cmd/haseen-sidecar
        go build -trimpath -buildvcs=false -ldflags "-s -w -X main.version=$VERSION" -o "$OUT_DIR/haseen-palette" ./cmd/haseen-palette
    )
    echo "build-sidecar: $DEST ($VERSION)"
}

# wootingd builds outside the tree: cargo's target directory would otherwise
# land in core/wootingd/ (a tracked path) and in every copy of the tree.
wootingd_skipped() {
    echo "build-sidecar: $1; wootingd not built, so haseen.wooting and 'haseen setup wooting' cannot work (pacman -S rust, then run this again)" >&2
    [[ ${HASEEN_REQUIRE_CARGO:-0} != 1 ]]
}

build_wootingd() {
    local target
    # `cargo --version`, not only `command -v`: rustup's cargo is on PATH even
    # with no toolchain installed, and then fails.
    if ! command -v cargo >/dev/null; then
        wootingd_skipped "no cargo"
        return
    fi
    if ! cargo --version >/dev/null 2>&1; then
        wootingd_skipped "cargo does not run (a rustup without a toolchain? rustup default stable)"
        return
    fi
    target="${CARGO_TARGET_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/haseen/wootingd-target}"
    mkdir -p "$OUT_DIR"
    # --locked: the vendored Cargo.lock is the dependency set, never a newer one.
    if ! CARGO_TARGET_DIR="$target" cargo build --release --locked --quiet --manifest-path "$REPO/core/wootingd/Cargo.toml" ||
        [[ ! -x $target/release/wootingd ]]; then
        wootingd_skipped "the cargo build failed (see above)"
        return
    fi
    install -m 0755 "$target/release/wootingd" "$OUT_DIR/wootingd"
    echo "build-sidecar: $OUT_DIR/wootingd"
}

[[ ${HASEEN_BUILD_SIDECAR:-1} == 0 ]] || build_go
[[ ${HASEEN_BUILD_WOOTINGD:-1} == 0 ]] || build_wootingd
