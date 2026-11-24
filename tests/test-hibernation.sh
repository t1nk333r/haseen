# shellcheck shell=bash
# haseen:covers bin/haseen-hibernation-{setup,status} share/haseen/lib/{boot,hibernate,preflight}.sh
# haseen:covers tests/fixtures/mkinitcpio-omarchy-*/**
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# Hibernation: what the machine needs before it can suspend to disk, and the
# plan that gets it there on a LUKS + btrfs install.
sandbox hibernation

# make_sysroot NAME — a machine: image_size, meminfo, swaps, mkinitcpio hooks,
# bootloader. Callers overwrite the parts they are testing.
make_sysroot() {
    local root="$SANDBOX/$1"
    mkdir -p "$root/sys/power" "$root/proc" "$root/etc/mkinitcpio.conf.d" \
        "$root/etc/limine-entry-tool.d" "$root/etc/default" "$root/boot/EFI/limine"
    : >"$root/boot/EFI/limine/limine_x64.efi"
    echo 13312000000 >"$root/sys/power/image_size"
    echo "[s2idle]" >"$root/sys/power/mem_sleep"
    printf 'MemTotal:       32554964 kB\n' >"$root/proc/meminfo"
    printf 'Filename\t\t\t\tType\t\tSize\t\tUsed\t\tPriority\n' >"$root/proc/swaps"
    printf 'HOOKS=(base udev autodetect modconf kms keyboard block encrypt filesystems fsck)\n' \
        >"$root/etc/mkinitcpio.conf"
    printf 'cryptdevice=PARTUUID=x:root root=/dev/mapper/root rw\n' >"$root/proc/cmdline"
    printf 'ESP_PATH="/boot"\nKERNEL_CMDLINE[default]+="root=/dev/mapper/root rw"\n' \
        >"$root/etc/default/limine"
    printf '%s\n' "$root"
}

add_swap() { # ROOT KIB
    printf '/swap/swapfile                          file\t\t%s\t\t0\t\t0\n' "$2" >>"$1/proc/swaps"
    printf '/dev/zram0                              partition\t32553980\t0\t\t100\n' >>"$1/proc/swaps"
}

# --- a machine with nothing set up -------------------------------------------
plain="$(make_sysroot plain)"
export HASEEN_SYSROOT="$plain"

capture haseen hibernation status
assert_status "a machine without swap is not ready" 1 "$STATUS"
assert_contains "it says the kernel can hibernate" "$OUTPUT" "hibernation supported"
assert_contains "it reports the image limit" "$OUTPUT" "image:     up to 12.4 GiB"
assert_contains "it reports busybox hooks" "$OUTPUT" "busybox hooks"
assert_contains "and that nothing points at an image" "$OUTPUT" "no resume= parameter"
capture haseen hibernation status --quiet
assert_eq "--quiet prints nothing" "" "$OUTPUT"

# --- swap, hook and cmdline, one at a time -----------------------------------
add_swap "$plain" 32554512
capture haseen hibernation status
assert_status "swap alone is not enough" 1 "$STATUS"
assert_contains "the swapfile is seen" "$OUTPUT" "/swap/swapfile"
assert_contains "the resume hook is still missing" "$OUTPUT" "resume hook absent"

printf 'HOOKS+=(resume)\n' >"$plain/etc/mkinitcpio.conf.d/haseen-resume.conf"
capture haseen hibernation status
assert_contains "the resume hook is picked up from a drop-in" "$OUTPUT" "resume hook present"
assert_status "but without resume= it is still not ready" 1 "$STATUS"

printf 'KERNEL_CMDLINE[default]+=" resume=/dev/mapper/root resume_offset=1929459"\n' \
    >"$plain/etc/limine-entry-tool.d/haseen-resume.conf"
capture haseen hibernation status
assert_status "swap + hook + cmdline is ready" 0 "$STATUS"
assert_contains "the offset is reported" "$OUTPUT" "offset 1929459"

