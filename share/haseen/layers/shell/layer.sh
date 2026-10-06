# shellcheck shell=bash disable=SC2034  # LAYER_* are read by lib/layers.sh
# layers/shell — the haseen Quickshell shell as a user unit (architecture 5).

LAYER_SUMMARY="the haseen Quickshell shell as haseen-shell.service"
LAYER_REQUIRES=(desktop theme)
LAYER_CONFLICTS=()
LAYER_DISTROS=(cachyos arch omarchy)

SHELL_UNIT=haseen-shell.service
SHELL_UNIT_WANTS="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/graphical-session.target.wants/$SHELL_UNIT"
# Locks the screen before suspend (bin/haseen-lock-before-sleep). Part of the
# shell layer because the lock it triggers is the shell's.
SLEEP_LOCK_UNIT=haseen-sleep-lock.service
SLEEP_LOCK_UNIT_WANTS="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/graphical-session.target.wants/$SLEEP_LOCK_UNIT"
# Turns core dumps into a "diagnose with AI" notification (bin/haseen-crash-watch).
CRASH_WATCH_UNIT=haseen-crash-watch.service
CRASH_WATCH_UNIT_WANTS="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/graphical-session.target.wants/$CRASH_WATCH_UNIT"

layer_status() {
    local ok=0 missing=0 p
    for p in quickshell jq; do
        if pkg_installed "$p"; then
            echo "ok: $p installed"
            ok=$((ok + 1))
        else
            echo "missing: package $p"
            missing=$((missing + 1))
        fi
    done
    if [[ -e $HASEEN_USER_CONFIG/shell.json ]]; then
        echo "ok: $HASEEN_USER_CONFIG/shell.json"
        ok=$((ok + 1))
    else
        echo "missing: $HASEEN_USER_CONFIG/shell.json"
        missing=$((missing + 1))
    fi
    # The enable symlink, not `systemctl is-enabled`: status stays a pure read
    # that also works against fixtures.
    if [[ -L $SHELL_UNIT_WANTS ]]; then
        echo "ok: $SHELL_UNIT enabled"
        ok=$((ok + 1))
    else
        echo "missing: $SHELL_UNIT not enabled"
        missing=$((missing + 1))
    fi
    if [[ -L $SLEEP_LOCK_UNIT_WANTS ]]; then
        echo "ok: $SLEEP_LOCK_UNIT enabled"
        ok=$((ok + 1))
    else
        echo "missing: $SLEEP_LOCK_UNIT not enabled (no lock before suspend)"
        missing=$((missing + 1))
    fi
    if [[ -L $CRASH_WATCH_UNIT_WANTS ]]; then
        echo "ok: $CRASH_WATCH_UNIT enabled"
        ok=$((ok + 1))
    else
        echo "missing: $CRASH_WATCH_UNIT not enabled (no crash notifications)"
        missing=$((missing + 1))
    fi
    ((missing == 0)) && return 0
    ((ok == 0)) && return 1
    return 2
}

layer_apply() {
    seed_user_file "$LAYER_DIR/files/shell.json" "$HASEEN_USER_CONFIG/shell.json"
    seed_user_file "$LAYER_DIR/files/shell.example.json" "$HASEEN_USER_CONFIG/shell.example.json"
    if [[ -L $SHELL_UNIT_WANTS ]]; then
        info "$SHELL_UNIT already enabled"
    else
        run systemctl --user enable "$SHELL_UNIT"
    fi
    if [[ -L $SLEEP_LOCK_UNIT_WANTS ]]; then
        info "$SLEEP_LOCK_UNIT already enabled"
    else
        run systemctl --user enable "$SLEEP_LOCK_UNIT"
    fi
    if [[ -L $CRASH_WATCH_UNIT_WANTS ]]; then
        info "$CRASH_WATCH_UNIT already enabled"
    else
        run systemctl --user enable "$CRASH_WATCH_UNIT"
    fi
    info "the shell starts with the next graphical session; to start it now: haseen shell restart"
}

layer_remove() {
    if [[ -L $SHELL_UNIT_WANTS ]]; then
        run systemctl --user disable "$SHELL_UNIT"
    fi
    if [[ -L $SLEEP_LOCK_UNIT_WANTS ]]; then
        run systemctl --user disable "$SLEEP_LOCK_UNIT"
    fi
    if [[ -L $CRASH_WATCH_UNIT_WANTS ]]; then
        run systemctl --user disable "$CRASH_WATCH_UNIT"
    fi
    info "kept $HASEEN_USER_CONFIG/shell.json and plugins/ (user files)"
}
