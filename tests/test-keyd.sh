# shellcheck shell=bash
# haseen:covers bin/haseen-setup-keyd share/haseen/default/keyd/** share/haseen/layers/base/lib.sh
# haseen:covers share/haseen/lib/{packages,terminal}.sh
# haseen:covers share/haseen/migrations/1795510882-keyd-capslock-layer.sh
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# `haseen setup keyd` (plan 056): the dry-run plan, the backup of a differing
# /etc/keyd/default.conf, nothing to do when it already matches, status, off.
sandbox keyd
export HASEEN_INLINE=1
SHIPPED="$HASEEN_PATH/default/keyd/default.conf"

# sysroot NAME — an empty machine: no keyd, no config, no enabled units.
sysroot() {
    local root="$SANDBOX/$1"
    mkdir -p "$root/var/lib/pacman/local" "$root/etc/systemd/system"
    printf '%s\n' "$root"
}
install_keyd() { mkdir -p "$1/var/lib/pacman/local/keyd-2.6.0-5"; }
enable_keyd() {
    mkdir -p "$1/etc/systemd/system/multi-user.target.wants"
    touch "$1/etc/systemd/system/multi-user.target.wants/keyd.service"
}

# recorder — sudo that logs its argv and runs nothing; tee drains stdin.
recorder() {
    : >"$SANDBOX/sudo.log"
    stub sudo "printf '%s\n' \"\$*\" >>'$SANDBOX/sudo.log'; case \"\$1\" in tee) cat >/dev/null ;; esac; exit 0"
}

# --- the shipped mapping -----------------------------------------------------
shipped="$(grep -v '^#' "$SHIPPED")"
assert_contains "tap is Escape, hold is the hyper layer" "$shipped" "capslock = overload(hyper, esc)"
# In [main] a + left-hand side is a chord (both keys within keyd's 50 ms
# chord_timeout); RightAlt held is keyd's altgr layer (plan 190).
assert_contains "CapsLock pressed under RightAlt is the real CapsLock" "$shipped" $'[altgr]\ncapslock = capslock'
assert_not_contains "no RightAlt + CapsLock chord" "$shipped" "rightalt+capslock"
assert_contains "hyper is Ctrl+Meta+Alt+Shift" "$shipped" "[hyper:C-M-A-S]"

# --- dry-run on an empty machine ----------------------------------------------
root="$(sysroot empty)"
export HASEEN_SYSROOT="$root"
capture haseen setup keyd on --dry-run
assert_status "dry-run succeeds" 0 "$STATUS"
assert_dry_pure "dry-run" "$OUTPUT"
assert_contains "it installs keyd from the repos" "$OUTPUT" "DRYRUN: sudo pacman -S --needed keyd"
assert_contains "it writes the config" "$OUTPUT" "DRYRUN: write /etc/keyd/default.conf (mode 0644):"
assert_contains "the plan shows the mapping" "$OUTPUT" "| capslock = overload(hyper, esc)"
assert_contains "it enables the service" "$OUTPUT" "DRYRUN: sudo systemctl enable --now keyd.service"
assert_contains "it reloads keyd" "$OUTPUT" "DRYRUN: sudo keyd reload"
assert_not_contains "nothing to back up" "$OUTPUT" "haseen-bak"

# --- a differing config is backed up before it is replaced --------------------
root="$(sysroot differs)"
install_keyd "$root"
mkdir -p "$root/etc/keyd"
printf '[ids]\n*\n[main]\ncapslock = esc\n' >"$root/etc/keyd/default.conf"
export HASEEN_SYSROOT="$root"
recorder
capture haseen setup keyd on --yes
assert_status "on succeeds" 0 "$STATUS"
log="$(cat "$SANDBOX/sudo.log")"
assert_contains "the old config is copied aside" "$log" "cp -a /etc/keyd/default.conf /etc/keyd/default.conf.haseen-bak-"
assert_contains "the user is told where" "$OUTPUT" "backed up to /etc/keyd/default.conf.haseen-bak-"
assert_contains "the new config is written" "$log" "tee /etc/keyd/default.conf"
assert_eq "the backup comes before the write" "cp" "$(grep -m1 -oE '^(cp|tee)' <<<"$log")"
assert_not_contains "keyd is installed already: no pacman" "$log" "pacman"
assert_contains "the service is enabled" "$log" "systemctl enable --now keyd.service"
assert_contains "keyd reloads the new config" "$log" "keyd reload"

