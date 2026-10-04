# shellcheck shell=bash disable=SC2034  # SB_* settings are read by the commands and layer.sh
# secureboot.sh — shared by layers/secureboot/layer.sh, bin/haseen-secureboot-*
# and limine-hash-assets.sh. Sourced, never executed. Model: docs/architecture.md
# §8; evidence and rejected options: plans/002-secureboot-layer.md.
#
# Facts are read through sysroot_path, so the tests/fixtures/sb-* trees stand in
# for a machine. `sbctl status/verify` and `lsblk` are live-only probes and are
# skipped under a sysroot (lib/common.sh in_sysroot). Every mutation goes
# through sb_root or the common.sh write helpers, so --dry-run stays pure.
#
# Three facts shape the code below:
#   - Limine with an enrolled config hash panics on any boot path without a
#     #blake2b suffix, and on a stale hash (hash_mismatch_panic is forced on
#     under Secure Boot). Wallpapers and fonts without a hash are skipped.
#     (/usr/share/doc/limine/USAGE.md "Secure Boot", CONFIG.md "Paths")
#   - limine-entry-tool ignores ENABLE_ENROLL_LIMINE_CONFIG in its drop-ins:
#     load_config() resets it after reading /etc/limine-entry-tool.d/*.conf,
#     so only /etc/default/limine can set it (limine-common-functions:143).
#   - sbctl >= 0.17 ships the Microsoft 2023 CAs (Windows UEFI CA 2023,
#     Microsoft UEFI CA 2023, Option ROM UEFI CA 2023, KEK 2K CA 2023) next to
#     the 2011 ones that expired in June 2026 (sbctl commit 6df94e4).

[[ -n ${HASEEN_SECUREBOOT_SH:-} ]] && return 0
HASEEN_SECUREBOOT_SH=1
SB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/preflight.sh
source "$SB_DIR/../../lib/preflight.sh"
# shellcheck source=../../lib/packages.sh
source "$SB_DIR/../../lib/packages.sh"

SB_HOOK_SRC="$SB_DIR/files/zz-haseen-secureboot.hook"
SB_HOOK_DEST=/etc/pacman.d/hooks/zz-haseen-secureboot.hook
# The hook's Exec is rendered from where this tree is installed
# (PREFIX/share/haseen -> PREFIX/bin/haseen), so /usr/local today and /usr
# after the PKGBUILD phase both work without editing the file.
SB_HASEEN_BIN="$(cd "$SB_DIR/../../../.." && pwd)/bin/haseen"
sb_hook_render() { sed "s|@HASEEN_BIN@|$SB_HASEEN_BIN|" "$SB_HOOK_SRC"; }
SB_SBCTL_HOOK=zz-sbctl.hook
SB_SBCTL_MIN=0.17
SB_LIMINE_DEFAULT=/etc/default/limine
SB_LIMINE_DROPIN=/etc/limine-entry-tool.d/haseen-secureboot.conf
SB_LIMINE_MARKER='++CONFIG_B2SUM_SIGNATURE++'
SB_SDBOOT_SRC=/usr/lib/systemd/boot/efi/systemd-bootx64.efi
SB_RECOVERY_URL=https://aka.ms/myrecoverykey

# sb_root CMD... — a privileged step. The pacman hook already runs as root and
# must work without sudo(8) installed; everyone else goes through run_root.
sb_root() {
    if ((EUID == 0)); then
        run "$@"
    else
        run_root "$@"
    fi
}

# --- sbctl -------------------------------------------------------------------

# sb_sbctl_version — installed sbctl version (pkgrel stripped); fails when
# sbctl is not installed. Read from the pacman database, which is
# world-readable and present in fixtures, so no sbctl call is needed.
sb_sbctl_version() {
    local d
    for d in "$(sysroot_path /var/lib/pacman/local)"/sbctl-[0-9]*; do
        [[ -d $d ]] || continue
        d="${d##*/sbctl-}"
        printf '%s\n' "${d%-*}"
        return 0
    done
    return 1
}

# sb_version_ge A B — A >= B (sort -V order).
sb_version_ge() { [[ $(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1) == "$2" ]]; }

# sb_sbctl_conf KEY — value of KEY in /etc/sbctl/sbctl.conf (YAML scalar).
sb_sbctl_conf() {
    local f
    f="$(sysroot_path /etc/sbctl/sbctl.conf)"
    [[ -r $f ]] || return 0
    sed -n "s/^$1:[[:space:]]*//p" "$f" | head -n1 | tr -d "\"'"
}

