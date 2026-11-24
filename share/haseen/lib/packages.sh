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
pkg_guard_closure() { _pkg_guard pkg_closure "pacman would install" "$@"; }

# pkg_guard_aur_closure NAME... — the same guard before the AUR helper builds
# NAME...: the helper installs their dependencies itself, and under --yes it
# asks nothing (plan 185). A closure that cannot be read (no helper, the AUR
# unreachable) is refused under --yes, since nothing would check it then;
# without --yes the helper lists the dependencies and asks.
pkg_guard_aur_closure() { _pkg_guard pkg_aur_closure "building them would install" "$@"; }

# _pkg_guard CLOSURE_FN LABEL NAME... — pkg_guard_closure's body, with the
# function that lists the closure of NAME....
_pkg_guard() {
    local fn="$1" label="$2" closure denied p a ok row unapproved=()
    shift 2
    if ! closure="$("$fn" "$@")"; then
        [[ $fn == pkg_aur_closure ]] && $ASSUME_YES &&
            die "cannot read what building ${*##*/} from the AUR would install, so --yes cannot rule out omarchy packages among it; run the command without --yes and read the helper's list"
        return 0
    fi
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
    info "$label: $(paste -sd' ' <<<"$closure")"
    if grep -qx omarchy-settings <<<"$denied"; then
        info "omarchy-settings then owns these system files, which land on haseen subsystems (pacman -Ql omarchy-settings 4.0.4-1, read 2026-10-05):"
        for row in "${PKG_OMARCHY_COLLISIONS[@]}"; do
            printf '    %-56s %s\n' "${row%%|*}" "${row#*|}"
        done
    fi
    info "removing ${*##*/} with haseen remove (pacman -Rns) removes $(paste -sd' ' <<<"$denied") and their files again, unless another package still needs them"
    if $ASSUME_YES && ((${#unapproved[@]} > 0)); then
        closure="$("$fn" "${unapproved[@]}")" || closure="$(printf '%s\n' "${PKG_DENY[@]}")"
        [[ -z $(_pkg_denied_in "$closure") ]] ||
            die "${unapproved[*]##*/} would bring in omarchy packages, which --yes never accepts; run the command without --yes to review the list above and answer yourself"
    fi
    confirm "Install them, the omarchy packages included?" || die "not confirmed; nothing was installed"
}

# _pkg_dep_satisfied DEP — an installed package satisfies DEP (a name or a
# provided name). Under a sysroot, one by that name is installed.
_pkg_dep_satisfied() {
    if in_sysroot; then
        pkg_installed "$1"
    else
        pacman -T -- "$1" &>/dev/null
    fi
}

# _pkg_aur_deps NAME — the depends, makedepends and checkdepends of the AUR
# package NAME, one name per line, version constraints dropped: what the
# helper installs to build it. Read from the helper's `-Si --aur` (the AUR's
# RPC; LC_ALL=C keeps the field names English). Under a sysroot the fixture
# answers: var/lib/pacman/sync/NAME.deps, the pkg_closure convention.
_pkg_aur_deps() {
    if in_sysroot; then
        local deps
        deps="$(sysroot_path "/var/lib/pacman/sync/$1.deps")"
        [[ ! -r $deps ]] || cat -- "$deps"
        return 0
    fi
    local helper out
    helper="$(aur_helper)"
    [[ -n $helper ]] || return 1
    out="$(LC_ALL=C "$helper" -Si --aur -- "$1" </dev/null 2>/dev/null)" || return 1
    [[ -n $out ]] || return 1
    # "Depends On      : a  b>=2" and so on; a long value may wrap onto
    # indented lines, which belong to the field above them.
    awk '
        /^[^[:space:]][^:]*:/ {
            f = $0; sub(/[[:space:]]*:.*/, "", f)
            v = $0; sub(/^[^:]*:[[:space:]]*/, "", v)
            want = (f == "Depends On" || f == "Make Deps" || f == "Check Deps")
            if (want) emit(v)
            next
        }
        want { emit($0) }
        function emit(s,   n, i, w, a) {
            n = split(s, a, /[[:space:]]+/)
            for (i = 1; i <= n; i++) {
                w = a[i]; sub(/[<>=].*/, "", w)
                if (w != "" && w != "None") print w
            }
        }' <<<"$out"
}

# pkg_aur_closure NAME... — what building NAME... from the AUR would install:
# the targets, and each dependency not installed yet: one a sync repo has
# expanded by pkg_closure, one only the AUR has followed the same way. Fails
# when a package's dependencies cannot be read.
pkg_aur_closure() {
    local queue=("$@") seen=" " list="" n d out sub
    while ((${#queue[@]} > 0)); do
        n="${queue[0]}"
        queue=("${queue[@]:1}")
        [[ $seen != *" $n "* ]] || continue
        seen+="$n "
        list+="$n"$'\n'
        out="$(_pkg_aur_deps "$n")" || return 1
        while read -r d; do
            [[ -n $d ]] || continue
            _pkg_dep_satisfied "$d" && continue
            if sub="$(pkg_closure "$d")" && [[ -n $sub ]]; then
                list+="$sub"$'\n'
            else
                queue+=("$d")
            fi
        done <<<"$out"
    done
    awk 'NF && !seen[$0]++' <<<"$list"
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
# after the official ones, in that order. A dry run that applies the chaotic
# layer earlier plans every such entry from Chaotic-AUR, which the real run
# will have enabled by then (plan 185; its database cannot be read before).
pkg_source() {
    local repo
    while read -r repo; do
        [[ -n $repo && $repo != chaotic-aur && $repo != omarchy ]] || continue
        pkg_repo_has "$repo" "$1" && { echo "repo:$repo"; return 0; }
    done < <(pkg_enabled_repos)
    if chaotic_enabled; then
        if pkg_repo_has chaotic-aur "$1"; then
            echo chaotic
            return 0
        fi
    elif $DRY_RUN && _layer_applied_before chaotic; then
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
    if ((${#chaotic_pkgs[@]} > 0)) && ! chaotic_enabled; then
        info "planned from Chaotic-AUR, which this run enables first: ${chaotic_pkgs[*]#chaotic-aur/} (a package it does not carry goes on to [omarchy] or the AUR)"
    fi
    # The binary-repo part is checked here; an AUR build's part below, once a
    # helper can read it.
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
    # The helper installs the build's dependencies itself, --noconfirm under
    # --yes: what it would install gets the same omarchy guard first. A live
    # dry run does not ask the AUR (the network) for it; a fixture answers.
    if $DRY_RUN && ! in_sysroot; then
        echo "DRYRUN: read what building ${aur_pkgs[*]} would install from the AUR, and refuse omarchy or omarchy-settings among it as pacman installs do"
    else
        pkg_guard_aur_closure "${aur_pkgs[@]}"
    fi
    # A PKGBUILD is code from whoever maintains it, and the pacman steps above
    # may have left sudo's timestamp warm: run_cold drops it and makes every
    # sudo the build runs ask afresh (plan 103). The helper uses the `sudo` on
    # PATH, whatever its config names, and keeps no sudo loop, which with
    # nothing cached would only prompt again and again. These options go after
    # the targets so the plan still reads "paru -S --needed NAME".
    local cold=(--sudo sudo)
    case $helper in
    paru) cold+=(--nosudoloop) ;;
    yay) cold+=(--sudoloop=false) ;;
    esac
    run_cold "$helper" -S "${flags[@]}" "${aur_pkgs[@]}" "${cold[@]}"
}

# _layer_applied_before NAME — this `haseen layer apply` run applies layer
# NAME before the current one (HASEEN_APPLY_LAYERS, the apply order
# haseen-layer-apply exports).
_layer_applied_before() {
    local n
    for n in ${HASEEN_APPLY_LAYERS:-}; do
        [[ $n == "$1" ]] && return 0
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
    elif $DRY_RUN && _layer_applied_before omarchy-repo; then
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
