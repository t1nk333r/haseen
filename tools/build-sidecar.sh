#!/usr/bin/env bash
# tools/build-sidecar.sh [DEST] — build haseen-sidecar from core/.
#
# DEST defaults to share/haseen/sidecar/haseen-sidecar, which is where the
# installed tree keeps it and where qs.Haseen.Sidecar looks. Without a Go
# toolchain this exits 0 and says so: the shell then finds no daemon, the
# capability is absent, and the features that need it hide (plan 032).
set -Eeuo pipefail

REPO="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
DEST="${1:-$REPO/share/haseen/sidecar/haseen-sidecar}"
VERSION="$(cat "$REPO/share/haseen/VERSION")"

if ! command -v go >/dev/null; then
    echo "build-sidecar: no go toolchain; haseen-sidecar not built" >&2
    exit 0
fi

mkdir -p "$(dirname "$DEST")"
cd "$REPO/core"
# -trimpath keeps the build reproducible and -buildvcs=false keeps it from
# shelling out to git; the version is what the hello frame reports, so a stale
# binary is visible in `haseen sidecar status`.
go build -trimpath -buildvcs=false -ldflags "-s -w -X main.version=$VERSION" -o "$DEST" ./cmd/haseen-sidecar
echo "build-sidecar: $DEST ($VERSION)"
