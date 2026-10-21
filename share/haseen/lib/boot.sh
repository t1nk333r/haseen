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

# boot_hooks — the mkinitcpio HOOKS this machine actually builds with, one per
# line. Evaluated as mkinitcpio itself does (mkinitcpio 42.2,
# /usr/bin/mkinitcpio:1124-1143 and arrayize_config in
# /usr/lib/initcpio/functions:521-529): mkinitcpio.conf, then every *.conf in
# mkinitcpio.conf.d (a regular file or a link to one, names version-sorted),
# concatenated and sourced as one script; a HOOKS string is split into words.
# A drop-in is code, not just assignments: Omarchy 4.5 picks its baseline in an
# indented `case` on its platform detector
# (etc/mkinitcpio.conf.d/00-omarchy-hooks.conf@v4.5.0-rc1), and haseen's own
# plymouth drop-in edits the list with sed, so no line-by-line reading can be
# right. The files are sourced in a subshell, as the calling user, with their
# output discarded, and nothing they set leaks back. When the configuration
# does not source (a drop-in returns non-zero, as Omarchy's does for a machine
# its detector cannot place), or mkinitcpio.conf is missing or unreadable,
# mkinitcpio refuses to build, and this warns and fails rather than report an
# empty list.
boot_hooks() {
    local conf dir name files=()
    conf="$(sysroot_path /etc/mkinitcpio.conf)"
    dir="$conf.d"
    # mkinitcpio dies without it (/usr/bin/mkinitcpio:1131,1143); so does this,
    # rather than read the drop-ins alone or no hooks at all.
    if [[ ! -f $conf || ! -r $conf ]]; then
        warn "mkinitcpio's configuration $conf is missing or unreadable; mkinitcpio would not build without it"
        return 1
    fi
    files+=("$conf")
    if [[ -d $dir ]]; then
        while IFS= read -r -d '' name; do
            [[ -r $dir/$name ]] && files+=("$dir/$name")
        done < <(LC_ALL=C.UTF-8 find "$dir" -maxdepth 1 -xtype f -name '*.conf' -printf '%f\0' |
            LC_ALL=C.UTF-8 sort -zVu)
    fi
    if ! (
        set +Eeu +o pipefail
        trap - ERR
        unset HOOKS MODULES BINARIES FILES COMPRESSION COMPRESSION_OPTIONS
        # shellcheck disable=SC1090  # the machine's own configuration
        . <(cat -- "${files[@]}") >/dev/null 2>&1 </dev/null || exit 1
        if [[ ${HOOKS@a} != *a* ]]; then
            set -f
            IFS=' ' read -r -a HOOKS <<<"${HOOKS:-}"
        fi
        printf '%s\n' "${HOOKS[@]}" | grep -v '^$'
        exit 0
    ); then
        warn "mkinitcpio's configuration ($conf and its drop-ins) does not evaluate; mkinitcpio would not build with it either"
        return 1
    fi
}

# boot_hooks_known — die unless HOOKS can be read: a command about to add a
# hook must not mistake an unreadable configuration for a missing hook.
boot_hooks_known() {
    boot_hooks >/dev/null || die "fix mkinitcpio's configuration first (sudo mkinitcpio -P shows the error)"
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
