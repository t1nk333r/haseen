# shellcheck shell=bash
# layers/base/lib.sh — read-only probes shared by the base, desktop and gaming
# layers. Sourced from their layer.sh; defines functions only. Every probe
# reads through sysroot_path so the fixture trees stand in for a real host,
# and none of them calls systemctl or pacman (both are mutating binaries the
# test sandbox stubs out; the files they would read are readable directly).

[[ -n ${HASEEN_LAYERS_BASE_LIB:-} ]] && return 0
HASEEN_LAYERS_BASE_LIB=1

# unit_enabled UNIT — true when UNIT is enabled system-wide: a wants/requires
# symlink for it exists under /etc/systemd/system. (Alias units such as
# display-manager.service: see display_manager_unit.)
unit_enabled() {
    local etc
    etc="$(sysroot_path /etc/systemd/system)"
    compgen -G "$etc/*.wants/$1" >/dev/null || compgen -G "$etc/*.requires/$1" >/dev/null
}

# display_manager_unit — the unit display-manager.service points at (e.g.
# sddm.service, greetd.service); empty when no display manager is enabled.
display_manager_unit() {
    local link
    link="$(sysroot_path /etc/systemd/system/display-manager.service)"
    [[ -L $link || -e $link ]] || return 0
    if [[ -L $link ]]; then
        basename "$(readlink "$link")"
    else
        echo display-manager.service
    fi
}

# installed_packages_matching ERE — installed package names matching ERE
# (anchored by the caller). Reads the pacman local database directly; it is
# world-readable and identical to what `pacman -Qq` prints.
installed_packages_matching() {
    local re="$1" d name
    for d in "$(sysroot_path /var/lib/pacman/local)"/*/; do
        [[ -d $d ]] || continue
        name="$(basename "$d")"
        # <name>-<pkgver>-<pkgrel>: strip the last two dash-separated fields.
        name="${name%-*}"
        name="${name%-*}"
        [[ $name =~ $re ]] && printf '%s\n' "$name"
    done
    return 0
}

# root_fstype — filesystem type of / from /etc/fstab ("" when not listed).
root_fstype() {
    local fstab
    fstab="$(sysroot_path /etc/fstab)"
    [[ -r $fstab ]] || return 0
    awk '$1 !~ /^#/ && $2 == "/" { print $3; exit }' "$fstab"
}

# pacman_repo_enabled NAME — true when /etc/pacman.conf has an uncommented
# [NAME] section (repository sections are always declared there).
pacman_repo_enabled() {
    local name="$1" conf
    conf="$(sysroot_path /etc/pacman.conf)"
    [[ -r $conf ]] || return 1
    grep -Eq "^[[:space:]]*\[$name\][[:space:]]*$" "$conf"
}

# has_gpu VENDOR — VENDOR (intel|amd|nvidia) is in preflight's GPU_VENDORS.
has_gpu() { [[ " ${GPU_VENDORS:-} " == *" $1 "* ]]; }

# nvidia_device_id — PCI device id (hex, no 0x) of the first NVIDIA display
# controller in sysfs; empty when there is none.
nvidia_device_id() {
    local d
    for d in "$(sysroot_path /sys/bus/pci/devices)"/*; do
        [[ -r $d/class && -r $d/vendor && -r $d/device ]] || continue
        [[ $(<"$d/class") == 0x03* && $(<"$d/vendor") == 0x10de ]] || continue
        local id
        id="$(<"$d/device")"
        printf '%s\n' "${id#0x}"
        return 0
    done
}
