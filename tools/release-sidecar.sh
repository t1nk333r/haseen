#!/usr/bin/env bash
# tools/release-sidecar.sh [--target REF] [--dry-run]
# Build haseen-sidecar and haseen-palette for linux/amd64 and linux/arm64 and
# publish them as the `sidecar-v<share/haseen/VERSION>` release (plan 127).
#
# A machine the installer runs on without a Go toolchain downloads these
# instead of building them (tools/build-sidecar.sh), so this is what makes a
# new machine's sidecar arrive with `install.sh`. CGO is off: the daemon is
# pure Go, and a static binary is what a machine with no toolchain can run.
# Assets are replaced (`--clobber`) on every run: one release per version, and
# the SHA256SUMS beside them is what the installer checks before installing.
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

TMP="$(mktemp -d "${TMPDIR:-/tmp}/haseen-sidecar-release.XXXXXX")"
cleanup() { rm -rf -- "$TMP"; }
trap cleanup EXIT

for arch in amd64 arm64; do
    for cmd in haseen-sidecar haseen-palette; do
        (cd "$REPO/core" && CGO_ENABLED=0 GOOS=linux GOARCH="$arch" \
            go build -trimpath -buildvcs=false -ldflags "-s -w -X main.version=$VERSION" \
            -o "$TMP/$cmd-linux-$arch" "./cmd/$cmd")
    done
done
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
        --notes "Prebuilt haseen-sidecar and haseen-palette for linux/amd64 and linux/arm64, built from core/ at $(git -C "$REPO" rev-parse --short HEAD). A machine without a Go toolchain downloads these when install.sh runs (tools/build-sidecar.sh, plan 127); SHA256SUMS is checked before anything is installed."
fi
gh release upload "$TAG" "$TMP"/haseen-*-linux-* "$TMP/SHA256SUMS" --clobber
echo "release-sidecar: $TAG updated ($(gh release view "$TAG" --json url -q .url))"