# sbctl's state directory: /var/lib/sbctl since 0.14, /usr/share/secureboot
# before that (sbctl config.go DefaultConfig / OldConfig).
sb_sbctl_state_dir() {
    if [[ ! -d $(sysroot_path /var/lib/sbctl) && -d $(sysroot_path /usr/share/secureboot) ]]; then
        echo /usr/share/secureboot
    else
        echo /var/lib/sbctl
    fi
}

sb_keydir() {
    local v
    v="$(sb_sbctl_conf keydir)"
    [[ -n $v ]] && echo "$v" || echo "$(sb_sbctl_state_dir)/keys"
}

sb_files_db() {
    local v dir
    v="$(sb_sbctl_conf files_db)"
    [[ -n $v ]] && {
        echo "$v"
        return 0
    }
    dir="$(sb_sbctl_state_dir)"
    [[ $dir == /var/lib/sbctl ]] && echo "$dir/files.json" || echo "$dir/files.db"
}

# sb_keys_exist — sbctl create-keys has run. The key directories are 0755 and
# only the key files are 0400, so this works without root.
sb_keys_exist() {
    local kd
    kd="$(sysroot_path "$(sb_keydir)")"
    [[ -e $kd/db/db.key || -e $kd/db/db.pem ]]
}

# sb_tracked_files — host paths of every file sbctl re-signs (its database).
sb_tracked_files() {
    local db
    db="$(sysroot_path "$(sb_files_db)")"
    [[ -r $db ]] || return 0
    { grep -oE '"output_file": *"[^"]*"' "$db" || true; } | sed -E 's/^"output_file": *"//; s/"$//'
}

sb_is_tracked() {
    local f
    while IFS= read -r f; do
        [[ $f == "$1" ]] && return 0
    done < <(sb_tracked_files)
    return 1
}

# sb_sbctl_hook_active — sbctl's own pacman hook is installed and not masked,
# so its `sbctl sign-all -g` runs right after zz-haseen-secureboot.hook.
sb_sbctl_hook_active() {
    local mask
    [[ -e $(sysroot_path "/usr/share/libalpm/hooks/$SB_SBCTL_HOOK") ]] || return 1
    mask="$(sysroot_path "/etc/pacman.d/hooks/$SB_SBCTL_HOOK")"
    [[ -e $mask || -L $mask ]] && return 1
    return 0
}

# The read-only sbctl probes. They need the live firmware, the ESP and the key
# files (0400), so they run only on the live machine as root; elsewhere
# SB_SKIP_REASON says why. Tests replace these two functions.
sb_sbctl_readable() {
    if in_sysroot; then
        SB_SKIP_REASON="sbctl is a live-only probe (fixture)"
        return 1
    fi
    if ((EUID != 0)); then
        SB_SKIP_REASON="sbctl needs root to read the keys and the ESP (run as root: haseen secureboot status)"
        return 1
    fi
    have sbctl || {
        SB_SKIP_REASON="sbctl is not on PATH"
        return 1
    }
}
sb_sbctl_query() { sbctl "$@" --json 2>/dev/null; }

# sb_parse_verify — stdin: `sbctl verify --json`; stdout: "<is_signed> <file>"
# per entry (1 signed, 0 unsigned, -1 missing; sbctl cmd/sbctl/verify.go).
sb_parse_verify() {
    local tok v file=""
    while IFS= read -r tok; do
        v="${tok#*:}"
        v="${v#"${v%%[![:space:]]*}"}"
        case "$tok" in
        '"file_name"'*)
            file="${v#\"}"
            file="${file%\"}"
            ;;
        '"is_signed"'*)
            [[ -n $file ]] && printf '%s %s\n' "$v" "$file"
            file=""
            ;;
        esac
    done < <(grep -oE '"file_name": *"[^"]*"|"is_signed": *-?[0-9]+')
}

# --- ESP and boot chain ------------------------------------------------------

sb_esp() { sysroot_path "$ESP_PATH"; }

sb_esp_readable() {
    local e
    e="$(sb_esp)"
    [[ -d $e && -r $e && -x $e ]]
}

# sb_host PATH — strip the sysroot prefix (fixture path -> host path).
sb_host() { printf '%s\n' "${1#"$HASEEN_SYSROOT"}"; }

# sb_efi_kind FILE — limine | systemd-boot | other, from markers every build
# carries: Limine's config-checksum slot, systemd-boot's LoaderInfo string.
sb_efi_kind() {
    if grep -aqF "$SB_LIMINE_MARKER" "$1" 2>/dev/null; then
        echo limine
    elif grep -aqF '#### LoaderInfo: systemd-boot' "$1" 2>/dev/null; then
        echo systemd-boot
    else
        echo other
    fi
}

