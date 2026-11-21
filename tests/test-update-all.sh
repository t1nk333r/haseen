# shellcheck shell=bash
# haseen:covers bin/haseen-update bin/haseen-update-notify share/haseen/lib/self-update.sh
# haseen:covers share/haseen/systemd/user/haseen-update-notify.*
# haseen:covers share/haseen/migrations/1795289723-update-notify-timer.sh
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# `haseen update` in one step, and the notice that updates are waiting
# (plan 182). A real bare repository stands in for GitHub, so the clone,
# fetch and commit comparisons are the real thing; root, pacman's helpers,
# Flatpak, Hyprland, systemd and the notification daemon are stubs that
# record what they were asked.

sandbox update-all
LOG="$SANDBOX/calls.log"
: >"$LOG"
export LOG
# A fresh package check every time: the cache would answer one run with the
# last one's packages.
export HASEEN_UPDATES_CACHE_TTL=0
tools="$SANDBOX/tools-stubs"
mkdir -p "$tools"
# mk NAME BODY — a stub that records its arguments, then runs BODY.
mk() {
    printf '#!/bin/sh\necho "%s $*" >>"$LOG"\n%s\n' "$1" "${2:-exit 0}" >"$tools/$1"
    chmod 755 "$tools/$1"
}
mk sudo "[ \"\$1\" = -h ] && echo 'usage: sudo [-ABbEHkNnPS] [-C num]'; [ \"\$1\" = true ] && [ -n \"\${SUDO_FAIL:-}\" ] && exit 1; exit 0"
# The AUR build and Flatpak take a moment, so a sudo kept warm every second
# would show up in the log while they run.
mk paru 'case "$*" in *-Qua*) [ -n "${PARU_QUA:-}" ] || exit 1; printf "%s\n" "$PARU_QUA" ;; *-Sua*) sleep "${PARU_SLEEP:-0}" ;; esac; exit 0'
mk flatpak 'sleep "${FLATPAK_SLEEP:-0}"'
mk hyprctl
mk systemctl '[ "$2" = show-environment ] && [ -n "${SYSTEMCTL_NO_MANAGER:-}" ] && exit 1; exit 0'
# A transient unit: run what follows --.
mk systemd-run 'while [ "$#" -gt 0 ] && [ "$1" != -- ]; do shift; done; shift; exec "$@"'
mk notify-send 'printf "%s" "${NOTIFY_ANSWER:-}"'
mk busctl '[ -z "${BUSCTL_FAIL:-}" ]'
printf '#!/bin/sh\n[ -n "${CHECKUPDATES_OUT:-}" ] || exit 2\nprintf "%%s\\n" "$CHECKUPDATES_OUT"\n' >"$tools/checkupdates"
chmod 755 "$tools/checkupdates"
REAL_PATH="$tools:$REPO/bin:/usr/bin:/bin"
g() { env PATH="$REAL_PATH" git "$@"; }
calls() { cat "$LOG"; }

