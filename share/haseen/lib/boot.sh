# shellcheck shell=bash
# boot.sh — the kernel command line and the initramfs, per bootloader. Sourced.
#
# Two things need this: hibernation (resume=, resume_offset=) and Plymouth
# (quiet splash). Each bootloader reads its command line from somewhere else,
# and getting it wrong is an unbootable machine, so the knowledge lives once.

[[ -n ${HASEEN_BOOT_SH:-} ]] && return 0
HASEEN_BOOT_SH=1

# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
# shellcheck source=preflight.sh
source "$(dirname "${BASH_SOURCE[0]}")/preflight.sh" # preflight_bootloader -> BOOTLOADER

# boot_cmdline — the command line this machine booted with.
boot_cmdline() {
    local f
    f="$(sysroot_path /proc/cmdline)"
    [[ -r $f ]] && cat "$f" || true
}

# boot_cmdline_has WORD — is that parameter on the current command line?
boot_cmdline_has() {
    [[ " $(boot_cmdline) " == *" $1 "* || " $(boot_cmdline) " == *" $1="* ]]
}

# boot_cmdline_add NAME ARGS… — append kernel parameters where this machine's
# bootloader reads them. NAME names the drop-in, so a second call replaces the
# same file instead of stacking duplicates. GRUB has no drop-in directory:
# there the parameters are printed for the owner to paste, and the caller is
# told nothing was written (return 2).
boot_cmdline_add() {
    local name="$1"
    shift
    local args="$*"
    [[ -n ${BOOTLOADER:-} ]] || preflight_bootloader
    case "$BOOTLOADER" in
    limine)
        printf 'KERNEL_CMDLINE[default]+=" %s"\n' "$args" |
            write_root_file "/etc/limine-entry-tool.d/haseen-$name.conf"
        ;;
    systemd-boot)
        local current="" f
        f="$(sysroot_path /etc/kernel/cmdline)"
        [[ -f $f ]] && current="$(<"$f")"
        # One file, no drop-ins: keep what is there, add only what is missing.
        local word out="$current"
        for word in $args; do
            [[ " $current " == *" $word "* ]] || out="${out:+$out }$word"
        done
        printf '%s\n' "$out" | write_root_file /etc/kernel/cmdline
        ;;
    grub)
        warn "add this to GRUB_CMDLINE_LINUX_DEFAULT in /etc/default/grub, then run grub-mkconfig:"
        warn "  $args"
        return 2
        ;;
    *)
        warn "unknown bootloader; add '$args' to the kernel command line yourself"
        return 2
        ;;
    esac
}

# boot_hooks — the mkinitcpio HOOKS this machine actually builds with.
# mkinitcpio reads mkinitcpio.conf and then every conf.d drop-in in order,
# where `HOOKS=` replaces and `HOOKS+=` appends, so the answer is not "every
# HOOKS line in every file": a drop-in that replaces the list is what counts.
boot_hooks() {
    local file line hooks=""
    for file in "$(sysroot_path /etc/mkinitcpio.conf)" "$(sysroot_path /etc/mkinitcpio.conf.d)"/*.conf; do
        [[ -r $file ]] || continue
        while IFS= read -r line; do
            case "$line" in
            HOOKS=*) hooks="$(tr -d '()"' <<<"${line#HOOKS=}")" ;;
            HOOKS+=*) hooks+=" $(tr -d '()"' <<<"${line#HOOKS+=}")" ;;
            esac
        done <"$file"
    done
    tr ' ' '\n' <<<"$hooks" | grep -v '^$' || true
}

# boot_initramfs_rebuild — regenerate every initramfs. limine-mkinitcpio keeps
# the bootloader's copies in step, so it wins when it is installed.
boot_initramfs_rebuild() {
    [[ -n ${BOOTLOADER:-} ]] || preflight_bootloader
    if [[ $BOOTLOADER == limine ]] && have limine-mkinitcpio; then
        run_root limine-mkinitcpio
    else
        run_root mkinitcpio -P
    fi
}
