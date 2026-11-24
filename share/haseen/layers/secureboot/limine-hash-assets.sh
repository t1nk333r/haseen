#!/usr/bin/env bash
# limine-hash-assets.sh CONF ESP — add or refresh the #blake2b suffix of every
# `wallpaper:` and `term_font:` line in Limine's config. Runs as root (through
# sb_root) because the ESP is 0700; changes nothing when every hash is current.
#
# Why: with a config hash enrolled and Secure Boot on, Limine skips assets that
# carry no hash and panics on a stale one (USAGE.md "Secure Boot"). Kernel and
# module paths are deliberately left alone: limine-entry-tool writes those, and
# re-hashing whatever sits on the ESP would defeat the check.
#
# It holds Limine's boot-partition lock from the plan to the rename, as
# limine-header.sh does: the plan names lines by number, so a
# limine-snapper-sync or limine-entry-tool write in between would be lost or
# have the wrong line replaced, and that config would then be enrolled
# (plan 188).
set -Eeuo pipefail
# shellcheck source=secureboot.sh
source "$(dirname "$(readlink -f "$0")")/secureboot.sh"
# shellcheck source=../../lib/bootmenu.sh
source "$SB_DIR/../../lib/bootmenu.sh" # BOOTMENU_LOCK

(($# == 2)) || {
    echo "Usage: limine-hash-assets.sh /path/to/limine.conf /path/to/esp" >&2
    exit 2
}
conf="$1"
esp="$2"
[[ -f $conf && -r $conf && ! -L $conf ]] || die "not a readable regular file: $conf"
[[ -d $esp ]] || die "not a directory: $esp"

lock="$(sysroot_path "$BOOTMENU_LOCK")"
mkdir -p "${lock%/*}"
exec 9>"$lock"
flock -w 30 9 || die "$BOOTMENU_LOCK is held by another Limine tool; try again"

plan="$(sb_limine_asset_plan "$conf" "$esp")"
[[ -n $plan ]] || exit 0

tmp="$(mktemp "$conf.haseen.XXXXXX")"
trap 'rm -f "$tmp"' EXIT
awk '
    NR == FNR { i = index($0, "\t"); n = substr($0, 1, i - 1); rest = substr($0, i + 1)
                j = index(rest, "\t"); repl[n] = substr(rest, j + 1); next }
    (FNR in repl) { print repl[FNR]; next }
    { print }
' <(printf '%s\n' "$plan") "$conf" >"$tmp"
# Keep the original mode where the filesystem has one (vfat refuses chmod).
chmod --reference="$conf" "$tmp" 2>/dev/null || true
mv -f "$tmp" "$conf"
sync -f "$conf" 2>/dev/null || true
while IFS=$'\t' read -r n state line; do
    printf 'limine.conf:%s: %s hash %s -> %s\n' "$n" "$state" "$([[ $state == missing ]] && echo added || echo refreshed)" "${line#"${line%%[![:space:]]*}"}"
done <<<"$plan"
