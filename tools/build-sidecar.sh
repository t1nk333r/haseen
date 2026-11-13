#!/usr/bin/env bash
# tools/build-sidecar.sh [DEST] — build haseen's compiled helpers into the tree:
# haseen-sidecar from core/sidecar/ (Rust, plan 167), haseen-palette from
# core/ (Go), and wootingd from core/wootingd/ (Rust, plan 099).
#
# DEST defaults to share/haseen/sidecar/haseen-sidecar, which is where the
# installed tree keeps it and where qs.Haseen.Sidecar looks; the other two
# land beside it. The daemon is built with cargo and the palette with go; a
# tool that is on PATH but does not run — a mise shim with no version set, a
# rustup with no toolchain — counts as none. Whatever cannot be built is
# **downloaded** from the sidecar release
# (plan 127): `sidecar-v$VERSION` on GitHub, assets named
# haseen-sidecar-linux-<arch> and haseen-palette-linux-<arch>, checked against
# the release's SHA256SUMS before anything is installed. A cargo build that
# fails (a compiler too old for the crate) fetches the daemon the same way. A
# machine with neither a toolchain nor a reachable release ships without the
# daemon: the shell then finds no capability and hides what needs it (plan 032).
# HASEEN_FETCH_SIDECAR=0 turns the download off; HASEEN_SIDECAR_URL points it
# at another base (a mirror, or a file:// directory in tests).
# Without a working cargo (none, or a rustup with no toolchain) or when its
# build fails, wootingd is skipped, with a message naming what then does not
# work (haseen.wooting, `haseen setup wooting`): it serves one off-by-default
# plugin, so it never stops an install. HASEEN_REQUIRE_CARGO=1 makes that an
# error instead.
# HASEEN_BUILD_SIDECAR=0 leaves out the daemon and the palette,
# HASEEN_BUILD_DAEMON=0 the daemon only, HASEEN_BUILD_PALETTE=0 the palette
# only, HASEEN_BUILD_WOOTINGD=0 wootingd.
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

# cargo_runs — a cargo that is on PATH and answers. rustup's cargo is on PATH
# even with no toolchain installed, and then fails.
cargo_runs() {
    command -v cargo >/dev/null && cargo --version >/dev/null 2>&1
}

# install_asset NAME FILE — put one helper where the tree keeps it. Every
# step returns its failure: fetch_assets runs where errexit is off.
install_asset() {
    mkdir -p "$OUT_DIR" || return 1
    case $1 in
    haseen-sidecar) install -m 0755 "$2" "$DEST" ;;
    *) install -m 0755 "$2" "$OUT_DIR/$1" ;;
    esac
}

# fetch_assets WHY NAME... — the prebuilt helpers for the release of this
# version. WHY says what could not build them. Nothing is installed unless
# SHA256SUMS names every one and the hashes match. It is called as
# plainly, so errexit ends the script on a `return 1`; and every step that can
# fail is checked here anyway, because an `||` around the call would turn
# errexit off for the whole body (plan 167's review).
fetch_assets() {
    local why="$1" arch tmp name where
    shift
    if ! arch="$(release_arch)"; then
        echo "build-sidecar: $why, and no release asset for $(uname -m); $* not installed" >&2
        return 0
    fi
    if ! command -v curl >/dev/null; then
        echo "build-sidecar: $why and no curl; $* not installed" >&2
        return 0
    fi
    if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/haseen-sidecar.XXXXXX")"; then
        echo "build-sidecar: no temporary directory for the download; $* not installed" >&2
        return 1
    fi
    # A slow link is not a missing release: IO took 2m6s for the palette on
    # 2026-10-26, past the 120 s this used to allow, and the install said the
    # asset was not in the release. HASEEN_SIDECAR_TIMEOUT moves the limit.
    local limit="${HASEEN_SIDECAR_TIMEOUT:-300}" status=0
    if ! curl -fsSL -m 60 -o "$tmp/SHA256SUMS" "$SIDECAR_URL/SHA256SUMS"; then
        rm -rf -- "$tmp"
        echo "build-sidecar: $why and $SIDECAR_URL/SHA256SUMS is not reachable; $* not installed" >&2
        return 0
    fi
    for name in "$@"; do
        status=0
        curl -fsSL -m "$limit" -o "$tmp/$name-linux-$arch" "$SIDECAR_URL/$name-linux-$arch" || status=$?
        if ((status != 0)); then
            rm -rf -- "$tmp"
            # 22 is curl's "HTTP error", the only one that means the asset is
            # not there; anything else is the link, and says so.
            if ((status == 22)); then
                echo "build-sidecar: $name-linux-$arch is not in the release; $* not installed" >&2
            else
                echo "build-sidecar: $name-linux-$arch did not download (curl exit $status, ${limit}s limit); $* not installed" >&2
            fi
            return 0
        fi
    done
    # --ignore-missing lets the sums file name the other architecture, so a
    # release that names none of the assets must be refused before the check:
    # it would otherwise pass with nothing verified.
    for name in "$@"; do
        if ! grep -qE "^[0-9a-f]{64} [ *]$name-linux-$arch\$" "$tmp/SHA256SUMS"; then
            rm -rf -- "$tmp"
            echo "build-sidecar: SHA256SUMS does not name $name-linux-$arch; $* not installed" >&2
            return 1
        fi
    done
    # The sums file names the assets, so check them where they were saved.
    if ! (cd "$tmp" && sha256sum --ignore-missing -c SHA256SUMS >/dev/null); then
        rm -rf -- "$tmp"
        echo "build-sidecar: $SIDECAR_URL does not match its SHA256SUMS; nothing installed" >&2
        return 1
    fi
    for name in "$@"; do
        if ! install_asset "$name" "$tmp/$name-linux-$arch"; then
            rm -rf -- "$tmp"
            echo "build-sidecar: $name could not be installed in $OUT_DIR" >&2
            return 1
        fi
        [[ $name == haseen-sidecar ]] && where="$DEST" || where="$OUT_DIR/$name"
        echo "build-sidecar: $where ($VERSION, fetched linux-$arch)"
    done
    rm -rf -- "$tmp"
}

