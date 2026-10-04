# shellcheck shell=bash
# DMS layer: package plan, conflict drop-in, `haseen shell use`, IPC translation.

DMS_LAYER="$REPO/share/haseen/layers/dms"
TRANSLATE="$DMS_LAYER/ipc-translate"
# PREFIX resolves from HASEEN_PATH (= $REPO/share/haseen in tests).
DROPIN="$REPO/lib/systemd/user/dms.service.d/haseen.conf"

# mkroot NAME LAYER... — a CachyOS sysroot (copied fixture) with LAYERs marked
# applied; sets ROOT.
mkroot() {
    ROOT="$SANDBOX/root-$1"
    shift
    cp -a "$FIXTURES/cachyos-grub-plain" "$ROOT"
    mkdir -p "$ROOT/var/lib/haseen/layers"
    local l
    for l in "$@"; do printf 'version=test\n' >"$ROOT/var/lib/haseen/layers/$l"; done
}

# with_dms_installed — the package and its unit as pacman leaves them.
with_dms_installed() {
    mkdir -p "$ROOT/var/lib/pacman/local/dms-shell-1.6.0-2" "$ROOT/usr/lib/systemd/user"
    cp "$REFDMS_UNIT" "$ROOT/usr/lib/systemd/user/dms.service"
}

with_dropin() {
    mkdir -p "$(dirname "$ROOT$DROPIN")"
    cp "$DMS_LAYER/files/haseen.conf" "$ROOT$DROPIN"
}

# plan_steps OUTPUT — the planned systemctl/rm/write steps, in order.
plan_steps() { grep -E '^DRYRUN: (sudo )?(systemctl|rm|rmdir|write)' <<<"$1" || true; }

# A layer tree holding the real dms layer plus inert stand-ins for the layers
# it requires, so these tests do not depend on the desktop/shell slices.
sandbox dms-layers
LAYERS="$SANDBOX/layers"
mkdir -p "$LAYERS"
ln -s "$DMS_LAYER" "$LAYERS/dms"
for n in base desktop shell; do
    mkdir -p "$LAYERS/$n"
    printf 'LAYER_SUMMARY=stand-in\nLAYER_REQUIRES=()\nLAYER_CONFLICTS=()\nLAYER_DISTROS=(cachyos)\nlayer_status() { return 0; }\nlayer_apply() { run_root touch /etc/stand-in-%s; }\n' "$n" >"$LAYERS/$n/layer.sh"
done
export HASEEN_LAYERS_DIR="$LAYERS"
REFDMS_UNIT="$SANDBOX/dms.service"
# Upstream unit (DMS assets/systemd/dms.service), inlined so tests stay hermetic.
cat >"$REFDMS_UNIT" <<'EOF'
[Unit]
Description=Dank Material Shell (DMS)
PartOf=graphical-session.target
After=graphical-session.target
Requisite=graphical-session.target

[Service]
Type=dbus
BusName=org.freedesktop.Notifications
ExecStart=/usr/bin/dms run --session
EOF

# --- layer: fresh install plan ---------------------------------------------
sandbox dms-apply
mkroot fresh base desktop
capture env HASEEN_SYSROOT="$ROOT" haseen layer apply dms --dry-run
assert_status "dms apply dry-run exit" 0 "$STATUS"
assert_dry_pure "dms apply" "$OUTPUT"
assert_contains "pacman assumes the virtual compositor" "$OUTPUT" \
    "DRYRUN: sudo pacman -S --needed --assume-installed dms-shell-compositor=1 dms-shell"$'\n'
assert_contains "drop-in written under PREFIX" "$OUTPUT" "DRYRUN: write $DROPIN (mode 0644):"
assert_contains "drop-in conflicts with the haseen shell" "$OUTPUT" "    | Conflicts=haseen-shell.service"
assert_contains "drop-in orders the stop before the start" "$OUTPUT" "    | After=haseen-shell.service"
assert_not_contains "DMS is not enabled by default" "$OUTPUT" "systemctl"
assert_not_contains "no dankinstall" "$OUTPUT" "dankinstall"
assert_not_contains "no DMS config deployer" "$OUTPUT" "dms setup"
assert_not_contains "desktop already applied is skipped" "$OUTPUT" "stand-in-desktop"
assert_contains "marker written" "$OUTPUT" "write /var/lib/haseen/layers/dms"
assert_contains "switch hint" "$OUTPUT" "haseen shell use dms"