# seed → a bare origin (GitHub) and a second clone that pushes to it. The
# seed's install.sh writes the stamp a real install would.
seed="$SANDBOX/seed" origin="$SANDBOX/origin.git" other="$SANDBOX/other"
prefix="$SANDBOX/prefix" data="$SANDBOX/data"
copy="$data/haseen/checkout"
g init -q -b main "$seed"
g -C "$seed" config user.email t@example.invalid
g -C "$seed" config user.name Test
mkdir -p "$seed/share/haseen"
printf '0.3.0-dev\n' >"$seed/share/haseen/VERSION"
cat >"$seed/install.sh" <<'SH'
#!/usr/bin/env bash
echo "install: $*"
echo "install: $*" >>"$LOG"
p=""
while (($#)); do [[ $1 == --prefix ]] && p=$2; shift; done
mkdir -p "$p/share/haseen"
printf 'prefix=%s\ncommit=%s\nversion=0.3.0-dev\ndate=%s\n' "$p" "$(git rev-parse --short HEAD)" "$(date -Iseconds)" \
    >"$p/share/haseen/.installed"
SH
chmod 755 "$seed/install.sh"
g -C "$seed" add -A
g -C "$seed" commit -qm one
g clone -q --bare "$seed" "$origin"
g clone -q "$origin" "$other"
g -C "$other" config user.email t@example.invalid
g -C "$other" config user.name Test
one="$(g -C "$origin" rev-parse --short main)"
mkdir -p "$prefix/share/haseen"
printf 'prefix=%s\ncommit=%s\nversion=0.3.0-dev\ndate=2000-01-01T00:00:00+00:00\n' "$prefix" "$one" \
    >"$prefix/share/haseen/.installed"
# push SUBJECT — a new commit on GitHub's main.
push() {
    printf '%s\n' "$1" >"$other/NOTES"
    g -C "$other" add NOTES
    g -C "$other" commit -qm "$1"
    g -C "$other" push -q origin main
}
push "weather: a smoother curve"
two="$(g -C "$origin" rev-parse --short main)"

# Every migration as done, so `haseen migrate` in the update finds none.
env PATH="$REAL_PATH" haseen migrate --seal >/dev/null

# hu ARGS... — `haseen update` as the notification or a terminal starts it.
hu() {
    env PATH="$REAL_PATH" HASEEN_INLINE=1 XDG_DATA_HOME="$data" HASEEN_UPDATE_REMOTE="$origin" \
        HASEEN_UPDATE_PREFIX="$prefix" CHECKUPDATES_OUT="${CHECKUPDATES_OUT:-}" haseen update "$@"
}

# --- the plan -------------------------------------------------------------------
capture hu --dry-run
assert_status "a dry run plans the whole update" 0 "$STATUS"
assert_contains "it opens on the step's name" "$OUTPUT" "[*] haseen update: all"
assert_contains "it says haseen's copy is cloned on the first run" "$OUTPUT" "haseen     cloned from $origin on the first run"
assert_contains "it asks for sudo once, kept warm" "$OUTPUT" "DRYRUN: sudo true (kept warm while the update runs)"
assert_contains "it plans the clone" "$OUTPUT" "DRYRUN: git clone --quiet --filter=blob:none --branch main $origin $copy"
assert_contains "then the packages, in the next stage" "$OUTPUT" $'[*] official repositories\nDRYRUN: sudo '
assert_contains "the migrations" "$OUTPUT" "[*] haseen migrations"
assert_contains "the AUR, cold" "$OUTPUT" "DRYRUN: paru --sudo sudo --nosudoloop -Sua"
assert_eq "a dry run calls nothing" "" "$(calls)"
assert_eq "and clones nothing" "" "$(ls -A "$data" 2>/dev/null)"

# --- the update ------------------------------------------------------------------
CHECKUPDATES_OUT="mesa 1-1 -> 1-2" HASEEN_SUDO_WARM_INTERVAL=1 FLATPAK_SLEEP=2 PARU_SLEEP=3 capture hu --yes
assert_status "the update runs" 0 "$STATUS"
# sudo is kept warm through the hand-over to the new tree, and stops before
# the AUR: a PKGBUILD never runs beside a refreshed timestamp (plan 103).
assert_contains "sudo is kept warm while the update runs" "$(sed -n '/^install:/,/^paru .*-Sua/p' "$LOG")" "sudo -n true"
assert_eq "and no longer once the AUR builds start" "" "$(sed -n '/^paru .*-Sua/,$p' "$LOG" | grep 'sudo -n true' || true)"
assert_contains "it shows haseen's new commits" "$OUTPUT" "haseen     1 new commit(s), $one to $two:"
assert_contains "by their subjects" "$OUTPUT" "               weather: a smoother curve"
assert_contains "and the packages" "$OUTPUT" "packages   1 from the repositories, 0 from the AUR"
assert_contains "haseen is installed from its copy, tree only" "$OUTPUT" "install: --yes --prefix $prefix --tree-only"
assert_eq "the copy is at main" "$two" "$(g -C "$copy" rev-parse --short HEAD)"
# The order: one authorization, haseen, the repositories, Flatpak, the AUR
# with the timestamp dropped, then the reload.
# pacman's line carries Omarchy's guard variable and a systemd scope where
# the machine running the tests has them (plan 103); only its place counts.
order="$(sed -E 's/^sudo .*pacman -Syu.*/sudo pacman -Syu/' "$LOG" |
    grep -oE '^(sudo true|install:|sudo pacman -Syu|flatpak update --user|sudo -k|paru .*-Sua|hyprctl reload|systemctl --user restart haseen-shell.service)' |
    uniq | paste -sd'|')"
assert_eq "the steps run in order" \
    "sudo true|install:|sudo pacman -Syu|flatpak update --user|sudo -k|paru --sudo sudo --nosudoloop -Sua|sudo -k|hyprctl reload|systemctl --user restart haseen-shell.service" \
    "$order"
assert_contains "the units are read again before the restart" "$(calls)" "systemctl --user daemon-reload"
assert_contains "it ends saying so" "$OUTPUT" "[*] haseen update: done"

: >"$LOG"
capture hu --yes
assert_status "an update with nothing new from haseen runs" 0 "$STATUS"
assert_contains "it says haseen is current" "$OUTPUT" "haseen     up to date ($two)"
assert_contains "it says the packages are counted" "$OUTPUT" "packages   0 from the repositories, 0 from the AUR"
assert_not_contains "it installs no haseen" "$(calls)" "install:"
assert_contains "the packages are still upgraded" "$(calls)" "pacman -Syu"
assert_not_contains "and an unchanged tree is not reloaded" "$(calls)" "hyprctl reload"

# --- sudo refused -----------------------------------------------------------------
: >"$LOG"
capture env SUDO_FAIL=1 PATH="$REAL_PATH" HASEEN_INLINE=1 XDG_DATA_HOME="$data" HASEEN_UPDATE_REMOTE="$origin" \
    HASEEN_UPDATE_PREFIX="$prefix" haseen update --yes
assert_status "a refused sudo stops the update" 1 "$STATUS"
assert_contains "it says nothing was changed" "$OUTPUT" "sudo did not authorize the update; nothing was changed"
assert_not_contains "and nothing is installed" "$(calls)" "install:"
assert_not_contains "or upgraded" "$(calls)" "pacman -Syu"

# --- the rest runs the installed router -----------------------------------------
# Started from a checkout, the second half is the prefix's haseen, finding its
# own tree, not the checkout's.
mkdir -p "$prefix/bin"
printf '#!/bin/sh\necho "prefix-router $* stage=$HASEEN_UPDATE_STAGE path=${HASEEN_PATH:-unset}" >>"$LOG"\n' >"$prefix/bin/haseen"
chmod 755 "$prefix/bin/haseen"
: >"$LOG"
capture hu --yes
assert_status "the hand-over to the prefix runs" 0 "$STATUS"
assert_contains "the rest is the prefix's router, in the second stage, on its own tree" "$(calls)" \
    "prefix-router update all --yes stage=rest path=unset"
assert_not_contains "and the checkout's code does not upgrade" "$(calls)" "pacman -Syu"
rm -rf "$prefix/bin"

# --- the question ---------------------------------------------------------------
push "bar: a new widget"
: >"$LOG"
capture env PATH="$REAL_PATH" XDG_DATA_HOME="$data" HASEEN_UPDATE_REMOTE="$origin" HASEEN_UPDATE_PREFIX="$prefix" \
    script -qec "haseen update" /dev/null <<<"n"
assert_contains "on a terminal it asks first" "$OUTPUT" "Update now? [Y/n]"
assert_contains "no is respected" "$OUTPUT" "nothing was changed"
assert_eq "and nothing is run (the preview only counted)" "paru -Qua" "$(calls)"

# --- haseen cannot be reached ---------------------------------------------------
: >"$LOG"
capture env PATH="$REAL_PATH" HASEEN_INLINE=1 XDG_DATA_HOME="$SANDBOX/offline" HASEEN_UPDATE_REMOTE="$SANDBOX/missing.git" \
    HASEEN_UPDATE_PREFIX="$prefix" haseen update --yes
assert_status "an unreachable haseen fails the update" 128 "$STATUS"
assert_contains "the preview says so" "$OUTPUT" "haseen     could not fetch $SANDBOX/missing.git"
assert_contains "the packages are upgraded all the same" "$(calls)" "pacman -Syu"
assert_contains "and the end says what is left" "$OUTPUT" "the packages are updated, haseen is not"

# --- the notice -----------------------------------------------------------------
state="$HOME/.local/state/haseen/update-notified"
hn() {
    env PATH="$REAL_PATH" XDG_DATA_HOME="$data" HASEEN_UPDATE_REMOTE="$origin" HASEEN_UPDATE_PREFIX="$prefix" \
        CHECKUPDATES_OUT="${CHECKUPDATES_OUT:-}" haseen update notify "$@"
}
three="$(g -C "$origin" rev-parse --short main)"

: >"$LOG"
capture hn --dry-run
assert_status "a dry notice runs" 0 "$STATUS"
assert_contains "it says what it would send" "$OUTPUT" "DRYRUN: notify: Updates are ready: haseen: 1 new change"
assert_eq "and sends nothing" "" "$(grep notify-send "$LOG" || true)"
assert_eq "and remembers nothing" "" "$(cat "$state" 2>/dev/null)"

CHECKUPDATES_OUT="mesa 1-1 -> 1-2" capture hn
assert_status "the notice runs" 0 "$STATUS"
assert_contains "one notification, with an Update button" "$(calls)" \
    "notify-send -a haseen --wait -A update=Update Updates are ready haseen: 1 new change · 1 package to upgrade"
assert_eq "what it was about is remembered" "haseen $three|mesa 1-1 -> 1-2" "$(paste -sd'|' "$state")"

: >"$LOG"
CHECKUPDATES_OUT="mesa 1-1 -> 1-2" capture hn
assert_eq "the same updates are not notified again" "" "$(grep notify-send "$LOG" || true)"

CHECKUPDATES_OUT=$'mesa 1-1 -> 1-2\nlinux 6.1-1 -> 6.2-1' capture hn
assert_contains "a new package is" "$(calls)" "haseen: 1 new change · 2 packages to upgrade"

# Installed up to main, with nothing pending: the list is cleared, so the
# next update is news again.
printf 'prefix=%s\ncommit=%s\nversion=0.3.0-dev\ndate=2000-01-01T00:00:00+00:00\n' "$prefix" "$three" \
    >"$prefix/share/haseen/.installed"
: >"$LOG"
capture hn
assert_status "nothing pending is quiet" 0 "$STATUS"
assert_eq "no notification" "" "$(grep notify-send "$LOG" || true)"
assert_eq "and the list is gone" "no" "$([[ -e $state ]] && echo yes || echo no)"

CHECKUPDATES_OUT="mesa 1-1 -> 1-2" capture env BUSCTL_FAIL=1 PATH="$REAL_PATH" XDG_DATA_HOME="$data" \
    HASEEN_UPDATE_REMOTE="$origin" HASEEN_UPDATE_PREFIX="$prefix" CHECKUPDATES_OUT="mesa 1-1 -> 1-2" haseen update notify
assert_contains "without a notification daemon it says so on stderr" "$OUTPUT" "Updates are ready: 1 package to upgrade. Run: haseen update"
assert_eq "and remembers nothing, for the next run in a session" "no" "$([[ -e $state ]] && echo yes || echo no)"

# The Update button runs the update (inline here; a floating terminal from
# the unit).
: >"$LOG"
capture env NOTIFY_ANSWER=update HASEEN_INLINE=1 PATH="$REAL_PATH" XDG_DATA_HOME="$data" HASEEN_UPDATE_REMOTE="$origin" \
    HASEEN_UPDATE_PREFIX="$prefix" CHECKUPDATES_OUT="mesa 1-1 -> 1-2" haseen update notify
assert_status "Update runs the update" 0 "$STATUS"
assert_contains "in a unit of its own, not the notice's idle one" "$(calls)" \
    "systemd-run --user --quiet --collect --slice=app-graphical.slice -- $REPO/bin/haseen update"
assert_contains "it reaches pacman" "$(calls)" "pacman -Syu"
assert_contains "and finishes" "$OUTPUT" "[*] haseen update: done"

# --- the timer, and its migration ----------------------------------------------
units="$HASEEN_PATH/systemd/user"
assert_contains "the timer looks every four hours" "$(cat "$units/haseen-update-notify.timer")" "OnUnitActiveSec=4h"
assert_contains "the timer starts the notice" "$(cat "$units/haseen-update-notify.timer")" "Unit=haseen-update-notify.service"
assert_contains "the notice runs haseen update notify" "$(cat "$units/haseen-update-notify.service")" \
    "ExecStart=/usr/bin/env haseen update notify"
assert_contains "the shell layer enables it" "$(cat "$HASEEN_PATH/layers/shell/layer.sh")" \
    'run systemctl --user enable "$UPDATE_NOTIFY_TIMER"'

mig="$HASEEN_PATH/migrations/1795289723-update-notify-timer.sh"
wants="$HOME/.config/systemd/user"
runmig() { env PATH="$REAL_PATH" HASEEN_PATH="$HASEEN_PATH" bash -Eeuo pipefail -c 'source "$1"' bash "$mig"; }
: >"$LOG"
capture runmig
assert_status "without haseen's shell the migration has nothing to do" 0 "$STATUS"
assert_eq "and enables nothing" "" "$(calls)"
mkdir -p "$wants/graphical-session.target.wants"
ln -s /dev/null "$wants/graphical-session.target.wants/haseen-shell.service"
export SYSTEMCTL_NO_MANAGER=1
capture runmig
unset SYSTEMCTL_NO_MANAGER
assert_status "without a user manager the migration does not fail" 0 "$STATUS"
assert_contains "it says how to turn the notice on" "$OUTPUT" "to turn the update notice on: systemctl --user enable --now haseen-update-notify.timer"
assert_not_contains "and enables nothing" "$(calls)" "enable"
capture runmig
assert_status "with haseen's shell it runs" 0 "$STATUS"
assert_contains "it enables and starts the timer" "$(calls)" "systemctl --user enable --now haseen-update-notify.timer"
assert_eq "and remembers that haseen turned it on" "yes" "$([[ -e $HOME/.local/state/haseen/update-notify-enabled ]] && echo yes || echo no)"
mkdir -p "$wants/timers.target.wants"
ln -s /dev/null "$wants/timers.target.wants/haseen-update-notify.timer"
: >"$LOG"
capture runmig
assert_eq "an enabled timer is left as it is" "" "$(calls)"
