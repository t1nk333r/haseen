# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# haseen's answers to Omarchy's restart-*, screensaver, setup-*, show-*,
# snapshot, state, sudo-*, system-* and tailscale-* commands (plan 093, g5).

OMA="$HASEEN_PATH/omarchy/bin"

# wait_for FILE PATTERN — up to 2 s for a background step to log PATTERN.
wait_for() {
    local i
    for ((i = 0; i < 20; i++)); do
        grep -qF -- "$2" "$1" 2>/dev/null && return 0
        sleep 0.1
    done
    return 1
}

# fake_bin NAME... — a tree whose bin/ holds recorders for these haseen
# commands; scripts run with HASEEN_PATH=$FAKE/share/haseen reach them.
fake_bin() {
    FAKE="$SANDBOX/fake"
    mkdir -p "$FAKE/bin" "$FAKE/share/haseen"
    [[ -e $FAKE/share/haseen/lib ]] || ln -s "$HASEEN_PATH/lib" "$FAKE/share/haseen/lib"
    [[ -e $FAKE/share/haseen/omarchy ]] || ln -s "$HASEEN_PATH/omarchy" "$FAKE/share/haseen/omarchy"
    local t
    for t in "$@"; do
        printf '#!/bin/sh\nprintf %%s "${0##*/}" >>"%s"; for a in "$@"; do printf " [%%s]" "$a" >>"%s"; done; echo >>"%s"\n' \
            "$SANDBOX/fake.log" "$SANDBOX/fake.log" "$SANDBOX/fake.log" >"$FAKE/bin/$t"
        chmod +x "$FAKE/bin/$t"
    done
}

MINE=(omarchy-restart-app omarchy-restart-btop omarchy-restart-helix omarchy-restart-herdr
    omarchy-restart-hyprctl omarchy-restart-hyprsunset omarchy-restart-opencode
    omarchy-restart-terminal omarchy-restart-tmux omarchy-restart-xcompose omarchy-screensaver
    omarchy-setup-direct-boot omarchy-setup-security-sshd omarchy-setup-security-sudoless-docker
    omarchy-show-done omarchy-show-logo omarchy-snapshot omarchy-state omarchy-sudo-docker
    omarchy-sudo-passwordless omarchy-system-lid-close omarchy-system-lock omarchy-system-reboot
    omarchy-system-shutdown omarchy-system-sleep-lock omarchy-system-stats
    omarchy-tailscale-receive omarchy-tailscale-send)

# --- every script: help, lib, notice --------------------------------------------
sandbox omarchy-g5-help
bad=""
for name in "${MINE[@]}"; do
    capture "$OMA/$name" --help
    [[ $STATUS == 0 && $OUTPUT == *Usage* && $OUTPUT != *STUB-CALLED* ]] || bad+="$name($STATUS) "
    [[ -x $OMA/$name && ! -L $OMA/$name ]] || bad+="$name(not a script) "
done
assert_eq "every g5 script answers --help and runs nothing" "" "$bad"

# --- restart-app ------------------------------------------------------------------
sandbox omarchy-restart-app
capture env UWSM_FINALIZE_VARNAMES=x "$OMA/omarchy-restart-app" --dry-run foot --server
assert_status "restart-app dry-run" 0 "$STATUS"
assert_dry_pure "restart-app" "$OUTPUT"
assert_contains "restart-app stops the app by exact name" "$OUTPUT" "DRYRUN: pkill -x -- foot"
assert_contains "restart-app relaunches through uwsm-app in a uwsm session" "$OUTPUT" "DRYRUN: uwsm-app -- foot --server"
capture "$OMA/omarchy-restart-app" --dry-run foot
assert_contains "restart-app without uwsm uses a scope in app-graphical.slice" "$OUTPUT" \
    "DRYRUN: systemd-run --user --scope --slice=app-graphical.slice --collect --quiet --unit=app-haseen-foot-"
assert_contains "the scope runs the app" "$OUTPUT" ".scope -- foot"
capture "$OMA/omarchy-restart-app"
assert_status "restart-app without a name is a usage error" 2 "$STATUS"
LOG="$SANDBOX/calls.log"
stub pkill 'echo "pkill $*" >>"'"$LOG"'"; exit 1'
stub uwsm-app 'echo "uwsm-app $*" >>"'"$LOG"'"'
capture env UWSM_FINALIZE_VARNAMES=x "$OMA/omarchy-restart-app" foot --dry-run
assert_status "restart-app runs although nothing was running" 0 "$STATUS"
wait_for "$LOG" "uwsm-app" || true
assert_contains "the app's own --dry-run is its argument" "$(cat "$LOG")" "uwsm-app -- foot --dry-run"
assert_contains "the old instance is signalled" "$(cat "$LOG")" "pkill -x -- foot"

# --- signal reloads: btop, helix, opencode ----------------------------------------------
sandbox omarchy-restart-signals
LOG="$SANDBOX/calls.log"
stub pgrep 'exit 1'
for spec in "btop -SIGUSR2" "helix -USR1" "opencode -SIGUSR2"; do
    read -r app sig <<<"$spec"
    capture "$OMA/omarchy-restart-$app"
    assert_status "restart-$app without $app succeeds" 0 "$STATUS"
    assert_dry_pure "restart-$app without $app" "$OUTPUT"
done
stub pgrep '[ "$1" = -x ] && [ "$2" = "${PGREP_RUNNING:-}" ]'
stub pkill 'echo "pkill $*" >>"'"$LOG"'"'
for spec in "btop -SIGUSR2" "helix -USR1" "opencode -SIGUSR2"; do
    read -r app sig <<<"$spec"
    capture env PGREP_RUNNING="$app" DRY_RUN=true "$OMA/omarchy-restart-$app"
    assert_contains "restart-$app dry-run prints the signal" "$OUTPUT" "DRYRUN: pkill $sig -x $app"
    assert_eq "restart-$app dry-run sends nothing" "" "$(cat "$LOG" 2>/dev/null)"
    capture env PGREP_RUNNING="$app" "$OMA/omarchy-restart-$app"
    assert_status "restart-$app" 0 "$STATUS"
    assert_eq "restart-$app signals exactly $app" "pkill $sig -x $app" "$(cat "$LOG")"
    rm -f "$LOG"