capture env HASEEN_SYSROOT="$ROOT" haseen layer apply dms --dry-run --yes
assert_contains "--yes is non-interactive pacman" "$OUTPUT" \
    "pacman -S --needed --noconfirm --assume-installed dms-shell-compositor=1 dms-shell"
capture env HASEEN_SYSROOT="$ROOT" haseen layer apply dms --dry-run -- --bogus
assert_status "dms layer rejects arguments" 1 "$STATUS"

capture env HASEEN_SYSROOT="$ROOT" haseen layer status dms
assert_status "status: not applied" 1 "$STATUS"
assert_contains "status names missing package" "$OUTPUT" "missing: dms-shell package"

# --- layer: re-apply converges ---------------------------------------------
mkroot converged base desktop dms
with_dms_installed
with_dropin
capture env HASEEN_SYSROOT="$ROOT" haseen layer apply dms --dry-run
assert_status "re-apply exit" 0 "$STATUS"
assert_not_contains "installed package not reinstalled" "$OUTPUT" "DRYRUN: sudo pacman"
assert_not_contains "identical drop-in not rewritten" "$OUTPUT" "write $DROPIN"
assert_contains "drop-in reported current" "$OUTPUT" "conflict drop-in up to date"
capture env HASEEN_SYSROOT="$ROOT" haseen layer status dms
assert_status "status: healthy" 0 "$STATUS"
assert_contains "status sees the package unit" "$OUTPUT" "ok: /usr/lib/systemd/user/dms.service"

mkdir -p "$ROOT/var/lib/pacman/local/dms-shell-git-1.6.0.r1-1"
rm -rf "$ROOT/var/lib/pacman/local/dms-shell-1.6.0-2"
capture env HASEEN_SYSROOT="$ROOT" haseen layer apply dms --dry-run
assert_not_contains "dms-shell-git counts as installed" "$OUTPUT" "DRYRUN: sudo pacman"

printf '[Unit]\nConflicts=haseen-shell.service\n' >"$ROOT$DROPIN"
capture env HASEEN_SYSROOT="$ROOT" haseen layer status dms
assert_status "status: edited drop-in is degraded" 2 "$STATUS"
capture env HASEEN_SYSROOT="$ROOT" haseen layer apply dms --dry-run
assert_contains "edited drop-in restored" "$OUTPUT" "DRYRUN: write $DROPIN (mode 0644):"

# --- shell use: refusals ---------------------------------------------------
sandbox dms-use-refuse
mkroot shell-only base desktop shell
capture env HASEEN_SYSROOT="$ROOT" haseen shell use dms --dry-run
assert_status "use dms without the layer refused" 1 "$STATUS"
assert_contains "refusal names the fix" "$OUTPUT" "haseen layer apply dms"
assert_not_contains "refusal plans nothing" "$OUTPUT" "DRYRUN"
capture env HASEEN_SYSROOT="$ROOT" haseen shell use dms --yes
assert_status "use dms without the layer refused (live)" 1 "$STATUS"
assert_dry_pure "refused live switch" "$OUTPUT"
assert_eq "refusal writes no state" "absent" "$([[ -e $HOME/.local/state/haseen/active-shell ]] && echo present || echo absent)"

mkroot dms-only base desktop dms
capture env HASEEN_SYSROOT="$ROOT" haseen shell use haseen --dry-run
assert_status "use haseen without the shell layer refused" 1 "$STATUS"
assert_contains "refusal names the shell layer" "$OUTPUT" "haseen layer apply shell"
capture env HASEEN_SYSROOT="$ROOT" haseen shell use kde --dry-run
assert_status "unknown shell is a usage error" 2 "$STATUS"
capture env HASEEN_SYSROOT="$ROOT" haseen shell use --dry-run
assert_status "missing shell is a usage error" 2 "$STATUS"