# The helpers that could not be built, fetched together at the end so one
# SHA256SUMS covers them, and why.
FETCH=()
FETCH_WHY=()

# want_fetch NAME WHY — fetch NAME from the release, or say it is not built.
want_fetch() {
    if [[ ${HASEEN_FETCH_SIDECAR:-1} == 0 ]]; then
        echo "build-sidecar: $2; $1 not built" >&2
        return 0
    fi
    FETCH+=("$1")
    FETCH_WHY+=("$2")
}

# build_sidecar — the daemon, from core/sidecar/ (plan 167). Its target
# directory is outside the tree for the reason wootingd's is (below).
build_sidecar() {
    local target
    if ! command -v cargo >/dev/null; then
        want_fetch haseen-sidecar "no cargo"
        return
    fi
    if ! cargo_runs; then
        want_fetch haseen-sidecar "cargo does not run"
        return
    fi
    target="${CARGO_TARGET_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/haseen/sidecar-target}"
    # --locked: Cargo.lock is the dependency set (libc, plan 167). The version
    # is what the hello frame reports, so a stale binary is visible in
    # `haseen sidecar status`.
    if ! HASEEN_VERSION="$VERSION" CARGO_TARGET_DIR="$target" \
        cargo build --release --locked --quiet --manifest-path "$REPO/core/sidecar/Cargo.toml" ||
        [[ ! -x $target/release/haseen-sidecar ]]; then
        want_fetch haseen-sidecar "the cargo build failed (see above)"
        return
    fi
    install_asset haseen-sidecar "$target/release/haseen-sidecar"
    echo "build-sidecar: $DEST ($VERSION)"
}

build_palette() {
    # `go version`, not only `command -v`: a mise shim is on PATH with no
    # version set and then fails ("mise ERROR No version is set for shim: go",
    # IO, 2026-10-26), which used to stop the install instead of fetching the
    # release (plan 130).
    if ! "$GO" version >/dev/null 2>&1; then
        want_fetch haseen-palette "no go toolchain"
        return
    fi
    mkdir -p "$OUT_DIR"
    # -trimpath keeps the build reproducible and -buildvcs=false keeps it from
    # shelling out to git.
    (
        cd "$REPO/core"
        "$GO" build -trimpath -buildvcs=false -ldflags "-s -w -X main.version=$VERSION" -o "$OUT_DIR/haseen-palette" ./cmd/haseen-palette
    )
    echo "build-sidecar: $OUT_DIR/haseen-palette ($VERSION)"
}

# wootingd builds outside the tree: cargo's target directory would otherwise
# land in core/wootingd/ (a tracked path) and in every copy of the tree.
wootingd_skipped() {
    echo "build-sidecar: $1; wootingd not built, so haseen.wooting and 'haseen setup wooting' cannot work (pacman -S rust, then run this again)" >&2
    [[ ${HASEEN_REQUIRE_CARGO:-0} != 1 ]]
}

build_wootingd() {
    local target
    if ! command -v cargo >/dev/null; then
        wootingd_skipped "no cargo"
        return
    fi
    if ! cargo_runs; then
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

if [[ ${HASEEN_BUILD_SIDECAR:-1} != 0 ]]; then
    [[ ${HASEEN_BUILD_DAEMON:-1} == 0 ]] || build_sidecar
    [[ ${HASEEN_BUILD_PALETTE:-1} == 0 ]] || build_palette
    if ((${#FETCH[@]} > 0)); then
        # One reason, or both when the two helpers failed differently.
        why="${FETCH_WHY[0]}"
        [[ ${FETCH_WHY[1]:-${FETCH_WHY[0]}} == "${FETCH_WHY[0]}" ]] || why+=" and ${FETCH_WHY[1]}"
        fetch_assets "$why" "${FETCH[@]}"
    fi
fi
[[ ${HASEEN_BUILD_WOOTINGD:-1} == 0 ]] || build_wootingd