done

# --- restart-hyprctl --------------------------------------------------------------
sandbox omarchy-restart-hyprctl
capture "$OMA/omarchy-restart-hyprctl" --dry-run
assert_eq "restart-hyprctl dry-run" "DRYRUN: hyprctl reload" "$OUTPUT"
stub hyprctl 'echo ok; exit 3'
capture "$OMA/omarchy-restart-hyprctl"
assert_status "restart-hyprctl passes hyprctl's status on" 3 "$STATUS"
assert_eq "restart-hyprctl hides hyprctl's reply" "" "$OUTPUT"

# --- restart-terminal ----------------------------------------------------------------
sandbox omarchy-restart-terminal
LOG="$SANDBOX/calls.log"
ala="$XDG_CONFIG_HOME/alacritty/alacritty.toml"
mkdir -p "${ala%/*}"
printf '[font]\nsize = 11\n' >"$ala"
touch -d '2000-01-01 00:00' "$ala"
stub pgrep '[ "$2" = kitty ]'
capture "$OMA/omarchy-restart-terminal" --dry-run
assert_dry_pure "restart-terminal" "$OUTPUT"
assert_contains "restart-terminal dry-run touches alacritty's config" "$OUTPUT" "DRYRUN: touch -- $ala"
assert_contains "restart-terminal dry-run signals kitty" "$OUTPUT" "DRYRUN: pkill -USR1 -x kitty"
assert_not_contains "ghostty is not running" "$OUTPUT" "ghostty"
assert_eq "dry-run leaves the mtime" "2000" "$(date -r "$ala" +%Y)"
stub pkill 'echo "pkill $*" >>"'"$LOG"'"'
capture "$OMA/omarchy-restart-terminal"
assert_status "restart-terminal" 0 "$STATUS"
assert_eq "kitty is reloaded, ghostty is not" "pkill -USR1 -x kitty" "$(cat "$LOG")"
assert_not_contains "alacritty's config gets a new mtime" "$(date -r "$ala" +%Y)" "2000"
assert_eq "alacritty's config keeps its contents" $'[font]\nsize = 11' "$(cat "$ala")"

# --- restart-tmux ------------------------------------------------------------------
sandbox omarchy-restart-tmux
LOG="$SANDBOX/calls.log"
stub tmux 'case "$1" in has-session) exit 1 ;; *) echo "tmux $*" >>"'"$LOG"'" ;; esac'
capture "$OMA/omarchy-restart-tmux"
assert_status "restart-tmux without a server" 0 "$STATUS"
assert_eq "restart-tmux without a server sources nothing" "" "$(cat "$LOG" 2>/dev/null)"
stub tmux 'case "$1" in has-session) exit 0 ;; *) echo "tmux $*" >>"'"$LOG"'" ;; esac'
mkdir -p "$XDG_CONFIG_HOME/tmux"
: >"$XDG_CONFIG_HOME/tmux/tmux.conf"
capture "$OMA/omarchy-restart-tmux" --dry-run
assert_eq "restart-tmux dry-run" "DRYRUN: tmux source-file $XDG_CONFIG_HOME/tmux/tmux.conf" "$OUTPUT"
: >"$SANDBOX/custom.conf"
capture env TMUX_CONF="$SANDBOX/custom.conf" "$OMA/omarchy-restart-tmux"
assert_eq "restart-tmux sources \$TMUX_CONF first" "tmux source-file $SANDBOX/custom.conf" "$(cat "$LOG")"

# --- restart-herdr -------------------------------------------------------------------
sandbox omarchy-restart-herdr
stub herdr 'case "$1 $2" in "status server") echo "{\"running\":false}" ;; *) echo "STUB-CALLED: herdr $*" >&2; exit 97 ;; esac'
capture "$OMA/omarchy-restart-herdr"
assert_status "restart-herdr without a server" 0 "$STATUS"
assert_dry_pure "restart-herdr without a server" "$OUTPUT"
stub herdr 'case "$1 $2" in "status server") echo "{\"running\":true}" ;; "server reload-config") echo "$HERDR_REPLY" ;; esac'
capture "$OMA/omarchy-restart-herdr" --dry-run
assert_eq "restart-herdr dry-run" "DRYRUN: herdr server reload-config" "$OUTPUT"
capture env HERDR_REPLY='{"result":{"status":"failed","diagnostics":["unknown key: foo"]}}' "$OMA/omarchy-restart-herdr"
assert_status "a failed reload exits 1" 1 "$STATUS"
assert_contains "the reload's diagnostics are shown" "$OUTPUT" "unknown key: foo"
capture env HERDR_REPLY='{"result":{"status":"ok","diagnostics":[]}}' "$OMA/omarchy-restart-herdr"
assert_status "a good reload exits 0" 0 "$STATUS"
capture env HERDR_REPLY='not json' "$OMA/omarchy-restart-herdr"
assert_status "a reply that is not JSON is a failure" 1 "$STATUS"

# --- restart-xcompose ---------------------------------------------------------------
sandbox omarchy-restart-xcompose
stub fcitx5 'exit 0'
stub systemctl 'case "$*" in
"--user show -p LoadState --value app-org.fcitx.Fcitx5@autostart.service") echo "${AUTOSTART_STATE:-not-found}" ;;
"--user show -p LoadState --value "*) echo not-found ;;
*) echo "STUB-CALLED: systemctl $*" >&2; exit 97 ;;
esac'
capture env AUTOSTART_STATE=loaded "$OMA/omarchy-restart-xcompose" --dry-run
assert_dry_pure "restart-xcompose (autostart unit)" "$OUTPUT"
assert_contains "the autostart unit is stopped" "$OUTPUT" "DRYRUN: systemctl --user stop app-org.fcitx.Fcitx5@autostart.service"
assert_contains "a stray fcitx5 is stopped" "$OUTPUT" "DRYRUN: pkill -x fcitx5"
assert_contains "the autostart unit is started" "$OUTPUT" "DRYRUN: systemctl --user start app-org.fcitx.Fcitx5@autostart.service"
assert_not_contains "Omarchy's unit is not assumed" "$OUTPUT" "omarchy-fcitx5"
capture env UWSM_FINALIZE_VARNAMES=x "$OMA/omarchy-restart-xcompose" --dry-run
assert_dry_pure "restart-xcompose (no unit)" "$OUTPUT"
assert_contains "without a unit fcitx5 restarts in the session" "$OUTPUT" "DRYRUN: uwsm-app -- fcitx5 -d"

