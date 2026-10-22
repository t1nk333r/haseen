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
# told nothing was written (return 2). A Limine drop-in that a later
# `KERNEL_CMDLINE[default]=` replaces is written but returns 2 too: the
# parameters would not reach the kernel. Neither bootloader is left without
# the root= the machine boots with (boot_limine_keep_root, and the seed of a
# new /etc/kernel/cmdline below); a command line that cannot be kept is
# refused before anything is written.
boot_cmdline_add() {
    local name="$1"
    shift
    local args="$*"
    [[ -n ${BOOTLOADER:-} ]] || preflight_bootloader
    case "$BOOTLOADER" in
    limine)
        local dropin="$BOOT_LIMINE_DROPINS/haseen-$name.conf" line word merged
        line="$(printf 'KERNEL_CMDLINE[default]+=" %s"' "$args")"
        boot_limine_keep_root "$dropin" "$line"
        printf '%s\n' "$line" | write_root_file "$dropin"
        merged="$(boot_cmdline_words "$BOOT_LIMINE_CMDLINE")"
        for word in $args; do
            if ! grep -qxF -- "$word" <<<"$merged"; then
                warn "$BOOT_LIMINE_REPLACED sets KERNEL_CMDLINE[default] with '=', which replaces every drop-in, so $dropin has no effect: add '$args' to that line yourself"
                return 2
            fi
        done
        ;;
    systemd-boot)
        local current="" f
        f="$(sysroot_path /etc/kernel/cmdline)"
        if [[ -f $f ]]; then
            current="$(<"$f")"
        else
            current="$(boot_cmdline_seed)" || die "refusing to write that command line down as this machine's"
        fi
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

# boot_cmdline_seed — what a new /etc/kernel/cmdline starts from: the line
# kernel-install and mkinitcpio use while it does not exist,
# /usr/lib/kernel/cmdline, else the running kernel's without the loader's
# BOOT_IMAGE= and initrd= (systemd 262 90-loaderentry.install:88-93,
# mkinitcpio 42.2 /usr/bin/mkinitcpio:590-606). Starting from nothing would
# leave the next image only the new parameters, root= gone. A snapshot or
# live boot's line is not a machine's own: refused.
boot_cmdline_seed() {
    local f word words=()
    f="$(sysroot_path /usr/lib/kernel/cmdline)"
    if [[ -f $f ]]; then
        grep -v '^[[:space:]]*#' "$f" | tr -s '[:space:]' ' ' | sed 's/^ //; s/ $//'
        return 0
    fi
    boot_cmdline_own "$(boot_cmdline)" || return 1
    while IFS= read -r word; do
        [[ $word == BOOT_IMAGE=* || $word == initrd=* ]] || words+=("$word")
    done < <(boot_cmdline_words "$(boot_cmdline)")
    printf '%s\n' "${words[*]}"
}

# boot_cmdline_own TEXT — TEXT, a running kernel's command line, describes this
# installation: not a read-only snapshot booted through limine-snapper-sync
# (rootflags=subvol=…/.snapshots/N/snapshot) or a live medium (archiso). Says
# why not and fails, so it is never written down as the machine's own.
boot_cmdline_own() {
    if [[ $1 == *'.snapshots/'* ]]; then
        warn "this boot is a snapshot (its command line names /.snapshots/): boot the installed system before changing the kernel command line"
        return 1
    fi
    if boot_cmdline_states archisobasedir "$1" || boot_cmdline_states archisolabel "$1"; then
        warn "this boot is a live medium (archiso): change the installed system's kernel command line from the installed system"
        return 1
    fi
}

