# shellcheck shell=bash
# layers/mobile/mobile.sh — read-only probes and the honest capability text
# shared by the mobile layer and the bin/haseen-mobile-* commands. Sourced,
# never executed.
#
# Every probe reads through sysroot_path, so the fixture trees under
# tests/fixtures/mobile-* stand in for a machine with a phone plugged in.
# Nothing here calls pacman, systemctl, adb or any idevice* tool: the commands
# do that, the layer does not.

[[ -n ${HASEEN_MOBILE_SH:-} ]] && return 0
HASEEN_MOBILE_SH=1
# shellcheck source=../../lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../lib/common.sh"
# shellcheck source=../../lib/packages.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../lib/packages.sh"
# unit_enabled, used for the firewalld check.
# shellcheck source=../base/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../base/lib.sh"

# KDE Connect binds a dynamic port in this range for UDP discovery and TCP
# payloads, so a deny-incoming firewall blocks pairing outright. The range is
# upstream's: https://userbase.kde.org/KDEConnect/en ("KDE Connect uses dynamic
# ports in the range 1714-1764 for UDP and TCP"), which documents exactly the
# two ufw rules below and the firewalld service name.
MOBILE_KDECONNECT_PORTS=1714:1764

# The packages.txt set, split so status can report the two halves separately.
# shellcheck disable=SC2034  # read by layer_status in layer.sh
MOBILE_ANDROID_PKGS=(android-tools android-udev scrcpy kdeconnect gvfs-mtp android-file-transfer)
# shellcheck disable=SC2034  # read by layer_status in layer.sh
MOBILE_IOS_PKGS=(usbmuxd libimobiledevice gvfs-afc gvfs-gphoto2)

# ifuse is deliberately not in packages.txt. Upstream's README: "Version 1.2.0
# has a serious bug that results in data corruption ... fixed in Version 1.2.1"
# (https://github.com/libimobiledevice/ifuse). Arch still ships exactly
# 1.2.0-1 (`pacman -Si ifuse`, checked 2026-10-05), so `--ifuse` is refused
# until the repos move on. gvfs-gphoto2 (photos/videos) and gvfs-afc (app
# document sandboxes) cover what ifuse would add, without the write path.
MOBILE_IFUSE_BAD_VERSION=1.2.0

# mobile_ifuse_version — the ifuse version the repositories offer, empty when
# that cannot be determined. Fixture convention, the same shape as
# var/lib/pacman/sync/REPO.pkgs in lib/packages.sh: a sysroot answers from
# var/lib/pacman/sync/ifuse.version, one "pkgver-pkgrel" line.
mobile_ifuse_version() {
    local f
    if in_sysroot; then
        f="$(sysroot_path /var/lib/pacman/sync/ifuse.version)"
        [[ -r $f ]] || return 0
        head -n1 "$f"
    else
        pacman -Si ifuse 2>/dev/null | sed -n 's/^Version[[:space:]]*:[[:space:]]*//p' | head -n1
    fi
}

# mobile_ifuse_safe — true only when the repos offer something other than the
# data-corrupting 1.2.0. An unknown version is treated as unsafe: a filesystem
# that may corrupt the user's photos is not the place to guess.
mobile_ifuse_safe() {
    local v
    v="$(mobile_ifuse_version)"
    [[ -n $v ]] || return 1
    [[ ${v%%-*} != "$MOBILE_IFUSE_BAD_VERSION" ]]
}

mobile_ifuse_refusal() {
    local v
    v="$(mobile_ifuse_version)"
    printf 'refusing to install ifuse: the repositories offer %s, and upstream says "Version %s has a serious bug that results in data corruption" (fixed in 1.2.1, https://github.com/libimobiledevice/ifuse). gvfs-gphoto2 gives you photos and videos and gvfs-afc gives you app document folders without it.\n' \
        "${v:-an unknown version}" "$MOBILE_IFUSE_BAD_VERSION"
}

# --- USB -------------------------------------------------------------------

