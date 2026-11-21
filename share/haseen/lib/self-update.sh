# shellcheck shell=bash
# lib/self-update.sh — where haseen updates itself from (plan 182).
#
# `haseen update` installs haseen from its own copy of the repository, kept in
# $XDG_DATA_HOME/haseen/checkout and following one branch of one remote
# (GitHub's main by default). It is haseen's, like a package cache: nobody
# works in it, so it can always be moved to the branch's tip, and a developer's
# checkout (dirty, on a topic branch) is never what an update installs unless
# it is named with --source (owner, 2026-11-21: "Managed clone of main").
#
# Sourced after common.sh and install-stamp.sh.

SELF_UPDATE_REMOTE="${HASEEN_UPDATE_REMOTE:-https://github.com/t1nk333r/haseen.git}"
SELF_UPDATE_BRANCH="${HASEEN_UPDATE_BRANCH:-main}"
SELF_UPDATE_REF="origin/$SELF_UPDATE_BRANCH"

self_update_dir() { printf '%s\n' "${XDG_DATA_HOME:-$HOME/.local/share}/haseen/checkout"; }

# self_update_fetch — create haseen's copy, or bring its remote branch up to
# date. Nothing is checked out here; the copy's working tree moves only when
# an update installs (self_update_checkout). A blobless clone keeps the whole
# history (the installed commit is compared with the branch) without
# downloading every old file. Returns 3 under --dry-run when there is no copy
# yet, as there is then nothing to compare. Every step returns its own
# failure: callers run this under `||`, where errexit does not stop it.
self_update_fetch() {
    local dir
    dir="$(self_update_dir)"
    if [[ ! -d $dir/.git ]]; then
        [[ ! -e $dir ]] || die "$dir is not a git checkout; move it away and the next update clones haseen there again"
        run mkdir -p "${dir%/*}" || return
        run git clone --quiet --filter=blob:none --branch "$SELF_UPDATE_BRANCH" "$SELF_UPDATE_REMOTE" "$dir" || return
        $DRY_RUN && return 3
        return 0
    fi
    # The remote may have been set to another one since the copy was made.
    if [[ $(git -C "$dir" remote get-url origin 2>/dev/null) != "$SELF_UPDATE_REMOTE" ]]; then
        run git -C "$dir" remote set-url origin "$SELF_UPDATE_REMOTE" || return
    fi
    run git -C "$dir" fetch --quiet origin "+refs/heads/$SELF_UPDATE_BRANCH:refs/remotes/$SELF_UPDATE_REF" || return
}

# self_update_checkout — move haseen's copy to the branch's tip. Changes made
# by hand in it are refused, not overwritten: someone put them there.
self_update_checkout() {
    local dir dirty
    dir="$(self_update_dir)"
    dirty="$(git -C "$dir" status --porcelain --untracked-files=no)"
    [[ -z $dirty ]] ||
        die "haseen's copy in $dir has changes made by hand (first: $(head -n1 <<<"$dirty")); remove the directory and the next update clones it again"
    run git -C "$dir" checkout --quiet --detach "$SELF_UPDATE_REF"
}

# self_update_prefix [PREFIX] — the install prefix, and so the stamp to trust:
# PREFIX when given, else $HASEEN_UPDATE_PREFIX (`haseen update` has no
# --prefix of its own), else the running tree's own parent when it is an
# installed tree, else the prefix of an existing stamp, else install.sh's
# default (/usr/local). A checkout run by hand has HASEEN_PATH inside git, so
# its directory is never mistaken for a prefix.
self_update_prefix() {
    local want="${1:-${HASEEN_UPDATE_PREFIX:-}}" tree p
    want="${want%/}"
    if [[ -n $want ]]; then
        printf '%s\n' "$want"
        return 0
    fi
    tree="${HASEEN_PATH%/share/haseen}"
    if [[ $tree != "$HASEEN_PATH" ]] && ! git -C "$tree" rev-parse --git-dir >/dev/null 2>&1; then
        printf '%s\n' "$tree"
        return 0
    fi
    for p in /usr/local /usr; do
        [[ -r $(install_stamp_path "$p") ]] || continue
        printf '%s\n' "$p"
        return 0
    done
    printf '/usr/local\n'
}

# self_update_relation DIR INSTALLED TARGET [INSTALLED_AT] — how the installed
# commit stands to TARGET in the checkout DIR:
#   same     it is TARGET
#   behind   TARGET has it and more
#   ahead    it has TARGET and more: installing TARGET would go back
#   local    not on TARGET's history (a pull request's tree, a checkout with
#            work of its own) or a commit this copy does not have, installed
#            (INSTALLED_AT, the stamp's date) after TARGET was committed: it is
#            left until the branch moves on, as it most likely carries what
#            TARGET has (luna runs a pull request before it is merged)
#   apart    the same, installed before TARGET: installing TARGET is right
#   unknown  no stamp, or no date to tell the two cases apart
self_update_relation() {
    local dir=$1 installed=$2 target=$3 at=${4:-} a b when
    b="$(git -C "$dir" rev-parse --verify --quiet "$target^{commit}")"
    a=""
    if [[ -n $installed && $installed != unknown ]]; then
        a="$(git -C "$dir" rev-parse --verify --quiet "$installed^{commit}" 2>/dev/null || true)"
    fi
    if [[ -n $a ]]; then
        if [[ $a == "$b" ]]; then
            echo same
            return 0
        elif git -C "$dir" merge-base --is-ancestor "$a" "$b"; then
            echo behind
            return 0
        elif git -C "$dir" merge-base --is-ancestor "$b" "$a"; then
            echo ahead
            return 0
        fi
    fi
    when="$(date -d "$at" +%s 2>/dev/null || true)"
    if [[ -z $installed || -z $when ]]; then
        echo unknown
    elif ((when >= $(git -C "$dir" show -s --format=%ct "$b"))); then
        echo local
    else
        echo apart
    fi
}

# self_update_new_commits DIR INSTALLED TARGET — the subjects of the commits
# TARGET has that the installed tree does not, newest first; nothing when the
# installed commit is unknown here.
self_update_new_commits() {
    local dir=$1 installed=$2 target=$3
    git -C "$dir" rev-parse --verify --quiet "$installed^{commit}" >/dev/null 2>&1 || return 0
    git -C "$dir" log --format=%s "$installed..$target"
}

# self_update_reload_desktop — reload what reads the installed tree: the
# compositor's binds, rules and look, then the shell (the user unit; DMS and a
# hand-started shell are left alone).
self_update_reload_desktop() {
    if have hyprctl; then
        if $DRY_RUN; then
            echo "DRYRUN: hyprctl reload"
        else
            hyprctl reload >/dev/null || warn "hyprctl reload did not answer; the next session loads the new binds"
        fi
    fi
    # install.sh has rewritten the user units, and the user manager keeps the
    # copy it read until told to read them again: a restart without this runs
    # the old unit and warns that it changed on disk (plan 142).
    run systemctl --user daemon-reload || warn "systemctl --user daemon-reload failed; the units are read again at the next login"
    if systemctl --user is-active --quiet haseen-shell.service 2>/dev/null; then
        if $DRY_RUN; then
            echo "DRYRUN: systemctl --user restart haseen-shell.service"
        else
            systemctl --user restart haseen-shell.service
            info "haseen-shell.service restarted"
        fi
    elif [[ $(cat "$HASEEN_USER_STATE/active-shell" 2>/dev/null) == dms ]]; then
        info "DMS is the active shell; haseen-shell.service stays stopped"
    else
        warn "haseen-shell.service is not running: the next shell start uses the new tree"
    fi
}
