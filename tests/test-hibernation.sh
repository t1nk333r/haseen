# shellcheck shell=bash
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

# On systemd hooks the resume hook must NOT be added: the busybox hook does not
# exist there and would fail the build.
HASEEN_SYSROOT="$sdroot" capture haseen hibernation setup --dry-run --yes
assert_not_contains "no resume hook on a systemd initramfs" "$OUTPUT" "HOOKS+=(resume)"

# An already-configured machine is left alone.
HASEEN_SYSROOT="$sdroot" capture haseen hibernation setup --yes
assert_status "a configured machine needs no work" 0 "$STATUS"
assert_contains "and says so" "$OUTPUT" "already set up"
assert_dry_pure "no-op setup" "$OUTPUT"