# boot_cmdline_words TEXT — the parameters the kernel reads in TEXT, one per
# line: split at blanks outside double quotes, an unmatched quote running to
# the end (the kernel's next_arg(), lib/cmdline.c). Quotes stay in the word.
boot_cmdline_words() {
    local text="$1" word="" c i quoted=false
    for ((i = 0; i < ${#text}; i++)); do
        c="${text:i:1}"
        if [[ $c == '"' ]]; then
            if $quoted; then quoted=false; else quoted=true; fi
        elif ! $quoted && [[ $c == [[:space:]] ]]; then
            [[ -n $word ]] && printf '%s\n' "$word"
            word=""
            continue
        fi
        word+="$c"
    done
    [[ -n $word ]] && printf '%s\n' "$word"
    return 0
}

# boot_cmdline_states NAME TEXT — TEXT sets kernel parameter NAME: a word
# NAME or NAME=…. A word that opens with a quote, or root= inside another
# parameter's quoted value, does not count: the check errs towards "not
# stated", whose cost is one pin too many.
boot_cmdline_states() {
    local w
    while IFS= read -r w; do
        [[ $w == "$1" || $w == "$1="* ]] && return 0
    done < <(boot_cmdline_words "$2")
    return 1
}

# --- Limine: keep root= when haseen adds a drop-in ---------------------------
#
# limine-entry-tool builds every entry's command line from KERNEL_CMDLINE[...]
# in its config layers, read in this order: /usr/share/limine-entry-tool.d/
# *.conf, /etc/limine-entry-tool.conf, /etc/limine-entry-tool.d/*.conf, then
# /etc/default/limine; `+=` appends and `=` replaces. Only while no layer sets
# the key does it read /etc/kernel/cmdline or /proc/cmdline instead, and any
# `+=` turns that off (limine-entry-tool README, "Kernel Command Line
# Configuration", limine-mkinitcpio-hook 1.40.0). So haseen's first `+=`
# drop-in can drop the root= a machine boots with, and the image built next
# stops in an emergency shell: Omarchy hit it in 393a43d46 (#6951), whose
# merge (bin/omarchy-upgrade-to-quattro@v4.5.0-rc1, kernel_cmdline_root_pinned;
# MIT, Copyright (c) David Heinemeier Hansson) the code below reads the same
# way, rewritten.

BOOT_LIMINE_DROPINS=/etc/limine-entry-tool.d
# Where haseen pins the command line it must not lose. It sorts before
# haseen's other drop-ins, so a pinned resume= comes before theirs.
BOOT_LIMINE_PIN="$BOOT_LIMINE_DROPINS/haseen-cmdline.conf"
# The parameters that find and open the root filesystem: Omarchy's list
# (preserve_kernel_cmdline_root) without resume= and resume_offset=, which
# haseen's own hibernation drop-in states and must win.
BOOT_ROOT_PARAMS=(root rw ro cryptdevice cryptkey rd.luks.name rd.luks.uuid rd.luks.options
    rd.luks.key rd.luks.crypttab dm-mod.create rootflags rootfstype rootwait rootdelay
    rd.lvm.lv rd.lvm.vg rd.md.uuid rd.dm.uuid)

# boot_limine_merge [PATH TEXT]... — KERNEL_CMDLINE[default] as
# limine-entry-tool merges its layers, each PATH (a host path, maybe not
# written yet) read as TEXT. Sets BOOT_LIMINE_SET (some layer assigns the key),
# BOOT_LIMINE_CMDLINE (the merged value) and BOOT_LIMINE_REPLACED (the last
# layer that replaced it with `=`). A value loses a pair of surrounding double
# quotes and trailing blanks; single quotes stay, as they do for the tool.
# Fails, saying which, when a layer that exists cannot be read: a pin it holds
# would otherwise read as missing.
boot_limine_merge() {
    local -A over=()
    local f host content files=() names=()
    while (($# >= 2)); do
        over["$1"]="$2"
        shift 2
    done
    for f in "$(sysroot_path /usr/share/limine-entry-tool.d)"/*.conf; do
        [[ -e $f ]] && names+=("/usr/share/limine-entry-tool.d/${f##*/}")
    done
    mapfile -t files < <(printf '%s\n' "${names[@]}" | LC_ALL=C sort)
    files+=(/etc/limine-entry-tool.conf)
    names=()
    for f in "$(sysroot_path "$BOOT_LIMINE_DROPINS")"/*.conf; do
        [[ -e $f ]] && names+=("$BOOT_LIMINE_DROPINS/${f##*/}")
    done
    for f in "${!over[@]}"; do
        [[ $f == "$BOOT_LIMINE_DROPINS"/*.conf ]] && names+=("$f")
    done
    mapfile -t -O "${#files[@]}" files < <(printf '%s\n' "${names[@]}" | LC_ALL=C sort -u)
    files+=(/etc/default/limine)
    BOOT_LIMINE_SET=false
    BOOT_LIMINE_CMDLINE=""
    BOOT_LIMINE_REPLACED=""
    for f in "${files[@]}"; do
        [[ -n $f ]] || continue
        host="$(sysroot_path "$f")"
        if [[ -n ${over[$f]+set} ]]; then
            content="${over[$f]}"
        elif [[ -e $host ]]; then
            [[ -f $host && -r $host ]] || {
                warn "cannot read $f, so whether the kernel command line keeps root= is unknown"
                return 1
            }
            content="$(<"$host")"
        else
            continue
        fi
        _boot_limine_layer "$f" "$content"
    done
}

# _boot_limine_layer PATH CONTENT — fold one layer's KERNEL_CMDLINE[default]
# lines into BOOT_LIMINE_SET, BOOT_LIMINE_CMDLINE and BOOT_LIMINE_REPLACED.
_boot_limine_layer() {
    local line value
    while IFS= read -r line || [[ -n $line ]]; do
        [[ $line =~ ^[[:space:]]*KERNEL_CMDLINE\[default\][[:space:]]*(\+?)=[[:space:]]*(.*)$ ]] || continue
        value="${BASH_REMATCH[2]}"
        value="${value%"${value##*[![:space:]]}"}"
        [[ ${#value} -ge 2 && $value == \"*\" ]] && value="${value:1:${#value}-2}"
        BOOT_LIMINE_SET=true
        if [[ -n ${BASH_REMATCH[1]} ]]; then
            BOOT_LIMINE_CMDLINE+=" $value"
        else
            BOOT_LIMINE_CMDLINE="$value"
            BOOT_LIMINE_REPLACED="$1"
        fi
    done <<<"$2"
}

# boot_limine_fallback — the line limine-entry-tool reads while no layer sets
# KERNEL_CMDLINE[default]: /etc/kernel/cmdline, else the running kernel's
# (limine-entry-tool README, KERNEL_CMDLINE; its "Detected a chroot
# environment, skipping reading /proc/cmdline" string), without the
# BOOT_IMAGE= another loader adds.
boot_limine_fallback() {
    local f word words=()
    f="$(sysroot_path /etc/kernel/cmdline)"
    if [[ -f $f ]]; then
        grep -v '^[[:space:]]*#' "$f" | tr -s '[:space:]' ' ' | sed 's/^ //; s/ $//'
        return 0
    fi
    while IFS= read -r word; do
        [[ $word == BOOT_IMAGE=* ]] || words+=("$word")
    done < <(boot_cmdline_words "$(boot_cmdline)")
    printf '%s\n' "${words[*]}"
}

# boot_cmdline_root_params TEXT — the BOOT_ROOT_PARAMS words of TEXT, in order.
boot_cmdline_root_params() {
    local w p out=()
    while IFS= read -r w; do
        for p in "${BOOT_ROOT_PARAMS[@]}"; do
            if [[ $w == "$p" || $w == "$p="* ]]; then
                out+=("$w")
                break
            fi
        done
    done < <(boot_cmdline_words "$1")
    printf '%s\n' "${out[*]}"
}

# boot_limine_keep_root DROPIN LINE — run before haseen writes LINE, a `+=`
# line, as DROPIN. When the layers with it no longer state root=, pin what
# the next image would otherwise lose in BOOT_LIMINE_PIN first:
#   - no layer set KERNEL_CMDLINE[default] before (limine-entry-tool used its
#     fallback): the whole fallback line, so nothing it carried is lost;
#   - a layer already did: the root parameters the running kernel was given.
# Refuses (dies, nothing written) when that line has no root= or is not the
# machine's own (boot_cmdline_own), or when a later `=` would replace the pin
# too. Leaves BOOT_LIMINE_CMDLINE as the merge with DROPIN (and the pin).
boot_limine_keep_root() {
    local dropin="$1" line="$2" was_set pin from pinline
    boot_limine_merge || die "fix the permissions on that file, then run this again"
    was_set=$BOOT_LIMINE_SET
    boot_limine_merge "$dropin" "$line" || die "fix the permissions on that file, then run this again"
    boot_cmdline_states root "$BOOT_LIMINE_CMDLINE" && return 0
    if $was_set; then
        from=/proc/cmdline
        pin="$(boot_cmdline_root_params "$(boot_cmdline)")"
    else
        from="$([[ -f $(sysroot_path /etc/kernel/cmdline) ]] && echo /etc/kernel/cmdline || echo /proc/cmdline)"
        pin="$(boot_limine_fallback)"
    fi
    boot_cmdline_states root "$pin" ||
        die "Limine's config states no root=, and $from has none either: haseen's drop-in would leave the next boot image without one. Add KERNEL_CMDLINE[default]+=\" root=… rw\" to /etc/default/limine, then run this again."
    boot_cmdline_own "$pin" || die "refusing to write that command line down as this machine's"
    pinline="$(printf 'KERNEL_CMDLINE[default]+=" %s"' "$pin")"
    boot_limine_merge "$dropin" "$line" "$BOOT_LIMINE_PIN" "$pinline" || die "fix the permissions on that file, then run this again"
    boot_cmdline_states root "$BOOT_LIMINE_CMDLINE" ||
        die "$BOOT_LIMINE_REPLACED replaces KERNEL_CMDLINE[default] with '=' and states no root=: state root= on that line yourself, then run this again"
    info "Limine's config does not state root=; pinning it from $from in $BOOT_LIMINE_PIN"
    printf '%s\n' \
        "# Written by haseen: limine-entry-tool reads $from only while no" \
        "# config layer sets KERNEL_CMDLINE[default], and haseen's += drop-ins" \
        "# end that, so the parameters the next boot needs are stated here." \
        "$pinline" | write_root_file "$BOOT_LIMINE_PIN"
}

# boot_cmdline_value NAME TEXT — the value of the last NAME= word in TEXT,
# the one the kernel keeps for root= (each root= overwrites the last); fails
# when there is none.
boot_cmdline_value() {
    local w word=""
    while IFS= read -r w; do
        [[ $w == "$1="* ]] && word="$w"
    done < <(boot_cmdline_words "$2")
    [[ -n $word ]] && printf '%s\n' "${word#*=}"
}

# boot_limine_pin_report — haseen doctor's line about the root= pin, when there
# is one (plan 111). The pin is written once and then kept: a root device that
# changed since (a reinstall, a new disk, a filesystem made again) leaves it
# naming the old one, and the next image limine-entry-tool builds (any kernel
# or initramfs update) would boot that. So the root= the merged config gives
# the next image is compared with the one this boot used. Two spellings of one
# device (UUID= and /dev/…) read as different: it is a hint, never a failure.
# Prints nothing without a pin.
boot_limine_pin_report() {
    local pin next="" booted pinned="" where
    pin="$(sysroot_path "$BOOT_LIMINE_PIN")"
    [[ -e $pin ]] || return 0
    if ! boot_limine_merge 2>/dev/null; then
        echo "limine root pin=unknown: a Limine config layer cannot be read"
        return 0
    fi
    if ! booted="$(boot_cmdline_value root "$(boot_cmdline)")"; then
        echo "limine root pin=unknown: this boot's command line states no root="
        return 0
    fi
    next="$(boot_cmdline_value root "$BOOT_LIMINE_CMDLINE")" || next=""
    if [[ -n $next && $next == "$booted" ]]; then
        echo "limine root pin=ok (root=$booted, as this boot)"
        return 0
    fi
    # What the pin alone says, read the way the merge reads every layer.
    BOOT_LIMINE_CMDLINE=""
    _boot_limine_layer "$BOOT_LIMINE_PIN" "$(<"$pin")"
    pinned="$(boot_cmdline_value root "$BOOT_LIMINE_CMDLINE")" || pinned=""
    if [[ $pinned == "$next" ]]; then
        where="in $BOOT_LIMINE_PIN (sudoedit it)"
    else
        where="in the layer of Limine's config after the pin that states it (/etc/default/limine or a later drop-in in $BOOT_LIMINE_DROPINS)"
    fi
    next="${next:+root=$next}"
    pinned="${pinned:+root=$pinned}"
    printf 'limine root pin=differs: the next boot image gets %s (%s pins %s), but this boot used root=%s. If the root device changed, set root=%s %s, then rebuild (sudo limine-mkinitcpio); if both name the same device, nothing is wrong\n' \
        "${next:-no root=}" "$BOOT_LIMINE_PIN" "${pinned:-no root=}" "$booted" "$booted" "$where"
}

# --- Boot drop-ins (the base layer) -------------------------------------------
#
# Two of Omarchy 4.5's boot speed-ups are plain systemd drop-ins, shipped under
# haseen's names in share/haseen/default/systemd/ (MIT, Copyright (c) David
# Heinemeier Hansson): d10031418 (#15175) mounts binfmt_misc before
# systemd-binfmt registers formats, so the boot does not wait on the
# automount, and 60e96ac0d (#15182) raises the mount-event rate limit that
# can defer local filesystems at boot. omarchy-settings 4.5 installs the same
# content under Omarchy's names; where its copy is there, haseen's is not
# installed, or is removed, so one file says each thing once. Each takes
# effect at the next boot.

# Each entry: the shipped file under default/systemd/ (also its path under
# /etc/systemd/) and the name of Omarchy's copy in the same directory.
BOOT_DROPINS=(
    "system/systemd-binfmt.service.d/10-haseen-eager-mount.conf 10-eager-mount.conf"
    "system/proc-sys-fs-binfmt_misc.mount.d/10-haseen-conditions.conf 10-omarchy-conditions.conf"
    "system.conf.d/20-haseen-mount-events.conf 20-mount-events.conf"
)

# boot_dropin_state REL TWIN — one drop-in: "omarchy" (Omarchy's copy is
# there), "ok" (haseen's matches the shipped one), "stale" or "missing".
boot_dropin_state() {
    local dest="/etc/systemd/$1"
    if [[ -e $(sysroot_path "${dest%/*}/$2") ]]; then
        echo omarchy
    elif cmp -s "$HASEEN_PATH/default/systemd/$1" "$(sysroot_path "$dest")"; then
        echo ok
    elif [[ -e $(sysroot_path "$dest") ]]; then
        echo stale
    else
        echo missing
    fi
}

# boot_dropins_status — "STATE /etc/systemd/REL" per drop-in.
boot_dropins_status() {
    local entry rel twin
    for entry in "${BOOT_DROPINS[@]}"; do
        read -r rel twin <<<"$entry"
        printf '%s /etc/systemd/%s\n' "$(boot_dropin_state "$rel" "$twin")" "$rel"
    done
}

# boot_dropins_apply — install the missing or stale ones; remove haseen's copy
# where Omarchy's is there. Reloads systemd once when a unit drop-in changed.
boot_dropins_apply() {
    local entry rel twin dest changed=false
    for entry in "${BOOT_DROPINS[@]}"; do
        read -r rel twin <<<"$entry"
        dest="/etc/systemd/$rel"
        case "$(boot_dropin_state "$rel" "$twin")" in
        omarchy)
            if [[ -e $(sysroot_path "$dest") ]]; then
                info "boot: Omarchy's ${dest%/*}/$twin is installed; removing haseen's copy"
                run_root rm -f "$dest"
                [[ $rel == system/* ]] && changed=true
            fi
            ;;
        ok) ;;
        *)
            info "boot: $dest"
            install_root_file "$HASEEN_PATH/default/systemd/$rel" "$dest" 0644
            [[ $rel == system/* ]] && changed=true
            ;;
        esac
    done
    if $changed; then
        run_root systemctl daemon-reload
    fi
    return 0
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
