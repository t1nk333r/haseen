#!/usr/bin/env bash
# Apply a staged main→checkout sync: write each staged file and delete each
# listed one only if the checkout still holds the version the snapshot saw (a
# concurrent edit is never overwritten), then move git to origin/main without
# touching files.
# usage: sync-apply.sh REPO STAGE_TAR EXPECT_TSV DELETE_TSV
set -Eeuo pipefail
repo=$1 tarball=$2 expect=$3 deletes=$4
cd "$repo"
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
tar -xf "$tarball" -C "$stage"
have() { if [[ -e $1 ]]; then git hash-object -- "$1"; else echo ABSENT; fi; }
skipped=0 written=0 removed=0
while IFS=$'\t' read -r path want; do
    if [[ $(have "$path") != "$want" ]]; then
        echo "SKIP $path: changed since the snapshot"
        skipped=$((skipped + 1))
        continue
    fi
    mkdir -p "$(dirname "$path")"
    cp -p "$stage/$path" "$path"
    written=$((written + 1))
done <"$expect"
while IFS=$'\t' read -r path want; do
    [[ -n $path ]] || continue
    if [[ $(have "$path") != "$want" ]]; then
        echo "SKIP delete $path: changed since the snapshot"
        skipped=$((skipped + 1))
        continue
    fi
    rm -f -- "$path"
    removed=$((removed + 1))
done <"$deletes"
git fetch -q origin
[[ $(git rev-parse --abbrev-ref HEAD) == main ]] || { echo "not on main"; exit 1; }
git reset -q origin/main
echo "written $written, removed $removed, skipped $skipped; HEAD $(git rev-parse --short HEAD); status $(git status --short | wc -l)"