# --- shell use: switch sequence, both directions ---------------------------
sandbox dms-use
mkroot both base desktop shell dms
STATE="$HOME/.local/state/haseen/active-shell"
capture env HASEEN_SYSROOT="$ROOT" haseen shell use dms --dry-run
assert_status "use dms dry-run exit" 0 "$STATUS"
assert_dry_pure "use dms" "$OUTPUT"
assert_eq "use dms plan" "DRYRUN: systemctl --user daemon-reload
DRYRUN: systemctl --user disable --now haseen-shell.service
DRYRUN: systemctl --user enable dms.service
DRYRUN: systemctl --user start dms.service
DRYRUN: write $STATE:" "$(plan_steps "$OUTPUT")"
assert_contains "state content planned" "$OUTPUT" "write $STATE:"$'\n'"    | dms"
assert_contains "warns DMS takes over services" "$OUTPUT" "DMS will claim notifications, the polkit agent and the lock screen"

capture env HASEEN_SYSROOT="$ROOT" haseen shell use haseen --dry-run
assert_dry_pure "use haseen" "$OUTPUT"
assert_eq "use haseen plan" "DRYRUN: systemctl --user daemon-reload
DRYRUN: systemctl --user disable --now dms.service
DRYRUN: systemctl --user enable haseen-shell.service
DRYRUN: systemctl --user start haseen-shell.service
DRYRUN: write $STATE:" "$(plan_steps "$OUTPUT")"
assert_not_contains "no DMS notice when leaving DMS" "$OUTPUT" "DMS will claim"

# Live run against a recording systemctl: the state file is what `haseen
# shell ipc` reads, so it must really be written.
LOG="$SANDBOX/systemctl.log"
stub systemctl "echo \"\$*\" >>'$LOG'"
capture env HASEEN_SYSROOT="$ROOT" haseen shell use dms --yes
assert_status "use dms live exit" 0 "$STATUS"
assert_eq "use dms live calls" "--user daemon-reload
--user disable --now haseen-shell.service
--user enable dms.service
--user start dms.service" "$(<"$LOG")"
assert_eq "active-shell = dms" "dms" "$(<"$STATE")"
: >"$LOG"
capture env HASEEN_SYSROOT="$ROOT" haseen shell use haseen --yes
assert_eq "use haseen live calls" "--user daemon-reload
--user disable --now dms.service
--user enable haseen-shell.service
--user start haseen-shell.service" "$(<"$LOG")"
assert_eq "active-shell = haseen" "haseen" "$(<"$STATE")"

# Outside a graphical session dms.service (Requisite=graphical-session.target)
# cannot start: the switch still enables it and records the choice.
stub systemctl "[ \"\$2\" = start ] && exit 1; exit 0"
capture env HASEEN_SYSROOT="$ROOT" haseen shell use dms --yes
assert_status "start failure is not fatal" 0 "$STATUS"
assert_contains "start failure explained" "$OUTPUT" "starts at the next login"
assert_eq "active-shell recorded despite start failure" "dms" "$(<"$STATE")"

# Without the shell layer there is no haseen-shell.service to disable.
mkroot dms-no-shell base desktop dms
capture env HASEEN_SYSROOT="$ROOT" haseen shell use dms --dry-run
assert_not_contains "absent haseen unit not disabled" "$OUTPUT" "haseen-shell.service"