# zram cannot hold a hibernation image: it lives in the memory being saved.
zramonly="$(make_sysroot zramonly)"
printf '/dev/zram0                              partition\t32553980\t0\t\t100\n' >>"$zramonly/proc/swaps"
printf 'HOOKS+=(resume)\n' >"$zramonly/etc/mkinitcpio.conf.d/haseen-resume.conf"
printf 'KERNEL_CMDLINE[default]+=" resume=/dev/mapper/root resume_offset=1"\n' \
    >"$zramonly/etc/limine-entry-tool.d/haseen-resume.conf"
HASEEN_SYSROOT="$zramonly" capture haseen hibernation status
assert_status "zram alone is not hibernation swap" 1 "$STATUS"

# The help says what the check compares: swap against image_size, not RAM.
capture haseen hibernation status --help
assert_contains "the help names the image limit swap must hold" "$OUTPUT" "at least /sys/power/image_size"
assert_not_contains "and not RAM's size" "$OUTPUT" "as large as RAM"

# --- resume= only counts where the next boot reads it (plan 188) -----------------
# /etc/default/limine replaces KERNEL_CMDLINE[default] with '=', so the
# drop-in's resume= never reaches the merged line limine-entry-tool writes.
replaced="$(make_sysroot replaced)"
add_swap "$replaced" 32554512
printf 'HOOKS+=(resume)\n' >"$replaced/etc/mkinitcpio.conf.d/haseen-resume.conf"
printf 'ESP_PATH="/boot"\nKERNEL_CMDLINE[default]="root=UUID=abc rw quiet splash"\n' >"$replaced/etc/default/limine"
printf 'KERNEL_CMDLINE[default]+=" resume=/dev/mapper/root resume_offset=123"\n' \
    >"$replaced/etc/limine-entry-tool.d/haseen-resume.conf"
HASEEN_SYSROOT="$replaced" capture haseen hibernation status
assert_status "a drop-in a later '=' replaces: not ready" 1 "$STATUS"
assert_contains "and no resume= is reported" "$OUTPUT" "no resume= parameter"
# The same words in '+=' form do reach it.
printf 'ESP_PATH="/boot"\nKERNEL_CMDLINE[default]+="root=UUID=abc rw quiet splash"\n' >"$replaced/etc/default/limine"
HASEEN_SYSROOT="$replaced" capture haseen hibernation status
assert_status "appended, the drop-in counts" 0 "$STATUS"
assert_contains "with its offset" "$OUTPUT" "offset 123"
printf 'ESP_PATH="/boot"\nKERNEL_CMDLINE[default]="root=UUID=abc rw quiet splash"\n' >"$replaced/etc/default/limine"
# GRUB: a commented-out line is not the command line.
grubroot="$(make_sysroot grub)"
add_swap "$grubroot" 32554512
printf 'HOOKS+=(resume)\n' >"$grubroot/etc/mkinitcpio.conf.d/haseen-resume.conf"
rm "$grubroot/etc/default/limine"
printf '#GRUB_CMDLINE_LINUX_DEFAULT="quiet resume=/dev/mapper/root resume_offset=9"\nGRUB_CMDLINE_LINUX_DEFAULT="quiet"\n' \
    >"$grubroot/etc/default/grub"
HASEEN_SYSROOT="$grubroot" capture env BOOTLOADER=grub haseen hibernation status
assert_status "GRUB: a commented resume= does not count" 1 "$STATUS"
printf 'GRUB_CMDLINE_LINUX_DEFAULT="quiet resume=/dev/mapper/root resume_offset=9"\n' >"$grubroot/etc/default/grub"
HASEEN_SYSROOT="$grubroot" capture env BOOTLOADER=grub haseen hibernation status
assert_status "GRUB: the uncommented line does" 0 "$STATUS"
assert_not_contains "GRUB: no systemd-boot note" "$OUTPUT" "static loader entry"

# systemd-boot: /etc/kernel/cmdline counts, with a note that a static Type 1
# entry's options line is not checked, until the running kernel shows resume=.
sdbroot="$(make_sysroot sdboot)"
add_swap "$sdbroot" 32554512
printf 'HOOKS+=(resume)\n' >"$sdbroot/etc/mkinitcpio.conf.d/haseen-resume.conf"
rm "$sdbroot/etc/default/limine"
mkdir -p "$sdbroot/etc/kernel"
printf '# resume=/dev/mapper/root\nroot=/dev/mapper/root rw resume=/dev/mapper/root resume_offset=9\n' \
    >"$sdbroot/etc/kernel/cmdline"
