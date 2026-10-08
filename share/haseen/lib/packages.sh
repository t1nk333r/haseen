# shellcheck shell=bash
# packages.sh — package manifests. Sourced, never executed.
#
# Manifest format (layers/<name>/packages.txt and friends):
#   pkgname            # official repos (CachyOS repos first on CachyOS)
#   aur:pkgname        # not in the official repos; see pkg_install_aur
#   omarchy:pkgname    # taken prebuilt from Omarchy's [omarchy] repo only,
#                      # skipped with a warning without it; see
#                      # pkg_install_omarchy
#   # comment          # whole-line or trailing comments; blank lines ignored
# A package name must match pacman's charset; anything else is a manifest
# error, not something to pass to a shell.
#
# Source order for aur: entries (owner decisions 2026-10-04): an enabled
# official/CachyOS repo, then Chaotic-AUR (the `chaotic` layer), then
# Omarchy's [omarchy] repo (the `omarchy-repo` layer), and the AUR itself only
# as the last resort.

[[ -n ${HASEEN_PACKAGES_SH:-} ]] && return 0
HASEEN_PACKAGES_SH=1
# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# Spelled out, not [a-z]: a bracket range follows the caller's locale
# collation (a UTF-8 locale can admit "á"), a literal list never does. The
# same ASCII set as metadata.py's NAME.
PKG_NAME_RE='^[abcdefghijklmnopqrstuvwxyz0123456789@._+][abcdefghijklmnopqrstuvwxyz0123456789@._+-]*$'
# Manifest whitespace, ASCII only for the same reason ([[:space:]] admits
# Unicode spaces under a UTF-8 locale).
PKG_SPACE=$' \t\r\n\v\f'

# manifest_entries FILE KIND — print package names of KIND (repo|aur|omarchy).
manifest_entries() {
    local file="$1" kind="$2" line name
    [[ -r $file ]] || die "manifest not readable: $file"
    while IFS= read -r line || [[ -n $line ]]; do
        line="${line%%#*}"
        line="${line//[$PKG_SPACE]/}"
        [[ -n $line ]] || continue
        case "$line" in
        aur:* | omarchy:*)
            [[ $kind == "${line%%:*}" ]] || continue
            name="${line#*:}"
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

# Packages haseen never installs, from any source: Omarchy's own system
# packages overwrite pacman.conf, the mirrorlist and the mkinitcpio HOOKS
# (ADR 0001, omacachy plan 015). The [omarchy] repo is used only for leaf
# packages such as ttfx.
PKG_DENY=(omarchy omarchy-settings)

