# shellcheck shell=bash
# haseen:covers bin/haseen-setup-boot-menu bin/haseen-system share/haseen/default/hypr/binds.lua
# haseen:covers share/haseen/default/systemd/system/** share/haseen/default/systemd/system.conf.d/**
# haseen:covers share/haseen/lib/{boot,bootmenu,limine-header,screen}.sh share/haseen/layers/base/layer.sh
# haseen:covers share/haseen/layers/secureboot/secureboot.sh share/haseen/omarchy/bin/omarchy-system
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# Omarchy 4.5's boot and logout changes (plan 104): the root= guard before
# haseen's Limine drop-ins (and the seed of a new /etc/kernel/cmdline), the
# binfmt and mount-event drop-ins, closing apps before logout, reboot and
# shutdown, and the opt-in 1-second boot menu. Every run below is a dry run
# against a sysroot, or a real run against scratch files and stubs.
sandbox omarchy45-boot
GUID=8be4df61-93ca-11d2-aa0d-00e098032b8c

# limine_root NAME CMDLINE — a Limine machine: an ESP with a limine.conf, no
# KERNEL_CMDLINE anywhere, /proc/cmdline as given. Callers add the layers.
limine_root() {
    local root="$SANDBOX/$1"
    rm -rf "$root"
    mkdir -p "$root/etc/limine-entry-tool.d" "$root/etc/default" "$root/proc" \
        "$root/boot/EFI/limine" "$root/sys/firmware/efi/efivars" "$root/var/lib/pacman/local"
    printf 'timeout: 3\n#quiet: yes\n\n/+CachyOS\n    comment: machine-id=0\n    //linux\n        protocol: linux\n' \
        >"$root/boot/limine.conf"
    printf 'MZ fixture Limine EFI binary\n++CONFIG_B2SUM_SIGNATURE++%0128d\n' 0 >"$root/boot/EFI/limine/limine_x64.efi"
    printf 'ESP_PATH="/boot"\n' >"$root/etc/default/limine"
    printf '%s\n' "$2" >"$root/proc/cmdline"
    efivar "$root" SecureBoot 0
    efivar "$root" SetupMode 0
    printf '%s\n' "$root"
}
efivar() { printf '\x06\x00\x00\x00\x0'"$3" >"$1/sys/firmware/efi/efivars/$2-$GUID"; }
installed() { mkdir -p "$1/var/lib/pacman/local/$2-1-1" && printf '%%NAME%%\n%s\n' "$2" >"$1/var/lib/pacman/local/$2-1-1/desc"; }

# add ROOT NAME ARGS — boot_cmdline_add as haseen plymouth set calls it, dry.
add() {
    (
        export HASEEN_SYSROOT="$1" DRY_RUN=true
        unset BOOTLOADER
        # shellcheck source=../share/haseen/lib/boot.sh
        source "$HASEEN_PATH/lib/boot.sh"
        boot_cmdline_add "$2" "${@:3}"
    )
}