# sb_limine_main — host path of the Limine binary the firmware entry boots:
# limine-entry-tool's EFI/limine/limine_x64.efi, else the only Limine binary
# in EFI/limine/.
sb_limine_main() {
    local esp f limines=()
    esp="$(sb_esp)"
    if [[ $(sb_efi_kind "$esp/EFI/limine/limine_x64.efi") == limine ]]; then
        echo "$ESP_PATH/EFI/limine/limine_x64.efi"
        return 0
    fi
    for f in "$esp"/EFI/limine/*.[eE][fF][iI]; do
        [[ -f $f && $(sb_efi_kind "$f") == limine ]] && limines+=("$(sb_host "$f")")
    done
    ((${#limines[@]} == 1)) || return 1
    echo "${limines[0]}"
}

# sb_limine_fallback — host path of EFI/BOOT/BOOTX64.EFI when it is a Limine
# copy (limine-install writes the raw, unenrolled package binary there).
sb_limine_fallback() {
    local f="$ESP_PATH/EFI/BOOT/BOOTX64.EFI"
    [[ $(sb_efi_kind "$(sysroot_path "$f")") == limine ]] && echo "$f"
}

# sb_limine_enrolled FILE — the config hash enrolled in a Limine binary
# (128 hex digits after the marker; all zeros = none). Empty when none.
sb_limine_enrolled() {
    local h
    h="$(grep -aoE '\+\+CONFIG_B2SUM_SIGNATURE\+\+[0-9a-f]{128}' "$1" 2>/dev/null | head -n1)" || true
    h="${h#"$SB_LIMINE_MARKER"}"
    [[ $h == *[!0]* ]] || h=""
    printf '%s\n' "$h"
}

sb_limine_conf() { sysroot_path "$ESP_PATH/limine.conf"; }

sb_b2sum() { b2sum "$1" | cut -d' ' -f1; }

# sb_limine_value KEY — KEY as limine-entry-tool's load_config resolves it:
# /usr/share drop-ins, /etc/limine-entry-tool.conf, /etc drop-ins, then
# /etc/default/limine; last assignment wins, one pair of quotes stripped.
# ENABLE_ENROLL_LIMINE_CONFIG is reset after the drop-ins, so only
# /etc/default/limine counts for it.
sb_limine_value() {
    local key="$1" f line val="" files=()
    if [[ $key != ENABLE_ENROLL_LIMINE_CONFIG ]]; then
        for f in "$(sysroot_path /usr/share/limine-entry-tool.d)"/*.conf; do files+=("$f"); done
        files+=("$(sysroot_path /etc/limine-entry-tool.conf)")
        for f in "$(sysroot_path /etc/limine-entry-tool.d)"/*.conf; do files+=("$f"); done
    fi
    files+=("$(sysroot_path "$SB_LIMINE_DEFAULT")")
    for f in "${files[@]}"; do
        [[ -f $f && -r $f ]] || continue
        while IFS= read -r line || [[ -n $line ]]; do
            [[ $line =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=[[:space:]]*(.*)$ ]] || continue
            [[ ${BASH_REMATCH[1]} == "$key" ]] || continue
            val="${BASH_REMATCH[2]}"
            val="${val%\"}"
            val="${val#\"}"
        done <"$f"
    done
    printf '%s\n' "$val"
}

# sb_limine_tools — limine-entry-tool (CachyOS: limine-mkinitcpio-hook) keeps
# limine.conf hashes current on every kernel update; without it an enrolled
# config goes stale and Limine panics, so the Limine path requires it.
sb_limine_tools() { pkg_installed limine-mkinitcpio-hook || pkg_installed limine-entry-tool; }

# sb_limine_unhashed CONF — "LINE: text" for each kernel/module/DTB path in a
# non-EFI entry without a #blake2b suffix. EFI chainload entries are exempt:
# the firmware checks their signature instead (Limine USAGE.md).
sb_limine_unhashed() {
    awk '
        function flush(   i) { if (!efi) for (i = 1; i <= n; i++) print buf[i]; n = 0; efi = 0 }
        /^[[:space:]]*#/ { next }
        /^[[:space:]]*\// { flush(); entry = 1; next }
        entry && /^[[:space:]]*protocol:/ {
            p = $0; sub(/^[[:space:]]*protocol:[[:space:]]*/, "", p)
            if (p ~ /^(efi|efi_chainload)[[:space:]]*$/) efi = 1
        }
        entry && /^[[:space:]]*(path|kernel_path|module_path|dtb_path|image_path):/ {
            v = $0; sub(/^[^:]*:[[:space:]]*/, "", v)
            if (v !~ /#/) { line = $0; sub(/^[[:space:]]+/, "", line); buf[++n] = NR ": " line }
        }
        END { flush() }
    ' "$1"
}

