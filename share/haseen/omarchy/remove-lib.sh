# shellcheck shell=bash
# omarchy/remove-lib.sh — shared by haseen's omarchy-remove-* commands (plan
# 093). Sourced after omarchy/lib.sh, never executed.
#
# Omarchy's removers drop packages with omarchy-pkg-drop (sudo pacman -Rns
# --noconfirm), delete data with rm -rf and ask with gum confirm. haseen's
# answers remove packages and Flatpaks through bin/haseen-remove, delete only
# through common.sh's `run` (so --dry-run prints the whole plan), and ask at
# the terminal with `ask`:
#
#   ask Q          default no; --yes answers no: the data stays. For data
#                  Omarchy only deletes after asking.
#   ask Q yes      default no; --yes answers yes. For data Omarchy deletes
#                  without asking, so a non-interactive run does what it did.
#
# A dry run prints each question and plans the yes. Without a terminal
# (stdin at EOF) the answer is no.

[[ -n ${HASEEN_OMARCHY_REMOVE_LIB:-} ]] && return 0
HASEEN_OMARCHY_REMOVE_LIB=1
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
# shellcheck source=../lib/terminal.sh
source "$HASEEN_PATH/lib/terminal.sh"

# quiet CMD... — CMD with its errors silenced, as Omarchy runs its best-effort
# steps; a dry run prints it.
quiet() {
    if $DRY_RUN; then
        run "$@"
    else
        "$@" 2>/dev/null
    fi
}

# silent CMD... — CMD with all its output silenced; a dry run prints it.
silent() {
    if $DRY_RUN; then
        run "$@"
    else
        "$@" >/dev/null 2>&1
    fi
}

# haseen_remove ARGS... — bin/haseen-remove inline (this command already has
# its terminal), non-interactive like omarchy-pkg-drop, and dry with us.
haseen_remove() {
    local flags=(--yes)
    $DRY_RUN && flags+=(--dry-run)
    HASEEN_INLINE=1 "$HASEEN_BIN/haseen-remove" "$@" "${flags[@]}"
}