# --- restart-hyprsunset ----------------------------------------------------------------
sandbox omarchy-restart-hyprsunset
LOG="$SANDBOX/calls.log"
capture "$OMA/omarchy-restart-hyprsunset" --dry-run
assert_dry_pure "restart-hyprsunset" "$OUTPUT"
assert_contains "restart-hyprsunset asks haseen.nightlight" "$OUTPUT" "haseen-shell-ipc nightlight refresh"
stub qs 'echo "qs $*" >>"'"$LOG"'"'
capture "$OMA/omarchy-restart-hyprsunset"
assert_status "restart-hyprsunset" 0 "$STATUS"
assert_eq "the night light's own instance is refreshed" "qs -p $HASEEN_PATH/shell ipc call nightlight refresh" "$(cat "$LOG")"

# --- screensaver --------------------------------------------------------------------------
sandbox omarchy-screensaver
mkdir -p "$XDG_STATE_HOME/haseen/flags"
: >"$XDG_STATE_HOME/haseen/flags/screensaver-off"
capture "$OMA/omarchy-screensaver" --dry-run
assert_status "screensaver dry-run" 0 "$STATUS"
assert_dry_pure "screensaver" "$OUTPUT"
assert_contains "the screensaver is haseen's, shown even when off" "$OUTPUT" "DRYRUN: haseen shell ipc screensaver start default"

# --- setup-direct-boot ------------------------------------------------------------------
sandbox omarchy-direct-boot
ROOT="$SANDBOX/root"
mkdir -p "$ROOT/sys/firmware/efi" "$ROOT/sys/class/dmi/id" "$ROOT/boot/EFI/limine" "$ROOT/boot/EFI/Linux" \
    "$ROOT/usr/lib/modules/6.9.1-test" "$ROOT/etc/mkinitcpio.d"
echo LENOVO >"$ROOT/sys/class/dmi/id/bios_vendor"
: >"$ROOT/boot/EFI/limine/limine_x64.efi"
printf 'timeout: 5\n' >"$ROOT/boot/limine.conf"
: >"$ROOT/boot/EFI/Linux/cachyos-linux-cachyos.efi"
: >"$ROOT/boot/EFI/Linux/cachyos-linux-cachyos-fallback.efi"
echo linux-cachyos >"$ROOT/usr/lib/modules/6.9.1-test/pkgbase"
printf 'ALL_kver="/boot/vmlinuz-linux-cachyos"\ndefault_uki="/boot/EFI/Linux/cachyos-linux-cachyos.efi"\n' \
    >"$ROOT/etc/mkinitcpio.d/linux-cachyos.preset"
stub uname 'echo 6.9.1-test'
stub findmnt 'echo /dev/nvme0n1p1'
stub efibootmgr '[ $# -eq 0 ] || { echo "STUB-CALLED: efibootmgr $*" >&2; exit 97; }
printf "BootCurrent: 0001\nBootOrder: 0001\nBoot0001* Limine\tHD(1,GPT)\n%b" "${EXTRA_ENTRIES:-}"'
export HASEEN_SYSROOT="$ROOT"
capture "$OMA/omarchy-setup-direct-boot" --dry-run
assert_status "direct-boot dry-run" 0 "$STATUS"
assert_dry_pure "direct-boot" "$OUTPUT"
assert_contains "direct-boot adds a haseen entry for the running kernel's UKI" "$OUTPUT" \
    'DRYRUN: sudo efibootmgr --create --disk /dev/nvme0n1 --part 1 --label haseen --loader \EFI\Linux\cachyos-linux-cachyos.efi'
