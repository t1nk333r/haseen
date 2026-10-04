# shellcheck shell=bash
# packages.sh — package manifests. Sourced, never executed.
#
# Manifest format (layers/<name>/packages.txt and friends):
#   pkgname            # official repos (CachyOS repos first on CachyOS)
#   aur:pkgname        # AUR, built by paru or yay as the invoking user
#   # comment          # whole-line or trailing comments; blank lines ignored
# A package name must match pacman's charset; anything else is a manifest
# error, not something to pass to a shell.

[[ -n ${HASEEN_PACKAGES_SH:-} ]] && return 0
HASEEN_PACKAGES_SH=1
# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

PKG_NAME_RE='^[a-z0-9@._+][a-z0-9@._+-]*$'

# manifest_entries FILE KIND — print package names of KIND (repo|aur).
manifest_entries() {
    local file="$1" kind="$2" line name
    [[ -r $file ]] || die "manifest not readable: $file"
    while IFS= read -r line || [[ -n $line ]]; do
        line="${line%%#*}"
        line="${line//[[:space:]]/}"
        [[ -n $line ]] || continue
        case "$line" in
        aur:*)
            [[ $kind == aur ]] || continue
            name="${line#aur:}"
            ;;
        *:*) die "$file: unknown source prefix in '$line'" ;;
        *)
            [[ $kind == repo ]] || continue
            name="$line"
            ;;
        esac
        [[ $name =~ $PKG_NAME_RE ]] || die "$file: invalid package name '$name'"
        printf '%s\n' "$name"
    done <"$file"
}

# pkg_installed NAME — true when NAME is installed (fixture-aware).
pkg_installed() {
    if in_sysroot; then
        compgen -G "$(sysroot_path /var/lib/pacman/local)/$1-[0-9]*" >/dev/null
    else
        pacman -Qq "$1" &>/dev/null
    fi
}

# aur_helper — paru (CachyOS default) or yay; empty when neither exists.
aur_helper() {
    if have paru; then
        echo paru
    elif have yay; then
        echo yay
    fi
}

# pkg_install NAME... — install official-repo packages that are missing.
pkg_install() {
    local missing=() p
    for p in "$@"; do
        pkg_installed "$p" || missing+=("$p")
    done
    ((${#missing[@]} > 0)) || return 0
    local flags=(--needed)
    $ASSUME_YES && flags+=(--noconfirm)
    run_root pacman -S "${flags[@]}" "${missing[@]}"
}

# pkg_install_aur NAME... — install AUR packages that are missing, as the user.
pkg_install_aur() {
    local missing=() p helper
    for p in "$@"; do
        pkg_installed "$p" || missing+=("$p")
    done
    ((${#missing[@]} > 0)) || return 0
    helper="$(aur_helper)"
    [[ -n $helper ]] || die "AUR packages needed (${missing[*]}) but neither paru nor yay is installed"
    local flags=(--needed)
    $ASSUME_YES && flags+=(--noconfirm)
    run "$helper" -S "${flags[@]}" "${missing[@]}"
}

# pkg_install_manifest FILE — install every entry of a manifest. Entries are
# read through command substitution (not process substitution) so a manifest
# error aborts the caller instead of dying in a subshell.
pkg_install_manifest() {
    local file="$1" out repo=() aur=()
    out="$(manifest_entries "$file" repo)" || return 1
    [[ -z $out ]] || mapfile -t repo <<<"$out"
    out="$(manifest_entries "$file" aur)" || return 1
    [[ -z $out ]] || mapfile -t aur <<<"$out"
    ((${#repo[@]} == 0)) || pkg_install "${repo[@]}"
    ((${#aur[@]} == 0)) || pkg_install_aur "${aur[@]}"
}
