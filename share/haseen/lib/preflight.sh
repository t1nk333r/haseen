# shellcheck shell=bash disable=SC2034  # the globals set here are this library's output
# preflight.sh — read-only detection of the machine haseen is about to touch.
# Sourced, never executed. Every probe reads through sysroot_path so fixture
# trees under tests/fixtures/ can stand in for a real host; probes that need a
# live kernel or firmware (bootctl, lsblk) are skipped under a sysroot.
#
# Bootloader and LUKS detection adapted from omacachy
# bin/install-omarchy-quattro.sh (t1nk33r, own code): detect from what the
# firmware loaded and what the ESP carries, never from installed packages.

[[ -n ${HASEEN_PREFLIGHT_SH:-} ]] && return 0
HASEEN_PREFLIGHT_SH=1
# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

EFI_GLOBAL_GUID=8be4df61-93ca-11d2-aa0d-00e098032b8c

# os_release_field KEY — value of KEY in os-release, quotes stripped.
os_release_field() {
    local file
    file="$(sysroot_path /etc/os-release)"
    [[ -r $file ]] || file="$(sysroot_path /usr/lib/os-release)"
    [[ -r $file ]] || return 0
    sed -n "s/^$1=//p" "$file" | head -n1 | tr -d '"'
}

# preflight_distro — sets HASEEN_DISTRO to cachyos | arch | omarchy | nixos |
# unsupported, and DISTRO_PRETTY. CachyOS is the primary target; plain Arch is
# supported; an Omarchy host is supported with a warning (haseen replaces it,
# see docs/decisions/0001). NixOS is recognised only so that callers can refuse
# it by name: it is not supported.
preflight_distro() {
    local id like
    id="$(os_release_field ID)"
    like="$(os_release_field ID_LIKE)"
    DISTRO_PRETTY="$(os_release_field PRETTY_NAME)"
    case "$id" in
    cachyos) HASEEN_DISTRO=cachyos ;;
    arch) HASEEN_DISTRO=arch ;;
    omarchy) HASEEN_DISTRO=omarchy ;;
    nixos) HASEEN_DISTRO=nixos ;;
    *)
        # CachyOS derivatives and Omarchy-on-CachyOS hosts keep ID=cachyos;
        # anything else Arch-like is treated as Arch.
        if [[ -r $(sysroot_path /etc/cachyos-release) ]]; then
            HASEEN_DISTRO=cachyos
        elif [[ " $like " == *" arch "* ]]; then
            HASEEN_DISTRO=arch
        else
            HASEEN_DISTRO=unsupported
        fi
        ;;
    esac
}

# efivar_byte NAME — the first data byte of a global EFI variable (efivarfs
# prefixes 4 attribute bytes). Empty when unreadable.
efivar_byte() {
    local f
    f="$(sysroot_path "/sys/firmware/efi/efivars/$1-$EFI_GLOBAL_GUID")"
    [[ -r $f ]] || return 0
    od -An -t u1 -j4 -N1 "$f" | tr -d ' '
}

# preflight_firmware — FIRMWARE (uefi|bios) and SECUREBOOT_STATE
# (enabled | disabled | setup | unknown). "setup" means Setup Mode: custom keys
# can be enrolled without touching firmware menus.
preflight_firmware() {
    if [[ -d $(sysroot_path /sys/firmware/efi) ]]; then
        FIRMWARE=uefi
    else
        FIRMWARE=bios
        SECUREBOOT_STATE=unknown
        return 0
    fi
    local sb setup
    sb="$(efivar_byte SecureBoot)"
    setup="$(efivar_byte SetupMode)"
    if [[ $setup == 1 ]]; then
        SECUREBOOT_STATE=setup
    elif [[ $sb == 1 ]]; then
        SECUREBOOT_STATE=enabled
    elif [[ $sb == 0 ]]; then
        SECUREBOOT_STATE=disabled
    else
        SECUREBOOT_STATE=unknown
    fi
}

# Candidate ESP mount points, most authoritative first.
esp_candidates() {
    if ! in_sysroot && have bootctl; then
        local esp
        esp="$(bootctl --print-esp-path 2>/dev/null || true)"
        [[ -z $esp ]] || sysroot_path "$esp"
    fi
    sysroot_path /boot
    sysroot_path /efi
    sysroot_path /boot/efi
}