# --- layer remove: switch back first, then drop the drop-in ----------------
sandbox dms-remove
mkroot remove base desktop shell dms
with_dms_installed
with_dropin
mkdir -p "$HOME/.local/state/haseen"
echo dms >"$HOME/.local/state/haseen/active-shell"
capture env HASEEN_SYSROOT="$ROOT" haseen layer remove dms --dry-run
assert_status "remove dry-run exit" 0 "$STATUS"
assert_dry_pure "dms remove" "$OUTPUT"
assert_eq "remove: switch back, then drop-in" "DRYRUN: systemctl --user daemon-reload
DRYRUN: systemctl --user disable --now dms.service
DRYRUN: systemctl --user enable haseen-shell.service
DRYRUN: systemctl --user start haseen-shell.service
DRYRUN: write $HOME/.local/state/haseen/active-shell:
DRYRUN: sudo rm -f $DROPIN
DRYRUN: sudo rmdir --ignore-fail-on-non-empty ${DROPIN%/*}
DRYRUN: systemctl --user daemon-reload
DRYRUN: sudo rm -f /var/lib/haseen/layers/dms" "$(plan_steps "$OUTPUT")"
assert_contains "package removal left to the user" "$OUTPUT" "pacman -Rns dms-shell"
assert_not_contains "package not removed by haseen" "$OUTPUT" "DRYRUN: sudo pacman -R"

echo haseen >"$HOME/.local/state/haseen/active-shell"
capture env HASEEN_SYSROOT="$ROOT" haseen layer remove dms --dry-run
assert_not_contains "remove while haseen active: no switch" "$OUTPUT" "enable haseen-shell.service"
assert_contains "remove while haseen active: drop-in removed" "$OUTPUT" "DRYRUN: sudo rm -f $DROPIN"

mkroot remove-no-shell base desktop dms
with_dropin
echo dms >"$HOME/.local/state/haseen/active-shell"
capture env HASEEN_SYSROOT="$ROOT" haseen layer remove dms --dry-run
assert_contains "no shell layer: DMS stopped" "$OUTPUT" "DRYRUN: systemctl --user disable --now dms.service"
assert_contains "no shell layer: state cleared" "$OUTPUT" "DRYRUN: rm -f $HOME/.local/state/haseen/active-shell"
assert_not_contains "no shell layer: haseen unit untouched" "$OUTPUT" "haseen-shell.service"
unset HASEEN_LAYERS_DIR

# --- ipc-translate ---------------------------------------------------------
sandbox dms-ipc
stub dms 'echo "dms $*"'
check_map() { # EXPECTED HASEEN-CALL...
    local want="$1"
    shift
    capture "$TRANSLATE" "$@"
    assert_status "translate $* exit" 0 "$STATUS"
    assert_eq "translate $*" "$want" "$OUTPUT"
}
check_map "dms ipc call launcher toggle" launcher toggle
check_map "dms ipc call lock lock" lock lock
check_map "dms ipc call notifications clearAll" notifications clear
check_map "dms ipc call notifications toggleDoNotDisturb" notifications toggleDnd
check_map "dms ipc call launcher toggle" panel toggle haseen.launcher
check_map "dms ipc call notifications toggle" panel toggle haseen.notifications
check_map "dms ipc call powermenu toggle" panel toggle haseen.session
check_map "dms restart" shell reload

check_unmapped() { # HASEEN-CALL...
    capture "$TRANSLATE" "$@"
    assert_status "unmapped $* exits 3" 3 "$STATUS"
    assert_not_contains "unmapped $* never reaches dms" "$OUTPUT" "dms ipc"
    assert_eq "unmapped $* is one line" 1 "$(wc -l <<<"$OUTPUT")"
}
check_unmapped panel toggle haseen.ai
check_unmapped panel close
check_unmapped shell plugins
check_unmapped launcher toggle extra-arg
check_unmapped bar toggle
capture "$TRANSLATE" panel toggle haseen.ai
assert_contains "unmapped message names the call" "$OUTPUT" '"panel toggle haseen.ai" has no DMS equivalent'

capture "$TRANSLATE" launcher
assert_status "translate usage error" 2 "$STATUS"
capture "$TRANSLATE" panel toggle
assert_status "panel toggle without id is a usage error" 2 "$STATUS"

stub dms 'exit 5'
capture "$TRANSLATE" lock lock
assert_status "dms failure propagates" 5 "$STATUS"

sandbox dms-ipc-dry
capture "$TRANSLATE" --dry-run panel toggle haseen.session
assert_dry_pure "translate" "$OUTPUT"
assert_eq "translate dry-run" "DRYRUN: dms ipc call powermenu toggle" "$OUTPUT"
