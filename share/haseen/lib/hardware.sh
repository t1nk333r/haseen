# shellcheck shell=bash
# hardware.sh — which hardware quirks this machine needs. Sourced, never executed.
#
# Adapted from Omarchy bin/omarchy-hw-match and install/hardware/all.sh (MIT,
# Copyright (c) David Heinemeier Hansson). Upstream matches a pattern against
# the DMI product name or family inside each fix script, and runs every script
# in a fixed list. Here the match rule is data: `share/haseen/hardware/quirks.tsv`
# holds one row per quirk, and the body beside it is optional, so adding a quirk
# is one file and never a dispatcher change.
#
# Every probe reads through sysroot_path, so `tests/fixtures/<name>/` stands in
# for a real machine and HASEEN_SYSROOT exercises any model without owning it.

[[ -n ${HASEEN_HARDWARE_SH:-} ]] && return 0
HASEEN_HARDWARE_SH=1

# shellcheck source=ledger.sh
source "$(dirname "${BASH_SOURCE[0]}")/ledger.sh"

QUIRK_ID_RE='^[a-z0-9][a-z0-9-]*$'

hw_dir() { printf '%s\n' "${HASEEN_HARDWARE_DIR:-$HASEEN_PATH/hardware}"; }
hw_table() { printf '%s\n' "$(hw_dir)/quirks.tsv"; }
hw_body() { printf '%s\n' "$(hw_dir)/$1.sh"; }
hw_has_body() { [[ -r $(hw_body "$1") ]]; }

# --- DMI ------------------------------------------------------------------

# hw_dmi FIELD — sys_vendor, product_name, product_family, chassis_type.
# Firmware that leaves a field unset writes a placeholder; those are noise in a
# match, so they read as empty.
hw_dmi() {
    local file value
    file="$(sysroot_path "/sys/class/dmi/id/$1")"
    [[ -r $file ]] || return 0
    value="$(tr -d '\0' <"$file" 2>/dev/null || true)"
    value="${value%"${value##*[![:space:]]}"}"
    case "${value,,}" in
    "" | "to be filled by o.e.m."* | "system product name" | "system manufacturer" | \
        "default string" | "none" | "not applicable" | "unknown" | "n/a") return 0 ;;
    esac
    printf '%s\n' "$value"
}

# hw_dmi_line — "vendor | product | family" for people, never for matching.
hw_dmi_line() {
    printf '%s | %s | %s\n' "$(hw_dmi sys_vendor)" "$(hw_dmi product_name)" "$(hw_dmi product_family)"
}

# --- probes ---------------------------------------------------------------
# Each answers one question about this machine, read-only, exit 0 for yes.

