# shellcheck shell=bash
# omarchy-guard.sh — keep Omarchy's own packages from undoing haseen on a
# machine that still has them (plan 101). Sourced, never executed.
#
# The `omarchy` package ships Omarchy's migrations, and `omarchy-settings`
# rewrites /etc/plymouth/plymouthd.conf on every install and upgrade. haseen
# answers `omarchy-migrate` by name (plan 093), but /usr/bin/omarchy-migrate,
# and Omarchy's own /usr/bin/omarchy-update, which runs it right after its
# pacman transaction, still run Omarchy's scripts: in 4.5 they edit
# /boot/limine.conf without re-enrolling it, delete a link in the owner's
# read-only plugin directory, drop Ctrl+Space from fcitx5, uninstall Tensaku
# and enable a second wallpaper daemon. So haseen records every one of them as
# done in Omarchy's own ledger ("sealing"): from a haseen migration once, and
# from a pacman hook (default/omarchy-guard/50-haseen-omarchy.hook, installed
# by the base layer) whenever either package is installed or upgraded.
#
# The ledger rule is Omarchy's bin/omarchy-migrate (MIT, Copyright (c) David
# Heinemeier Hansson), unchanged from v4.0.6 to v4.5.0-rc1: a script in
# ${OMARCHY_PATH:-/usr/share/omarchy}/migrations/<name>.sh is done when the
# regular file ${OMARCHY_MIGRATION_STATE:-$HOME/.local/state/omarchy/migrations}/<name>.sh
# exists; its content is never read.

[[ -n ${HASEEN_OMARCHY_GUARD_SH:-} ]] && return 0
HASEEN_OMARCHY_GUARD_SH=1

# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# shellcheck disable=SC2034  # read by bin/haseen-omarchy-guard and the base layer
OMARCHY_GUARD_HOOK=/etc/pacman.d/hooks/50-haseen-omarchy.hook
OMARCHY_GUARD_SRC="$HASEEN_PATH/default/omarchy-guard"
# Omarchy's login notice for pending migrations (default/systemd/user/ in
# Omarchy, /usr/lib/systemd/user/ in its package). Its ExecStart is an
# absolute path, so haseen's `omarchy-migrate-notify` answer never replaces it.
OMARCHY_NOTIFY_UNIT='omarchy-migrate-notify.service'

# omarchy_migrations_dir — where Omarchy's runner looks, on the machine being
# inspected.
omarchy_migrations_dir() { sysroot_path "${OMARCHY_PATH:-/usr/share/omarchy}/migrations"; }

# omarchy_ledger_dir — this user's Omarchy ledger. $HOME, not XDG_STATE_HOME:
# that is what omarchy-migrate reads.
omarchy_ledger_dir() { printf '%s\n' "${OMARCHY_MIGRATION_STATE:-$HOME/.local/state/omarchy/migrations}"; }

# omarchy_migrations_count — how many migrations the installed package ships.
omarchy_migrations_count() {
    local f n=0
    for f in "$(omarchy_migrations_dir)"/*.sh; do
        [[ -f $f ]] && n=$((n + 1))
    done
    printf '%s\n' "$n"
}

# omarchy_migrations_unsealed — the names Omarchy's runner would run for this
# user, in its order (the glob's), one per line.
omarchy_migrations_unsealed() {
    local f ledger
    ledger="$(omarchy_ledger_dir)"
    for f in "$(omarchy_migrations_dir)"/*.sh; do
        [[ -f $f ]] || continue
        [[ -f $ledger/${f##*/} ]] || printf '%s\n' "${f##*/}"
    done
}