HASEEN_SYSROOT="$sdbroot" capture env BOOTLOADER=systemd-boot haseen hibernation status
assert_status "systemd-boot: /etc/kernel/cmdline counts" 0 "$STATUS"
assert_contains "systemd-boot: with its offset" "$OUTPUT" "offset 9"
assert_contains "systemd-boot: the static-entry note" "$OUTPUT" "check the options line of any static loader entry"
printf 'root=/dev/mapper/root rw resume=/dev/mapper/root resume_offset=9\n' >"$sdbroot/proc/cmdline"
HASEEN_SYSROOT="$sdbroot" capture env BOOTLOADER=systemd-boot haseen hibernation status
assert_status "systemd-boot: booted with resume=" 0 "$STATUS"
assert_not_contains "systemd-boot: no note once the kernel has it" "$OUTPUT" "static loader entry"

# --- hooks are evaluated the way mkinitcpio evaluates them -------------------
# A drop-in that assigns HOOKS replaces the list; the systemd initramfs resumes
# from the command line and needs no resume hook at all.
sdroot="$(make_sysroot systemd)"
add_swap "$sdroot" 32554512
printf 'HOOKS=(base systemd autodetect modconf kms keyboard sd-vconsole block sd-encrypt filesystems fsck)\n' \
    >"$sdroot/etc/mkinitcpio.conf.d/zz-systemd.conf"
printf 'KERNEL_CMDLINE[default]+=" resume=/dev/mapper/root resume_offset=1929459"\n' \
    >"$sdroot/etc/limine-entry-tool.d/haseen-resume.conf"
HASEEN_SYSROOT="$sdroot" capture haseen hibernation status
assert_contains "systemd hooks are detected" "$OUTPUT" "systemd hooks"
assert_contains "and the resume hook is called unnecessary" "$OUTPUT" "not needed"
assert_status "a systemd initramfs is ready without the hook" 0 "$STATUS"

# The reverse: mkinitcpio.conf says systemd, a drop-in replaces it with busybox.
mixed="$(make_sysroot mixed)"
add_swap "$mixed" 32554512
printf 'HOOKS=(base systemd autodetect block sd-encrypt filesystems fsck)\n' >"$mixed/etc/mkinitcpio.conf"
printf 'HOOKS=(base udev autodetect block encrypt filesystems fsck)\n' >"$mixed/etc/mkinitcpio.conf.d/omarchy_hooks.conf"
HASEEN_SYSROOT="$mixed" capture haseen hibernation status
assert_contains "the last HOOKS= assignment wins" "$OUTPUT" "busybox hooks"
assert_status "so that machine does need a resume hook" 1 "$STATUS"

# --- the plan on a fresh LUKS + btrfs machine --------------------------------
export HASEEN_SYSROOT="$plain"
rm -f "$plain/etc/mkinitcpio.conf.d/haseen-resume.conf" \
    "$plain/etc/limine-entry-tool.d/haseen-resume.conf"
: >"$plain/etc/fstab"
# btrfs-progs is not in every container; a dry run must never execute it, so a
# stub is both the presence check and the purity check.
stub btrfs 'echo "STUB-CALLED: btrfs $*" >&2; exit 97'
# Same for the Limine initramfs rebuild: present on a Limine machine, absent in
# a container, and never run by a dry run.
stub limine-mkinitcpio 'echo "STUB-CALLED: limine-mkinitcpio $*" >&2; exit 97'
stub findmnt 'case "$*" in
    *FSTYPE*) echo btrfs ;;
    *UUID*) echo 2543f8d6-312f-4c8a-8bfb-01bd10d7766c ;;
    *SOURCE*) echo "/dev/mapper/root[/@swap]" ;;
    *TARGET*) exit 1 ;;