hw_probe_laptop() {
    local state
    for state in "$(sysroot_path /proc/acpi/button/lid)"/*/state; do
        [[ -e $state ]] && return 0
    done
    # Laptop chassis types: 8 Portable, 9 Laptop, 10 Notebook, 14 Sub Notebook,
    # 30 Tablet, 31 Convertible, 32 Detachable.
    case "$(hw_dmi chassis_type)" in
    8 | 9 | 10 | 14 | 30 | 31 | 32) return 0 ;;
    esac
    return 1
}

hw_probe_vm() {
    # A fixture has no hypervisor to detect, so there the firmware strings every
    # hypervisor writes are the signal.
    if in_sysroot; then
        [[ "$(hw_dmi sys_vendor) $(hw_dmi product_name)" =~ (QEMU|KVM|VMware|VirtualBox|innotek|Xen|Virtual\ Machine|Parallels|Bochs) ]]
        return
    fi
    have systemd-detect-virt || return 1
    systemd-detect-virt --vm --quiet
}

# hw_pci_class_vendor CLASS VENDOR [MIN_DEVICE] — a PCI device of that class and
# vendor exists. Reads the cached sysfs ids, never lspci, which resumes a
# runtime-suspended GPU to read its config space.
hw_pci_class_vendor() {
    local class="$1" vendor="$2" min="${3:-}" device id
    shopt -s nullglob
    for device in "$(sysroot_path /sys/bus/pci/devices)"/*; do
        [[ -r $device/vendor && -r $device/class ]] || continue
        [[ "$(<"$device/vendor")" == "$vendor" ]] || continue
        [[ "$(<"$device/class")" == $class* ]] || continue
        [[ -z $min ]] && return 0
        id="$(<"$device/device")"
        ((${id/0x/16#} >= min)) && return 0
    done
    return 1
}

# Turing (device id 0x1e00) is the first NVIDIA generation with GSP firmware and
# the open kernel module; Maxwell, Pascal and Volta all sit below that line.
hw_probe_nvidia_gsp() { hw_pci_class_vendor 0x03 0x10de $((0x1e00)); }
hw_probe_nvidia() { hw_pci_class_vendor 0x03 0x10de; }
hw_probe_intel_gpu() { hw_pci_class_vendor 0x03 0x8086; }
hw_probe_amd_gpu() { hw_pci_class_vendor 0x03 0x1002; }

# hw_pci SPEC — SPEC is `VENDOR`, `VENDOR/CLASSPREFIX` or `VENDOR:DEVICE`, all
# as the lower-case hex sysfs writes (0x8086, 0x0403). Upstream greps `lspci
# -nn` for the same ids; sysfs is the cached copy and does not wake the device.
hw_pci() {
    local spec="$1" vendor class device dev
    vendor="${spec%%[:/]*}"
    class=""
    device=""
    [[ $spec == */* ]] && class="${spec#*/}"
    [[ $spec == *:* ]] && device="${spec#*:}"
    shopt -s nullglob
    for dev in "$(sysroot_path /sys/bus/pci/devices)"/*; do
        [[ -r $dev/vendor ]] || continue
        [[ "$(<"$dev/vendor")" == "$vendor" ]] || continue
        [[ -z $class || "$(<"$dev/class")" == "$class"* ]] || continue
        [[ -z $device || "$(<"$dev/device")" == "$device" ]] || continue
        return 0
    done
    return 1
}

# hw_usb VID:PID — a USB device with those ids is plugged in.
hw_usb() {
    local vid="${1%%:*}" pid="${1#*:}" dev
    shopt -s nullglob
    for dev in "$(sysroot_path /sys/bus/usb/devices)"/*; do
        [[ -r $dev/idVendor && -r $dev/idProduct ]] || continue
        [[ "$(<"$dev/idVendor")" == "$vid" && "$(<"$dev/idProduct")" == "$pid" ]] && return 0
    done
    return 1
}

# hw_input RE — an input device whose name matches RE (the file upstream greps
# for the Synaptics touchpad).
hw_input() {
    local devices
    devices="$(sysroot_path /proc/bus/input/devices)"
    [[ -r $devices ]] || return 1
    grep -qiE -- "$1" "$devices"
}

hw_cpu() {
    local info
    info="$(sysroot_path /proc/cpuinfo)"
    [[ -r $info ]] || return 1
    grep -qiE -- "$1" "$info"
}

hw_probe_webcam() {
    local dev
    shopt -s nullglob
    for dev in "$(sysroot_path /sys/class/video4linux)"/*; do
        [[ -e $dev ]] && return 0
    done
    return 1
}

hw_probe_wifi() {
    local dev
    shopt -s nullglob
    for dev in "$(sysroot_path /sys/class/net)"/*/wireless; do
        [[ -e $dev ]] && return 0
    done
    return 1
}

# hw_probe_touchpad — an input device the kernel describes as a touchpad: a
# pointer (INPUT_PROP_POINTER) that is not direct (a touchscreen), reports
# finger tools (BTN_TOOL_FINGER, 0x145) and no pen (BTN_TOOL_PEN, 0x140).
# That is udev's ID_INPUT_TOUCHPAD rule, which is what libinput (and so
# Hyprland's gestures) goes by. Names are not used: Apple's bcm5974 and many
# I2C pads never say "touchpad", and a TrackPoint is a pointer without finger
# tools. The bitmaps are the kernel's hex longs, most significant first
# (64-bit words on the x86_64 kernels haseen targets).
hw_probe_touchpad() {
    local devices
    devices="$(sysroot_path /proc/bus/input/devices)"
    [[ -r $devices ]] || return 1
    awk -v RS= -F'\n' '
        function bit(map, n,   words, w, word, d, v) {
            w = split(map, words, " ")
            w -= int(n / 64)
            if (w < 1) return 0
            word = words[w]
            n %= 64
            d = int(n / 4)
            if (d >= length(word)) return 0
            v = index("0123456789abcdef", tolower(substr(word, length(word) - d, 1))) - 1
            return int(v / 2 ^ (n % 4)) % 2
        }
        {
            prop = ""
            key = ""
            for (i = 1; i <= NF; i++) {
                if ($i ~ /^B: PROP=/) prop = substr($i, 9)
                else if ($i ~ /^B: KEY=/) key = substr($i, 8)
            }
            if (bit(prop, 0) && !bit(prop, 1) && bit(key, 325) && !bit(key, 320)) {
                found = 1
                exit
            }
        }
        END { exit !found }
    ' "$devices"
}

