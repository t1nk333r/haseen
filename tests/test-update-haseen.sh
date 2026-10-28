# shellcheck shell=bash
# haseen:covers bin/haseen-update-haseen share/haseen/lib/install-stamp.sh
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# `haseen update haseen` (plan 134): pull the checkout, run its install.sh,
# reload Hyprland and the shell. A real bare repository stands in for origin,
# so fetch, fast-forward and the commit comparison are the real thing; only
# the installer, hyprctl and systemctl are stubs. The sandbox stubs git, so
# everything here runs with the real one back on PATH.

sandbox update-haseen
LOG="$SANDBOX/calls.log"
: >"$LOG"
export LOG
# The harness stubs git itself, and Hyprland's and systemd's own binaries
# exist on a real machine: these two stubs go in a directory of their own,
# ahead of /usr/bin, while the real git comes from /usr/bin.
mkdir -p "$SANDBOX/tools-stubs" "$SANDBOX/stubs"
printf '%s\n' '#!/bin/sh' 'echo "hyprctl $*" >>"$LOG"' >"$SANDBOX/tools-stubs/hyprctl"
# SYSTEMCTL_NO_MANAGER makes daemon-reload fail, as it does when no user
# manager answers (ssh without XDG_RUNTIME_DIR); SYSTEMCTL_SHELL_STOPPED makes
# is-active report the shell stopped.
printf '%s\n' '#!/bin/sh' 'echo "systemctl $*" >>"$LOG"' \
    '[ "$2" = daemon-reload ] && [ -n "${SYSTEMCTL_NO_MANAGER:-}" ] && exit 1' \
    '[ "$2" = is-active ] && [ -n "${SYSTEMCTL_SHELL_STOPPED:-}" ] && exit 3' 'exit 0' >"$SANDBOX/tools-stubs/systemctl"