# sb_limine_asset_plan CONF ESP — wallpaper/term_font lines whose #blake2b is
# missing or stale: "LINE<TAB>missing|stale<TAB>new line". ESP is the
# directory boot():/ resolves to. Unresolvable sources are reported and left.
sb_limine_asset_plan() {
    local conf="$1" esp="$2" n=0 line indent key val spec old rel file new
    while IFS= read -r line || [[ -n $line ]]; do
        n=$((n + 1))
        [[ $line =~ ^([[:space:]]*)(wallpaper|term_font):[[:space:]]*(.*[^[:space:]])[[:space:]]*$ ]] || continue
        indent="${BASH_REMATCH[1]}" key="${BASH_REMATCH[2]}" val="${BASH_REMATCH[3]}"
        spec="${val%%#*}"
        old=""
        [[ $val == *#* ]] && old="${val#*#}"
        rel="${spec#\$}"
        if [[ $rel != 'boot():/'* ]]; then
            warn "limine.conf:$n: $key '$spec' is not on boot():/; hash it by hand"
            continue
        fi
        file="$esp/${rel#boot():/}"
        if [[ ! -f $file ]]; then
            warn "limine.conf:$n: $key file '$spec' not found on the ESP"
            continue
        fi
        new="$(sb_b2sum "$file")"
        [[ $old == "$new" ]] && continue
        printf '%s\t%s\t%s%s: %s#%s\n' "$n" "$([[ -z $old ]] && echo missing || echo stale)" "$indent" "$key" "$spec" "$new"
    done <"$conf"
}

# sb_limine_shadows — config files Limine would find before ESP/limine.conf
# (CONFIG.md "Location of the config file"); the enrolled hash would not match.
sb_limine_shadows() {
    local esp p
    esp="$(sb_esp)"
    for p in EFI/limine/limine.conf EFI/BOOT/limine.conf boot/limine/limine.conf boot/limine.conf limine/limine.conf; do
        [[ -e $esp/$p ]] && echo "$ESP_PATH/$p"
    done
    return 0
}

# sb_limine_problems — "blocker: …" / "note: …" lines for the Limine side of
# Secure Boot. Needs a readable ESP.
sb_limine_problems() {
    local conf hash main fb h l state
    conf="$(sb_limine_conf)"
    if [[ ! -r $conf ]]; then
        echo "blocker: $ESP_PATH/limine.conf not found"
        return 0
    fi
    hash="$(sb_b2sum "$conf")"
    if main="$(sb_limine_main)"; then
        h="$(sb_limine_enrolled "$(sysroot_path "$main")")"
        if [[ -z $h ]]; then
            echo "blocker: $main has no config hash enrolled"
        elif [[ $h != "$hash" ]]; then
            echo "blocker: $main has a stale config hash (limine.conf changed since enrollment)"
        fi
    else
        echo "blocker: no Limine binary found in $ESP_PATH/EFI/limine/"
    fi
    if fb="$(sb_limine_fallback)"; then
        h="$(sb_limine_enrolled "$(sysroot_path "$fb")")"
        [[ $h == "$hash" ]] || echo "blocker: fallback $fb is a Limine copy without the current config hash"
    fi
    while IFS= read -r l; do
        [[ -n $l ]] && echo "blocker: limine.conf:$l (no #blake2b: Limine panics under Secure Boot)"
    done < <(sb_limine_unhashed "$conf")
    while IFS=$'\t' read -r l state _; do
        [[ -n $l ]] || continue
        if [[ $state == stale ]]; then
            echo "blocker: limine.conf:$l: wallpaper/font hash is stale (Limine panics on a hash mismatch)"
        else
            echo "note: limine.conf:$l: wallpaper/font has no #blake2b (Limine skips it under Secure Boot)"
        fi
    done < <(sb_limine_asset_plan "$conf" "$(sb_esp)" 2>/dev/null)
    while IFS= read -r l; do
        [[ -n $l ]] && echo "blocker: $l shadows $ESP_PATH/limine.conf (the enrolled hash would not match)"
    done < <(sb_limine_shadows)
    return 0
}

# sb_grub_id — the --bootloader-id of the installed GRUB (EFI/<id>/grubx64.efi).
sb_grub_id() {
    local f
    for f in "$(sb_esp)"/EFI/*/grubx64.efi; do
        [[ -f $f ]] || continue
        f="${f%/grubx64.efi}"
        echo "${f##*/}"
        return 0
    done
    return 1
}

# sb_chain_files — host paths that must carry our signature for this
# bootloader to boot under Secure Boot. Needs a readable ESP.
#   limine:       the Limine binary, a Limine fallback, UKIs (chainloaded).
#                 Plain kernels are checked by #blake2b, not by signature.
#   systemd-boot: the loader, its fallback copy, UKIs, Type 1 entry kernels.
#   grub:         grubx64.efi and /boot/vmlinuz-*.
sb_chain_files() {
    local esp f k p
    esp="$(sb_esp)"
    {
        case "$BOOTLOADER" in
        limine)
            sb_limine_main || true
            sb_limine_fallback || true
            ;;
        systemd-boot)
            [[ -f $esp/EFI/systemd/systemd-bootx64.efi ]] && echo "$ESP_PATH/EFI/systemd/systemd-bootx64.efi"
            [[ $(sb_efi_kind "$esp/EFI/BOOT/BOOTX64.EFI") == systemd-boot ]] && echo "$ESP_PATH/EFI/BOOT/BOOTX64.EFI"
            for f in "$esp"/loader/entries/*.conf; do
                [[ -r $f ]] || continue
                while read -r k p _; do
                    [[ $k == linux || $k == efi ]] || continue
                    [[ -f $esp$p ]] && echo "$ESP_PATH$p"
                done <"$f"
            done
            ;;
        grub)
            for f in "$esp"/EFI/*/grubx64.efi; do
                [[ -f $f ]] && sb_host "$f"
            done
            for f in "$(sysroot_path /boot)"/vmlinuz-*; do
                [[ -f $f ]] && sb_host "$f"
            done
            ;;
        esac
        if [[ $BOOTLOADER == limine || $BOOTLOADER == systemd-boot ]]; then
            for f in "$esp"/EFI/Linux/*.[eE][fF][iI]; do
                [[ -f $f ]] && sb_host "$f"
            done
        fi
        # The group's status is its last test; pipefail must not see it.
        :
    } | awk '!seen[$0]++'
}

# sb_classify_verify JSON — sorts `sbctl verify --json` output against the
# boot chain. Sets SB_SIGNED (count), SB_BLOCKERS and SB_NOTES (arrays).
# Blockers: a tracked or boot-chain file that is unsigned, missing or not
# verified. Ignored: Microsoft's own binaries (trusted through the enrolled
# Microsoft keys) and, on Limine, kernels (checked by #blake2b).
sb_classify_verify() {
    local json="$1" st f
    local -a must=()
    local -A want=() seen=()
    SB_SIGNED=0
    SB_BLOCKERS=()
    SB_NOTES=()
    while IFS= read -r f; do
        [[ -n $f && -z ${want[$f]:-} ]] || continue
        want[$f]=1
        must+=("$f")
    done < <(sb_tracked_files; sb_chain_files)
    while read -r st f; do
        [[ -n $f ]] || continue
        seen[$f]=1
        if [[ $st == 1 ]]; then
            SB_SIGNED=$((SB_SIGNED + 1))
        elif [[ -n ${want[$f]:-} ]]; then
            SB_BLOCKERS+=("$f: $([[ $st == -1 ]] && echo 'missing' || echo 'not signed')")
        elif [[ ${f,,} == */efi/microsoft/* ]]; then
            continue
        elif [[ $BOOTLOADER == limine && ${f##*/} == vmlinuz* ]]; then
            continue
        else
            SB_NOTES+=("$f: not signed (outside the detected boot chain; sign it with sbctl sign -s if you boot it)")
        fi
    done < <(printf '%s\n' "$json" | sb_parse_verify)
    for f in "${must[@]}"; do
        [[ -n ${seen[$f]:-} ]] || SB_BLOCKERS+=("$f: not verified (sbctl does not track it)")
    done
}

