#!/usr/bin/env bash
# tools/release-sidecar.sh [--target REF] [--dry-run]
# Build haseen-sidecar and haseen-palette for linux/amd64 and linux/arm64 and
# publish them as the `sidecar-v<share/haseen/VERSION>` release (plan 127).
#
# A machine the installer runs on without the toolchains downloads these
# instead of building them (tools/build-sidecar.sh), so this is what makes a
# new machine's sidecar arrive with `install.sh`. Both are static: the daemon
# is Rust built for the musl targets (plan 167; rustup target add
# x86_64-unknown-linux-musl aarch64-unknown-linux-musl), the palette Go with
# CGO off. Assets are replaced (`--clobber`) on every run: one release per
# version, and the SHA256SUMS beside them is what the installer checks.
set -Eeuo pipefail

REPO="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
VERSION="$(cat "$REPO/share/haseen/VERSION")"
TAG="sidecar-v$VERSION"
DRY_RUN=false
TARGET=HEAD
while (($# > 0)); do
    case $1 in
    --dry-run) DRY_RUN=true ;;
    --target)
        if (($# < 2)); then
            echo "release-sidecar: --target needs a ref" >&2
            exit 2
        fi
        TARGET="$2"
        shift
        ;;
    -h | --help)
        sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
        exit 0
        ;;
    *)
        echo "release-sidecar: unknown argument $1" >&2
        exit 2
        ;;
    esac
    shift
done

command -v go >/dev/null || {
    echo "release-sidecar: no go toolchain to build with" >&2
    exit 1
}
command -v cargo >/dev/null || {
    echo "release-sidecar: no cargo to build with" >&2
    exit 1
}

TMP="$(mktemp -d "${TMPDIR:-/tmp}/haseen-sidecar-release.XXXXXX")"
cleanup() { rm -rf -- "$TMP"; }
trap cleanup EXIT

# musl_target ARCH — the Rust target each release architecture is built for.
musl_target() {
    case $1 in
    amd64) echo x86_64-unknown-linux-musl ;;
    arm64) echo aarch64-unknown-linux-musl ;;
    esac
}

for arch in amd64 arm64; do
    target="$(musl_target "$arch")"
    # rust-lld links the arm64 binary with the target's self-contained musl
    # runtime: the host's cc cannot (measured, plan 167). A fresh target
    # directory: never an earlier build of another version.
    if ! HASEEN_VERSION="$VERSION" CARGO_TARGET_DIR="$TMP/target" \
        CARGO_TARGET_AARCH64_UNKNOWN_LINUX_MUSL_LINKER=rust-lld \
        cargo build --release --locked --quiet --target "$target" \
        --manifest-path "$REPO/core/sidecar/Cargo.toml"; then
        echo "release-sidecar: the $target build failed (rustup target add $target?)" >&2
        exit 1
    fi
    install -m 0755 "$TMP/target/$target/release/haseen-sidecar" "$TMP/haseen-sidecar-linux-$arch"
    (cd "$REPO/core" && CGO_ENABLED=0 GOOS=linux GOARCH="$arch" \
        go build -trimpath -buildvcs=false -ldflags "-s -w -X main.version=$VERSION" \
        -o "$TMP/haseen-palette-linux-$arch" ./cmd/haseen-palette)
done
rm -rf -- "$TMP/target"

# Each daemon must at least start and know its version before it is
# published: amd64 here, arm64 under qemu when this machine has it.
check_version() { # ARCH RUNNER...
    local arch="$1" got
    shift
    got="$("$@" "$TMP/haseen-sidecar-linux-$arch" -version 2>&1)" || got="failed: $got"
    if [[ $got != "$VERSION" ]]; then
        echo "release-sidecar: haseen-sidecar-linux-$arch -version said '$got', not $VERSION" >&2
        exit 1
    fi
    echo "release-sidecar: haseen-sidecar-linux-$arch runs ($got)"
}
case "$(uname -m)" in
x86_64) check_version amd64 env ;;
aarch64)
    check_version arm64 env
    echo "release-sidecar: an arm64 host; the amd64 daemon is published untried" >&2
    ;;
esac
if [[ $(uname -m) != aarch64 ]]; then
    if command -v qemu-aarch64-static >/dev/null; then
        check_version arm64 qemu-aarch64-static
    else
        echo "release-sidecar: no qemu-aarch64-static; the arm64 daemon is published untried" >&2
    fi
fi
(cd "$TMP" && sha256sum haseen-*-linux-* >SHA256SUMS)
ls -l "$TMP"

if $DRY_RUN; then
    assets="$(printf '%q ' "$TMP"/haseen-*-linux-* "$TMP/SHA256SUMS")"
    printf "DRYRUN: gh release view '%s' (create when absent)\n" "$TAG"
    printf "DRYRUN: gh release create '%s' --title 'haseen-sidecar %s' --target %s\n" "$TAG" "$VERSION" "$(git -C "$REPO" rev-parse "$TARGET")"
    printf "DRYRUN: gh release upload '%s' %s--clobber\n" "$TAG" "$assets"
    exit 0
fi

if ! gh release view "$TAG" >/dev/null 2>&1; then
    gh release create "$TAG" \
        --title "haseen-sidecar $VERSION" \
        --target "$(git -C "$REPO" rev-parse "$TARGET")" \
        --notes "Prebuilt static haseen-sidecar (Rust, core/sidecar/) and haseen-palette (Go, core/) for linux/amd64 and linux/arm64, built at $(git -C "$REPO" rev-parse --short HEAD). A machine without the toolchains downloads these when install.sh runs (tools/build-sidecar.sh, plan 127); SHA256SUMS is checked before anything is installed."
fi
gh release upload "$TAG" "$TMP"/haseen-*-linux-* "$TMP/SHA256SUMS" --clobber
echo "release-sidecar: $TAG updated ($(gh release view "$TAG" --json url -q .url))"