esac'
capture haseen hibernation setup --dry-run --yes
assert_status "the setup plans a fresh machine" 0 "$STATUS"
assert_dry_pure "hibernation setup dry run" "$OUTPUT"
assert_contains "it says the image is encrypted with the disk" "$OUTPUT" "inside the LUKS container"
assert_contains "the swap subvolume is top-level, not nested" "$OUTPUT" "mount -o subvolid=5"
assert_contains "and is created as @swap" "$OUTPUT" "btrfs subvolume create"
assert_contains "it is mounted from fstab by UUID" "$OUTPUT" "subvol=/@swap,noatime"
assert_contains "the swapfile is made with mkswapfile (NOCOW)" "$OUTPUT" "btrfs filesystem mkswapfile"
assert_contains "zram keeps priority over it" "$OUTPUT" "pri=0"
assert_contains "the resume hook is added for busybox hooks" "$OUTPUT" "HOOKS+=(resume)"
assert_contains "the command line gets resume=" "$OUTPUT" "resume=/dev/mapper/root"
assert_contains "s2idle gets the ACPI alarm" "$OUTPUT" "rtc_cmos.use_acpi_alarm=1"
assert_contains "and the initramfs is rebuilt" "$OUTPUT" "limine-mkinitcpio"
assert_contains "and it says it is set up" "$OUTPUT" "hibernation is set up;"
before_append="$(grep -n 'append to /etc/fstab' <<<"$OUTPUT" | head -n1 | cut -d: -f1 || true)"
mount_at="$(grep -n 'mount -o subvol=/@swap,noatime' <<<"$OUTPUT" | head -n1 | cut -d: -f1 || true)"
[[ -n $mount_at && -n $before_append ]] && ((mount_at < before_append)) && _pass ||
    _fail "the new fstab line is written only after its subvolume has mounted"

# Where the drop-in cannot reach the kernel (a later '=' replaces it), setup
# says what to add and fails instead of saying it is set up (plan 188).
rm -f "$replaced/etc/limine-entry-tool.d/haseen-resume.conf"
: >"$replaced/etc/fstab"
HASEEN_SYSROOT="$replaced" capture haseen hibernation setup --dry-run --yes
assert_status "a drop-in that cannot count: setup fails" 1 "$STATUS"
assert_dry_pure "hibernation setup, replaced cmdline" "$OUTPUT"
assert_contains "it says where to add resume=" "$OUTPUT" "replaces every drop-in"
assert_contains "and that hibernation is not set up yet" "$OUTPUT" "hibernation is not set up yet"
assert_not_contains "never that it is set up" "$OUTPUT" "hibernation is set up;"

# A real run, with a sudo that records and runs nothing: the subvolume setup
# looks for is the one it creates and mounts (plan 188: it once looked for
# "swap" and created "@swap").
: >"$SANDBOX/sudo.log"
stub sudo "printf '%s\n' \"\$*\" >>'$SANDBOX/sudo.log'
case \"\$*\" in
'btrfs subvolume show '*/@swap) [ -n \"\${HASEEN_TEST_NO_SWAP:-}\" ] && exit 1; exit 0 ;;
'btrfs subvolume show '*) exit 1 ;;
'btrfs subvolume create '*) [ -n \"\${HASEEN_TEST_CREATE_FAILS:-}\" ] && exit 1; exit 0 ;;
tee* | 'sh -c'*) cat >/dev/null ;;
esac
exit 0"
capture haseen hibernation setup --yes
assert_contains "an existing @swap is looked up by that name" "$(<"$SANDBOX/sudo.log")" "btrfs subvolume show "
assert_contains "as @swap" "$(grep 'subvolume show' "$SANDBOX/sudo.log")" "/@swap"
assert_not_contains "and is not created again" "$(<"$SANDBOX/sudo.log")" "btrfs subvolume create"
# No @swap, and creating it fails: the top level is unmounted before it stops,
# and fstab gets no line for a subvolume that does not exist.
: >"$SANDBOX/sudo.log"
capture env HASEEN_TEST_NO_SWAP=1 HASEEN_TEST_CREATE_FAILS=1 haseen hibernation setup --yes
assert_status "a failed create stops setup" 1 "$STATUS"
assert_contains "and says so" "$OUTPUT" "could not create the @swap subvolume"
create_at="$(grep -n '^btrfs subvolume create' "$SANDBOX/sudo.log" | cut -d: -f1 || true)"
umount_at="$(grep -n '^umount ' "$SANDBOX/sudo.log" | cut -d: -f1 || true)"
[[ -n $create_at && -n $umount_at ]] && ((create_at < umount_at)) && _pass ||
    _fail "the top level is unmounted after the failed create" "$(<"$SANDBOX/sudo.log")"