hw_probe_bluetooth() {
    local dev
    shopt -s nullglob
    for dev in "$(sysroot_path /sys/class/bluetooth)"/*; do
        [[ -e $dev ]] && return 0
    done
    return 1
}

hw_probe() {
    case "$1" in
    laptop) hw_probe_laptop ;;
    vm) hw_probe_vm ;;
    nvidia) hw_probe_nvidia ;;
    nvidia-gsp) hw_probe_nvidia_gsp ;;
    nvidia-no-gsp) hw_probe_nvidia && ! hw_probe_nvidia_gsp ;;
    intel-gpu) hw_probe_intel_gpu ;;
    amd-gpu) hw_probe_amd_gpu ;;
    wifi) hw_probe_wifi ;;
    bluetooth) hw_probe_bluetooth ;;
    touchpad) hw_probe_touchpad ;;
    webcam) hw_probe_webcam ;;
    *) die "unknown probe in $(hw_table): $1" ;;
    esac
}

# --- the table ------------------------------------------------------------

# hw_rows — "id<TAB>match<TAB>summary" for every quirk, comments dropped.
hw_rows() {
    local id match summary
    [[ -r $(hw_table) ]] || die "missing quirk table: $(hw_table)"
    while IFS=$'\t' read -r id match summary; do
        [[ -n $id && $id != \#* ]] || continue
        [[ $id =~ $QUIRK_ID_RE ]] || die "malformed quirk id in $(hw_table): $id"
        [[ -n $match ]] || die "quirk $id has no match rule"
        printf '%s\t%s\t%s\n' "$id" "$match" "$summary"
    done <"$(hw_table)"
}

# hw_check_table — read the table in the caller's own shell, so a malformed row
# stops the command. Later reads all happen inside `< <(hw_rows)` or a pipeline,
# where a die would only end the subshell.
hw_check_table() { hw_rows >/dev/null; }

hw_row_field() { # ID FIELD(2=match,3=summary)
    hw_rows | awk -F'\t' -v id="$1" -v f="$2" '$1 == id { print $f; exit }'
}

# hw_matches MATCH — the rule holds on this machine. A rule is `*` (always) or
# comma-separated terms that must all hold:
#   vendor:RE product:RE family:RE chassis:RE   case-insensitive ERE over DMI
#   probe:NAME                                  one of the probes above
#   pci:VENDOR[/CLASS][:DEVICE]                 a PCI device is present
#   usb:VID:PID                                 a USB device is plugged in
#   input:RE                                    /proc/bus/input/devices matches
#   cpu:RE                                      /proc/cpuinfo matches
hw_matches() {
    local rule="$1" term key pattern value
    [[ $rule == '*' ]] && return 0
    local IFS=,
    for term in $rule; do
        key="${term%%:*}"
        pattern="${term#*:}"
        [[ -n $key && $term == *:* ]] || die "malformed match term: $term"
        case "$key" in
        vendor) value="$(hw_dmi sys_vendor)" ;;
        product) value="$(hw_dmi product_name)" ;;
        family) value="$(hw_dmi product_family)" ;;
        chassis) value="$(hw_dmi chassis_type)" ;;
        probe)
            hw_probe "$pattern" || return 1
            continue
            ;;
        pci)
            hw_pci "$pattern" || return 1
            continue
            ;;
        usb)
            hw_usb "$pattern" || return 1
            continue
            ;;
        input)
            hw_input "$pattern" || return 1
            continue
            ;;
        cpu)
            hw_cpu "$pattern" || return 1
            continue
            ;;
        *) die "unknown match key: $key" ;;
        esac
        shopt -s nocasematch
        [[ $value =~ $pattern ]] || {
            shopt -u nocasematch
            return 1
        }
        shopt -u nocasematch
    done
    return 0
}

# hw_matched — ids whose rule holds here, in table order.
hw_matched() {
    local id match summary
    while IFS=$'\t' read -r id match summary; do
        hw_matches "$match" && printf '%s\n' "$id"
    done < <(hw_rows)
    # The loop ends on whatever the last rule answered; listing is not a test.
    return 0
}

# hw_state ID — what `haseen hw list` and `haseen hw apply` report:
#   applied        matched, has a body, already recorded in the ledger
#   pending        matched, has a body, not run yet
#   unimplemented  matched, but no body ships for it yet
#   not-matched    the rule does not hold on this machine
hw_state() {
    local id="$1"
    hw_matches "$(hw_row_field "$id" 2)" || {
        echo not-matched
        return 0
    }
    hw_has_body "$id" || {
        echo unimplemented
        return 0
    }
    if ledger_applied hardware "$id"; then echo applied; else echo pending; fi
}