# mobile_usb_kind DIR VENDOR — classify one /sys/bus/usb/devices entry:
# "ios", "android-adb", "android-mtp" or nothing. Apple is identified by its
# USB vendor id 05ac; an Android device in debugging mode exposes the ADB
# interface (class ff, subclass 42, protocol 01, the AOSP values), and an
# Android device in file-transfer mode exposes an imaging-class interface.
mobile_usb_kind() {
    local dir="$1" vendor="$2" iface cls sub proto mtp=false
    [[ ${vendor,,} == 05ac ]] && {
        echo ios
        return 0
    }
    for iface in "$dir"/*:*; do
        [[ -r $iface/bInterfaceClass ]] || continue
        cls="$(<"$iface/bInterfaceClass")"
        sub=00
        proto=00
        [[ -r $iface/bInterfaceSubClass ]] && sub="$(<"$iface/bInterfaceSubClass")"
        [[ -r $iface/bInterfaceProtocol ]] && proto="$(<"$iface/bInterfaceProtocol")"
        if [[ ${cls,,} == ff && ${sub,,} == 42 && ${proto,,} == 01 ]]; then
            echo android-adb
            return 0
        fi
        [[ ${cls,,} == 06 ]] && mtp=true
    done
    $mtp && echo android-mtp
    return 0
}

# mobile_usb_devices — one "kind<TAB>vvvv:pppp<TAB>name" line per phone on the
# USB bus. Hubs, keyboards and the root hubs produce nothing.
mobile_usb_devices() {
    local base d vendor product kind name
    base="$(sysroot_path /sys/bus/usb/devices)"
    [[ -d $base ]] || return 0
    for d in "$base"/*; do
        [[ -r $d/idVendor && -r $d/idProduct ]] || continue
        vendor="$(<"$d/idVendor")"
        product="$(<"$d/idProduct")"
        kind="$(mobile_usb_kind "$d" "$vendor")"
        [[ -n $kind ]] || continue
        name=""
        [[ -r $d/manufacturer ]] && name="$(<"$d/manufacturer")"
        [[ -r $d/product ]] && name="${name:+$name }$(<"$d/product")"
        printf '%s\t%s:%s\t%s\n' "$kind" "${vendor,,}" "${product,,}" "${name:-unnamed}"
    done
}

# --- V4L2 loopback ---------------------------------------------------------

# mobile_v4l2_loopback_nodes — /dev/videoN nodes backed by no hardware, in
# numeric order (video2 before video10). A real capture device has a `device`
# link to its PCI/USB parent in sysfs; a v4l2loopback device, being virtual,
# has none.
mobile_v4l2_loopback_nodes() {
    local base d
    base="$(sysroot_path /sys/class/video4linux)"
    [[ -d $base ]] || return 0
    for d in "$base"/video*; do
        [[ -d $d && ! -e $d/device && ${d##*/video} =~ ^[0-9]+$ ]] || continue
        printf '%s\n' "${d##*/video}"
    done | sort -n | sed 's|^|/dev/video|'
}