pkg_refuse_denied() {
    local p d
    for p in "$@"; do
        for d in "${PKG_DENY[@]}"; do
            [[ ${p##*/} == "$d" ]] && die "haseen never installs '$d': it overwrites pacman.conf, the mirrorlist and the initramfs HOOKS (docs/decisions/0001)"
        done
    done
    return 0
}

# pkg_install NAME... — install official-repo packages that are missing.
pkg_install() {
    local missing=() p
    pkg_refuse_denied "$@"
    for p in "$@"; do
        pkg_installed "$p" || missing+=("$p")
    done
    ((${#missing[@]} > 0)) || return 0
    local flags=(--needed)
    $ASSUME_YES && flags+=(--noconfirm)
    run_root pacman -S "${flags[@]}" "${missing[@]}"
}

# pkg_enabled_repos — the sync repositories pacman uses, one per line.
# Fixture-aware: under a sysroot the [sections] of its pacman.conf.
pkg_enabled_repos() {
    if in_sysroot; then
        local conf
        conf="$(sysroot_path /etc/pacman.conf)"
        [[ -r $conf ]] || return 0
        sed -n 's/^[[:space:]]*\[\([^]]*\)\][[:space:]]*$/\1/p' "$conf" | grep -vx options || true
    else
        pacman-conf --repo-list 2>/dev/null || true
    fi
}

# pkg_repo_has REPO NAME — REPO's sync database carries NAME. Read-only.
# Under a sysroot the fixture lists a repo's packages, one per line, in
# var/lib/pacman/sync/REPO.pkgs (a test convention, not a pacman file).
pkg_repo_has() {
    if in_sysroot; then
        local list
        list="$(sysroot_path "/var/lib/pacman/sync/$1.pkgs")"
        [[ -r $list ]] && grep -qxF "$2" "$list"
    else
        pacman -Si "$1/$2" &>/dev/null
    fi
}

chaotic_enabled() { pkg_enabled_repos | grep -qx chaotic-aur; }
omarchy_repo_enabled() { pkg_enabled_repos | grep -qx omarchy; }

# pkg_source NAME — where an aur: entry comes from: "repo:REPO" (an enabled
# official/CachyOS repo carries it after all), "chaotic", "omarchy" or "aur".
# Chaotic-AUR and [omarchy] are third-party binary repos and are asked only
# after the official ones, in that order.
pkg_source() {
    local repo
    while read -r repo; do
        [[ -n $repo && $repo != chaotic-aur && $repo != omarchy ]] || continue
        pkg_repo_has "$repo" "$1" && { echo "repo:$repo"; return 0; }
    done < <(pkg_enabled_repos)
    if chaotic_enabled && pkg_repo_has chaotic-aur "$1"; then
        echo chaotic
        return 0
    fi
    if omarchy_repo_enabled && pkg_repo_has omarchy "$1"; then
        echo omarchy
        return 0
    fi
    echo aur
}

# pkg_install_aur NAME... — install packages that are not in the official
# repos. Each one comes from the first source that has it: an enabled repo,
# Chaotic-AUR, the [omarchy] repo, then the AUR as the last resort (built as
# the invoking user).
pkg_install_aur() { _pkg_install_sourced aur "$@"; }

# _pkg_install_sourced LAST NAME... — the shared source order. LAST is what
# happens to a package no enabled binary repo carries (or whose lookup
# failed): "aur" builds it, "skip" leaves it out with a warning. The source of
# each package is resolved once, so a lookup that fails cannot route it
# differently between the decision and the install.
_pkg_install_sourced() {
    local last=$1
    shift
    local missing=() p src helper repo_pkgs=() chaotic_pkgs=() omarchy_pkgs=() aur_pkgs=()
    pkg_refuse_denied "$@"
    for p in "$@"; do
        pkg_installed "$p" || missing+=("$p")
    done
    ((${#missing[@]} > 0)) || return 0
    for p in "${missing[@]}"; do
        src="$(pkg_source "$p")"
        case "$src" in
        repo:*) repo_pkgs+=("$p") ;;
        chaotic) chaotic_pkgs+=("chaotic-aur/$p") ;;
        omarchy) omarchy_pkgs+=("omarchy/$p") ;;
        *) aur_pkgs+=("$p") ;;
        esac
    done
    local flags=(--needed)
    $ASSUME_YES && flags+=(--noconfirm)
    ((${#repo_pkgs[@]} == 0)) || run_root pacman -S "${flags[@]}" "${repo_pkgs[@]}"
    ((${#chaotic_pkgs[@]} == 0)) || run_root pacman -S "${flags[@]}" "${chaotic_pkgs[@]}"
    ((${#omarchy_pkgs[@]} == 0)) || run_root pacman -S "${flags[@]}" "${omarchy_pkgs[@]}"
    ((${#aur_pkgs[@]} > 0)) || return 0

    if [[ $last == skip ]]; then
        warn "skipping ${aur_pkgs[*]}: haseen installs them only prebuilt, and no enabled repository ([omarchy] included) carries them; they are never built from the AUR"
        return 0
    fi
    if chaotic_enabled; then
        warn "not in the official repos, Chaotic-AUR or [omarchy], building from the AUR (last resort): ${aur_pkgs[*]}"
    else
        warn "building from the AUR (last resort): ${aur_pkgs[*]}. Prebuilt binaries: haseen layer apply chaotic"
    fi
    helper="$(aur_helper)"
    if [[ -z $helper ]]; then
        # A helper is itself an AUR package on Arch; Chaotic-AUR ships paru prebuilt.
        if chaotic_enabled && pkg_repo_has chaotic-aur paru; then
            run_root pacman -S "${flags[@]}" chaotic-aur/paru
            helper=paru
        else
            die "AUR packages needed (${aur_pkgs[*]}) but neither paru nor yay is installed (haseen layer apply chaotic provides paru)"
        fi
    fi
    run "$helper" -S "${flags[@]}" "${aur_pkgs[@]}"
}

# _omarchy_repo_applied_before — this `haseen layer apply` run applies the
# omarchy-repo layer before the current one (HASEEN_APPLY_LAYERS, the apply
# order haseen-layer-apply exports).
_omarchy_repo_applied_before() {
    local n
    for n in ${HASEEN_APPLY_LAYERS:-}; do
        [[ $n == omarchy-repo ]] && return 0
        [[ $n == "${LAYER_NAME:-}" ]] && return 1
    done
    return 1
}

# pkg_install_omarchy NAME... — omarchy: entries: packages haseen takes only
# prebuilt from Omarchy's [omarchy] repo (owner, 2026-10-08), such as herdr,
# whose AUR build differs in licence and once hung for 44 minutes (plan 014).
# With the repo enabled they go through the binary part of pkg_install_aur's
# source order; one that no enabled repo carries, or whose lookup fails, is
# skipped with a warning, never built from the AUR. Without the repo they are
# skipped with a warning too. A dry run that applies omarchy-repo earlier
# plans them from the repo, which the real run will have enabled by then.
pkg_install_omarchy() {
    local p missing=()
    pkg_refuse_denied "$@"
    if omarchy_repo_enabled; then
        _pkg_install_sourced skip "$@"
        return
    fi
    for p in "$@"; do
        pkg_installed "$p" || missing+=("$p")
    done
    ((${#missing[@]} > 0)) || return 0
    if $DRY_RUN && _omarchy_repo_applied_before; then
        local flags=(--needed)
        $ASSUME_YES && flags+=(--noconfirm)
        run_root pacman -S "${flags[@]}" "${missing[@]/#/omarchy/}"
        return 0
    fi
    warn "skipping ${missing[*]}: haseen installs them only from Omarchy's [omarchy] repo, which is not enabled. To add them: haseen layer apply omarchy-repo ${LAYER_NAME:-desktop}"
}

# pkg_install_manifest FILE — install every entry of a manifest. Entries are
# read through command substitution (not process substitution) so a manifest
# error aborts the caller instead of dying in a subshell.
pkg_install_manifest() {
    local file="$1" out repo=() aur=() omarchy=()
    out="$(manifest_entries "$file" repo)" || return 1
    [[ -z $out ]] || mapfile -t repo <<<"$out"
    out="$(manifest_entries "$file" aur)" || return 1
    [[ -z $out ]] || mapfile -t aur <<<"$out"
    out="$(manifest_entries "$file" omarchy)" || return 1
    [[ -z $out ]] || mapfile -t omarchy <<<"$out"
    ((${#repo[@]} == 0)) || pkg_install "${repo[@]}"
    ((${#aur[@]} == 0)) || pkg_install_aur "${aur[@]}"
    ((${#omarchy[@]} == 0)) || pkg_install_omarchy "${omarchy[@]}"
}
