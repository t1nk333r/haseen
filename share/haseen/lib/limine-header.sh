#!/usr/bin/env bash
# limine-header.sh — change the menu wait in Limine's config (plan 104).
#   limine-header.sh set CONF TIMEOUT QUIET   set timeout: and quiet: (- removes one)
#   limine-header.sh restore CONF BACKUP      put CONF's bytes back from BACKUP
# Run as root by bin/haseen-setup-boot-menu (through run_root; the ESP is
# 0700), never sourced. It takes Limine's own boot-partition lock while it
# reads and replaces CONF, so a limine-entry-tool or limine-snapper-sync
# write is neither lost nor overwritten, checks the layout again under that
# lock, and replaces CONF through a temporary file beside it and a rename, as
# limine-hash-assets.sh does. Nothing else in CONF changes.
set -Eeuo pipefail
# shellcheck source=bootmenu.sh
source "$(dirname "$(readlink -f "$0")")/bootmenu.sh"

usage() { sed -n '3,4s/^# \{0,1\}//p' "$0"; }

mode="${1:-}"
if [[ $mode == set ]] && (($# == 4)); then
    if ! bootmenu_valid timeout "$3" || ! bootmenu_valid quiet "$4"; then
        die "not a timeout/quiet pair haseen writes: '$3' '$4'"
    fi
elif [[ $mode != restore ]] || (($# != 3)); then
    usage >&2
    exit 2
fi
conf="$2"
[[ -f $conf && ! -L $conf ]] || die "not a regular file: $conf"

lock="$(sysroot_path "$BOOTMENU_LOCK")"
mkdir -p "${lock%/*}"
exec 9>"$lock"
flock -w 30 9 || die "$BOOTMENU_LOCK is held by another Limine tool; try again"

tmp="$(mktemp "$conf.haseen.XXXXXX")"
trap 'rm -f "$tmp"' EXIT
if [[ $mode == set ]]; then
    problems="$(bootmenu_problems "$conf")"
    [[ -z $problems ]] || die "$conf is not a layout haseen edits: ${problems//$'\n'/; }"
    bootmenu_render "$conf" "$3" "$4" >"$tmp"
else
    [[ -f $3 && -r $3 ]] || die "not a readable backup: $3"
    cat -- "$3" >"$tmp"
fi
if cmp -s "$tmp" "$conf"; then
    echo "limine.conf: unchanged"
    exit 0
fi
# Keep the original mode where the filesystem has one (vfat refuses chmod).
chmod --reference="$conf" "$tmp" 2>/dev/null || true
mv -f -- "$tmp" "$conf"
sync -f "$conf" 2>/dev/null || true
echo "limine.conf: timeout: $(bootmenu_value timeout "$conf"), quiet: $(bootmenu_value quiet "$conf")"
