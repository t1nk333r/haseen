# shellcheck shell=bash
# hibernate.sh — what this machine needs to resume from disk. Sourced, never
# executed.
#
# The shape (swap subvolume, swapfile, resume hook, resume= cmdline, s2idle RTC
# alarm) comes from Omarchy bin/omarchy-hibernation-setup (MIT, Copyright (c)
# David Heinemeier Hansson). The logic below is haseen's own, because that
# script assumes neither LUKS nor a CachyOS-style btrfs layout:
#
#   - The swapfile lives in a **top-level** `@swap` subvolume mounted at /swap,
#     not a nested one inside the root subvolume. A nested subvolume travels
#     with `@` and makes a snapper rollback of the root subvolume take the swap
#     area with it.
#   - The resume device is whatever holds the swapfile, which on a LUKS install
#     is the opened mapper device (/dev/mapper/root), not a partition. The
#     initramfs must therefore open the container *before* it resumes:
#       * busybox hooks: `resume` must come after `encrypt` — appending it in a
#         drop-in puts it last, which satisfies that.
#       * systemd hooks (`systemd`/`sd-encrypt`): there is no `resume` hook at
#         all; systemd-hibernate-resume acts on the resume= cmdline itself, and
#         adding the busybox hook would fail the build.
#   - The kernel command line is written where this machine's bootloader reads
#     it (limine-entry-tool drop-in, /etc/kernel/cmdline, or GRUB), not only
#     Limine's.

[[ -n ${HASEEN_HIBERNATE_SH:-} ]] && return 0
HASEEN_HIBERNATE_SH=1

# shellcheck source=preflight.sh
source "$(dirname "${BASH_SOURCE[0]}")/preflight.sh"
# shellcheck source=boot.sh
source "$(dirname "${BASH_SOURCE[0]}")/boot.sh" # boot_hooks, boot_cmdline_add
# shellcheck disable=SC2034  # read by bin/haseen-hibernation-*
SWAP_SUBVOL_NAME="${HASEEN_SWAP_SUBVOL:-@swap}"
SWAP_MOUNT="${HASEEN_SWAP_MOUNT:-/swap}"
SWAP_FILE="$SWAP_MOUNT/swapfile"
# shellcheck disable=SC2034  # read by bin/haseen-hibernation-setup
RESUME_HOOK_CONF=/etc/mkinitcpio.conf.d/haseen-resume.conf

# hibernate_supported — the kernel can hibernate at all.
hibernate_supported() { [[ -f $(sysroot_path /sys/power/image_size) ]]; }

# hibernate_mem_kib — MemTotal, the size a hibernation image can reach.
hibernate_mem_kib() {
    awk '/^MemTotal/ {print $2}' "$(sysroot_path /proc/meminfo)" 2>/dev/null
}

# hibernate_swap_kib — swap that can hold an image. zram cannot: it lives in
# the memory it would have to save.
hibernate_swap_kib() {
    awk '!/^Filename/ && $1 !~ /zram/ {sum += $3} END {print sum + 0}' \
        "$(sysroot_path /proc/swaps)" 2>/dev/null
}


# hibernate_initramfs_style — systemd | busybox, from those effective hooks.
hibernate_initramfs_style() {
    if boot_hooks | grep -qx -e systemd -e sd-encrypt; then
        echo systemd
    else
        echo busybox
    fi
}

# hibernate_resume_hook_present — a `resume` hook is configured (by haseen or
# by whoever set this machine up before).
hibernate_resume_hook_present() { boot_hooks | grep -qx resume; }

# hibernate_cmdline — every kernel command line this machine can boot with:
# the bootloader's own configuration plus the running one.
hibernate_cmdline() {
    local file
    for file in "$(sysroot_path /etc/default/limine)" "$(sysroot_path /etc/limine-entry-tool.d)"/*.conf \
        "$(sysroot_path /etc/kernel/cmdline)" "$(sysroot_path /etc/default/grub)" \
        "$(sysroot_path /proc/cmdline)"; do
        [[ -r $file ]] && cat "$file"
    done
    return 0
}

hibernate_cmdline_has_resume() { hibernate_cmdline | grep -q 'resume=[^ "]'; }
hibernate_cmdline_resume_offset() {
    hibernate_cmdline | sed -n 's/.*resume_offset=\([0-9]\+\).*/\1/p' | tail -n1
}

# hibernate_resume_device — the device the swapfile sits on, with any btrfs
# subvolume suffix stripped. On LUKS this is the opened mapper device.
hibernate_resume_device() {
    in_sysroot && return 0
    findmnt -no SOURCE -T "$SWAP_FILE" 2>/dev/null | sed 's/\[.*\]//'
}

# hibernate_resume_offset — the swapfile's first physical page, which is what
# the kernel needs to find the image inside the filesystem.
hibernate_resume_offset() {
    in_sysroot && return 0
    $DRY_RUN && return 0
    run_root btrfs inspect-internal map-swapfile -r "$SWAP_FILE" 2>/dev/null
}

hibernate_swapfile_active() {
    grep -q "^${SWAP_FILE//\//\\/}[[:space:]]" "$(sysroot_path /proc/swaps)" 2>/dev/null
}

# hibernate_image_kib — the largest image this kernel will write.
# /sys/power/image_size is 2/5 of RAM by default and is what upstream's
# availability check compares against; swap merely has to hold that much.
hibernate_image_kib() {
    local bytes
    bytes="$(cat "$(sysroot_path /sys/power/image_size)" 2>/dev/null || echo 0)"
    echo $((bytes / 1024))
}

# hibernate_ready — swap big enough for an image, a resume hook where one is
# needed, and a resume= on the command line.
hibernate_ready() {
    hibernate_supported || return 1
    local swap image
    swap="$(hibernate_swap_kib)"
    image="$(hibernate_image_kib)"
    ((swap > 0 && swap >= image)) || return 1
    [[ $(hibernate_initramfs_style) == systemd ]] || hibernate_resume_hook_present || return 1
    hibernate_cmdline_has_resume
}
