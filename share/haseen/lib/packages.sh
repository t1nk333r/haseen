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

# Packages haseen never installs as a target, from any source: Omarchy's own
# system packages overwrite pacman.conf, the mirrorlist and the mkinitcpio
# HOOKS (ADR 0001, omacachy plan 015). pkg_guard_closure covers them arriving
# as dependencies.
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

# Packages whose pull of omarchy and omarchy-settings the owner approved, so
# that --yes may answer pkg_guard_closure for them. Filled by catalog.sh from
# the catalogue entries marked "pullsOmarchy" (flea: owner, 2026-10-05,
# confirmed 2026-10-08 and 2026-10-13).
PKG_OMARCHY_APPROVED=()

# Files omarchy-settings owns that land on a haseen subsystem, as
# "<path>|<subsystem>". Read with `pacman -Ql omarchy-settings` (4.0.4-1) on
# 2026-10-05: listing them at run time would need the package installed.
PKG_OMARCHY_COLLISIONS=(
    "/etc/fonts/conf.d/50-omarchy.conf|fonts: haseen's fontconfig seed and theme render"
    "/etc/limine-entry-tool.d/omarchy-defaults.conf|Limine entries: plan 002 Secure Boot"
    "/etc/limine-entry-tool.d/omarchy-uki.conf|Limine entries: plan 002 Secure Boot"
    "/etc/mkinitcpio.conf.d/omarchy_hooks.conf|initramfs HOOKS: plan 033 hibernation"
    "/etc/sddm.conf.d/10-theme.conf|display manager: haseen uses greetd + tuigreet"
    "/etc/sddm.conf.d/10-wayland.conf|display manager: haseen uses greetd + tuigreet"
    "/usr/lib/environment.d/10-omarchy-fcitx.conf|input method: haseen's fcitx5 seed"
    "/usr/share/applications/mimeapps.list|default handlers: haseen's vendor mimeapps.list"
    "/usr/share/xdg-terminal-exec/hyprland-xdg-terminals.list|default terminal: haseen's vendor list"
)