capture haseen setup keyd status
assert_contains "status: installed" "$OUTPUT" "installed: yes"
assert_contains "status: not enabled in the fixture" "$OUTPUT" "enabled:   no"
assert_contains "status: config differs" "$OUTPUT" "config:    differs"

# --- equal config, installed and enabled: nothing to do -----------------------
root="$(sysroot same)"
install_keyd "$root"
enable_keyd "$root"
mkdir -p "$root/etc/keyd"
cp "$SHIPPED" "$root/etc/keyd/default.conf"
export HASEEN_SYSROOT="$root"
recorder
capture haseen setup keyd on --yes
assert_status "a second on succeeds" 0 "$STATUS"
assert_contains "it says so" "$OUTPUT" "already on"
assert_eq "and runs nothing privileged" "" "$(cat "$SANDBOX/sudo.log")"

capture haseen setup keyd
assert_status "status is the default verb" 0 "$STATUS"
assert_contains "status: enabled" "$OUTPUT" "enabled:   yes"
assert_contains "status: config matches" "$OUTPUT" "config:    matches"

# --- off -------------------------------------------------------------------------
capture haseen setup keyd off --yes
assert_status "off succeeds" 0 "$STATUS"
assert_contains "off disables the service" "$(cat "$SANDBOX/sudo.log")" "systemctl disable --now keyd.service"
assert_not_contains "off leaves the config" "$(cat "$SANDBOX/sudo.log")" "rm"

root="$(sysroot off)"
export HASEEN_SYSROOT="$root"
recorder
capture haseen setup keyd off --yes
assert_contains "off on a machine without keyd is a no-op" "$OUTPUT" "already off"
assert_eq "and runs nothing privileged" "" "$(cat "$SANDBOX/sudo.log")"

# --- the migration from the RightAlt + CapsLock chord (plan 190) ---------------
mig="$HASEEN_PATH/migrations/1795510882-keyd-capslock-layer.sh"
runmig() { env HASEEN_PATH="$HASEEN_PATH" bash -Eeuo pipefail -c 'source "$1"' bash "$mig"; }
# The only file `haseen setup keyd on` wrote before plan 190 (90a8afd2).
old_conf='# Written by `haseen setup keyd` (/etc/keyd/default.conf).
# Hold CapsLock = hyper (Ctrl+Meta+Alt+Shift, i.e. SUPER + SHIFT + ALT + CTRL
# in Hyprland binds); tap CapsLock = Escape; RightAlt+CapsLock = real CapsLock.
[ids]
*

[main]
capslock = overload(hyper, esc)
rightalt+capslock = capslock

[hyper:C-M-A-S]'
root="$(sysroot mig-old)"
mkdir -p "$root/etc/keyd"
printf '%s\n' "$old_conf" >"$root/etc/keyd/default.conf"
export HASEEN_SYSROOT="$root"
recorder
capture runmig
assert_status "the migration succeeds on the old file" 0 "$STATUS"
assert_contains "it replaces the file haseen wrote" "$(cat "$SANDBOX/sudo.log")" "tee /etc/keyd/default.conf"
assert_contains "and says why" "$OUTPUT" "50 ms chord"
capture env DRY_RUN=true HASEEN_PATH="$HASEEN_PATH" bash -Eeuo pipefail -c 'source "$1"' bash "$mig"
assert_contains "its dry run shows the [altgr] line" "$OUTPUT" "    | [altgr]"
for case in edited new missing; do
    root="$(sysroot "mig-$case")"
    mkdir -p "$root/etc/keyd"
    case $case in
    edited) printf '%s\n# mine\n' "$old_conf" >"$root/etc/keyd/default.conf" ;;
    new) cp "$SHIPPED" "$root/etc/keyd/default.conf" ;;
    esac
    export HASEEN_SYSROOT="$root"
    recorder
    capture runmig
    assert_status "the migration succeeds on a $case file" 0 "$STATUS"
    assert_eq "and leaves a $case file alone" "" "$(cat "$SANDBOX/sudo.log")"
done

capture haseen setup keyd sideways
assert_status "an unknown verb is a usage error" 2 "$STATUS"
unset HASEEN_SYSROOT HASEEN_INLINE