# --- Limine: the layers merged as limine-entry-tool merges them --------------
# Omarchy's fixture cases for the same check (test/shell.d/
# upgrade-to-quattro-test.sh@v4.5.0-rc1:298-322; MIT, Copyright (c) David
# Heinemeier Hansson), each a layer and a line.
merged_root() { # LAYER LINE [LAYER LINE...] — exit 0 when root= is stated
    local root
    root="$(limine_root merge 'quiet')"
    while (($#)); do
        mkdir -p "$(dirname "$root/$1")"
        printf '%s\n' "$2" >>"$root/$1"
        shift 2
    done
    (
        export HASEEN_SYSROOT="$root"
        source "$HASEEN_PATH/lib/boot.sh"
        boot_limine_merge && boot_cmdline_states root "$BOOT_LIMINE_CMDLINE"
    )
}
pin_case() { # LABEL EXPECT(0|1) LAYER LINE...
    local label="$1" want="$2" got=0
    shift 2
    merged_root "$@" || got=1
    assert_eq "merge: $label" "$want" "$got"
}
pin_case "a quoted root= pin" 0 etc/default/limine 'KERNEL_CMDLINE[default]+=" root=UUID=abc rw"'
pin_case "an unquoted root= pin" 0 etc/default/limine 'KERNEL_CMDLINE[default]=root=UUID=abc'
pin_case "a quoted parameter before root=" 0 etc/default/limine 'KERNEL_CMDLINE[default]+=" dm-mod.create="foo" root=UUID=abc rw"'
pin_case "an appending layer keeps an earlier pin" 0 \
    usr/share/limine-entry-tool.d/root.conf 'KERNEL_CMDLINE[default]+="root=UUID=abc"' etc/default/limine 'KERNEL_CMDLINE[default]+=" rw"'
pin_case "spaces around +=" 0 etc/default/limine 'KERNEL_CMDLINE[default] += " root=UUID=abc rw"'
pin_case "a pin in an /etc drop-in" 0 etc/limine-entry-tool.d/10-root.conf 'KERNEL_CMDLINE[default]+=" root=UUID=abc"'
pin_case "single quotes stay, as the tool keeps them" 1 etc/default/limine "KERNEL_CMDLINE[default]+='root=UUID=abc rw'"
pin_case "a renamed key is no pin" 1 etc/default/limine 'OLD_KERNEL_CMDLINE[default]+=" root=UUID=abc rw"'
pin_case "a commented-out pin is no pin" 1 etc/default/limine '# KERNEL_CMDLINE[default]+=" root=UUID=abc rw"'
pin_case "a fallback-only pin does not cover default" 1 etc/default/limine 'KERNEL_CMDLINE[fallback]+=" root=UUID=abc rw"'
pin_case "rootflags= is not root=" 1 etc/default/limine 'KERNEL_CMDLINE[default]+=" rootflags=subvol=@ rw"'
pin_case "root= inside a quoted value" 1 etc/default/limine 'KERNEL_CMDLINE[default]+=" systemd.setenv="root=UUID=abc" rw"'
pin_case "root= after a space inside a quoted value" 1 etc/default/limine 'KERNEL_CMDLINE[default]+=" systemd.setenv="NOTE=x root=UUID=abc" rw"'
pin_case "root= after an unmatched quote" 1 etc/default/limine 'KERNEL_CMDLINE[default]=systemd.setenv="NOTE=x root=UUID=abc rw'
pin_case "a quoted segment inside a parameter name" 1 etc/default/limine 'KERNEL_CMDLINE[default]=ro"x"ot=UUID=abc rw'
pin_case "a pin replaced by a later layer" 1 \
    etc/limine-entry-tool.conf 'KERNEL_CMDLINE[default]=root=UUID=abc rw' etc/default/limine 'KERNEL_CMDLINE[default]=quiet'
pin_case "a pin replaced later in the same layer" 1 \
    etc/default/limine 'KERNEL_CMDLINE[default]+=" root=UUID=abc rw"' etc/default/limine 'KERNEL_CMDLINE[default]="quiet"'
pin_case "/etc/default/limine wins over the drop-ins" 1 \
    etc/limine-entry-tool.d/root.conf 'KERNEL_CMDLINE[default]+=" root=UUID=abc"' etc/default/limine 'KERNEL_CMDLINE[default]=quiet'

# --- Limine: boot_cmdline_add keeps root= ------------------------------------
# Stated in /etc/default/limine (a CachyOS install): only the drop-in.
root="$(limine_root stated 'root=UUID=abc rw quiet')"
printf 'KERNEL_CMDLINE[default]+="root=UUID=abc rw"\n' >>"$root/etc/default/limine"
capture add "$root" plymouth quiet splash
assert_status "root= stated: written" 0 "$STATUS"
assert_dry_pure "root= stated" "$OUTPUT"
assert_contains "root= stated: the drop-in" "$OUTPUT" "DRYRUN: write /etc/limine-entry-tool.d/haseen-plymouth.conf"
assert_not_contains "root= stated: no pin" "$OUTPUT" "haseen-cmdline.conf"

# No layer sets the key: limine-entry-tool reads /proc/cmdline, so all of it
# is pinned (BOOT_IMAGE= aside) before the drop-in that ends the fallback.
root="$(limine_root fallback 'BOOT_IMAGE=/vmlinuz root=UUID=abc rw rootflags=subvol=/@ nvidia-drm.modeset=1')"
capture add "$root" plymouth quiet splash
assert_status "fallback: written" 0 "$STATUS"
assert_dry_pure "fallback" "$OUTPUT"
assert_contains "fallback: the whole line is pinned" "$OUTPUT" \
    'KERNEL_CMDLINE[default]+=" root=UUID=abc rw rootflags=subvol=/@ nvidia-drm.modeset=1"'
assert_not_contains "fallback: without the loader's BOOT_IMAGE=" "$OUTPUT" "BOOT_IMAGE"
pin_at="$(grep -n 'haseen-cmdline.conf (mode' <<<"$OUTPUT" | cut -d: -f1)"
dropin_at="$(grep -n 'haseen-plymouth.conf (mode' <<<"$OUTPUT" | cut -d: -f1)"
[[ -n $pin_at && -n $dropin_at ]] && ((pin_at < dropin_at)) && _pass || _fail "fallback: the pin is written before the drop-in"
assert_contains "fallback: says where it came from" "$OUTPUT" "pinning it from /proc/cmdline"

# /etc/kernel/cmdline is the fallback when it exists.
mkdir -p "$root/etc/kernel"
printf '# comment\nroot=UUID=kern rw\nquiet\n' >"$root/etc/kernel/cmdline"
capture add "$root" plymouth quiet splash
assert_contains "kernel/cmdline: pinned from it" "$OUTPUT" 'KERNEL_CMDLINE[default]+=" root=UUID=kern rw quiet"'
assert_contains "kernel/cmdline: says so" "$OUTPUT" "pinning it from /etc/kernel/cmdline"

# A += layer already ended the fallback (Omarchy's omarchy-defaults.conf) and
# none states root=: the running kernel's root parameters are pinned, not
# its resume=, which haseen's hibernation drop-in owns.
root="$(limine_root omarchy-plus 'quiet rd.luks.uuid=1234 root=/dev/mapper/luks-1234 rw rootflags=subvol=/@ resume=/dev/x splash')"
printf 'KERNEL_CMDLINE[default]+=" quiet splash"\n' >"$root/etc/limine-entry-tool.d/omarchy-defaults.conf"
capture add "$root" resume resume=/dev/mapper/root resume_offset=1
assert_status "a += layer: written" 0 "$STATUS"
assert_contains "a += layer: the root parameters are pinned" "$OUTPUT" \
    'KERNEL_CMDLINE[default]+=" rd.luks.uuid=1234 root=/dev/mapper/luks-1234 rw rootflags=subvol=/@"'
assert_contains "a += layer: then the drop-in" "$OUTPUT" 'KERNEL_CMDLINE[default]+=" resume=/dev/mapper/root resume_offset=1"'

# A pin from an earlier run counts: nothing more is pinned.
printf 'KERNEL_CMDLINE[default]+=" root=/dev/mapper/luks-1234 rw"\n' >"$root/etc/limine-entry-tool.d/haseen-cmdline.conf"
capture add "$root" resume resume=/dev/mapper/root resume_offset=1
assert_not_contains "an existing pin: not pinned again" "$OUTPUT" "haseen-cmdline.conf (mode"

# Refusals: nothing is written.
root="$(limine_root no-root 'quiet splash')"
capture add "$root" plymouth quiet splash
assert_status "no root= anywhere: refused" 1 "$STATUS"
assert_contains "no root= anywhere: says how to fix it" "$OUTPUT" "KERNEL_CMDLINE[default]+=\" root=… rw\""
assert_not_contains "no root= anywhere: nothing written" "$OUTPUT" "DRYRUN"
root="$(limine_root replaced 'root=UUID=abc rw')"
printf 'KERNEL_CMDLINE[default]=quiet\n' >>"$root/etc/default/limine"
capture add "$root" plymouth quiet splash
assert_status "a later = without root=: refused" 1 "$STATUS"
assert_contains "a later = without root=: names the file" "$OUTPUT" "/etc/default/limine replaces KERNEL_CMDLINE[default]"
assert_not_contains "a later = without root=: nothing written" "$OUTPUT" "DRYRUN"
root="$(limine_root snapshot 'root=UUID=abc rw rootflags=subvol=/@/.snapshots/12/snapshot')"
capture add "$root" plymouth quiet splash
assert_status "a snapshot boot: refused" 1 "$STATUS"
assert_contains "a snapshot boot: says so" "$OUTPUT" "this boot is a snapshot"
assert_not_contains "a snapshot boot: nothing written" "$OUTPUT" "DRYRUN"
root="$(limine_root unreadable 'root=UUID=abc rw')"
printf 'KERNEL_CMDLINE[default]+=" quiet"\n' >"$root/etc/limine-entry-tool.d/private.conf"
chmod 000 "$root/etc/limine-entry-tool.d/private.conf"
if [[ -r $root/etc/limine-entry-tool.d/private.conf ]]; then
    _pass # running as root: nothing is unreadable
else
    capture add "$root" plymouth quiet splash
    assert_status "an unreadable layer: refused" 1 "$STATUS"
    assert_contains "an unreadable layer: named" "$OUTPUT" "cannot read /etc/limine-entry-tool.d/private.conf"
fi
chmod 644 "$root/etc/limine-entry-tool.d/private.conf"

# haseen doctor's hint (plan 111): the pin is kept once written, so a root
# device that changed since leaves it naming the old one. The root= the merged
# config gives the next image is compared with this boot's.
pin_report() { # ROOT — boot_limine_pin_report under ROOT
    capture env HASEEN_SYSROOT="$1" bash -c 'source "$HASEEN_PATH/lib/boot.sh"; boot_limine_pin_report'
}
PIN=/etc/limine-entry-tool.d/haseen-cmdline.conf
root="$(limine_root pin-report 'BOOT_IMAGE=/vmlinuz root=UUID=new rw quiet')"
pin_report "$root"
assert_eq "doctor, no pin: nothing to say" "" "$OUTPUT"
printf '# Written by haseen\nKERNEL_CMDLINE[default]+=" root=UUID=new rw quiet"\n' >"$root$PIN"
pin_report "$root"
assert_eq "doctor, the pin names this boot's root=" "limine root pin=ok (root=UUID=new, as this boot)" "$OUTPUT"
printf '# Written by haseen\nKERNEL_CMDLINE[default]+=" root=UUID=old rw quiet"\n' >"$root$PIN"
pin_report "$root"
assert_contains "doctor, a stale pin: both named" "$OUTPUT" \
    "limine root pin=differs: the next boot image gets root=UUID=old ($PIN pins root=UUID=old), but this boot used root=UUID=new."
assert_contains "doctor, a stale pin: how to refresh it" "$OUTPUT" \
    "set root=UUID=new in $PIN (sudoedit it), then rebuild (sudo limine-mkinitcpio)"
assert_contains "doctor, a stale pin: a hint, not a verdict" "$OUTPUT" "if both name the same device, nothing is wrong"
capture env HASEEN_SYSROOT="$root" haseen doctor
assert_contains "haseen doctor prints it" "$OUTPUT" "limine root pin=differs: the next boot image gets root=UUID=old"
# A later layer that states this boot's root= wins over the pin.
printf 'KERNEL_CMDLINE[default]+=" root=UUID=new"\n' >>"$root/etc/default/limine"
pin_report "$root"
assert_eq "doctor, a later layer's root= wins: ok" "limine root pin=ok (root=UUID=new, as this boot)" "$OUTPUT"
# A later layer that states another one: that layer is the one to change.
printf 'KERNEL_CMDLINE[default]+=" root=UUID=new"\n' >"$root$PIN"
printf 'ESP_PATH="/boot"\nKERNEL_CMDLINE[default]+=" root=UUID=other"\n' >"$root/etc/default/limine"
pin_report "$root"
assert_contains "doctor, a later layer's stale root=: it is named, not the pin" "$OUTPUT" \
    "the next boot image gets root=UUID=other ($PIN pins root=UUID=new), but this boot used root=UUID=new. If the root device changed, set root=UUID=new in the layer of Limine's config after the pin"
printf 'ESP_PATH="/boot"\n' >"$root/etc/default/limine"
printf 'quiet splash\n' >"$root/proc/cmdline"
pin_report "$root"
assert_eq "doctor, this boot states no root=: unknown" "limine root pin=unknown: this boot's command line states no root=" "$OUTPUT"
printf 'root=UUID=new rw\n' >"$root/proc/cmdline"
chmod 000 "$root$PIN"
if [[ -r $root$PIN ]]; then
    _pass # running as root: nothing is unreadable
else
    pin_report "$root"
    assert_eq "doctor, an unreadable layer: unknown" "limine root pin=unknown: a Limine config layer cannot be read" "$OUTPUT"
fi
chmod 644 "$root$PIN"

# A later `=` that states root= replaces the drop-in: written, but status 2
# and the caller is told to add the words there.
root="$(limine_root moot 'root=UUID=abc rw')"
printf 'KERNEL_CMDLINE[default]="root=UUID=abc rw quiet"\n' >>"$root/etc/default/limine"
capture add "$root" plymouth quiet splash
assert_status "a replacing = with root=: status 2" 2 "$STATUS"
assert_contains "a replacing = with root=: explains" "$OUTPUT" "has no effect: add 'quiet splash' to that line yourself"

# The callers take the guard as is: haseen plymouth set on a fallback machine
# pins before its drop-in.
root="$(limine_root plymouth 'root=UUID=abc rw')"
printf 'HOOKS=(base udev autodetect modconf kms keyboard block filesystems fsck)\n' >"$root/etc/mkinitcpio.conf"
mkdir -p "$root/usr/bin" "$root/etc/plymouth"
printf '#!/bin/sh\nexit 0\n' >"$root/usr/bin/plymouth-set-default-theme"
chmod +x "$root/usr/bin/plymouth-set-default-theme"
capture env HASEEN_SYSROOT="$root" haseen plymouth set --theme kanagawa --no-rebuild --dry-run
assert_status "plymouth set: dry run" 0 "$STATUS"
assert_dry_pure "plymouth set" "$OUTPUT"
assert_contains "plymouth set: the pin" "$OUTPUT" "DRYRUN: write /etc/limine-entry-tool.d/haseen-cmdline.conf"
assert_contains "plymouth set: its drop-in" "$OUTPUT" "DRYRUN: write /etc/limine-entry-tool.d/haseen-plymouth.conf"

# --- systemd-boot: a new /etc/kernel/cmdline starts from the fallback --------
sdroot="$SANDBOX/sdboot"
mkdir -p "$sdroot/proc" "$sdroot/etc"
sd_add() { (
    export HASEEN_SYSROOT="$sdroot" DRY_RUN=true BOOTLOADER=systemd-boot
    source "$HASEEN_PATH/lib/boot.sh"
    boot_cmdline_add plymouth quiet splash
); }
printf 'BOOT_IMAGE=/vmlinuz-linux initrd=\\amd-ucode.img root=UUID=abc rw\n' >"$sdroot/proc/cmdline"
capture sd_add
assert_status "systemd-boot seed: written" 0 "$STATUS"
assert_contains "systemd-boot seed: from /proc/cmdline, loader words dropped" "$OUTPUT" "| root=UUID=abc rw quiet splash"
mkdir -p "$sdroot/usr/lib/kernel"
printf 'root=UUID=lib ro\n' >"$sdroot/usr/lib/kernel/cmdline"
capture sd_add
assert_contains "systemd-boot seed: /usr/lib/kernel/cmdline first" "$OUTPUT" "| root=UUID=lib ro quiet splash"
rm -r "$sdroot/usr/lib/kernel"
mkdir -p "$sdroot/etc/kernel"
printf 'root=UUID=etc rw\n' >"$sdroot/etc/kernel/cmdline"
capture sd_add
assert_contains "systemd-boot: an existing file is kept" "$OUTPUT" "| root=UUID=etc rw quiet splash"
rm -r "$sdroot/etc/kernel"
printf 'root=UUID=abc rw archisobasedir=arch\n' >"$sdroot/proc/cmdline"
capture sd_add
assert_status "systemd-boot seed: a live medium is refused" 1 "$STATUS"
assert_not_contains "systemd-boot seed: nothing written" "$OUTPUT" "DRYRUN"

# --- boot drop-ins (base layer) ----------------------------------------------
dropins() { # ROOT FUNCTION
    (
        export HASEEN_SYSROOT="$1" DRY_RUN=true
        source "$HASEEN_PATH/lib/boot.sh"
        "$2"
    )
}
SD="$HASEEN_PATH/default/systemd"
assert_contains "binfmt is mounted before registration" "$(<"$SD/system/systemd-binfmt.service.d/10-haseen-eager-mount.conf")" \
    "Wants=proc-sys-fs-binfmt_misc.mount"
assert_contains "with the automount's conditions" "$(<"$SD/system/proc-sys-fs-binfmt_misc.mount.d/10-haseen-conditions.conf")" \
    $'ConditionPathExists=/proc/sys/fs/binfmt_misc/\nConditionPathIsReadWrite=/proc/sys/'
assert_contains "mount events: 30 a second" "$(<"$SD/system.conf.d/20-haseen-mount-events.conf")" \
    "ManagerEnvironment=SYSTEMD_DEFAULT_MOUNT_RATE_LIMIT_BURST=30"
for f in "$SD"/system/*/*.conf "$SD"/system.conf.d/*.conf; do
    assert_contains "${f#"$SD/"}: keeps Omarchy's notice" "$(<"$f")" "MIT, Copyright (c) David Heinemeier Hansson"
done

droot="$SANDBOX/dropins"
mkdir -p "$droot/etc/systemd/system"
capture dropins "$droot" boot_dropins_apply
assert_dry_pure "drop-ins: apply" "$OUTPUT"
for rel in system/systemd-binfmt.service.d/10-haseen-eager-mount.conf \
    system/proc-sys-fs-binfmt_misc.mount.d/10-haseen-conditions.conf system.conf.d/20-haseen-mount-events.conf; do
    assert_contains "drop-ins: installs $rel" "$OUTPUT" "DRYRUN: sudo install -Dm0644 $SD/$rel /etc/systemd/$rel"
done
assert_contains "drop-ins: reloads systemd once" "$OUTPUT" "DRYRUN: sudo systemctl daemon-reload"
capture dropins "$droot" boot_dropins_status
assert_eq "drop-ins: three missing" 3 "$(grep -c '^missing ' <<<"$OUTPUT")"

# Installed and current: nothing to do.
for rel in system/systemd-binfmt.service.d/10-haseen-eager-mount.conf \
    system/proc-sys-fs-binfmt_misc.mount.d/10-haseen-conditions.conf system.conf.d/20-haseen-mount-events.conf; do
    mkdir -p "$(dirname "$droot/etc/systemd/$rel")"
    cp "$SD/$rel" "$droot/etc/systemd/$rel"
done
capture dropins "$droot" boot_dropins_apply
assert_eq "drop-ins: current, nothing done" "" "$OUTPUT"

# omarchy-settings 4.5 installs Omarchy's copies: haseen's go, once.
: >"$droot/etc/systemd/system/systemd-binfmt.service.d/10-eager-mount.conf"
: >"$droot/etc/systemd/system.conf.d/20-mount-events.conf"
capture dropins "$droot" boot_dropins_apply
assert_contains "drop-ins: Omarchy's binfmt copy wins" "$OUTPUT" \
    "DRYRUN: sudo rm -f /etc/systemd/system/systemd-binfmt.service.d/10-haseen-eager-mount.conf"
assert_contains "drop-ins: Omarchy's mount-event copy wins" "$OUTPUT" \
    "DRYRUN: sudo rm -f /etc/systemd/system.conf.d/20-haseen-mount-events.conf"
assert_not_contains "drop-ins: the conditions copy stays (no twin)" "$OUTPUT" "10-haseen-conditions.conf"
rm "$droot/etc/systemd/system/systemd-binfmt.service.d/10-haseen-eager-mount.conf" \
    "$droot/etc/systemd/system.conf.d/20-haseen-mount-events.conf"
capture dropins "$droot" boot_dropins_apply
assert_eq "drop-ins: with Omarchy's copies alone, nothing added" "" "$OUTPUT"
capture dropins "$droot" boot_dropins_status
assert_eq "drop-ins: two are Omarchy's" 2 "$(grep -c '^omarchy ' <<<"$OUTPUT")"
echo changed >>"$droot/etc/systemd/system/proc-sys-fs-binfmt_misc.mount.d/10-haseen-conditions.conf"
capture dropins "$droot" boot_dropins_apply
assert_contains "drop-ins: a stale copy is replaced" "$OUTPUT" \
    "DRYRUN: sudo install -Dm0644 $SD/system/proc-sys-fs-binfmt_misc.mount.d/10-haseen-conditions.conf"

# The base layer reports and applies them.
capture env HASEEN_SYSROOT="$droot" haseen layer status base
assert_contains "base status: a stale drop-in" "$OUTPUT" \
    "warn: boot drop-in /etc/systemd/system/proc-sys-fs-binfmt_misc.mount.d/10-haseen-conditions.conf is stale"
assert_contains "base status: Omarchy's copy counts" "$OUTPUT" \
    "ok: boot drop-in /etc/systemd/system.conf.d/20-haseen-mount-events.conf (Omarchy's copy in /etc/systemd/system.conf.d instead)"
assert_contains "base apply runs the step" "$(sed -n '/^layer_apply()/,/^}/p' "$HASEEN_PATH/layers/base/layer.sh")" "base_boot_dropins"

# --- haseen system: close apps first -----------------------------------------
LOG="$SANDBOX/calls.log"
: >"$LOG"
# Two apps, one with two windows, and the terminal this test runs in ($$, an
# ancestor of every command it starts).
cat >"$SANDBOX/clients.json" <<EOF
[{"address":"0xa1","pid":4101},{"address":"0xa2","pid":4101},{"address":"0xb1","pid":4202},
 {"address":"0xd1","pid":-1},{"address":"0xc1","pid":$$}]
EOF
stub hyprctl 'echo "hyprctl $*" >>"'"$LOG"'"
case "$1" in
clients) cat "'"$SANDBOX"'/clients.json" ;;
status) echo "{\"configProvider\":\"lua\"}" ;;
*) echo ok ;;
esac'
stub pidwait 'echo "pidwait $*" >>"'"$LOG"'"'
stub systemctl 'echo "systemctl $*" >>"'"$LOG"'"'
stub uwsm 'echo "uwsm $*" >>"'"$LOG"'"'

capture env HYPRLAND_INSTANCE_SIGNATURE=test haseen system reboot --dry-run
assert_status "reboot dry run" 0 "$STATUS"
assert_dry_pure "reboot" "$OUTPUT"
assert_contains "every app window is asked to close" "$OUTPUT" \
    'DRYRUN: hyprctl dispatch hl.dsp.window.close({ window = "address:0xa1" })'
assert_contains "the second app too" "$OUTPUT" 'hl.dsp.window.close({ window = "address:0xb1" })'
assert_contains "a window without a process id is closed too" "$OUTPUT" 'hl.dsp.window.close({ window = "address:0xd1" })'
assert_not_contains "the terminal it runs in stays open" "$OUTPUT" "0xc1"
assert_contains "then it waits 2 s at most, once per process" "$OUTPUT" "DRYRUN: timeout 2s pidwait --euid $UID --pid 4101,4202"
assert_contains "then it reboots" "$OUTPUT" "DRYRUN: systemctl reboot"
close_at="$(grep -n 'pidwait' <<<"$OUTPUT" | cut -d: -f1)"
act_at="$(grep -n 'systemctl reboot' <<<"$OUTPUT" | cut -d: -f1)"
((close_at < act_at)) && _pass || _fail "the apps close before the reboot"
assert_eq "a dry run dispatches nothing" "" "$(grep -v 'hyprctl \(clients\|status\)' "$LOG")"

capture env HYPRLAND_INSTANCE_SIGNATURE=test haseen system logout --dry-run
assert_contains "logout closes the apps too" "$OUTPUT" "DRYRUN: timeout 2s pidwait"
assert_contains "then ends the uwsm session" "$OUTPUT" "DRYRUN: uwsm stop"
capture env HYPRLAND_INSTANCE_SIGNATURE=test haseen system shutdown --dry-run
assert_contains "shutdown closes the apps too" "$OUTPUT" "DRYRUN: timeout 2s pidwait"
assert_contains "then powers off" "$OUTPUT" "DRYRUN: systemctl poweroff"
capture env HYPRLAND_INSTANCE_SIGNATURE=test haseen system suspend --dry-run
assert_eq "suspend closes nothing" "DRYRUN: systemctl suspend" "$OUTPUT"
capture env HYPRLAND_INSTANCE_SIGNATURE=test haseen system lock --dry-run
assert_not_contains "lock closes nothing" "$OUTPUT" "pidwait"
capture haseen system reboot --dry-run
assert_eq "without a Hyprland session: nothing to close" "DRYRUN: systemctl reboot" "$OUTPUT"

# A legacy (non-Lua) Hyprland takes the old dispatcher.
stub hyprctl 'case "$1" in clients) cat "'"$SANDBOX"'/clients.json" ;; status) exit 1 ;; *) echo ok ;; esac'
capture env HYPRLAND_INSTANCE_SIGNATURE=test haseen system reboot --dry-run
assert_contains "legacy Hyprland: closewindow" "$OUTPUT" "DRYRUN: hyprctl dispatch closewindow address:0xa1"

# For real, with every effect stubbed: the windows close, the wait is
# bounded, and the reboot follows even when an app will not exit.
stub hyprctl 'echo "hyprctl $*" >>"'"$LOG"'"
case "$1" in clients) cat "'"$SANDBOX"'/clients.json" ;; status) echo "{\"configProvider\":\"lua\"}" ;; *) echo ok ;; esac'
stub pidwait 'echo "pidwait $*" >>"'"$LOG"'"; exec sleep 30'
: >"$LOG"
start=$SECONDS
capture env HYPRLAND_INSTANCE_SIGNATURE=test haseen system reboot
elapsed=$((SECONDS - start))
assert_status "reboot" 0 "$STATUS"
assert_eq "four windows closed, the terminal's kept" 4 "$(grep -c 'dispatch hl.dsp.window.close' "$LOG")"
assert_contains "the wait names both processes" "$(cat "$LOG")" "pidwait --euid $UID --pid 4101,4202"
assert_contains "the reboot follows" "$(cat "$LOG")" "systemctl reboot"
((elapsed <= 5)) && _pass || _fail "a hung app delays the reboot about 2 s, not $elapsed s"
assert_eq "the dispatch output stays quiet" "" "$OUTPUT"

# Omarchy 4.5's omarchy-system (plan 102) reaches the same code: logout is
# haseen system logout, and shutdown's last stage execs haseen system.
OMA="$HASEEN_PATH/omarchy/bin"
stub pidwait 'echo "pidwait $*" >>"'"$LOG"'"'
capture env HYPRLAND_INSTANCE_SIGNATURE=test "$OMA/omarchy-system" logout --dry-run
assert_contains "omarchy-system logout closes the apps first" "$OUTPUT" "DRYRUN: timeout 2s pidwait"
assert_contains "and ends the session" "$OUTPUT" "DRYRUN: uwsm stop"
capture env HYPRLAND_INSTANCE_SIGNATURE=test "$OMA/omarchy-system-shutdown" --inhibited --dry-run
assert_contains "omarchy-system shutdown's last stage waits for the apps" "$OUTPUT" "DRYRUN: timeout 2s pidwait"
assert_contains "and powers off through haseen" "$OUTPUT" "DRYRUN: systemctl poweroff"

# The log-out key goes through haseen system too.
assert_contains "SUPER + SHIFT + ESCAPE logs out through haseen system" \
    "$(<"$HASEEN_PATH/default/hypr/binds.lua")" 'b("SUPER + SHIFT + ESCAPE", "Log out", "haseen system logout")'

# --- the boot menu: limine.conf's header --------------------------------------
bm() { # FUNCTION ARGS — a bootmenu.sh function
    (
        source "$HASEEN_PATH/lib/bootmenu.sh"
        "$@"
    )
}
BMD="$SANDBOX/bm"
mkdir -p "$BMD"
# limine-entry-tool's own header (the template its binary writes into a new
# limine.conf) and Omarchy 4.0.6's (default/limine/limine.conf@v4.0.6:2).
printf '### Hide Limine\n#quiet: yes\ntimeout: 3\ndefault_entry: 2\n\n/+CachyOS\n    //linux\n        protocol: linux\n' >"$BMD/cachyos.conf"
printf '### Read more\n#timeout: 3\ndefault_entry: 2\nhash_mismatch_panic: no\n\n/+Omarchy\n    //linux\n' >"$BMD/omarchy.conf"
printf 'default_entry: 1\n/Arch\n    protocol: linux\n' >"$BMD/bare.conf"
for f in cachyos omarchy bare; do
    assert_eq "layout: $f.conf is one haseen edits" "" "$(bm bootmenu_problems "$BMD/$f.conf")"
done
assert_eq "render: limine-entry-tool's header" \
    $'### Hide Limine\n#quiet: yes\ntimeout: 1\nquiet: yes\ndefault_entry: 2\n\n/+CachyOS\n    //linux\n        protocol: linux' \
    "$(bm bootmenu_render "$BMD/cachyos.conf" 1 yes)"
assert_eq "render: Omarchy 4.0.6's header" \
    $'timeout: 1\nquiet: yes\n### Read more\n#timeout: 3\ndefault_entry: 2\nhash_mismatch_panic: no\n\n/+Omarchy\n    //linux' \
    "$(bm bootmenu_render "$BMD/omarchy.conf" 1 yes)"
bm bootmenu_render "$BMD/cachyos.conf" 1 yes >"$BMD/fast.conf"
assert_eq "render: twice changes nothing" "$(cat "$BMD/fast.conf")" "$(bm bootmenu_render "$BMD/fast.conf" 1 yes)"
assert_eq "render: the recorded values put the file back" "$(cat "$BMD/cachyos.conf")" "$(bm bootmenu_render "$BMD/fast.conf" 3 -)"
assert_eq "render: quiet alone, first" $'quiet: yes\ndefault_entry: 1\n/Arch\n    protocol: linux' \
    "$(bm bootmenu_render "$BMD/bare.conf" - yes)"
assert_eq "value: absent" "-" "$(bm bootmenu_value timeout "$BMD/omarchy.conf")"
assert_eq "value: case-insensitive key" "4" "$(printf 'TIMEOUT: 4\n/x\n' >"$BMD/u.conf" && bm bootmenu_value timeout "$BMD/u.conf")"

layout() { # LABEL TEXT NEEDLE
    printf '%b' "$2" >"$BMD/bad.conf"
    assert_contains "layout refused: $1" "$(bm bootmenu_problems "$BMD/bad.conf")" "$3"
}
layout "no entry" 'timeout: 3\n' "no menu entry"
layout "two timeouts" 'timeout: 3\ntimeout: 4\n/x\n' "sets timeout: more than once (lines 1 2)"
layout "two quiets" 'quiet: yes\n/x\nquiet: no\n' "sets quiet: more than once"
layout "a timeout below the first entry" '/x\n    protocol: linux\ntimeout: 3\n' "is not in the header"
layout "an unknown timeout" 'timeout: soon\n/x\n' "its timeout: value 'soon'"
layout "an unknown quiet" 'quiet: maybe\n/x\n' "its quiet: value 'maybe'"
layout "carriage returns" 'timeout: 3\r\n/x\r\n' "carriage-return"
ln -sf "$BMD/cachyos.conf" "$BMD/link.conf"
assert_contains "layout refused: a symbolic link" "$(bm bootmenu_problems "$BMD/link.conf")" "not a regular file"

# The root helper, for real on scratch files: under Limine's lock, through a
# rename, nothing else changed, and it checks the layout again itself.
HELPER="$HASEEN_PATH/lib/limine-header.sh"
cp "$BMD/cachyos.conf" "$BMD/esp.conf"
chmod 640 "$BMD/esp.conf"
capture env HASEEN_SYSROOT="$BMD" "$HELPER" set "$BMD/esp.conf" 1 yes
assert_status "helper: set" 0 "$STATUS"
assert_eq "helper: says what it set" "limine.conf: timeout: 1, quiet: yes" "$OUTPUT"
assert_eq "helper: the rendered file" "$(cat "$BMD/fast.conf")" "$(cat "$BMD/esp.conf")"
assert_eq "helper: the mode is kept" 640 "$(stat -c %a "$BMD/esp.conf")"
[[ -e $BMD/run/lock/boot-partition.lock ]] && _pass || _fail "helper: takes Limine's boot-partition lock"
assert_eq "helper: no temporary file left" "" "$(find "$BMD" -name '*.haseen.*')"
capture env HASEEN_SYSROOT="$BMD" "$HELPER" set "$BMD/esp.conf" 1 yes
assert_eq "helper: again, unchanged" "limine.conf: unchanged" "$OUTPUT"
capture env HASEEN_SYSROOT="$BMD" "$HELPER" restore "$BMD/esp.conf" "$BMD/cachyos.conf"
assert_status "helper: restore" 0 "$STATUS"
cmp -s "$BMD/esp.conf" "$BMD/cachyos.conf" && _pass || _fail "helper: restore puts the bytes back"
printf 'timeout: 3\n/x\ntimeout: 4\n' >"$BMD/bad.conf"
cp "$BMD/bad.conf" "$BMD/bad.orig"
capture env HASEEN_SYSROOT="$BMD" "$HELPER" set "$BMD/bad.conf" 1 yes
assert_status "helper: a layout it does not know" 1 "$STATUS"
cmp -s "$BMD/bad.conf" "$BMD/bad.orig" && _pass || _fail "helper: and leaves it alone"
capture env HASEEN_SYSROOT="$BMD" "$HELPER" set "$BMD/esp.conf" 'soon' yes
assert_status "helper: a value it does not write" 1 "$STATUS"
capture env HASEEN_SYSROOT="$BMD" "$HELPER" frob "$BMD/esp.conf"
assert_status "helper: usage" 2 "$STATUS"
# Another Limine tool holds the lock: the helper waits, then gives up untouched.
if command -v flock >/dev/null; then
    (
        exec 9>"$BMD/run/lock/boot-partition.lock"
        flock 9
        sleep 3
    ) &
    holder=$!
    sleep 0.3
    capture env HASEEN_SYSROOT="$BMD" timeout 1 "$HELPER" set "$BMD/esp.conf" 1 yes
    assert_status "helper: waits while the lock is held" 124 "$STATUS"
    cmp -s "$BMD/esp.conf" "$BMD/cachyos.conf" && _pass || _fail "helper: nothing written without the lock"
    wait "$holder" || true
fi

# --- haseen setup boot-menu ----------------------------------------------------
root="$(limine_root menu 'root=UUID=abc rw')"
capture env HASEEN_SYSROOT="$root" haseen setup boot-menu
assert_status "status" 0 "$STATUS"
assert_contains "status: the wait" "$OUTPUT" "timeout: 3 s"
assert_contains "status: the menu shows" "$OUTPUT" "quiet:   not set (the menu shows)"
assert_contains "status: normal" "$OUTPUT" "mode:    normal"
assert_contains "status: nothing recorded" "$OUTPUT" "haseen:  has not changed the menu wait"
assert_contains "status: no hash enrolled" "$OUTPUT" "hash:    none enrolled (/boot/EFI/limine/limine_x64.efi)"

capture env HASEEN_SYSROOT="$root" haseen setup boot-menu fast --dry-run
assert_status "fast" 0 "$STATUS"
assert_dry_pure "fast" "$OUTPUT"
assert_contains "fast: the change" "$OUTPUT" "timeout: 3 s -> 1 s"
assert_contains "fast: backs the file up first" "$OUTPUT" "DRYRUN: sudo install -Dm0600 /boot/limine.conf /var/lib/haseen/boot-menu/limine.conf."
assert_contains "fast: records what it replaces" "$OUTPUT" $'DRYRUN: write /var/lib/haseen/boot-menu/original (mode 0600):\n    | timeout=3\n    | quiet=-'
assert_contains "fast: the helper edits as root" "$OUTPUT" "DRYRUN: sudo $HELPER set /boot/limine.conf 1 yes"
assert_contains "fast: nothing to enroll" "$OUTPUT" "then:    nothing (no config hash is enrolled in Limine)"
backup_at="$(grep -n 'install -Dm0600' <<<"$OUTPUT" | cut -d: -f1)"
edit_at="$(grep -n "$HELPER set" <<<"$OUTPUT" | cut -d: -f1)"
((backup_at < edit_at)) && _pass || _fail "fast: the backup comes before the edit"

# Already fast: nothing to do.
bm bootmenu_render "$root/boot/limine.conf" 1 yes >"$root/boot/limine.new" && mv "$root/boot/limine.new" "$root/boot/limine.conf"
capture env HASEEN_SYSROOT="$root" haseen setup boot-menu fast --dry-run
assert_eq "fast again: nothing to do" "[*] the boot menu already waits 1 second, quietly" "$OUTPUT"
capture env HASEEN_SYSROOT="$root" haseen setup boot-menu normal --dry-run
assert_contains "normal without a record: nothing to put back" "$OUTPUT" "nothing to put back"
assert_not_contains "normal without a record: nothing written" "$OUTPUT" "DRYRUN"

# With haseen's record, normal puts the recorded lines back and forgets them.
mkdir -p "$root/var/lib/haseen/boot-menu"
printf 'timeout=3\nquiet=-\n' >"$root/var/lib/haseen/boot-menu/original"
capture env HASEEN_SYSROOT="$root" haseen setup boot-menu
assert_contains "status: the record" "$OUTPUT" "haseen:  normal puts back timeout: 3 and quiet: -"
capture env HASEEN_SYSROOT="$root" haseen setup boot-menu normal --dry-run
assert_status "normal" 0 "$STATUS"
assert_dry_pure "normal" "$OUTPUT"
assert_contains "normal: the recorded values" "$OUTPUT" "DRYRUN: sudo $HELPER set /boot/limine.conf 3 -"
assert_contains "normal: forgets the record" "$OUTPUT" "DRYRUN: sudo rm -f /var/lib/haseen/boot-menu/original"
assert_not_contains "normal: keeps the record of fast alone" "$OUTPUT" "write /var/lib/haseen/boot-menu/original"
# The owner changed the wait since: theirs stays.
sed -i 's/^timeout: 1$/timeout: 2/' "$root/boot/limine.conf"
capture env HASEEN_SYSROOT="$root" haseen setup boot-menu normal --dry-run
assert_contains "normal after a hand edit: leaves it" "$OUTPUT" "changed after haseen set it (timeout: 2, quiet: yes)"
assert_not_contains "normal after a hand edit: no edit" "$OUTPUT" "$HELPER"
printf 'timeout=soon\nquiet=-\n' >"$root/var/lib/haseen/boot-menu/original"
sed -i 's/^timeout: 2$/timeout: 1/' "$root/boot/limine.conf"
capture env HASEEN_SYSROOT="$root" haseen setup boot-menu normal --dry-run
assert_status "normal: a record haseen did not write is refused" 1 "$STATUS"
rm -r "$root/var/lib/haseen"

# Refusals.
capture env HASEEN_SYSROOT="$root" haseen setup boot-menu fast --yes
assert_status "a real run under HASEEN_SYSROOT is refused" 1 "$STATUS"
assert_contains "and says why" "$OUTPUT" "would edit this machine's limine.conf"
printf 'timeout: 3\n/x\ntimeout: 4\n' >"$root/boot/limine.conf"
capture env HASEEN_SYSROOT="$root" haseen setup boot-menu fast --dry-run
assert_status "an unknown layout is refused" 1 "$STATUS"
assert_contains "with the reason" "$OUTPUT" "sets timeout: more than once"
assert_not_contains "and nothing written" "$OUTPUT" "DRYRUN"
capture env HASEEN_SYSROOT="$root" haseen setup boot-menu
assert_contains "status shows the layout problem" "$OUTPUT" "layout:  not one haseen edits"
printf 'timeout: 3\n/x\n' >"$root/boot/limine.conf"
mkdir -p "$root/boot/EFI/BOOT"
printf '/y\n' >"$root/boot/EFI/BOOT/limine.conf"
capture env HASEEN_SYSROOT="$root" haseen setup boot-menu fast --dry-run
assert_status "a shadowing config is refused" 1 "$STATUS"
assert_contains "and named" "$OUTPUT" "Limine reads /boot/EFI/BOOT/limine.conf before /boot/limine.conf"
rm "$root/boot/EFI/BOOT/limine.conf"
capture env HASEEN_SYSROOT="$FIXTURES/sb-sdboot-enabled" haseen setup boot-menu fast --dry-run
assert_status "systemd-boot is refused" 1 "$STATUS"
assert_contains "for Limine only" "$OUTPUT" "for Limine only"
capture haseen setup boot-menu sideways
assert_status "an unknown verb" 2 "$STATUS"
capture haseen setup boot-menu --help
assert_contains "--help" "$OUTPUT" "Usage: haseen setup boot-menu"

# The ESP is readable only by root: a dry run as a user shows the root step.
if [[ $EUID != 0 ]]; then
    chmod 000 "$root/boot"
    capture env HASEEN_SYSROOT="$root" haseen setup boot-menu fast --dry-run
    chmod 755 "$root/boot"
    assert_status "an unreadable ESP: dry run" 0 "$STATUS"
    assert_contains "an unreadable ESP: says when it is checked" "$OUTPUT" "readable only by root"
    assert_contains "an unreadable ESP: the root step" "$OUTPUT" "DRYRUN: sudo $HELPER set /boot/limine.conf 1 yes"
fi

# Secure Boot: the edited config is enrolled again, the way haseen signs.
enroll_hash() { printf 'MZ fixture\n++CONFIG_B2SUM_SIGNATURE++%s\n' "$(b2sum "$1/boot/limine.conf" | cut -d' ' -f1)" >"$1/boot/EFI/limine/limine_x64.efi"; }
root="$(limine_root sb 'root=UUID=abc rw')"
enroll_hash "$root"
capture env HASEEN_SYSROOT="$root" haseen setup boot-menu
assert_contains "status: an enrolled hash" "$OUTPUT" "hash:    enrolled and current"
capture env HASEEN_SYSROOT="$root" haseen setup boot-menu fast --dry-run
assert_status "enrolled, nothing would enroll it again: refused" 1 "$STATUS"
assert_contains "names ENABLE_ENROLL_LIMINE_CONFIG" "$OUTPUT" "ENABLE_ENROLL_LIMINE_CONFIG is not yes"
assert_not_contains "nothing written" "$OUTPUT" "DRYRUN"
printf 'ENABLE_ENROLL_LIMINE_CONFIG=yes\n' >>"$root/etc/default/limine"
capture env HASEEN_SYSROOT="$root" haseen setup boot-menu fast --dry-run
assert_status "without limine-enroll-config: refused" 1 "$STATUS"
assert_contains "names the package" "$OUTPUT" "limine-mkinitcpio-hook"
installed "$root" limine-mkinitcpio-hook
capture env HASEEN_SYSROOT="$root" haseen setup boot-menu fast --dry-run
assert_status "no Secure Boot keys, Secure Boot off: limine-enroll-config" 0 "$STATUS"
assert_contains "the enroll step" "$OUTPUT" "DRYRUN: sudo limine-enroll-config"
edit_at="$(grep -n "$HELPER set" <<<"$OUTPUT" | cut -d: -f1)"
enroll_at="$(grep -n 'limine-enroll-config$' <<<"$OUTPUT" | cut -d: -f1)"
((edit_at < enroll_at)) && _pass || _fail "the config is enrolled after the edit"
efivar "$root" SecureBoot 1
capture env HASEEN_SYSROOT="$root" haseen setup boot-menu fast --dry-run
assert_status "Secure Boot on with keys haseen does not hold: refused" 1 "$STATUS"
assert_contains "and why" "$OUTPUT" "keys haseen does not manage"
installed "$root" sbctl
mkdir -p "$root/var/lib/sbctl/keys/db"
: >"$root/var/lib/sbctl/keys/db/db.key"
capture env HASEEN_SYSROOT="$root" haseen setup boot-menu fast --dry-run
assert_status "haseen's Secure Boot keys: haseen secureboot sign" 0 "$STATUS"
assert_dry_pure "secure boot" "$OUTPUT"
assert_contains "the sign step" "$OUTPUT" "DRYRUN: $REPO/bin/haseen-secureboot-sign --yes --dry-run"
printf '\n' >>"$root/boot/limine.conf"
capture env HASEEN_SYSROOT="$root" haseen setup boot-menu
assert_contains "status: a stale hash" "$OUTPUT" "enrolled but stale"

# A real run, with a sudo that records and runs nothing (the same exception
# haseen secureboot setup's tests use): the order of the steps, and the way
# back when enrolling the edited config fails.
root="$(limine_root real 'root=UUID=abc rw')"
printf 'ENABLE_ENROLL_LIMINE_CONFIG=yes\n' >>"$root/etc/default/limine"
installed "$root" limine-mkinitcpio-hook
enroll_hash "$root"
SUDOLOG="$SANDBOX/sudo.log"
recorder() { # FAILS — the first FAILS limine-enroll-config calls fail; FAIL_SET=1 fails the edit
    : >"$SUDOLOG"
    rm -f "$SANDBOX/enrolls"
    stub sudo "printf '%s\n' \"\$*\" >>'$SUDOLOG'
case \"\$*\" in
tee* | 'sh -c'*) cat >/dev/null ;;
limine-enroll-config)
    n=\$(cat '$SANDBOX/enrolls' 2>/dev/null || echo 0)
    n=\$((n + 1))
    echo \$n >'$SANDBOX/enrolls'
    [ \$n -gt ${1:-0} ] || exit 1
    ;;
*'limine-header.sh set'*) [ -z '${FAIL_SET:-}' ] || exit 1 ;;
esac
exit 0"
}
recorder 0
capture env HASEEN_SYSROOT="$root" HASEEN_TEST_STUBBED_SUDO=1 haseen setup boot-menu fast --yes
assert_status "real run" 0 "$STATUS"
steps="$(grep -v '^\(install -d\|chmod\)' "$SUDOLOG")"
assert_eq "real run: backup, record, edit, enroll, in that order" \
    "install -Dm0600 /boot/limine.conf /var/lib/haseen/boot-menu/limine.conf.@
tee /var/lib/haseen/boot-menu/original
$HELPER set /boot/limine.conf 1 yes
limine-enroll-config" "$(sed -E 's/limine\.conf\.[0-9]{8}T[0-9]{6}Z$/limine.conf.@/' <<<"$steps")"

recorder 1
capture env HASEEN_SYSROOT="$root" HASEEN_TEST_STUBBED_SUDO=1 haseen setup boot-menu fast --yes
assert_status "enrolling fails: the command fails" 1 "$STATUS"
assert_contains "enrolling fails: says the wait did not change" "$OUTPUT" "the boot menu's wait was not changed"
backup="$(sed -n 's/^install -Dm0600 \/boot\/limine.conf //p' "$SUDOLOG")"
log="$(cat "$SUDOLOG")"
assert_contains "enrolling fails: the copy goes back" "$log" "$HELPER restore /boot/limine.conf $backup"
assert_contains "enrolling fails: the record of a first fast goes" "$log" "rm -f /var/lib/haseen/boot-menu/original"
assert_eq "enrolling fails: the restored file is enrolled again" 2 "$(grep -cx 'limine-enroll-config' "$SUDOLOG")"
before_restore="${log%%"$HELPER restore"*}"
[[ $before_restore == *"limine-enroll-config"* && $log == *"$HELPER restore"*"limine-enroll-config" ]] && _pass ||
    _fail "enrolling fails: enroll, restore, enroll again"

recorder 2
capture env HASEEN_SYSROOT="$root" HASEEN_TEST_STUBBED_SUDO=1 haseen setup boot-menu fast --yes
assert_status "enrolling fails twice" 1 "$STATUS"
assert_contains "enrolling fails twice: do not reboot" "$OUTPUT" "do not reboot with Secure Boot on until haseen secureboot status is all ok"

FAIL_SET=1 recorder 0
capture env HASEEN_SYSROOT="$root" HASEEN_TEST_STUBBED_SUDO=1 haseen setup boot-menu fast --yes
assert_status "the edit fails" 1 "$STATUS"
assert_contains "the edit fails: says so" "$OUTPUT" "/boot/limine.conf was not changed"
assert_contains "the edit fails: the record goes" "$(cat "$SUDOLOG")" "rm -f /var/lib/haseen/boot-menu/original"
assert_not_contains "the edit fails: nothing is enrolled" "$(cat "$SUDOLOG")" "limine-enroll-config"

# A sudo outside tests/.out never gets the exception. It is a recorder too,
# so a mistake here cannot reach the real one.
othersudo="$(mktemp -d "${TMPDIR:-/tmp}/othersudo.XXXXXX")"
printf '#!/bin/sh\necho "$*" >>"%s/calls"\nexit 1\n' "$othersudo" >"$othersudo/sudo"
chmod +x "$othersudo/sudo"
capture env HASEEN_SYSROOT="$root" HASEEN_TEST_STUBBED_SUDO=1 PATH="$othersudo:$PATH" haseen setup boot-menu fast --yes
assert_status "another sudo under HASEEN_SYSROOT: refused" 1 "$STATUS"
assert_contains "another sudo under HASEEN_SYSROOT: says why" "$OUTPUT" "would edit this machine's limine.conf"
[[ ! -e $othersudo/calls ]] && _pass || _fail "another sudo under HASEEN_SYSROOT: never called"
rm -rf "$othersudo"
