# shellcheck shell=bash disable=SC2034  # LAYER_* are read by lib/layers.sh
# layers/shell — the haseen Quickshell shell as a user unit (architecture 5),
# and the Helium browser with the Cairn extension (owner, 2026-10-07, plan 073).

LAYER_SUMMARY="the haseen Quickshell shell as haseen-shell.service, and Helium with Cairn"
LAYER_REQUIRES=(desktop theme)
LAYER_CONFLICTS=()
LAYER_DISTROS=(cachyos arch omarchy)

# Linted on its own: followed from here, shellcheck mixes common.sh's
# require_cmds array `missing` with layer_status's counter (SC2178).
# shellcheck source=/dev/null
source "$HASEEN_PATH/lib/cairn.sh"

SHELL_UNIT=haseen-shell.service
SHELL_UNIT_WANTS="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/graphical-session.target.wants/$SHELL_UNIT"
# Locks the screen before suspend (bin/haseen-lock-before-sleep). Part of the
# shell layer because the lock it triggers is the shell's.
SLEEP_LOCK_UNIT=haseen-sleep-lock.service
SLEEP_LOCK_UNIT_WANTS="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/graphical-session.target.wants/$SLEEP_LOCK_UNIT"
# Turns core dumps into a "diagnose with AI" notification and keeps the last
# good shell.json for shell recovery (bin/haseen-crash-watch, plan 061).
CRASH_WATCH_UNIT=haseen-crash-watch.service
CRASH_WATCH_UNIT_WANTS="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/graphical-session.target.wants/$CRASH_WATCH_UNIT"
# dms:// links (the DankMaterialShell plugin gallery's Install button) open
# bin/haseen-plugin-url. The desktop file is installed with the tree.
DMS_URL_DESKTOP=haseen-dms-url.desktop
DMS_URL_MIME=x-scheme-handler/dms
# DMS's own handler (assets/dms-open.desktop in dms-shell) is replaced:
# haseen-plugin-url hands the link back to `dms open` when DMS is the active shell.
DMS_OWN_DESKTOP=dms-open.desktop
MIMEAPPS_LIST="${XDG_CONFIG_HOME:-$HOME/.config}/mimeapps.list"

# dms_url_handler — the dms:// default the user's mimeapps.list names, if any.
# Read directly rather than through `xdg-mime query`, which also falls back to
# system caches: only an explicit choice counts as the user's.
dms_url_handler() {
    [[ -r $MIMEAPPS_LIST ]] || return 0
    awk -F= -v key="$DMS_URL_MIME" '
        /^\[/ { section = $0; next }
        section == "[Default Applications]" && $1 == key { split($2, v, ";"); print v[1]; exit }
    ' "$MIMEAPPS_LIST"
}

layer_status() {
    local ok=0 missing=0 p
    for p in quickshell jq helium-browser-bin; do
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
    local handler
    handler="$(dms_url_handler)"
    case "$handler" in
    "$DMS_URL_DESKTOP")
        echo "ok: dms:// links open haseen plugin url"
        ok=$((ok + 1))
        ;;
    "" | "$DMS_OWN_DESKTOP")
        echo "missing: dms:// links are not handled by haseen (no plugin installs from the DMS gallery)"
        missing=$((missing + 1))
        ;;
    *)
        echo "ok: dms:// links open $handler (your choice)"
        ok=$((ok + 1))
        ;;
    esac
    if cairn_status; then
        ok=$((ok + 1))
    else
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
    local handler
    handler="$(dms_url_handler)"
    case "$handler" in
    "$DMS_URL_DESKTOP") info "dms:// links already open haseen plugin url" ;;
    "" | "$DMS_OWN_DESKTOP") run xdg-mime default "$DMS_URL_DESKTOP" "$DMS_URL_MIME" ;;
    *) info "dms:// links stay with $handler (your choice); haseen's is: xdg-mime default $DMS_URL_DESKTOP $DMS_URL_MIME" ;;
    esac
    # Cairn is fetched from its releases; without a network the shell still
    # applies, and status reports Cairn missing.
    cairn_install || warn "Cairn was not set up for Helium; run: haseen setup cairn"
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
    info "kept $HASEEN_USER_CONFIG/shell.json and plugins/ (user files), and Helium with Cairn"
}