# omarchy_seal_migrations — record every unsealed migration as done in this
# user's Omarchy ledger, without running it. A marker Omarchy wrote is never
# touched; haseen's say who wrote them, for a later bug report. Idempotent.
# One migration that cannot be sealed (its name in the ledger is not a regular
# file, or the write fails) does not stop the others: all are attempted, every
# failure is named, and the status is 1.
omarchy_seal_migrations() {
    local ledger name n=0 stamp failed=()
    ledger="$(omarchy_ledger_dir)"
    stamp="sealed by haseen $(cat "$HASEEN_PATH/VERSION") on $(date -Is): never run here (plan 101)"
    while IFS= read -r name; do
        [[ -n $name ]] || continue
        if [[ -e $ledger/$name || -L $ledger/$name ]]; then
            warn "$ledger/$name exists but is not a regular file, so Omarchy's runner would still run $name; remove it and run haseen migrate omarchy again"
            failed+=("$name")
        elif printf '%s\n' "$stamp" | write_user_file "$ledger/$name"; then
            n=$((n + 1))
        else
            warn "could not write $ledger/$name"
            failed+=("$name")
        fi
    done < <(omarchy_migrations_unsealed)
    if ((n > 0)); then
        info "Omarchy's migrations: sealed $n"
    elif ((${#failed[@]} == 0)); then
        info "Omarchy's migrations: nothing to seal ($(omarchy_migrations_count) recorded)"
    fi
    if ((${#failed[@]})); then
        warn "Omarchy's migrations: ${#failed[@]} not sealed, so /usr/bin/omarchy-migrate would still run them: ${failed[*]}"
        return 1
    fi
    ((n == 0)) || info "Omarchy's migrations: /usr/bin/omarchy-migrate runs none of them"
}

# omarchy_guard_prefix — haseen's PREFIX (/usr/local, or /usr after the
# PKGBUILD phase), from HASEEN_PATH = PREFIX/share/haseen.
omarchy_guard_prefix() { (cd "$HASEEN_PATH/../.." && pwd); }

# omarchy_guard_hook_render [HASEEN_BIN] — the pacman hook as installed: its
# Exec names the haseen this tree belongs to.
omarchy_guard_hook_render() {
    local bin="${1:-$(omarchy_guard_prefix)/bin/haseen}"
    sed "s|@HASEEN_BIN@|$bin|" "$OMARCHY_GUARD_SRC/50-haseen-omarchy.hook"
}

omarchy_guard_hook_current() {
    cmp -s <(omarchy_guard_hook_render) "$(sysroot_path "$OMARCHY_GUARD_HOOK")"
}

# omarchy_guard_exec_trusted — the hook's Exec runs as root: the haseen it
# names, the command that routes to, and the libraries that command sources
# (lib/: omarchy-guard.sh, common.sh, plymouth.sh and theirs) must be files
# only root can change, along the router's own resolution
# (root_trusted_haseen), so a hook is never written for a checkout or any
# other tree a user owns. install.sh copies the tree as root
# (install.sh:233-235). So must the template the hook is rendered from, which
# decides its Exec, and every directory on its path (plan 111). Prints why not.
omarchy_guard_exec_trusted() {
    root_trusted_haseen "$(omarchy_guard_prefix)/bin/haseen" omarchy-guard lib &&
        root_trusted_exec "$OMARCHY_GUARD_SRC/50-haseen-omarchy.hook"
}

# omarchy_guard_untrusted_note WHY — what to do about it.
omarchy_guard_untrusted_note() {
    printf "the hook's %s runs as root, but %s; install haseen as root (./install.sh) and apply the base layer with the installed haseen\n" \
        "$(omarchy_guard_prefix)/bin/haseen" "$1"
}

# omarchy_notify_dropin [PREFIX] — the drop-in that silences Omarchy's login
# notice. systemd merges <unit>.d/ from every user unit path, so it sits next
# to haseen's own units, as the dms layer's drop-in does.
omarchy_notify_dropin() {
    printf '%s/lib/systemd/user/%s.d/haseen.conf\n' "${1:-$(omarchy_guard_prefix)}" "$OMARCHY_NOTIFY_UNIT"
}

omarchy_notify_dropin_src() { printf '%s\n' "$OMARCHY_GUARD_SRC/omarchy-migrate-notify.conf"; }

# omarchy_user_units_enabled — "unit<TAB>target" for every Omarchy user unit
# enabled for this user or globally (systemctl --global), read from the
# .wants/ links so it needs no running user manager. Omarchy's own are
# omarchy-*; its first run also enables bt-agent and OWE's owed
# (install/user/first-run/enable-user-units.sh@v4.5.0-rc1:21-32).
omarchy_user_units_enabled() {
    local dir link unit
    for dir in "${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user" "$(sysroot_path /etc/systemd/user)"; do
        for link in "$dir"/*.wants/*; do
            [[ -L $link || -e $link ]] || continue
            unit="${link##*/}"
            case "$unit" in
            omarchy-* | owed.* | owe-* | bt-agent.service) ;;
            *) continue ;;
            esac
            link="${link%/*}"
            link="${link##*/}"
            printf '%s\t%s\n' "$unit" "${link%.wants}"
        done
    done | LC_ALL=C sort -u
}

# omarchy_unit_note UNIT — why an enabled Omarchy unit matters under haseen;
# empty for one that does no harm.
omarchy_unit_note() {
    case "$1" in
    "$OMARCHY_NOTIFY_UNIT" | omarchy-update-user-notify.service)
        if [[ -f $(sysroot_path "$(omarchy_notify_dropin)") ]]; then
            echo "silenced by haseen's drop-in; haseen-migrate-notify.service tells you about haseen's"
        else
            echo "a second, Omarchy-branded pending-migration notice: reinstall haseen's tree (./install.sh --tree-only)"
        fi
        ;;
    owed.service)
        echo "a second wallpaper daemon beside haseen-background.service: systemctl --user disable --now owed.service"
        ;;
    esac
}

# omarchy_guard_doctor — the doctor's view; returns 1 when something leaves
# Omarchy's packages able to undo haseen.
omarchy_guard_doctor() {
    # shellcheck source=packages.sh
    source "$HASEEN_PATH/lib/packages.sh"
    # shellcheck source=plymouth.sh
    source "$HASEEN_PATH/lib/plymouth.sh"
    local ok=0 unsealed count unit target note why
    if ! pkg_installed omarchy && ! pkg_installed omarchy-settings && [[ ! -d $(omarchy_migrations_dir) ]]; then
        echo "omarchy package=not installed (nothing to guard)"
        return 0
    fi
    if [[ -d $(omarchy_migrations_dir) ]]; then
        count="$(omarchy_migrations_count)"
        unsealed="$(omarchy_migrations_unsealed | grep -c . || true)"
        if ((unsealed == 0)); then
            echo "omarchy migrations=sealed ($count): /usr/bin/omarchy-migrate runs none of them"
        else
            echo "omarchy migrations=$unsealed of $count not sealed: /usr/bin/omarchy-migrate would run them; haseen migrate omarchy"
            ok=1
        fi
    fi
    if omarchy_guard_hook_current; then
        if why="$(omarchy_guard_exec_trusted)"; then
            echo "omarchy pacman hook=installed ($OMARCHY_GUARD_HOOK)"
        else
            echo "omarchy pacman hook=unsafe: $(omarchy_guard_untrusted_note "$why")"
            ok=1
        fi
    elif [[ -e $(sysroot_path "$OMARCHY_GUARD_HOOK") ]]; then
        echo "omarchy pacman hook=differs from this tree's: haseen layer apply base"
        ok=1
    else
        echo "omarchy pacman hook=missing: Omarchy's next upgrade is not sealed; haseen layer apply base"
        ok=1
    fi
    if plymouth_reset_by_omarchy; then
        echo "splash=Omarchy's omarchy-settings put Theme=omarchy back: sudo haseen omarchy guard"
        ok=1
    fi
    while IFS=$'\t' read -r unit target; do
        [[ -n $unit ]] || continue
        note="$(omarchy_unit_note "$unit")"
        echo "omarchy user unit=$unit enabled ($target)${note:+: $note}"
    done < <(omarchy_user_units_enabled)
    return "$ok"
}
