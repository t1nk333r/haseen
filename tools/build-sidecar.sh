#!/usr/bin/env bash
# tools/build-sidecar.sh [DEST] — build haseen's compiled helpers into the tree:
# haseen-sidecar and haseen-palette from core/ (Go), and wootingd from
# core/wootingd/ (Rust, plan 099).
#
# DEST defaults to share/haseen/sidecar/haseen-sidecar, which is where the
# installed tree keeps it and where qs.Haseen.Sidecar looks; the other two
# land beside it. With a Go toolchain the daemon and the palette are built
# from core/; a `go` that is on PATH but does not run — a mise shim with no
# version set — counts as no toolchain. Without one they are **downloaded**
# from the sidecar release
# (plan 127): `sidecar-v$VERSION` on GitHub, assets named
# haseen-sidecar-linux-<arch> and haseen-palette-linux-<arch>, checked against
# the release's SHA256SUMS before anything is installed. A machine with
# neither a toolchain nor a reachable release ships without the daemon: the
# shell then finds no capability and hides what needs it (plan 032).
# HASEEN_FETCH_SIDECAR=0 turns the download off; HASEEN_SIDECAR_URL points it
# at another base (a mirror, or a file:// directory in tests).
# Without a working cargo (none, or a rustup with no toolchain) or when its
# build fails, wootingd is skipped, with a message naming what then does not
# work (haseen.wooting, `haseen setup wooting`): it serves one off-by-default
# plugin, so it never stops an install. HASEEN_REQUIRE_CARGO=1 makes that an
# error instead.
# HASEEN_BUILD_SIDECAR=0 or HASEEN_BUILD_WOOTINGD=0 leaves one part out.
set -Eeuo pipefail

REPO="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
DEST="${1:-$REPO/share/haseen/sidecar/haseen-sidecar}"
VERSION="$(cat "$REPO/share/haseen/VERSION")"
OUT_DIR="$(dirname "$DEST")"
# GO overrides the toolchain, as tools/lint.sh and the tests do; a value that
# does not run is the same as none.
GO="${GO:-go}"
SIDECAR_URL="${HASEEN_SIDECAR_URL:-https://github.com/t1nk333r/haseen/releases/download/sidecar-v$VERSION}"

# release_arch — the asset suffix for this machine, or nothing.
release_arch() {
    case "$(uname -m)" in
    x86_64 | amd64) echo amd64 ;;
    aarch64 | arm64) echo arm64 ;;
    *) return 1 ;;
    esac
}

# fetch_go — the prebuilt daemon and palette for the release of this version.
# Nothing is installed unless SHA256SUMS names it and the hash matches.
fetch_go() {
    local arch tmp name
    if ! arch="$(release_arch)"; then
        echo "build-sidecar: no go toolchain, and no release asset for $(uname -m); haseen-sidecar not installed" >&2
        return 0
    fi
    if ! command -v curl >/dev/null; then
        echo "build-sidecar: no go toolchain and no curl; haseen-sidecar not installed" >&2
        return 0
    fi
    tmp="$(mktemp -d "${TMPDIR:-/tmp}/haseen-sidecar.XXXXXX")"
    # A slow link is not a missing release: IO took 2m6s for the palette on
    # 2026-10-26, past the 120 s this used to allow, and the install said the
    # asset was not in the release. HASEEN_SIDECAR_TIMEOUT moves the limit.
    local limit="${HASEEN_SIDECAR_TIMEOUT:-300}" status=0
    if ! curl -fsSL -m 60 -o "$tmp/SHA256SUMS" "$SIDECAR_URL/SHA256SUMS"; then
        rm -rf -- "$tmp"
        echo "build-sidecar: no go toolchain and $SIDECAR_URL/SHA256SUMS is not reachable; haseen-sidecar not installed" >&2
        return 0
    fi
    for name in haseen-sidecar "haseen-palette"; do
        status=0
        curl -fsSL -m "$limit" -o "$tmp/$name-linux-$arch" "$SIDECAR_URL/$name-linux-$arch" || status=$?
        if ((status != 0)); then
            rm -rf -- "$tmp"
            # 22 is curl's "HTTP error", the only one that means the asset is
            # not there; anything else is the link, and says so.
            if ((status == 22)); then
                echo "build-sidecar: $name-linux-$arch is not in the release; haseen-sidecar not installed" >&2
            else
                echo "build-sidecar: $name-linux-$arch did not download (curl exit $status, ${limit}s limit); haseen-sidecar not installed" >&2
            fi
            return 0
        fi
    done
    # --ignore-missing lets the sums file name the other architecture, so a
    # release that names neither asset must be refused before the check: it
    # would otherwise pass with nothing verified.
    for name in haseen-sidecar haseen-palette; do
        if ! grep -qE "^[0-9a-f]{64} [ *]$name-linux-$arch\$" "$tmp/SHA256SUMS"; then
            rm -rf -- "$tmp"
            echo "build-sidecar: SHA256SUMS does not name $name-linux-$arch; haseen-sidecar not installed" >&2
            return 1
        fi
    done
    # The sums file names the assets, so check them where they were saved.
    if ! (cd "$tmp" && sha256sum --ignore-missing -c SHA256SUMS >/dev/null); then
        rm -rf -- "$tmp"
        echo "build-sidecar: $SIDECAR_URL does not match its SHA256SUMS; nothing installed" >&2
        return 1
    fi
    mkdir -p "$OUT_DIR"
    install -m 0755 "$tmp/haseen-sidecar-linux-$arch" "$DEST"
    install -m 0755 "$tmp/haseen-palette-linux-$arch" "$OUT_DIR/haseen-palette"
    rm -rf -- "$tmp"
    echo "build-sidecar: $DEST ($VERSION, fetched linux-$arch)"
}

build_go() {
    # `go version`, not only `command -v`: a mise shim is on PATH with no
    # version set and then fails ("mise ERROR No version is set for shim: go",
    # IO, 2026-10-26), which used to stop the install instead of fetching the
    # release — the same trap `cargo --version` below avoids (plan 130).
    if ! "$GO" version >/dev/null 2>&1; then
        if [[ ${HASEEN_FETCH_SIDECAR:-1} != 0 ]]; then
            fetch_go
            return
        fi
        echo "build-sidecar: no go toolchain; haseen-sidecar not built" >&2
        return 0
    fi
    mkdir -p "$OUT_DIR"
    # -trimpath keeps the build reproducible and -buildvcs=false keeps it from
    # shelling out to git; the version is what the hello frame reports, so a
    # stale binary is visible in `haseen sidecar status`.
    (
        cd "$REPO/core"
        "$GO" build -trimpath -buildvcs=false -ldflags "-s -w -X main.version=$VERSION" -o "$DEST" ./cmd/haseen-sidecar
        "$GO" build -trimpath -buildvcs=false -ldflags "-s -w -X main.version=$VERSION" -o "$OUT_DIR/haseen-palette" ./cmd/haseen-palette
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