# removable PKG... — of the installed PKGs, print those no other installed
# package depends on (by name or by something they provide), and warn about
# the rest. pacman -R refuses a whole transaction that would break a
# dependency, so a shared helper (a Wine build, libfido2) is left to its other
# users instead of failing the removal, which Omarchy's single pacman call
# did. Reads the local database directly, so fixtures stand in for it.
removable() {
    local descs=() line kept=()
    mapfile -t descs < <(compgen -G "$(sysroot_path /var/lib/pacman/local)/*/desc" || true)
    ((${#descs[@]})) || return 0
    while IFS= read -r line; do
        case $line in
        "R "*) printf '%s\n' "${line#R }" ;;
        "K "*) kept+=("${line#K }") ;;
        esac
    done < <(awk -v want=" $* " '
        FNR == 1 { name = ""; sect = "" }
        /^%[A-Z0-9]+%$/ { sect = $0; next }
        /^$/ { sect = ""; next }
        sect == "%NAME%" { name = $0; pkgs[name] = 1; next }
        sect == "%DEPENDS%" { d = $0; sub(/[<>=].*/, "", d); deps[name] = deps[name] " " d; next }
        sect == "%PROVIDES%" { p = $0; sub(/[<>=].*/, "", p); prov[p] = prov[p] " " name; next }
        END {
            n = split(want, w, " ")
            for (i = 1; i <= n; i++) if (w[i] in pkgs) cand[w[i]] = 1
            # A candidate another package keeps stays, and so do its own
            # dependencies: repeat until nothing changes.
            do {
                changed = 0
                for (x in pkgs) {
                    if (x in cand) continue
                    m = split(deps[x], ds, " ")
                    for (j = 1; j <= m; j++) {
                        if (ds[j] in cand) { delete cand[ds[j]]; kept[ds[j]] = 1; changed = 1 }
                        k = split(prov[ds[j]], ps, " ")
                        for (l = 1; l <= k; l++)
                            if (ps[l] in cand) { delete cand[ps[l]]; kept[ps[l]] = 1; changed = 1 }
                    }
                }
            } while (changed)
            for (i = 1; i <= n; i++) {
                if (w[i] in cand) { print "R " w[i]; delete cand[w[i]] }
                else if (w[i] in kept) { print "K " w[i]; delete kept[w[i]] }
            }
        }' "${descs[@]}")
    ((${#kept[@]} == 0)) || warn "kept ${kept[*]}: another installed package needs it"
}

# remove_pkgs PKG... — omarchy-pkg-drop the haseen way: the installed PKGs
# that nothing else needs go in one `haseen remove package` (pacman -Rns).
remove_pkgs() {
    local pkgs=()
    mapfile -t pkgs < <(removable "$@")
    if ((${#pkgs[@]} == 0)); then
        info "no package to remove (not installed: $*)"
        return 0
    fi
    haseen_remove package "${pkgs[@]}"
}

# pkg_present NAME — NAME is installed: an exact name match in the local
# pacman database (<name>-<pkgver>-<pkgrel> directories), fixture-aware.
pkg_present() {
    local d n
    for d in "$(sysroot_path /var/lib/pacman/local)/$1"-*/; do
        [[ -d $d ]] || continue
        n="${d%/}"
        n="${n##*/}"
        n="${n%-*}"
        [[ ${n%-*} == "$1" ]] && return 0
    done
    return 1
}

# flatpak_installed ID — the Flatpak app is in the user or the system
# installation (the same file probe haseen's catalogue uses).
flatpak_installed() {
    [[ -d ${XDG_DATA_HOME:-$HOME/.local/share}/flatpak/app/$1 || -d $(sysroot_path /var/lib/flatpak/app)/$1 ]]
}

# remove_flatpak_app NAME ID — haseen's catalogue installs NAME as the Flatpak
# ID; remove it when that is installed (haseen remove app NAME).
remove_flatpak_app() {
    flatpak_installed "$2" || return 0
    haseen_remove app "$1"
}

# ask QUESTION [yes] — see the header.
ask() {
    local reply
    if $DRY_RUN; then
        echo "DRYRUN: ask '$1 [y/N]'; on yes:"
        return 0
    fi
    if $ASSUME_YES; then
        [[ ${2:-no} == yes ]] && return 0
        info "not done under --yes (answer at a terminal to do it): $1"
        return 1
    fi
    read -r -p "$1 [y/N] " reply || return 1
    [[ $reply =~ ^[Yy]$ ]]
}

# present PATH... — the PATHs that exist (dangling links too), into FOUND.
present() {
    FOUND=()
    local p
    for p in "$@"; do
        [[ -e $p || -L $p ]] && FOUND+=("$p")
    done
    return 0
}

# size_of PATH... — their total size as du -sh prints it ("" when unknown).
size_of() { du -shc -- "$@" 2>/dev/null | tail -n1 | cut -f1 || true; }

# delete_asked QUESTION yes|no PATH... — ask about the PATHs that exist, with
# their size, then rm -rf them on yes. False when nothing was deleted.
delete_asked() {
    local question=$1 yes=$2
    shift 2
    present "$@"
    ((${#FOUND[@]})) || return 1
    ask "$question ($(size_of "${FOUND[@]}"): ${FOUND[*]})?" "$yes" || return 1
    run rm -rf -- "${FOUND[@]}"
}

# rm_present PATH... — rm -f the PATHs that exist; the plan lists only those.
rm_present() {
    present "$@"
    ((${#FOUND[@]} == 0)) || run rm -f -- "${FOUND[@]}"
}

# unit_stopped UNIT — only systemd's own word counts as stopped: a failing
# is-active also covers an unreachable user manager.
unit_stopped() {
    local state
    state=$(systemctl --user is-active "$1" 2>/dev/null) || true
    [[ $state == inactive || $state == failed ]]
}

# webapp_remove NAME — remove the web app launcher NAME and its icon. One
# written by `haseen webapp install` (Exec with --app=) goes through
# bin/haseen-webapp-remove; one Omarchy wrote (Exec runs
# omarchy-launch-webapp or a web-app handler), which haseen's index does not
# see, is removed here the way Omarchy's omarchy-webapp-remove does. False
# when there is no such web app.
webapp_remove() {
    local name=$1 dir="${XDG_DATA_HOME:-$HOME/.local/share}" file found="" icon_name flags=()
    while IFS= read -r -d '' file; do
        [[ ${file##*/} == "$name.desktop" ]] || continue
        grep -q '^Exec=.*\(omarchy-launch-webapp\|omarchy-webapp-handler\|--app=\)' "$file" || continue
        found=$file
        break
    done < <(find "$dir/applications" -name '*.desktop' -print0 2>/dev/null)
    [[ -n $found ]] || {
        info "no web app named '$name'"
        return 1
    }
    if grep -q '^Exec=.*--app=' "$found"; then
        $DRY_RUN && flags+=(--dry-run)
        "$HASEEN_BIN/haseen-webapp-remove" "${flags[@]}" "$name"
        return
    fi
    icon_name="$(printf '%s\n' "$name" | tr '[:upper:]' '[:lower:]' | sed 's/[^[:alnum:]]\+/-/g; s/^-//; s/-$//')"
    run rm -f -- "$found"
    rm_present "$dir/icons/hicolor/256x256/apps/$icon_name.png" "$dir/icons/hicolor/256x256/apps/$name.png" \
        "$dir/applications/icons/$name.png"
    have update-desktop-database && { silent update-desktop-database "$dir/applications" || true; }
    info "web app removed: $name"
}

# plugin_off ID — turn an Omarchy plugin id off in haseen's shell when the
# user's shell.json names it (installed with `haseen plugin install` and
# enabled); haseen's defaults never do, and an id it never named needs no
# entry written for it.
plugin_off() {
    local flags=()
    grep -qsF "\"$1\"" "$HASEEN_USER_CONFIG/shell.json" || return 0
    $DRY_RUN && flags+=(--dry-run)
    "$HASEEN_BIN/haseen-plugin-disable" "$1" "${flags[@]}" || warn "could not turn $1 off in haseen's shell"
}

# pam_drop FILE OWN FOREIGN [GATE] — take authentication lines out of the PAM
# file FILE, rewritten whole through write_root_file (a dry run prints the
# result):
#   - lines equal to one of haseen's own (OWN, newline-separated; runs of
#     blanks compared as one) go without asking: haseen wrote them;
#   - other active lines matching the extended regex FOREIGN (Omarchy's or
#     the user's) are shown, then go after `ask ... yes`: removing them is
#     what the command is for, as in Omarchy, which asks nothing;
#   - a line matching GATE goes with the line after it: a [success=1] gate
#     left in front of the next rule would skip that rule instead.
# Sets PAM_KEPT=true when foreign lines stay.
pam_drop() {
    local file=$1 own=$2 foreign=$3 gate=${4:-} src old new lines mode drop=0
    src="$(sysroot_path "$file")"
    [[ -f $src ]] || return 0
    old="$(<"$src")"
    if [[ -n $foreign ]]; then
        lines="$(PAM_OWN=$own PAM_RE=$foreign PAM_DROP=0 pam_filter "$src" foreign)"
        if [[ -n $lines ]]; then
            printf '%s has authentication lines haseen did not write:\n%s\n' "$file" "$(sed 's/^/    /' <<<"$lines")"
            if ask "Remove them from $file" yes; then
                drop=1
            else
                # shellcheck disable=SC2034  # read by the calling command
                PAM_KEPT=true
            fi
        fi
    fi
    new="$(PAM_OWN=$own PAM_RE=$foreign PAM_DROP=$drop PAM_GATE=$gate pam_filter "$src" keep)"
    [[ $new != "$old" ]] || return 0
    mode="$(stat -c %a -- "$src" 2>/dev/null || echo 644)"
    printf '%s\n' "$new" | write_root_file "$file" "0$mode"
}

# pam_filter FILE foreign|keep — pam_drop's line filter (its settings come in
# the environment, so awk never rewrites a backslash in them).
pam_filter() {
    awk -v mode="$2" '
        function norm(t) { gsub(/^[ \t]+|[ \t]+$/, "", t); gsub(/[ \t]+/, " ", t); return t }
        BEGIN { n = split(ENVIRON["PAM_OWN"], o, "\n"); for (i = 1; i <= n; i++) if (o[i] != "") mine[norm(o[i])] = 1
                re = ENVIRON["PAM_RE"]; gate = ENVIRON["PAM_GATE"]; dropf = ENVIRON["PAM_DROP"] == 1 }
        { line[NR] = $0
          t = norm($0); active = t != "" && t !~ /^#/
          own[NR] = (t in mine)
          alien[NR] = active && !own[NR] && re != "" && $0 ~ re }
        END {
            for (i = NR; i >= 1; i--) {
                gone[i] = own[i] || (dropf && alien[i])
                if (!gone[i] && gate != "" && line[i] ~ gate && gone[i + 1]) gone[i] = 1
            }
            for (i = 1; i <= NR; i++) {
                if (mode == "foreign") { if (alien[i]) print line[i] }
                else if (!gone[i]) print line[i]
            }
        }' "$1"
}