assert_not_contains "no fstab line for it" "$(<"$SANDBOX/sudo.log")" "tee -a"
assert_eq "and nothing is mounted at /swap" "0" "$(grep -c ' /swap$' "$SANDBOX/sudo.log")"
rm -f "$SANDBOX/stubs/sudo"

# On systemd hooks the resume hook must NOT be added: the busybox hook does not
# exist there and would fail the build.
HASEEN_SYSROOT="$sdroot" capture haseen hibernation setup --dry-run --yes
assert_not_contains "no resume hook on a systemd initramfs" "$OUTPUT" "HOOKS+=(resume)"

# An already-configured machine is left alone.
HASEEN_SYSROOT="$sdroot" capture haseen hibernation setup --yes
assert_status "a configured machine needs no work" 0 "$STATUS"
assert_contains "and says so" "$OUTPUT" "already set up"
assert_dry_pure "no-op setup" "$OUTPUT"

# --- HOOKS on Omarchy's own layouts (plan 101) -----------------------------------
# A resume drop-in appends to whatever list is in force when it is sourced.
# Under Omarchy 4.0.6, omarchy_hooks.conf sorts after haseen-resume.conf and
# replaces HOOKS, so the append is lost, which mkinitcpio does too; under 4.5
# the baseline sorts first (00-omarchy-hooks.conf) and the append counts.
stub omarchy-hw-platform 'echo x86'
for v in 4.0.6 4.5; do
    root="$SANDBOX/omarchy-$v"
    cp -a "$FIXTURES/mkinitcpio-omarchy-$v" "$root"
    printf 'HOOKS+=(resume)\n' >"$root/etc/mkinitcpio.conf.d/haseen-resume.conf"
done
resume_in() {
    HASEEN_SYSROOT="$1" bash -c 'source "$HASEEN_PATH/lib/hibernate.sh"; hibernate_initramfs_style; hibernate_resume_hook_present && echo resume || echo no-resume' | paste -sd' '
}
assert_eq "4.0.6 layout: busybox, and Omarchy's list replaces the resume append" "busybox no-resume" \
    "$(resume_in "$SANDBOX/omarchy-4.0.6")"
assert_eq "4.5 layout: busybox, and the resume append takes effect" "busybox resume" "$(resume_in "$SANDBOX/omarchy-4.5")"
# HOOKS that cannot be read are unknown, never "busybox without resume".
rm "$SANDBOX/omarchy-4.5/etc/mkinitcpio.conf"
capture env HASEEN_SYSROOT="$SANDBOX/omarchy-4.5" bash -c 'source "$HASEEN_PATH/lib/hibernate.sh"; hibernate_initramfs_style'
assert_status "no mkinitcpio.conf: the initramfs style fails" 1 "$STATUS"
assert_contains "as unknown" "$OUTPUT" "unknown"
assert_not_contains "never a guess" "$OUTPUT" "busybox"
capture env HASEEN_SYSROOT="$SANDBOX/omarchy-4.5" bash -c 'source "$HASEEN_PATH/lib/hibernate.sh"; hibernate_resume_hook_present'
assert_status "and whether resume is there is unknown too" 2 "$STATUS"
mv "$plain/etc/mkinitcpio.conf" "$plain/etc/mkinitcpio.conf.away"
capture env HASEEN_SYSROOT="$plain" haseen hibernation status
assert_status "hibernation status: not ready" 1 "$STATUS"
assert_contains "and says the initramfs is unknown" "$OUTPUT" "initramfs: unknown (mkinitcpio's configuration does not evaluate)"
mv "$plain/etc/mkinitcpio.conf.away" "$plain/etc/mkinitcpio.conf"