# --- crypto and Windows ------------------------------------------------------

# sb_tpm_luks — prints "NAME DEVICE" for every crypttab volume unlocked by the
# TPM2 (tpm2-device=). Returns 0 found, 1 none, 2 unreadable (crypttab is
# 0600 on many installs).
sb_tpm_luks() {
    local f name dev key opts hit=1 unreadable=false cmdline
    for f in /etc/crypttab /etc/crypttab.initramfs; do
        f="$(sysroot_path "$f")"
        [[ -e $f ]] || continue
        if [[ ! -r $f ]]; then
            unreadable=true
            continue
        fi
        while read -r name dev key opts; do
            [[ -n $name && $name != \#* ]] || continue
            [[ ,$opts, == *,tpm2-device=* ]] || continue
            printf '%s %s\n' "$name" "$dev"
            hit=0
        done <"$f"
    done
    cmdline="$(sysroot_path /proc/cmdline)"
    if [[ -r $cmdline ]] && grep -qE '(^|[[:space:]])rd\.luks\.options=[^[:space:]]*tpm2-device=' "$cmdline"; then
        echo "initramfs rd.luks.options"
        hit=0
    fi
    ((hit == 0)) && return 0
    $unreadable && return 2
    return 1
}

# sb_dev_path SPEC — crypttab device spec as a /dev path for systemd-cryptenroll.
sb_dev_path() {
    case "$1" in
    UUID=*) echo "/dev/disk/by-uuid/${1#UUID=}" ;;
    PARTUUID=*) echo "/dev/disk/by-partuuid/${1#PARTUUID=}" ;;
    LABEL=*) echo "/dev/disk/by-label/${1#LABEL=}" ;;
    *) echo "$1" ;;
    esac
}

