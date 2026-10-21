# shellcheck shell=bash disable=SC2034  # WOOTING_* are read by the commands that source this
# wooting.sh — the one channel to the Wooting keyboard: wootingd's socket
# (plan 099). Adapted from the owner's t1nk333r/haseen-wooting lib/ipc.sh at
# 184f6fa (MIT, Copyright (c) 2026 t1nk33r); the functions are renamed
# wooting_*, the behaviour is the same.
#
# wootingd owns the Wooting vendor command interface (HID usage page 0xFF55).
# Quickshell has no HID access at all, and only one process may usefully hold
# that interface, so every consumer — `haseen wooting`, its doctor, the bar
# widget — asks the daemon instead of touching hidraw. There is deliberately
# no HID logic in this file, and there must never be.
#
# Protocol: one verb line in, exactly one JSON line back.
#
# Sourceable and side-effect-free: this file only defines functions and one
# tunable. It runs no command and writes nothing.

[[ -n ${HASEEN_WOOTING_SH:-} ]] && return 0
HASEEN_WOOTING_SH=1

# Seconds socat waits for the daemon (both transfer and inactivity timeout). A
# live daemon answers in microseconds; a wedged one must never hang a caller.
WOOTING_IPC_TIMEOUT="${WOOTING_IPC_TIMEOUT:-2}"

# wooting_socket — the daemon's socket path, resolved exactly as wootingd
# resolves it (core/wootingd/src/main.rs socket_path): $WOOTINGD_SOCKET, else
# $XDG_RUNTIME_DIR/wootingd.sock, else /tmp/wootingd-$UID.sock.
wooting_socket() {
    if [[ -n ${WOOTINGD_SOCKET:-} ]]; then
        printf '%s' "$WOOTINGD_SOCKET"
    elif [[ -n ${XDG_RUNTIME_DIR:-} ]]; then
        printf '%s' "$XDG_RUNTIME_DIR/wootingd.sock"
    else
        printf '%s' "/tmp/wootingd-$(id -u).sock"
    fi
}

# wooting_socket_present — true when a socket exists where the daemon puts one.
wooting_socket_present() { [[ -S "$(wooting_socket)" ]]; }

# wooting_send VERB... — send one verb line, print the single JSON reply line.
#   0  reply printed, and it is a JSON object
#   3  no socket, or the daemon never answered
#   1  the daemon answered with something that is not a JSON object
# The reply is passed through byte for byte: callers that want raw JSON get
# the daemon's own line, not a re-serialised copy.
wooting_send() {
    local sock verb raw reply
    sock=$(wooting_socket)
    verb="$*"

    if [[ ! -S $sock ]]; then
        printf 'wooting: no daemon socket at %s\n' "$sock" >&2
        return 3
    fi

    # `head -n 1` returns the moment the reply line lands, so a round trip
    # costs microseconds instead of waiting out the socat timeout; the
    # timeouts only bound the failure case. socat's exit status is ignored on
    # purpose: it is killed by SIGPIPE once head has what it needs.
    raw=$(printf '%s\n' "$verb" |
        socat -t"$WOOTING_IPC_TIMEOUT" -T"$WOOTING_IPC_TIMEOUT" - "UNIX-CONNECT:$sock" 2>/dev/null |
        head -n 1) || true
    reply=${raw%%$'\n'*}

    if [[ -z ${reply//[[:space:]]/} ]]; then
        printf 'wooting: daemon at %s did not answer %s\n' "$sock" "$verb" >&2
        return 3
    fi
    if ! jq -e 'type == "object"' >/dev/null 2>&1 <<<"$reply"; then
        printf 'wooting: daemon sent a reply that is not a JSON object: %s\n' "$reply" >&2
        return 1
    fi

    printf '%s\n' "$reply"
}

# --- who installed the rule and the unit (plan 099) ---------------------------
# haseen and the owner's t1nk33r.wooting plugin both start wootingd from a
# udev rule named 70-wootingd.rules that pulls in a user unit named
# wootingd.service. One name each, on purpose: udev can want only that one
# unit and systemd resolves the name to one file, so at most one daemon is ever
# started for the keyboard. `haseen setup wooting on` takes both names over;
# these tell the copies apart by a line each writer puts in its file.
WOOTING_RULE=/etc/udev/rules.d/70-wootingd.rules
WOOTING_UNIT_NAME=wootingd.service
# The line that marks haseen's copies (share/haseen/default/udev/70-wootingd.rules,
# share/haseen/default/systemd/wootingd.service).
WOOTING_HASEEN_MARK="# haseen: setup wooting (plan 099)"
# The plugin's rule: the header line its uninstall.sh recognises it by.
WOOTING_PLUGIN_RULE_MARK="Wooting Profiles plugin (t1nk33r.wooting)"
# The plugin's unit: its Documentation= line, kept by its install.sh.
WOOTING_PLUGIN_UNIT_MARK="Documentation=https://github.com/t1nk333r/haseen-wooting"

# wooting_unit_path — where the user unit lives: the user's own unit
# directory, which comes before every system one, so whatever is here is the
# wootingd.service the user manager runs.
wooting_unit_path() { printf '%s/systemd/user/%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}" "$WOOTING_UNIT_NAME"; }

# wooting_owner FILE KIND — who wrote FILE (KIND rule or unit): haseen,
# plugin, other, or missing.
wooting_owner() {
    local file=$1 kind=$2 mark
    if [[ ! -e $file && ! -L $file ]]; then
        echo missing
        return 0
    fi
    if grep -qxF -- "$WOOTING_HASEEN_MARK" "$file" 2>/dev/null; then
        echo haseen
        return 0
    fi
    mark=$WOOTING_PLUGIN_UNIT_MARK
    [[ $kind == rule ]] && mark=$WOOTING_PLUGIN_RULE_MARK
    if grep -qF -- "$mark" "$file" 2>/dev/null; then
        echo plugin
    else
        echo other
    fi
}