chmod 755 "$SANDBOX/tools-stubs"/*
REAL_PATH="$SANDBOX/tools-stubs:$REPO/bin:/usr/bin:/bin"
g() { env PATH="$REAL_PATH" git "$@"; }

# seed → a bare origin → two clones: the one that gets updated, and a second
# machine that pushes the new commit.
seed="$SANDBOX/seed" origin="$SANDBOX/origin.git" work="$SANDBOX/work" other="$SANDBOX/other"
prefix="$SANDBOX/prefix"
g init -q -b main "$seed"
g -C "$seed" config user.email t@example.invalid
g -C "$seed" config user.name Test
mkdir -p "$seed/share/haseen"
printf '0.2.0-dev\n' >"$seed/share/haseen/VERSION"
cat >"$seed/install.sh" <<'SH'
#!/usr/bin/env bash
echo "install: $*"
SH
chmod 755 "$seed/install.sh"
g -C "$seed" add -A
g -C "$seed" commit -qm one
g clone -q --bare "$seed" "$origin"
g clone -q "$origin" "$work"
g clone -q "$origin" "$other"
for d in "$work" "$other"; do
    g -C "$d" config user.email t@example.invalid
    g -C "$d" config user.name Test
done

# hx ARGS... — the command under test, with the checkout and prefix it needs.
# HASEEN_INLINE=1 is the documented test hook: without it the command, started
# without a terminal, would open a floating one for sudo's prompt (and there
# is no compositor here to open it in).
hx() { env PATH="$REAL_PATH" HASEEN_INLINE=1 haseen update haseen --source "$work" --prefix "$prefix" "$@"; }

# --- a checkout that is behind -------------------------------------------------
printf '0.3.0-dev\n' >"$other/share/haseen/VERSION"
g -C "$other" commit -qam two
g -C "$other" push -q origin main
commit="$(g -C "$other" rev-parse --short HEAD)"

capture hx --check
assert_status "--check reports" 0 "$STATUS"
assert_contains "--check names the checkout" "$OUTPUT" "source     $work"
assert_contains "--check counts what would be pulled" "$OUTPUT" "origin/main, 1 commit(s) to pull"
assert_contains "--check names the commit the checkout has" "$OUTPUT" "checkout   $(g -C "$work" rev-parse --short HEAD) (0.2.0-dev)"
assert_contains "--check says when nothing is installed yet" "$OUTPUT" "installed  unknown: no install stamp under $prefix"
assert_contains "--check says an update is available" "$OUTPUT" "update     available: 1 commit(s) to pull"
assert_eq "--check changes nothing" "" "$(cat "$LOG")"
assert_eq "--check does not merge" "0.2.0-dev" "$(cat "$work/share/haseen/VERSION")"

capture hx --dry-run
assert_status "--dry-run reports a plan" 0 "$STATUS"
assert_contains "--dry-run prints the fast-forward" "$OUTPUT" "DRYRUN: git -C $work merge --ff-only --quiet origin/main"
assert_contains "--dry-run prints the install" "$OUTPUT" "DRYRUN: (cd $work && ./install.sh --yes --prefix $prefix)"
assert_contains "--dry-run prints the Hyprland reload" "$OUTPUT" "DRYRUN: hyprctl reload"
assert_contains "--dry-run prints the unit reload" "$OUTPUT" "DRYRUN: systemctl --user daemon-reload"
assert_not_contains "--dry-run reloads no units" "$(cat "$LOG")" "daemon-reload"
assert_not_contains "--dry-run installs nothing" "$OUTPUT" "install: --yes"
assert_eq "--dry-run leaves the checkout where it was" "0.2.0-dev" "$(cat "$work/share/haseen/VERSION")"

# --- the update ---------------------------------------------------------------
capture hx
assert_status "the update runs" 0 "$STATUS"
assert_contains "the checkout is fast-forwarded" "$OUTPUT" "pulling 1 commit(s) into $work"
assert_contains "the tree is installed through install.sh" "$OUTPUT" "install: --yes --prefix $prefix"
assert_contains "Hyprland is reloaded" "$(cat "$LOG")" "hyprctl reload"
assert_contains "the shell is restarted" "$(cat "$LOG")" "systemctl --user restart haseen-shell.service"
# install.sh rewrote the units: the manager reads them again first, or the
# restart runs the old haseen-shell.service (plan 142).
assert_eq "the units are read again, then the shell restarts" \
    "systemctl --user daemon-reload|systemctl --user restart haseen-shell.service" \
    "$(grep -E 'daemon-reload|restart haseen-shell' "$LOG" | paste -sd'|')"
assert_contains "the update says what it did" "$OUTPUT" "haseen-shell.service restarted"
assert_eq "the checkout is at the new commit" "$commit" "$(g -C "$work" rev-parse --short HEAD)"
assert_eq "and at the new version" "0.3.0-dev" "$(cat "$work/share/haseen/VERSION")"

# --- an installed commit is not installed again -------------------------------
mkdir -p "$prefix/share/haseen"
printf 'prefix=%s\ncommit=%s\nversion=0.3.0-dev\ndate=2026-10-26T00:00:00+03:00\n' "$prefix" "$commit" \
    >"$prefix/share/haseen/.installed"
: >"$LOG"
capture hx
assert_status "a current install exits cleanly" 0 "$STATUS"
assert_contains "it says the commit is already installed" "$OUTPUT" "haseen 0.3.0-dev ($commit) is already installed under $prefix"
assert_not_contains "and installs nothing" "$OUTPUT" "install: --yes"
assert_eq "and reloads nothing" "" "$(cat "$LOG")"

capture hx --check
assert_contains "--check calls it up to date" "$OUTPUT" "update     none: the installed tree is this commit"

capture hx --force
assert_status "--force reinstalls" 0 "$STATUS"
assert_contains "--force runs the installer again" "$OUTPUT" "install: --yes --prefix $prefix"
assert_contains "--force reloads too" "$(cat "$LOG")" "hyprctl reload"

: >"$LOG"
capture env SYSTEMCTL_NO_MANAGER=1 PATH="$REAL_PATH" HASEEN_INLINE=1 haseen update haseen --source "$work" --prefix "$prefix" --force
assert_status "a user manager that does not answer is not a failure" 0 "$STATUS"
assert_contains "it says the units wait for the next login" "$OUTPUT" "systemctl --user daemon-reload failed; the units are read again at the next login"
assert_contains "and goes on to the shell" "$(cat "$LOG")" "systemctl --user restart haseen-shell.service"

# A stopped shell is not restarted, but its unit and the others are read
# again all the same: its next start must run the new unit (plan 142).
: >"$LOG"
capture env SYSTEMCTL_SHELL_STOPPED=1 PATH="$REAL_PATH" HASEEN_INLINE=1 haseen update haseen --source "$work" --prefix "$prefix" --force
assert_status "an update with the shell stopped runs" 0 "$STATUS"
assert_contains "the units are read again with the shell stopped" "$(cat "$LOG")" "systemctl --user daemon-reload"
assert_not_contains "a stopped shell is not restarted" "$(cat "$LOG")" "restart haseen-shell.service"
assert_contains "and the update says it is not running" "$OUTPUT" "haseen-shell.service is not running"

# --- the flags ----------------------------------------------------------------
: >"$LOG"
capture hx --force --tree-only --no-reload
assert_status "--tree-only --no-reload runs" 0 "$STATUS"
assert_contains "--tree-only is passed on" "$OUTPUT" "install: --yes --prefix $prefix --tree-only"
assert_eq "--no-reload touches neither Hyprland nor the shell" "" "$(cat "$LOG")"
assert_contains "--no-reload says so" "$OUTPUT" "not reloading (--no-reload)"

# --- what it refuses ----------------------------------------------------------
printf 'x\n' >>"$work/install.sh"
capture hx --force
assert_status "a dirty checkout is refused" 1 "$STATUS"
assert_contains "and says why" "$OUTPUT" "the checkout has uncommitted changes"
g -C "$work" checkout -q -- install.sh

capture env PATH="$REAL_PATH" HASEEN_INLINE=1 haseen update haseen --source "$SANDBOX" --prefix "$prefix"
assert_status "a directory that is not a checkout is refused" 1 "$STATUS"
assert_contains "and names what is missing" "$OUTPUT" "not a haseen checkout: $SANDBOX"

capture env -u HASEEN_SOURCE PATH="$REAL_PATH" HASEEN_INLINE=1 haseen update haseen --prefix "$prefix"
assert_status "no source is refused" 1 "$STATUS"
assert_contains "and says where to point it" "$OUTPUT" "no haseen checkout to install from"

# --- the stamp itself ---------------------------------------------------------
capture env PATH="$REAL_PATH" bash -c '
    source "$1/lib/install-stamp.sh"
    write_root_file() { mkdir -p "$(dirname "$1")"; cat >"$1"; }
    run_root() { "$@"; }
    install_stamp_write "$2/stamp-prefix" abc123 0.3.0-dev
    printf "%s|%s|%s\n" "$(install_stamp_get "$2/stamp-prefix" commit)" \
        "$(install_stamp_get "$2/stamp-prefix" version)" \
        "$(install_stamp_get "$2/stamp-prefix" prefix)"
    install_stamp_get "$2/no-stamp" commit || echo "none"
' bash "$HASEEN_PATH" "$SANDBOX"
assert_status "the stamp round-trips" 0 "$STATUS"
assert_contains "it keeps the commit, version and prefix" "$OUTPUT" "abc123|0.3.0-dev|$SANDBOX/stamp-prefix"
assert_contains "a missing stamp answers nothing" "$OUTPUT" "none"