# esp_carries ESP KIND — does the ESP root carry loader KIND?
esp_carries() {
    local esp="$1" kind="$2" hits=()
    shopt -s nullglob
    case "$kind" in
    grub)
        hits=("$esp"/EFI/*/grubx64.efi)
        [[ -e $esp/grub/grub.cfg ]] && hits+=(x)
        ;;
    systemd-boot)
        hits=("$esp"/EFI/systemd/systemd-boot*.efi)
        [[ -e $esp/loader/loader.conf ]] && hits+=(x)
        ;;
    limine)
        hits=("$esp"/EFI/limine/*.efi "$esp"/EFI/BOOT/limine*.efi)
        [[ -e $esp/limine.conf || -e $esp/limine/limine.conf ]] && hits+=(x)
        ;;
    windows)
        [[ -e $esp/EFI/Microsoft/Boot/bootmgfw.efi ]] && hits+=(x)
        ;;
    esac
    shopt -u nullglob
    ((${#hits[@]} > 0))
}

# preflight_bootloader — BOOTLOADER (limine | systemd-boot | grub | unknown),
# BOOTLOADER_SOURCE (the evidence), ESP_PATH (host path, sysroot stripped) and
# WINDOWS_ON_ESP (true|false).
preflight_bootloader() {
    BOOTLOADER=unknown
    BOOTLOADER_SOURCE=""
    ESP_PATH=""
    WINDOWS_ON_ESP=false

    if ! in_sysroot && have bootctl; then
        local product
        product="$(bootctl status 2>/dev/null | grep -m1 'Product:' || true)"
        case "${product,,}" in
        *limine*) BOOTLOADER=limine ;;
        *systemd-boot*) BOOTLOADER=systemd-boot ;;
        *grub*) BOOTLOADER=grub ;;
        esac
        [[ $BOOTLOADER == unknown ]] || BOOTLOADER_SOURCE="firmware LoaderInfo: ${product##*Product: }"
    fi

    local esp kind found=() where=""
    while read -r esp; do
        [[ -d $esp && -r $esp && -x $esp ]] || continue
        esp_carries "$esp" windows && WINDOWS_ON_ESP=true
        for kind in grub systemd-boot limine; do
            esp_carries "$esp" "$kind" || continue
            [[ " ${found[*]-} " == *" $kind "* ]] || found+=("$kind")
            where="$esp"
        done
        [[ -n $where ]] && break
    done < <(esp_candidates)
    [[ -n $where ]] && ESP_PATH="${where#"$HASEEN_SYSROOT"}"

    if [[ $BOOTLOADER == unknown ]] && ((${#found[@]} > 0)); then
        # A stray Limine EFI next to a live GRUB/systemd-boot is the realistic
        # collision; prefer the non-Limine loader and say so.
        for kind in grub systemd-boot limine; do
            [[ " ${found[*]} " == *" $kind "* ]] || continue
            BOOTLOADER="$kind"
            break
        done
        BOOTLOADER_SOURCE="ESP contents under $ESP_PATH"
        ((${#found[@]} > 1)) && warn "more than one bootloader on the ESP (${found[*]}); assuming $BOOTLOADER."
    fi

    # /etc/default/limine names the ESP even when /boot is 0700 and unreadable.
    if [[ -z $ESP_PATH ]]; then
        local def
        def="$(sysroot_path /etc/default/limine)"
        if [[ -r $def ]]; then
            ESP_PATH="$(sed -n 's/^ESP_PATH=//p' "$def" | tr -d '"' | tail -n1)"
            if [[ $BOOTLOADER == unknown ]]; then
                BOOTLOADER=limine
                BOOTLOADER_SOURCE="/etc/default/limine (ESP unreadable without root)"
            fi
        fi
    fi
    [[ -n $ESP_PATH ]] || ESP_PATH=/boot
}

# preflight_luks — LUKS_DETECTED (true|false): the root device sits behind
# LUKS, or the kernel command line carries an unlock parameter.
preflight_luks() {
    LUKS_DETECTED=false
    local cmdline=""
    [[ -r $(sysroot_path /proc/cmdline) ]] && cmdline="$(<"$(sysroot_path /proc/cmdline)")"
    if [[ $cmdline =~ (^|[[:space:]])(cryptdevice=|rd\.luks\.(uuid|name)=) ]]; then
        LUKS_DETECTED=true
        return 0
    fi
    in_sysroot && return 0
    local src
    src="$(findmnt -no SOURCE / 2>/dev/null || true)"
    src="${src%%\[*}"
    [[ -n $src ]] && lsblk -sno FSTYPE "$src" 2>/dev/null | grep -q crypto_LUKS && LUKS_DETECTED=true
    return 0
}

# preflight_gpu — GPU_VENDORS: space-separated subset of "intel amd nvidia",
# read from PCI display-class devices in sysfs.
preflight_gpu() {
    GPU_VENDORS=""
    local d class vendor name
    for d in "$(sysroot_path /sys/bus/pci/devices)"/*; do
        [[ -r $d/class && -r $d/vendor ]] || continue
        class="$(<"$d/class")"
        [[ $class == 0x03* ]] || continue
        vendor="$(<"$d/vendor")"
        case "$vendor" in
        0x8086) name=intel ;;
        0x1002) name=amd ;;
        0x10de) name=nvidia ;;
        *) continue ;;
        esac
        [[ " $GPU_VENDORS " == *" $name "* ]] || GPU_VENDORS="${GPU_VENDORS:+$GPU_VENDORS }$name"
    done
}

# preflight_all — run every probe.
preflight_all() {
    preflight_distro
    preflight_firmware
    preflight_bootloader
    preflight_luks
    preflight_gpu
}

# preflight_report — one fact per line, stable keys (tests compare these).
preflight_report() {
    printf 'distro=%s\n' "$HASEEN_DISTRO"
    printf 'firmware=%s\n' "$FIRMWARE"
    printf 'secureboot=%s\n' "$SECUREBOOT_STATE"
    printf 'bootloader=%s\n' "$BOOTLOADER"
    printf 'esp=%s\n' "$ESP_PATH"
    printf 'windows_on_esp=%s\n' "$WINDOWS_ON_ESP"
    printf 'luks=%s\n' "$LUKS_DETECTED"
    printf 'gpu=%s\n' "${GPU_VENDORS:-none}"
}