assert_contains "direct-boot warns that snapshots need the firmware menu" "$OUTPUT" "firmware's boot menu"
assert_not_contains "direct-boot never touches the bootloader's config" "$OUTPUT" "limine.conf"
capture env EXTRA_ENTRIES='Boot0003* Omarchy\tHD(1,GPT)\nBoot0004* haseen\tHD(1,GPT)\n' "$OMA/omarchy-setup-direct-boot" --dry-run
assert_dry_pure "direct-boot removal" "$OUTPUT"
assert_contains "an Omarchy entry is removed" "$OUTPUT" "DRYRUN: sudo efibootmgr --bootnum 0003 --delete-bootnum"
assert_contains "haseen's entry is removed" "$OUTPUT" "DRYRUN: sudo efibootmgr --bootnum 0004 --delete-bootnum"
assert_not_contains "removal creates nothing" "$OUTPUT" "--create"
: >"$ROOT/boot/EFI/Linux/omarchy_linux.efi"
capture "$OMA/omarchy-setup-direct-boot" --dry-run
assert_contains "an Omarchy host's UKI is Omarchy's" "$OUTPUT" '--loader \EFI\Linux\omarchy_linux.efi'
rm -f "$ROOT"/boot/EFI/Linux/*.efi
capture "$OMA/omarchy-setup-direct-boot" --dry-run
assert_status "no UKI fails" 1 "$STATUS"
assert_contains "no UKI says so" "$OUTPUT" "no unified kernel image"
echo "American Megatrends Inc." >"$ROOT/sys/class/dmi/id/bios_vendor"
capture "$OMA/omarchy-setup-direct-boot" --dry-run
assert_status "AMI firmware is refused" 1 "$STATUS"
rmdir "$ROOT/sys/firmware/efi"
capture "$OMA/omarchy-setup-direct-boot" --dry-run
assert_status "BIOS boot is refused" 1 "$STATUS"
assert_contains "BIOS boot says so" "$OUTPUT" "not started in UEFI mode"
unset HASEEN_SYSROOT

# --- setup-security-sshd ------------------------------------------------------------------
sandbox omarchy-sshd
export HASEEN_SYSROOT="$SANDBOX/root" HASEEN_INLINE=1
mkdir -p "$HASEEN_SYSROOT"
ssh-keygen -q -t ed25519 -N '' -C test@host -f "$SANDBOX/k"
ssh-keygen -q -t ed25519 -N '' -C other@host -f "$SANDBOX/k2"
pub="$(<"$SANDBOX/k.pub")"
keys="$HOME/.ssh/authorized_keys"
capture "$OMA/omarchy-setup-security-sshd" --key="$pub" --dry-run
assert_status "sshd dry-run" 0 "$STATUS"
assert_dry_pure "sshd" "$OUTPUT"
assert_contains "the key is appended to authorized_keys" "$OUTPUT" "DRYRUN: append to $keys:"
assert_contains "the appended line is the key" "$OUTPUT" "    | $pub"
assert_contains "then haseen's sshd setup runs" "$OUTPUT" "DRYRUN: sudo systemctl enable --now sshd.service"
[[ ! -e $keys ]] && _pass || _fail "sshd dry-run wrote authorized_keys"
capture "$OMA/omarchy-setup-security-sshd" --key="not a key" --dry-run
assert_status "an invalid key fails" 1 "$STATUS"
assert_contains "an invalid key says so" "$OUTPUT" "Not a valid SSH public key"
capture "$OMA/omarchy-setup-security-sshd" --bogus
assert_status "an unknown option is a usage error" 2 "$STATUS"
fake_bin haseen-setup-sshd
capture env HASEEN_PATH="$FAKE/share/haseen" "$OMA/omarchy-setup-security-sshd" --key="$pub" --yes
assert_status "sshd with a key" 0 "$STATUS"
assert_eq "authorized_keys holds the key" "$pub" "$(cat "$keys")"
assert_eq "a new ~/.ssh is private" "700" "$(stat -c %a "$HOME/.ssh")"
assert_eq "a new authorized_keys is private" "600" "$(stat -c %a "$keys")"
assert_eq "haseen setup sshd runs after the key" "haseen-setup-sshd [--yes]" "$(cat "$SANDBOX/fake.log")"
capture env HASEEN_PATH="$FAKE/share/haseen" "$OMA/omarchy-setup-security-sshd" --key="$pub" --yes
assert_contains "a known key is not added twice" "$OUTPUT" "Key already authorized"
assert_eq "authorized_keys still holds one key" "1" "$(wc -l <"$keys")"
chmod 644 "$keys"
capture env HASEEN_PATH="$FAKE/share/haseen" "$OMA/omarchy-setup-security-sshd" --key="$(<"$SANDBOX/k2.pub")" --yes
assert_eq "a second key is appended" "2" "$(wc -l <"$keys")"
assert_eq "the user's file keeps its mode" "644" "$(stat -c %a "$keys")"
assert_eq "the first key is untouched" "$pub" "$(head -n1 "$keys")"
capture "$OMA/omarchy-setup-security-sshd" --dry-run
assert_contains "with a key already there nothing is asked" "$OUTPUT" "already holds a key"
unset HASEEN_SYSROOT HASEEN_INLINE

# --- sudo-docker and sudoless docker --------------------------------------------------------
sandbox omarchy-docker
stub id 'case "$1" in -nG) echo "${ID_GROUPS:-wheel}" ;; -un) echo tester ;; *) exec /usr/bin/id "$@" ;; esac'
export USER=tester
: >"$SANDBOX/docker.sock"
capture env HASEEN_DOCKER_SOCKET="$SANDBOX/docker.sock" "$OMA/omarchy-sudo-docker"
assert_status "a writable socket needs no sudo" 1 "$STATUS"
capture env HASEEN_DOCKER_SOCKET="$SANDBOX/missing.sock" "$OMA/omarchy-sudo-docker"
assert_status "a missing socket needs sudo" 0 "$STATUS"
capture "$OMA/omarchy-sudo-docker" --configured
assert_status "outside the docker group sudo is needed" 0 "$STATUS"
capture env ID_GROUPS="wheel docker" "$OMA/omarchy-sudo-docker" --configured
assert_status "in the docker group it is not" 1 "$STATUS"
capture "$OMA/omarchy-sudo-docker" --bogus
assert_status "sudo-docker usage error" 2 "$STATUS"

export HASEEN_SYSROOT="$SANDBOX/root" HASEEN_INLINE=1
mkdir -p "$HASEEN_SYSROOT/etc"
printf 'root:x:0:\ndocker:x:970:\n' >"$HASEEN_SYSROOT/etc/group"
capture "$OMA/omarchy-setup-security-sudoless-docker" --dry-run
assert_status "sudoless docker dry-run" 0 "$STATUS"
assert_dry_pure "sudoless docker" "$OUTPUT"
assert_contains "the user joins the docker group" "$OUTPUT" "DRYRUN: sudo usermod -aG docker tester"
assert_contains "a reboot is recorded in haseen's store" "$OUTPUT" "DRYRUN: touch -- $XDG_STATE_HOME/haseen/omarchy-state/reboot-required"
assert_contains "a reboot is offered" "$OUTPUT" "Reboot now to apply?"
assert_contains "the warning names haseen" "$OUTPUT" "the protection haseen keeps"
capture env OMARCHY_DEFER_REBOOT=1 "$OMA/omarchy-setup-security-sudoless-docker" --dry-run
assert_not_contains "a deferred reboot is not offered" "$OUTPUT" "Reboot now"
capture env ID_GROUPS="wheel docker" "$OMA/omarchy-setup-security-sudoless-docker" --dry-run
assert_status "already enabled" 0 "$STATUS"
assert_contains "already enabled says so" "$OUTPUT" "already enabled"
assert_not_contains "already enabled changes nothing" "$OUTPUT" "usermod"
printf 'root:x:0:\n' >"$HASEEN_SYSROOT/etc/group"
capture "$OMA/omarchy-setup-security-sudoless-docker" --dry-run
assert_status "no docker group is refused" 1 "$STATUS"
unset HASEEN_SYSROOT HASEEN_INLINE

# --- show-done, show-logo -----------------------------------------------------------------
sandbox omarchy-show
capture setsid -w "$OMA/omarchy-show-done"
assert_status "show-done without a terminal returns at once" 0 "$STATUS"
assert_eq "show-done without a terminal prints nothing" "" "$OUTPUT"
capture env TERM=dumb "$OMA/omarchy-show-logo"
assert_status "show-logo" 0 "$STATUS"
assert_contains "show-logo prints haseen's default mark" "$OUTPUT" "$(head -n1 "$HASEEN_PATH/branding/logo-kufic.txt")"
assert_contains "show-logo prints in green" "$OUTPUT" $'\033[32m'
mkdir -p "$XDG_CONFIG_HOME/haseen"
echo '{"branding":{"mark":"shield"}}' >"$XDG_CONFIG_HOME/haseen/shell.json"
capture env TERM=dumb "$OMA/omarchy-show-logo"
assert_contains "show-logo follows the selected mark" "$OUTPUT" "$(head -n1 "$HASEEN_PATH/branding/logo-shield.txt")"
capture env TERM=dumb OMARCHY_PATH=/nonexistent "$OMA/omarchy-show-logo"
assert_status "Omarchy's logo is never read" 0 "$STATUS"

# --- snapshot --------------------------------------------------------------------------------
sandbox omarchy-snapshot
MINBIN="$SANDBOX/minbin"
mkdir -p "$MINBIN"
for t in bash dirname readlink cat sed tail; do ln -s "$(command -v "$t")" "$MINBIN/$t"; done
capture env PATH="$MINBIN" "$OMA/omarchy-snapshot" create
assert_status "snapshot without snapper exits 127 (omarchy-update relies on it)" 127 "$STATUS"
capture "$OMA/omarchy-snapshot"
assert_status "snapshot without a command" 1 "$STATUS"
export HASEEN_SYSROOT="$SANDBOX/root"
mkdir -p "$HASEEN_SYSROOT/etc/conf.d"
capture "$OMA/omarchy-snapshot" create --dry-run
assert_status "snapshot without snapper configs fails" 1 "$STATUS"
assert_contains "and points at haseen seed system" "$OUTPUT" "haseen seed system"
echo 'SNAPPER_CONFIGS="root home"' >"$HASEEN_SYSROOT/etc/conf.d/snapper"
capture "$OMA/omarchy-snapshot" create --dry-run
assert_status "snapshot create dry-run" 0 "$STATUS"
assert_dry_pure "snapshot create" "$OUTPUT"
assert_contains "a snapshot of root, labelled with haseen's version" "$OUTPUT" \
    "DRYRUN: sudo snapper -c root create -c number -d haseen $(<"$HASEEN_PATH/VERSION")"
assert_contains "a snapshot of home" "$OUTPUT" "DRYRUN: sudo snapper -c home create -c number"
assert_contains "then the number cleanup" "$OUTPUT" "DRYRUN: sudo snapper -c home cleanup number"
ln -s "$SANDBOX/stubs/snapper" "$MINBIN/snapper"
capture env PATH="$MINBIN" "$OMA/omarchy-snapshot" restore --dry-run
assert_status "restore without limine-snapper-restore fails" 1 "$STATUS"
assert_contains "and names the alternatives" "$OUTPUT" "snapper rollback"
stub limine-snapper-restore 'echo "STUB-CALLED: limine-snapper-restore" >&2; exit 97'
capture "$OMA/omarchy-snapshot" restore --dry-run
assert_contains "restore uses limine-snapper-restore" "$OUTPUT" "DRYRUN: sudo limine-snapper-restore"
assert_dry_pure "snapshot restore" "$OUTPUT"
unset HASEEN_SYSROOT

# --- state ---------------------------------------------------------------------------------------
sandbox omarchy-state
store="$XDG_STATE_HOME/haseen/omarchy-state"
capture "$OMA/omarchy-state" set reboot-required --dry-run
assert_contains "state set dry-run" "$OUTPUT" "DRYRUN: touch -- $store/reboot-required"
[[ ! -e $store ]] && _pass || _fail "state dry-run created the store"
capture "$OMA/omarchy-state" set reboot-required
assert_status "state set" 0 "$STATUS"
[[ -f $store/reboot-required ]] && _pass || _fail "state set made no marker"
"$OMA/omarchy-state" set restart-required
"$OMA/omarchy-state" set keep-me
echo haseen >"$XDG_STATE_HOME/haseen/active-shell"
mkdir -p "$XDG_STATE_HOME/haseen/flags"
: >"$XDG_STATE_HOME/haseen/flags/reboot-required"
capture "$OMA/omarchy-state" clear 're*-required' --dry-run
assert_contains "state clear dry-run names the marker" "$OUTPUT" "DRYRUN: rm $store/reboot-required"
[[ -f $store/reboot-required ]] && _pass || _fail "state clear dry-run removed a marker"
capture "$OMA/omarchy-state" clear 're*-required'
assert_eq "state clear removes the matching markers only" "keep-me" "$(ls "$store")"
capture "$OMA/omarchy-state" clear '*'
assert_eq "a wide pattern stays inside the store" "haseen" "$(cat "$XDG_STATE_HOME/haseen/active-shell")"
[[ -f $XDG_STATE_HOME/haseen/flags/reboot-required ]] && _pass || _fail "state clear reached haseen's flags"
capture "$OMA/omarchy-state" set ../escape
assert_status "a path is not a state name" 1 "$STATUS"
capture "$OMA/omarchy-state"
assert_status "state without a command" 1 "$STATUS"
capture "$OMA/omarchy-state" set
assert_status "state without a name" 1 "$STATUS"
[[ ! -e $XDG_STATE_HOME/omarchy ]] && _pass || _fail "omarchy-state wrote Omarchy's state directory"

# --- sudo-passwordless ------------------------------------------------------------------------
sandbox omarchy-nopasswd
export HASEEN_SYSROOT="$SANDBOX/root" HASEEN_INLINE=1
mkdir -p "$HASEEN_SYSROOT/etc/sudoers.d"
: >"$HASEEN_SYSROOT/etc/sudoers.d/90-haseen-tester"
stub id 'case "$1" in -un) echo tester ;; *) exec /usr/bin/id "$@" ;; esac'
stub systemctl 'case "$*" in "is-active --quiet "*) exit "${TIMER_STATE:-3}" ;; *) echo "STUB-CALLED: systemctl $*" >&2; exit 97 ;; esac'
nopw=/etc/sudoers.d/99-haseen-nopasswd-tester
capture "$OMA/omarchy-sudo-passwordless" --dry-run
assert_status "passwordless dry-run" 0 "$STATUS"
assert_dry_pure "passwordless" "$OUTPUT"
assert_contains "the timed rule is haseen's drop-in" "$OUTPUT" "DRYRUN: write $nopw (mode 0440):"
assert_contains "the rule lapses by itself" "$OUTPUT" "tester ALL=(ALL) NOTAFTER="
assert_contains "the rule is passwordless" "$OUTPUT" "NOPASSWD: ALL"
assert_contains "a root timer removes it after 15 minutes" "$OUTPUT" \
    "DRYRUN: sudo systemd-run --on-active=15m --timer-property=AccuracySec=1s --unit=haseen-nopasswd-expire-tester"
assert_contains "the timer removes the drop-in" "$OUTPUT" "/usr/bin/rm -f -- $nopw"
assert_contains "the warning is shown" "$OUTPUT" "WARNING"
assert_not_contains "haseen's permanent rule is not touched" "$OUTPUT" "90-haseen"
capture "$OMA/omarchy-sudo-passwordless" 30 --dry-run
assert_contains "MINUTES sets the expiry" "$OUTPUT" "--on-active=30m"
capture "$OMA/omarchy-sudo-passwordless" soon --dry-run
assert_status "MINUTES must be a number" 1 "$STATUS"
: >"$HASEEN_SYSROOT$nopw"
capture env TIMER_STATE=0 "$OMA/omarchy-sudo-passwordless" --dry-run
assert_dry_pure "passwordless off" "$OUTPUT"
assert_contains "on: the toggle removes haseen's and Omarchy's rule" "$OUTPUT" \
    "DRYRUN: sudo rm -f -- $nopw /etc/sudoers.d/99-omarchy-nopasswd-tester"
assert_contains "and stops the timers" "$OUTPUT" "DRYRUN: sudo systemctl stop haseen-nopasswd-expire-tester.timer omarchy-nopasswd-expire-tester.timer"
assert_not_contains "turning off does not write a rule" "$OUTPUT" "DRYRUN: write"
assert_not_contains "turning off leaves the permanent rule" "$OUTPUT" "90-haseen"
capture env TIMER_STATE=0 "$OMA/omarchy-sudo-passwordless" 5 --dry-run
assert_contains "on with MINUTES restarts the countdown" "$OUTPUT" "--on-active=5m"
assert_contains "and says so" "$OUTPUT" "timer updated"
capture "$OMA/omarchy-sudo-passwordless" --dry-run
assert_contains "a rule without its timer is stale and removed" "$OUTPUT" "DRYRUN: sudo rm -f -- $nopw"
assert_contains "then it is offered again" "$OUTPUT" "WARNING"
unset HASEEN_SYSROOT HASEEN_INLINE

# --- system-stats ------------------------------------------------------------------------
sandbox omarchy-stats
export HASEEN_SYSROOT="$SANDBOX/root"
mkdir -p "$HASEEN_SYSROOT/proc"
echo "cpu  100 0 50 800 50 0 0 0 0 0" >"$HASEEN_SYSROOT/proc/stat"
printf 'MemTotal:       16000000 kB\nMemFree:  1000 kB\nMemAvailable:    8000000 kB\n' >"$HASEEN_SYSROOT/proc/meminfo"
echo "0.50 0.40 0.30 1/200 1234" >"$HASEEN_SYSROOT/proc/loadavg"
capture "$OMA/omarchy-system-stats" --bar-widget
assert_eq "the bar widget contract" $'cpu\t800\t1000\nmemory\t50.00\nload\t0.50' "$OUTPUT"
stub top 'printf "top - 10:00:00 up 1 day\nTasks: 1 total\n%%Cpu(s):  5.0 us,  2.0 sy,  0.0 ni, 93.0 id,  0.0 wa\n"'
capture "$OMA/omarchy-system-stats"
assert_eq "the power panel contract" $'cpu\t7%\nmemory\t7.6GB / 15GB' "$OUTPUT"
capture "$OMA/omarchy-system-stats" --bogus
assert_status "system-stats usage error" 1 "$STATUS"
unset HASEEN_SYSROOT

# --- system-lock ---------------------------------------------------------------------------
sandbox omarchy-lock
LOG="$SANDBOX/calls.log"
stub pgrep 'exit 1'
stub hyprctl 'case "$1" in clients|monitors|status|activewindow|-j) echo "[]" ;; *) echo "STUB-CALLED: hyprctl $*" >&2; exit 97 ;; esac'
capture "$OMA/omarchy-system-lock" --dry-run
assert_status "lock dry-run" 0 "$STATUS"
assert_dry_pure "lock" "$OUTPUT"
assert_contains "lock goes through haseen system lock" "$OUTPUT" "DRYRUN: haseen shell ipc lock lock"
assert_contains "lock resets the keyboard layout" "$OUTPUT" "DRYRUN: hyprctl switchxkblayout all 0"
assert_contains "lock ends haseen's screensaver" "$OUTPUT" "DRYRUN: hyprctl eval"
assert_not_contains "no 1Password running, none locked" "$OUTPUT" "1password"
stub pgrep '[ "$2" = 1password ]'
stub 1password 'echo "STUB-CALLED: 1password $*" >&2; exit 97'
capture "$OMA/omarchy-system-lock" --dry-run
assert_contains "a running 1Password is locked, bounded" "$OUTPUT" "DRYRUN: timeout --kill-after=1s 3s 1password --lock"
assert_dry_pure "lock with 1Password" "$OUTPUT"
stub pgrep 'exit 1'
stub qs 'echo "qs $*" >>"'"$LOG"'"'
stub hyprctl 'echo "hyprctl $*" >>"'"$LOG"'"; case "$1" in clients|monitors|status|activewindow|-j) echo "[]" ;; esac'
capture "$OMA/omarchy-system-lock"
assert_status "lock always exits 0" 0 "$STATUS"
assert_contains "the shell is asked to lock" "$(cat "$LOG")" "ipc call lock lock"
assert_contains "the keyboard layout is reset" "$(cat "$LOG")" "hyprctl switchxkblayout all 0"

# --- system-lid-close ------------------------------------------------------------------------
sandbox omarchy-lid
export HASEEN_SYSROOT="$SANDBOX/root"
mkdir -p "$HASEEN_SYSROOT/proc/acpi/button/lid/LID0" "$HASEEN_SYSROOT/sys/class/drm/card1-eDP-1"
echo "state:      closed" >"$HASEEN_SYSROOT/proc/acpi/button/lid/LID0/state"
echo connected >"$HASEEN_SYSROOT/sys/class/drm/card1-eDP-1/status"
stub pgrep 'exit 1'
stub hyprctl 'case "$1" in clients|monitors|status|activewindow|-j) echo "[]" ;; *) echo "STUB-CALLED: hyprctl $*" >&2; exit 97 ;; esac'
capture "$OMA/omarchy-system-lid-close" --dry-run
assert_dry_pure "lid close" "$OUTPUT"
assert_contains "an undocked lid close locks at once" "$OUTPUT" "DRYRUN: haseen shell ipc lock lock"
mkdir -p "$HASEEN_SYSROOT/sys/class/drm/card1-HDMI-A-1"
echo connected >"$HASEEN_SYSROOT/sys/class/drm/card1-HDMI-A-1/status"
capture "$OMA/omarchy-system-lid-close" --dry-run
assert_dry_pure "docked lid close" "$OUTPUT"
assert_not_contains "a docked lid close does not lock" "$OUTPUT" "lock lock"
echo "state:      open" >"$HASEEN_SYSROOT/proc/acpi/button/lid/LID0/state"
rm -r "$HASEEN_SYSROOT/sys/class/drm/card1-HDMI-A-1"
capture "$OMA/omarchy-system-lid-close" --dry-run
assert_not_contains "an open lid does not lock" "$OUTPUT" "lock lock"
unset HASEEN_SYSROOT

# --- system-reboot, system-shutdown ------------------------------------------------------------
sandbox omarchy-power
LOG="$SANDBOX/calls.log"
store="$XDG_STATE_HOME/haseen/omarchy-state"
mkdir -p "$store"
: >"$store/reboot-required"
: >"$store/keep-me"
echo haseen >"$XDG_STATE_HOME/haseen/active-shell"
stub hyprctl 'case "$1" in clients|monitors|status|activewindow|-j) echo "[]" ;; *) echo "STUB-CALLED: hyprctl $*" >&2; exit 97 ;; esac'
capture "$OMA/omarchy-system-reboot" --dry-run
assert_status "reboot dry-run" 0 "$STATUS"
assert_dry_pure "reboot" "$OUTPUT"
assert_contains "the reboot is scheduled in the user manager, through haseen" "$OUTPUT" \
    "DRYRUN: systemd-run --user --collect --quiet --on-active=2s --timer-property=AccuracySec=100ms $REPO/bin/haseen-system reboot"
assert_contains "the reboot markers would be cleared" "$OUTPUT" "DRYRUN: rm $store/reboot-required"
assert_contains "the windows would be closed" "$OUTPUT" "DRYRUN: hyprctl dispatch"
[[ -f $store/reboot-required ]] && _pass || _fail "reboot dry-run cleared a marker"
stub systemd-run 'echo "systemd-run $*" >>"'"$LOG"'"'
stub hyprctl 'echo "hyprctl $*" >>"'"$LOG"'"; case "$1" in clients) echo "[{\"address\":\"0xabc\"}]" ;; monitors|status|activewindow|-j) echo "[]" ;; esac'
capture "$OMA/omarchy-system-reboot"
assert_status "reboot" 0 "$STATUS"
assert_contains "the reboot is scheduled" "$(cat "$LOG")" "systemd-run --user --collect --quiet --on-active=2s"
assert_contains "every window is asked to close" "$(cat "$LOG")" "address:0xabc"
assert_eq "the reboot markers are cleared, nothing else" "keep-me" "$(ls "$store")"
assert_eq "haseen's own state is untouched" "haseen" "$(cat "$XDG_STATE_HOME/haseen/active-shell")"
: >"$store/reboot-required"
rm -f "$LOG"
stub systemd-run 'exit 1'
capture "$OMA/omarchy-system-reboot"
assert_status "no scheduled reboot, no reboot" 1 "$STATUS"
[[ -f $store/reboot-required ]] && _pass || _fail "a failed reboot cleared the markers"
assert_eq "a failed reboot closes no window" "" "$(cat "$LOG" 2>/dev/null)"

stub hyprctl 'case "$1" in clients|monitors|status|activewindow|-j) echo "[]" ;; *) echo "STUB-CALLED: hyprctl $*" >&2; exit 97 ;; esac'
capture env OMARCHY_PATH=/usr/share/omarchy "$OMA/omarchy-system-shutdown" --dry-run
assert_status "shutdown dry-run" 0 "$STATUS"
assert_dry_pure "shutdown" "$OUTPUT"
assert_contains "shutdown hands itself to the user manager" "$OUTPUT" \
    "DRYRUN: systemd-run --user --collect --quiet --property=Type=exec --property=RuntimeMaxSec=30s $OMA/omarchy-system-shutdown --inhibit"
assert_not_contains "never Omarchy's own script" "$OUTPUT" "/usr/share/omarchy"
capture "$OMA/omarchy-system-shutdown" --inhibit --dry-run
assert_dry_pure "shutdown --inhibit" "$OUTPUT"
assert_contains "the second stage blocks sleep and the lid" "$OUTPUT" \
    "DRYRUN: systemd-inhibit --what=sleep:idle:handle-lid-switch --who=haseen --why=Shutdown in progress --mode=block $OMA/omarchy-system-shutdown --inhibited --dry-run"
capture "$OMA/omarchy-system-shutdown" --inhibited --dry-run
assert_dry_pure "shutdown --inhibited" "$OUTPUT"
assert_contains "the last stage clears the markers" "$OUTPUT" "DRYRUN: rm $store/reboot-required"
assert_contains "and closes the windows" "$OUTPUT" "DRYRUN: hyprctl dispatch"
assert_contains "and powers off through haseen" "$OUTPUT" "DRYRUN: systemctl poweroff"
stub systemd-inhibit 'exit 5'
stub notify-send 'echo "notify-send $*" >>"'"$LOG"'"'
capture "$OMA/omarchy-system-shutdown" --inhibit
assert_status "a failed shutdown keeps its status" 5 "$STATUS"
assert_contains "a failed shutdown is announced" "$(cat "$LOG")" "Shutdown failed"

# --- system-sleep-lock ----------------------------------------------------------------------
sandbox omarchy-sleep-lock
LOG="$SANDBOX/calls.log"
capture "$OMA/omarchy-system-sleep-lock" 3000 --dry-run
assert_status "sleep-lock dry-run" 0 "$STATUS"
assert_dry_pure "sleep-lock" "$OUTPUT"
assert_contains "sleep-lock asks haseen's shell to lock" "$OUTPUT" "haseen-shell-ipc lock lock (then wait up to 3000ms"
stub busctl 'echo "t 5000000"'
capture "$OMA/omarchy-system-sleep-lock" --dry-run
assert_contains "the budget follows logind's delay window" "$OUTPUT" "wait up to 4000ms"
stub qs 'echo "qs $*" >>"'"$LOG"'"'
stub hyprctl 'echo "[{\"solitaryBlockedBy\":[\"LOCK\"]}]"'
stub notify-send 'echo "notify-send $*" >>"'"$LOG"'"'
printf '1 sig\n' >"$XDG_RUNTIME_DIR/haseen-lock-held"
capture env HYPRLAND_INSTANCE_SIGNATURE=sig "$OMA/omarchy-system-sleep-lock" 2000
assert_status "a secure lock lets the sleep go on" 0 "$STATUS"
assert_contains "the lock was requested" "$(cat "$LOG")" "ipc call lock lock"
rm -f "$XDG_RUNTIME_DIR/haseen-lock-held" "$LOG"
capture env HYPRLAND_INSTANCE_SIGNATURE=sig "$OMA/omarchy-system-sleep-lock" 300
assert_status "no secure lock in time fails" 1 "$STATUS"
assert_contains "and says so" "$OUTPUT" "suspending without a secure lock"
assert_contains "and tells the user on unlock" "$(cat "$LOG")" "Screen did not lock before suspend"

# --- tailscale ------------------------------------------------------------------------------
sandbox omarchy-tailscale
LOG="$SANDBOX/calls.log"
DL="$SANDBOX/dl"
mkdir -p "$DL/.omarchy-taildrop"
echo old >"$DL/.omarchy-taildrop/a.txt"
echo mine >"$DL/b.txt"
stub tailscale 'echo "STUB-CALLED: tailscale $*" >&2; exit 97'
capture "$OMA/omarchy-tailscale-receive" --once "$DL" --dry-run
assert_status "receive dry-run" 0 "$STATUS"
assert_dry_pure "receive" "$OUTPUT"
assert_contains "Omarchy's staged file would be delivered" "$OUTPUT" "DRYRUN: deliver $DL/.omarchy-taildrop/a.txt to $DL"
assert_contains "the wait goes to haseen's staging" "$OUTPUT" "DRYRUN: tailscale file get --wait --conflict=rename $DL/.haseen-taildrop"
[[ -f $DL/.omarchy-taildrop/a.txt && ! -e $DL/.haseen-taildrop ]] && _pass || _fail "receive dry-run moved files"
# shellcheck disable=SC2016  # expands in the stub
stub tailscale 'for d; do :; done; echo png >"$d/photo.png"; echo new >"$d/b.txt"'
stub notify-send 'echo "notify-send $*" >>"'"$LOG"'"'
capture "$OMA/omarchy-tailscale-receive" --once "$DL"
assert_status "receive --once" 0 "$STATUS"
assert_eq "files land in the download dir under free names" "a.txt b-1.txt b.txt photo.png" "$(cd "$DL" && echo *)"
assert_eq "an existing file is not overwritten" "mine" "$(cat "$DL/b.txt")"
[[ ! -e $DL/.omarchy-taildrop && -z $(ls -A "$DL/.haseen-taildrop") ]] && _pass || _fail "receive left staged files"
wait_for "$LOG" "photo.png" || true
wait_for "$LOG" "b-1.txt" || true
assert_contains "an image is announced with itself as icon" "$(cat "$LOG")" "-i $DL/photo.png"
assert_contains "a delivery is announced by name" "$(cat "$LOG")" "Received b-1.txt"
stub tailscale 'exit 1'
capture "$OMA/omarchy-tailscale-receive" --once "$DL"
assert_status "a failed wait with --once fails" 1 "$STATUS"

rm -f "$LOG"
capture "$OMA/omarchy-tailscale-send"
assert_status "send without a machine" 1 "$STATUS"
stub tailscale 'echo "STUB-CALLED: tailscale $*" >&2; exit 97'
capture "$OMA/omarchy-tailscale-send" box.tail1.ts.net "$DL/a.txt" "$DL/b.txt" --dry-run
assert_dry_pure "send" "$OUTPUT"
assert_contains "send copies with Taildrop" "$OUTPUT" "DRYRUN: tailscale file cp --update-interval=0 -- $DL/a.txt $DL/b.txt box.tail1.ts.net:"
stub tailscale 'echo "tailscale $*" >>"'"$LOG"'"'
capture "$OMA/omarchy-tailscale-send" box.tail1.ts.net "$DL/a.txt" "$DL/b.txt"
assert_status "send" 0 "$STATUS"
assert_contains "the transfer runs" "$(cat "$LOG")" "tailscale file cp --update-interval=0 -- $DL/a.txt $DL/b.txt box.tail1.ts.net:"
assert_contains "success names the short machine name" "$(cat "$LOG")" "Sent to box 2 files"
stub tailscale 'echo "no such peer" >&2; exit 1'
capture "$OMA/omarchy-tailscale-send" box "$DL/a.txt"
assert_status "a failed transfer fails" 1 "$STATUS"
assert_contains "and is announced with the reason" "$(cat "$LOG")" "-u critical -- Could not send to box no such peer"