# sb_bitlocker_present — a BitLocker volume is visible (live only: lsblk).
sb_bitlocker_present() {
    in_sysroot && return 1
    have lsblk || return 1
    lsblk -rno FSTYPE 2>/dev/null | grep -qx BitLocker
}

sb_warn_bitlocker() {
    cat <<EOF

!! Windows / BitLocker
   Enrolling keys changes the firmware's db, and that changes TPM PCR 7.
   BitLocker seals its key to PCR 7, so Windows asks for the 48-digit
   BitLocker recovery key on its next boot. Get the key now, before you
   continue: $SB_RECOVERY_URL (or in Windows: manage-bde -protectors -get C:).
   After one boot with the recovery key, BitLocker reseals by itself.
EOF
}

sb_warn_tpm() {
    local rc=0 lines name dev
    lines="$(sb_tpm_luks)" || rc=$?
    if ((rc == 0)); then
        echo
        echo "!! LUKS unlocked by the TPM2"
        echo "   This volume's TPM2 policy covers PCR 7, which changes with Secure Boot."
        echo "   Expect the passphrase or recovery-key prompt once, then re-enroll the"
        echo "   TPM2 slot (as root) after Secure Boot is on:"
        while read -r name dev; do
            if [[ $name == initramfs ]]; then
                echo "     (rd.luks.options on the kernel command line: re-enroll that volume)"
            else
                echo "     systemd-cryptenroll --wipe-slot=tpm2 --tpm2-device=auto --tpm2-pcrs=7 $(sb_dev_path "$dev")   # $name"
            fi
        done <<<"$lines"
    elif ((rc == 2)) && $LUKS_DETECTED; then
        echo
        echo "!! LUKS: /etc/crypttab is readable only by root, so a TPM2 binding could not"
        echo "   be checked. If you enrolled the volume with systemd-cryptenroll --tpm2-device,"
        echo "   re-enroll it with --tpm2-pcrs=7 after Secure Boot is on."
    fi
    return 0
}

# --- firmware instructions ---------------------------------------------------

sb_firmware_steps() {
    local state="$SECUREBOOT_STATE"
    [[ $state == unknown ]] && state="in an unknown state (efivars unreadable)"
    cat <<EOF
Secure Boot is $state, and the firmware is not in Setup Mode, so keys cannot
be enrolled yet. Put the firmware into Setup Mode:

  1. Reboot into the firmware settings:
       systemctl reboot --firmware-setup
  2. Open the Secure Boot page and turn Secure Boot off for now (setup says
     when to turn it back on).
  3. Clear the keys so the firmware enters Setup Mode. The option is called
     "Reset to Setup Mode", "Clear Secure Boot keys" or "Delete all Secure
     Boot variables" (ASUS and MSI: set Secure Boot Mode to Custom first, then
     Key Management). "Restore factory keys" is NOT Setup Mode.
     Gigabyte: reject the "reset without saving" prompt that may follow.
  4. Save, boot back into this system and run:
       haseen secureboot setup

Windows keeps booting: setup enrolls Microsoft's keys next to yours.
EOF
    sb_keys_exist && printf '\nKeys already exist in %s. If they are enrolled and Secure Boot is on,\nthere is nothing to set up: check with  haseen secureboot status\n' "$(sb_keydir)"
    pkg_installed sbctl || printf '\nInstall sbctl first:  haseen layer apply secureboot\n'
    return 0
}

# --- status ------------------------------------------------------------------

sb_hook_current() { cmp -s <(sb_hook_render) "$(sysroot_path "$SB_HOOK_DEST")"; }