# mobile_v4l2_first_loopback_node — haseen's own node (card_label
# haseen-phone, its sysfs `name`) when there is one, so another program's
# virtual camera (OBS) is never taken over; otherwise the lowest-numbered
# loopback node; otherwise nothing. The list is read whole rather than with
# `| head -n1`, which would die of SIGPIPE under pipefail.
mobile_v4l2_first_loopback_node() {
    local node first="" base
    base="$(sysroot_path /sys/class/video4linux)"
    while IFS= read -r node; do
        [[ -n $first ]] || first=$node
        if [[ -r $base/${node#/dev/}/name && $(<"$base/${node#/dev/}/name") == haseen-phone ]]; then
            printf '%s\n' "$node"
            return 0
        fi
    done < <(mobile_v4l2_loopback_nodes)
    [[ -z $first ]] || printf '%s\n' "$first"
}

# mobile_v4l2_next_index — the index v4l2loopback would take when loaded with
# no video_nr=: the lowest free one.
mobile_v4l2_next_index() {
    local base n=0
    base="$(sysroot_path /sys/class/video4linux)"
    while [[ -d $base/video$n ]]; do n=$((n + 1)); done
    printf '%s\n' "$n"
}

# --- firewall --------------------------------------------------------------

# mobile_ufw_enabled — ufw is configured to come up enabled. /etc/ufw/ufw.conf
# is world-readable, so this needs no root and no `ufw status` call.
mobile_ufw_enabled() {
    local conf
    conf="$(sysroot_path /etc/ufw/ufw.conf)"
    [[ -r $conf ]] && grep -Eq '^ENABLED=yes' "$conf"
}

# mobile_ufw_rule_present PROTO — ufw already allows the KDE Connect range for
# PROTO. /etc/ufw/user.rules is world-readable (0644) and carries the
# generated iptables line for every rule.
mobile_ufw_rule_present() {
    local rules
    rules="$(sysroot_path /etc/ufw/user.rules)"
    [[ -r $rules ]] || return 1
    grep -qE -- "-p $1 .*--dport ${MOBILE_KDECONNECT_PORTS} -j ACCEPT" "$rules"
}

mobile_firewalld_active() { unit_enabled firewalld.service; }

# mobile_firewalld_default_zone — DefaultZone from the world-readable
# /etc/firewalld/firewalld.conf; firewalld's own default, public, otherwise.
mobile_firewalld_default_zone() {
    local conf zone=""
    conf="$(sysroot_path /etc/firewalld/firewalld.conf)"
    [[ -r $conf ]] && zone="$(sed -n 's/^[[:space:]]*DefaultZone[[:space:]]*=[[:space:]]*\([^[:space:]]*\).*/\1/p' "$conf" | tail -n1)"
    printf '%s\n' "${zone:-public}"
}

# --- portals ---------------------------------------------------------------

# mobile_remote_desktop_portal — the portal backend implementing
# org.freedesktop.impl.portal.RemoteDesktop, empty when none does. KDE
# Connect's Mousepad plugin needs it on Wayland.
mobile_remote_desktop_portal() {
    local dir f
    dir="$(sysroot_path /usr/share/xdg-desktop-portal/portals)"
    [[ -d $dir ]] || return 0
    for f in "$dir"/*.portal; do
        [[ -r $f ]] || continue
        grep -q 'org\.freedesktop\.impl\.portal\.RemoteDesktop' "$f" || continue
        basename "$f" .portal
        return 0
    done
    return 0
}

# --- the honest part -------------------------------------------------------

# mobile_limits — what this layer does NOT do, and why. Printed by the layer
# summary, by `haseen layer status mobile` and by every command's --help, so
# nobody has to find it in a plan file.
mobile_limits() {
    cat <<'EOF'
Not possible — do not expect these to start working:
  * iPhone notification mirroring. iOS gives an app no access to other apps'
    notifications (KDE Connect iOS README). The only mechanism is Apple's ANCS
    over Bluetooth LE, and its one implementation (pzmarzly/ancs4linux) has no
    release, no package anywhere, and a README that says the author stopped
    using it.
  * Sending SMS or iMessage to/from an iPhone, controlling an iPhone's media
    playback, or driving an iPhone's input: Apple publishes no third-party API.
  * Arbitrary iOS filesystem access. AFC exposes photos and videos
    (gvfs-gphoto2) and per-app document folders (gvfs-afc). That is all there
    is.
  * AirDrop. opendrop has not had a release since 2021 and needs owl/AWDL,
    which has no package and needs a patched monitor-mode Wi-Fi driver. Use
    LocalSend, which has real iOS and Android clients.
  * KDE Connect's Mousepad plugin (phone as a trackpad or keyboard) under
    Hyprland: it needs org.freedesktop.impl.portal.RemoteDesktop, and
    hyprland.portal implements only Screenshot, ScreenCast, GlobalShortcuts
    and InputCapture.
  * Android backup. `adb backup` is deprecated and neutered on current
    Android, and there is no maintained packaged replacement. Mount the phone
    with `aft-mtp-mount` and copy /sdcard, or use the vendor's cloud.
Android loses none of this: KDE Connect carries notifications, SMS, clipboard,
media control and file share, and scrcpy mirrors and fully controls the phone.
EOF
}
