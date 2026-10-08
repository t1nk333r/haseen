# shellcheck shell=bash disable=SC2034  # OUTPUT/STATUS/FIXTURES are read by the test files
# tests/lib.sh — assertions and sandbox helpers for tests/test-*.sh.
# Sourced by tests/run.sh into each test file's subshell.
#
# Every test runs hermetically:
#   - HASEEN_SYSROOT points at a fixture tree (tests/fixtures/<name>), so no
#     probe reads the live machine;
#   - HOME and XDG_* point into a scratch dir under tests/.out;
#   - PATH starts with a stub dir where every state-changing binary (sudo,
#     pacman, sbctl, systemctl, …) prints STUB-CALLED and exits 97. Dry-run
#     purity = the output of a --dry-run never contains STUB-CALLED.

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURES="$REPO/tests/fixtures"
OUT="$REPO/tests/.out"
export HASEEN_PATH="$REPO/share/haseen"

TESTS_RUN=0
TESTS_FAILED=0

# Binaries a dry run must never execute. Read-only tools tests rely on (od,
# sed, grep, jq) are deliberately absent.
STUBBED_CMDS=(sudo pkexec pacman paru yay makepkg sbctl systemctl limine
    limine-enroll-config limine-update limine-entry-tool limine-scan
    mkinitcpio bootctl efibootmgr mokutil cryptsetup systemd-cryptenroll
    podman docker distrobox ollama llama-server ufw snapper hyprctl qs
    quickshell dms flatpak curl wget git pkill gsettings secret-tool
    notify-send xdg-open systemd-run uwsm-app brightnessctl ddcutil)

# sandbox NAME — fresh scratch HOME + stub PATH; sets SANDBOX.
sandbox() {
    SANDBOX="$OUT/$1"
    rm -rf "$SANDBOX"
    mkdir -p "$SANDBOX/home" "$SANDBOX/stubs"
    local c
    for c in "${STUBBED_CMDS[@]}"; do
        printf '#!/bin/sh\necho "STUB-CALLED: %s $*" >&2\nexit 97\n' "$c" >"$SANDBOX/stubs/$c"
        chmod +x "$SANDBOX/stubs/$c"
    done
    export HOME="$SANDBOX/home"
    export XDG_CONFIG_HOME="$HOME/.config" XDG_STATE_HOME="$HOME/.local/state"
    export XDG_DATA_HOME="$HOME/.local/share" XDG_CACHE_HOME="$HOME/.cache"
    # The session's data dirs name this machine's /usr/share; a test that
    # needs some sets them itself (plan 037: a host app must not count).
    unset XDG_DATA_DIRS
    export PATH="$SANDBOX/stubs:$REPO/bin:/usr/bin:/bin"
    unset HASEEN_USER_CONFIG HASEEN_USER_STATE HASEEN_COMMON_SH
    # Nothing under test may reach the session it runs in: a test once sent
    # its `haseen plugin url dmsKeep` refusal to the owner's live notification
    # daemon. A dead bus address and no compositor sockets make any leak fail
    # inside the test instead.
    export DBUS_SESSION_BUS_ADDRESS=unix:path=/nonexistent
    export XDG_RUNTIME_DIR="$SANDBOX/run"
    mkdir "$XDG_RUNTIME_DIR" && chmod 0700 "$XDG_RUNTIME_DIR"
    unset WAYLAND_DISPLAY DISPLAY HYPRLAND_INSTANCE_SIGNATURE SWAYSOCK NIRI_SOCKET
    # The session's platform theme (gtk3) needs a display and aborts without one.
    unset QT_QPA_PLATFORMTHEME
}

# stub CMD SCRIPT — replace a stub with a scripted fake (e.g. a read-only
# probe that should answer). SCRIPT is the body of a /bin/sh script.
stub() {
    printf '#!/bin/sh\n%s\n' "$2" >"$SANDBOX/stubs/$1"
    chmod +x "$SANDBOX/stubs/$1"
}

_pass() { TESTS_RUN=$((TESTS_RUN + 1)); }
_fail() {
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    printf '  FAIL %s\n' "$1" >&2
    [[ -z ${2:-} ]] || printf '%s\n' "$2" | sed 's/^/       /' >&2
}

assert_eq() { # LABEL EXPECTED ACTUAL
    if [[ $2 == "$3" ]]; then _pass; else _fail "$1" "expected: $2"$'\n'"actual:   $3"; fi
}

assert_contains() { # LABEL HAYSTACK NEEDLE
    if [[ $2 == *"$3"* ]]; then _pass; else _fail "$1" "missing: $3"$'\n'"in: ${2:0:2000}"; fi
}

assert_not_contains() { # LABEL HAYSTACK NEEDLE
    if [[ $2 != *"$3"* ]]; then _pass; else _fail "$1" "unexpected: $3"$'\n'"in: ${2:0:2000}"; fi
}

assert_status() { # LABEL EXPECTED_CODE ACTUAL_CODE
    if [[ $2 == "$3" ]]; then _pass; else _fail "$1" "exit: expected $2, got $3"; fi
}

# assert_dry_pure LABEL OUTPUT — no stubbed binary ran.
assert_dry_pure() { assert_not_contains "$1 (dry-run purity)" "$2" "STUB-CALLED"; }

# capture CMD... — run CMD, set OUTPUT (stdout+stderr) and STATUS.
capture() {
    set +e
    OUTPUT="$("$@" 2>&1)"
    STATUS=$?
    set -e
}