# sb_report — read-only; never escalates. Prints ok:/warn:/missing: lines.
# Returns 0 when Secure Boot is enforcing and the whole boot chain verified
# signed (and, on Limine, the config is enrolled and fully hashed); 1 otherwise.
# Also sets SB_HAVE_SBCTL and SB_HAVE_HOOK for layer_status.
sb_report() {
    local ready=true ver rc json kind text l
    SB_HAVE_SBCTL=false
    SB_HAVE_HOOK=false

    if [[ $FIRMWARE != uefi ]]; then
        echo "missing: firmware: legacy BIOS boot; Secure Boot needs UEFI"
        return 1
    fi
    echo "ok: firmware: UEFI"
    case "$SECUREBOOT_STATE" in
    enabled) echo "ok: secure boot: enabled" ;;
    setup) echo "warn: secure boot: Setup Mode, no keys enrolled (next: haseen secureboot setup)" ;;
    disabled) echo "warn: secure boot: disabled in the firmware" ;;
    *) echo "warn: secure boot: state unknown (efivars unreadable)" ;;
    esac
    [[ $SECUREBOOT_STATE == enabled ]] || ready=false

    if [[ $BOOTLOADER == unknown ]]; then
        echo "warn: bootloader: not detected"
        ready=false
    else
        echo "ok: bootloader: $BOOTLOADER, ESP $ESP_PATH (${BOOTLOADER_SOURCE:-detected})"
    fi
    if $WINDOWS_ON_ESP; then
        echo "ok: windows: Boot Manager on the ESP (Microsoft keys stay enrolled)"
    elif ! sb_esp_readable; then
        echo "warn: windows: not checked (ESP $ESP_PATH is readable only by root)"
    fi
    sb_bitlocker_present && echo "warn: windows: BitLocker volume present; enrollment needs its recovery key ($SB_RECOVERY_URL)"

    if ver="$(sb_sbctl_version)"; then
        SB_HAVE_SBCTL=true
        if sb_version_ge "$ver" "$SB_SBCTL_MIN"; then
            echo "ok: sbctl: $ver"
        else
            echo "warn: sbctl: $ver predates the Microsoft 2023 CAs (needs >= $SB_SBCTL_MIN)"
            ready=false
        fi
    else
        echo "missing: sbctl: not installed (haseen layer apply secureboot)"
        ready=false
    fi
    if sb_keys_exist; then
        echo "ok: keys: $(sb_keydir)"
    else
        echo "missing: keys: none (haseen secureboot setup)"
        ready=false
    fi

    if $SB_HAVE_SBCTL && sb_sbctl_readable; then
        json="$(sb_sbctl_query status || true)"
        text="$(tr -d '\n ' <<<"$json")"
        if [[ $text =~ \"vendors\":\[([^]]*)\] ]]; then
            l="${BASH_REMATCH[1]//\"/}"
            if [[ ,$l, == *,microsoft,* ]]; then
                echo "ok: enrolled vendor keys: ${l//,/ }"
            else
                echo "warn: enrolled vendor keys: ${l:-none}; Microsoft's are missing (Windows, GPU option ROMs and anti-cheat need them)"
                [[ $SECUREBOOT_STATE == enabled ]] && ready=false
            fi
        fi
    fi

    if [[ $BOOTLOADER == limine ]]; then
        sb_limine_tools || echo "warn: limine: limine-entry-tool is not installed; kernel updates would leave limine.conf hashes stale"
        if [[ $(sb_limine_value ENABLE_ENROLL_LIMINE_CONFIG) == yes ]]; then
            echo "ok: limine: ENABLE_ENROLL_LIMINE_CONFIG=yes"
        else
            echo "warn: limine: ENABLE_ENROLL_LIMINE_CONFIG is not yes in $SB_LIMINE_DEFAULT (setup sets it)"
            ready=false
        fi
        [[ $(sb_limine_value ENABLE_VERIFICATION) == yes ]] || echo "warn: limine: ENABLE_VERIFICATION is not yes; new entries get no #blake2b"
        if sb_esp_readable; then
            local problems=0
            while IFS= read -r l; do
                [[ -n $l ]] || continue
                case "$l" in
                blocker:*)
                    echo "warn: limine: ${l#blocker: }"
                    problems=$((problems + 1))
                    ;;
                note:*) echo "warn: limine: ${l#note: }" ;;
                esac
            done < <(sb_limine_problems)
            if ((problems == 0)); then
                echo "ok: limine: config hash enrolled and current; every boot path carries #blake2b"
            else
                ready=false
            fi
        else
            echo "warn: limine: enrollment not checked (ESP $ESP_PATH is readable only by root)"
            ready=false
        fi
    fi

    if ! $SB_HAVE_SBCTL; then
        echo "warn: signatures: not checked (sbctl not installed)"
        ready=false
    elif ! sb_keys_exist; then
        echo "missing: signatures: no keys to sign with"
        ready=false
    elif ! sb_sbctl_readable; then
        echo "warn: signatures: not checked ($SB_SKIP_REASON)"
        ready=false
    else
        json="$(sb_sbctl_query verify || true)"
        sb_classify_verify "$json"
        if ((${#SB_BLOCKERS[@]} == 0)); then
            echo "ok: signatures: $SB_SIGNED file(s) signed, boot chain complete"
        else
            for l in "${SB_BLOCKERS[@]}"; do echo "missing: signature: $l"; done
            ready=false
        fi
        for l in "${SB_NOTES[@]}"; do echo "warn: signature: $l"; done
    fi

    rc=0
    l="$(sb_tpm_luks)" || rc=$?
    if ((rc == 0)); then
        while read -r kind text; do
            echo "warn: luks: $kind ($text) unlocks with the TPM2; re-enroll it with --tpm2-pcrs=7 after Secure Boot changes"
        done <<<"$l"
    elif ((rc == 2)) && $LUKS_DETECTED; then
        echo "warn: luks: TPM2 binding not checked (/etc/crypttab is readable only by root)"
    fi

    if sb_hook_current; then
        SB_HAVE_HOOK=true
        echo "ok: pacman hook: $SB_HOOK_DEST"
    elif [[ -e $(sysroot_path "$SB_HOOK_DEST") ]]; then
        SB_HAVE_HOOK=true
        echo "warn: pacman hook: $SB_HOOK_DEST differs from the shipped one (haseen layer apply secureboot)"
    else
        echo "missing: pacman hook: $SB_HOOK_DEST (haseen layer apply secureboot)"
    fi

    $ready
}

# --- signing steps (setup and sign) ------------------------------------------

# sb_limine_assets — add or refresh wallpaper/font #blake2b in limine.conf.
# Returns 0 when it changed (or, in a dry-run, would change) the config.
sb_limine_assets() {
    local conf plan n state line
    conf="$(sb_limine_conf)"
    if ! sb_esp_readable || [[ ! -r $conf ]]; then
        # Only a dry-run as a normal user gets here; the helper is a no-op
        # when every hash is current.
        sb_root "$SB_DIR/limine-hash-assets.sh" "$ESP_PATH/limine.conf" "$ESP_PATH"
        return 0
    fi
    plan="$(sb_limine_asset_plan "$conf" "$(sb_esp)")"
    [[ -n $plan ]] || return 1
    if $DRY_RUN; then
        while IFS=$'\t' read -r n state line; do
            echo "    limine.conf:$n ($state hash): ${line#"${line%%[![:space:]]*}"}"
        done <<<"$plan"
    fi
    sb_root "$SB_DIR/limine-hash-assets.sh" "$ESP_PATH/limine.conf" "$ESP_PATH"
}

# sb_limine_refresh_fallback [force] — limine-install copies the raw,
# unenrolled package binary to EFI/BOOT/BOOTX64.EFI. Signing that copy would
# leave a signed Limine that enforces nothing (no config hash), so the
# fallback becomes a copy of the enrolled, signed main binary instead.
sb_limine_refresh_fallback() {
    local force="${1:-}" main fb
    if ! sb_esp_readable; then
        echo "    (ESP not readable as this user: a Limine copy at $ESP_PATH/EFI/BOOT/BOOTX64.EFI is replaced with the enrolled binary when this runs)"
        return 0
    fi
    fb="$(sb_limine_fallback)" || return 0
    main="$(sb_limine_main)" || return 0
    if [[ -z $force && $(sb_limine_enrolled "$(sysroot_path "$fb")") == "$(sb_b2sum "$(sb_limine_conf)")" ]]; then
        return 0
    fi
    sb_root cp "$main" "$fb"
    sb_is_tracked "$fb" || sb_root sbctl sign -s "$fb"
}

# sb_track_chain — sign and track (-s) each boot-chain file sbctl does not
# track yet, so sign-all and zz-sbctl.hook keep it signed from now on. On
# Limine, UKIs are left to mkinitcpio's sbctl hook, which signs them before
# limine-entry-tool hashes them; signing afterwards would break the hash.
sb_track_chain() {
    local f files=()
    mapfile -t files < <(sb_chain_files)
    for f in "${files[@]}"; do
        [[ -n $f ]] || continue
        [[ $BOOTLOADER == limine && ${f,,} == */efi/linux/* ]] && continue
        sb_is_tracked "$f" && continue
        sb_root sbctl sign -s "$f"
    done
    return 0
}

# sb_reexec_as_root SELF ARGS... — setup and sign must read the ESP, which is
# 0700 on CachyOS/Omarchy installs. Rather than escalating read by read, the
# whole command reruns as root once. Never under a sysroot or a dry-run.
sb_reexec_as_root() {
    local self="$1"
    shift
    in_sysroot && return 0
    $DRY_RUN && return 0
    ((EUID == 0)) && return 0
    sb_esp_readable && return 0
    info "the ESP ($ESP_PATH) is readable only by root; continuing as root"
    local rc=0
    run_root "$self" "$@" || rc=$?
    exit "$rc"
}