# pkg_closure NAME... — every package `pacman -S NAME...` would install: the
# targets and each dependency not installed yet, one name per line. pacman -Sp
# resolves against the local sync databases, unprivileged and offline; it
# fails when a name is in no sync database (pacman -S then fails on it too).
# Under a sysroot the fixture answers: var/lib/pacman/sync/NAME.deps lists the
# dependencies NAME adds (a test convention, like REPO.pkgs); none without one.
pkg_closure() {
    local p deps
    if in_sysroot; then
        for p in "$@"; do
            printf '%s\n' "${p##*/}"
            deps="$(sysroot_path "/var/lib/pacman/sync/${p##*/}.deps")"
            [[ ! -r $deps ]] || cat -- "$deps"
        done | awk 'NF && !seen[$0]++'
        return 0
    fi
    pacman -Sp --noconfirm --print-format %n "$@" </dev/null 2>/dev/null
}

# _pkg_denied_in CLOSURE — the PKG_DENY names in a pkg_closure listing.
_pkg_denied_in() {
    local d
    for d in "${PKG_DENY[@]}"; do
        grep -qxF -- "$d" <<<"$1" && printf '%s\n' "$d"
    done
    return 0
}

# pkg_guard_closure NAME... — run before pacman installs NAME...: when the
# closure contains a PKG_DENY package, print the closure and the system files
# omarchy-settings would take over, then ask. --yes answers only when every
# target that pulls them in is in PKG_OMARCHY_APPROVED; otherwise it refuses,
# so an unattended run never brings omarchy in. A closure pacman cannot
# resolve is left to pacman, which fails on the same name.
pkg_guard_closure() {
    local closure denied p a ok row unapproved=()
    closure="$(pkg_closure "$@")" || return 0
    denied="$(_pkg_denied_in "$closure")"
    [[ -n $denied ]] || return 0
    for p in "$@"; do
        ok=false
        for a in "${PKG_OMARCHY_APPROVED[@]}"; do
            [[ ${p##*/} == "$a" ]] && ok=true
        done
        $ok || unapproved+=("$p")
    done
    warn "installing ${*##*/} also installs $(paste -sd' ' <<<"$denied"), which haseen never installs on its own (docs/decisions/0001)"
    info "pacman would install: $(paste -sd' ' <<<"$closure")"
    if grep -qx omarchy-settings <<<"$denied"; then
        info "omarchy-settings then owns these system files, which land on haseen subsystems (pacman -Ql omarchy-settings 4.0.4-1, read 2026-10-05):"
        for row in "${PKG_OMARCHY_COLLISIONS[@]}"; do
            printf '    %-56s %s\n' "${row%%|*}" "${row#*|}"
        done
    fi
    info "removing ${*##*/} with haseen remove (pacman -Rns) removes $(paste -sd' ' <<<"$denied") and their files again, unless another package still needs them"
    if $ASSUME_YES && ((${#unapproved[@]} > 0)); then
        closure="$(pkg_closure "${unapproved[@]}")" || closure="$(printf '%s\n' "${PKG_DENY[@]}")"
        [[ -z $(_pkg_denied_in "$closure") ]] ||
            die "${unapproved[*]##*/} would bring in omarchy packages, which --yes never accepts; run the command without --yes to review the list above and answer yourself"
    fi
    confirm "Install them, the omarchy packages included?" || die "not confirmed; nothing was installed"
}

# pkg_install NAME... — install official-repo packages that are missing.
pkg_install() {
    local missing=() p
    pkg_refuse_denied "$@"
    for p in "$@"; do
        pkg_installed "$p" || missing+=("$p")
    done
    ((${#missing[@]} > 0)) || return 0
    pkg_guard_closure "${missing[@]}"
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
# the invoking user). The source of each package is resolved once, so a lookup
# that fails cannot route it differently between the decision and the install.
pkg_install_aur() {
    local missing=() p helper repo_pkgs=() chaotic_pkgs=() omarchy_pkgs=() aur_pkgs=()
    pkg_refuse_denied "$@"
    for p in "$@"; do
        pkg_installed "$p" || missing+=("$p")
    done
    ((${#missing[@]} > 0)) || return 0
    for p in "${missing[@]}"; do
        case "$(pkg_source "$p")" in
        repo:*) repo_pkgs+=("$p") ;;
        chaotic) chaotic_pkgs+=("chaotic-aur/$p") ;;
        omarchy) omarchy_pkgs+=("omarchy/$p") ;;
        *) aur_pkgs+=("$p") ;;
        esac
    done
    # An AUR build's dependencies are resolved by the helper, which lists them
    # before it builds; only the binary-repo part has a closure to check here.
    local binary=("${repo_pkgs[@]}" "${chaotic_pkgs[@]}" "${omarchy_pkgs[@]}")
    ((${#binary[@]} == 0)) || pkg_guard_closure "${binary[@]}"
    local flags=(--needed)
    $ASSUME_YES && flags+=(--noconfirm)
    ((${#repo_pkgs[@]} == 0)) || run_root pacman -S "${flags[@]}" "${repo_pkgs[@]}"
    ((${#chaotic_pkgs[@]} == 0)) || run_root pacman -S "${flags[@]}" "${chaotic_pkgs[@]}"
    ((${#omarchy_pkgs[@]} == 0)) || run_root pacman -S "${flags[@]}" "${omarchy_pkgs[@]}"
    ((${#aur_pkgs[@]} > 0)) || return 0

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

# pkg_install_omarchy NAME... — omarchy: entries, which haseen takes only from
# Omarchy's [omarchy] repo (owner, 2026-10-08): herdr's AUR build is AGPL-3.0
# where [omarchy]'s is Apache-2.0, and it once hung for 44 minutes (plan 014).
# No other repository is asked, even one that carries the same name, and
# nothing is built. A package [omarchy] does not list (or whose lookup fails)
# is skipped with a warning, and so is every package while the repo is not
# enabled. A dry run that applies omarchy-repo earlier plans them from the
# repo, which the real run will have enabled by then.
pkg_install_omarchy() {
    local p missing=() from_repo=() absent=()
    pkg_refuse_denied "$@"
    for p in "$@"; do
        pkg_installed "$p" || missing+=("$p")
    done
    ((${#missing[@]} > 0)) || return 0
    if omarchy_repo_enabled; then
        for p in "${missing[@]}"; do
            if pkg_repo_has omarchy "$p"; then
                from_repo+=("omarchy/$p")
            else
                absent+=("$p")
            fi
        done
        ((${#absent[@]} == 0)) ||
            warn "skipping ${absent[*]}: haseen installs them only from Omarchy's [omarchy] repo, which does not list them; no other repository is used and nothing is built from the AUR"
    elif $DRY_RUN && _omarchy_repo_applied_before; then
        from_repo=("${missing[@]/#/omarchy/}")
    else
        warn "skipping ${missing[*]}: haseen installs them only from Omarchy's [omarchy] repo, which is not enabled. To add them: haseen layer apply omarchy-repo${LAYER_NAME:+ $LAYER_NAME}"
        return 0
    fi
    ((${#from_repo[@]} > 0)) || return 0
    pkg_guard_closure "${from_repo[@]}"
    local flags=(--needed)
    $ASSUME_YES && flags+=(--noconfirm)
    run_root pacman -S "${flags[@]}" "${from_repo[@]}"
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
