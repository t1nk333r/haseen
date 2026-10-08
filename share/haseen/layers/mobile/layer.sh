# shellcheck shell=bash disable=SC2034  # LAYER_* are read by lib/layers.sh
# layers/mobile — phones. Android gets KDE Connect (standalone kdeconnectd,
# no Plasma), scrcpy, adb and two MTP paths; iOS gets usbmuxd,
# libimobiledevice (idevicebackup2) and the two gvfs backends Apple's AFC
# actually allows. Contract: share/haseen/lib/layers.sh.
#
# Opt-in: it is a dozen packages and an open firewall range, and a desktop
# with no phone should carry neither.

LAYER_SUMMARY="phones: KDE Connect, scrcpy, adb and MTP for Android; usbmuxd, libimobiledevice and gvfs for iOS"
LAYER_REQUIRES=(desktop)
LAYER_CONFLICTS=()
LAYER_DISTROS=(cachyos arch omarchy)

# BASH_SOURCE, not LAYER_DIR: layer_field sources this file without the env.
# shellcheck source=mobile.sh
source "$(dirname "${BASH_SOURCE[0]}")/mobile.sh"

layer_usage() {
    cat <<'EOF'
mobile layer flags (after --):
  --v4l2           also install v4l2loopback-dkms, so `haseen mobile mirror
                   --v4l2` can publish the phone's camera as a webcam
  --no-firewall    leave the firewall alone. KDE Connect needs TCP and UDP
                   1714:1764 inbound, and haseen's base layer denies incoming,
                   so pairing will not work until you open them yourself
  --ifuse          also install ifuse. Refused while the repositories offer
                   1.2.0, which upstream declares data-corrupting
EOF
}

# mobile_parse_args ARGS... — MOBILE_V4L2, MOBILE_NO_FIREWALL, MOBILE_IFUSE.
# Called by both layer_precheck and layer_apply so either can run alone.
mobile_parse_args() {
    MOBILE_V4L2=false
    MOBILE_NO_FIREWALL=false
    MOBILE_IFUSE=false
    local arg
    for arg in "$@"; do
        case "$arg" in
        --v4l2) MOBILE_V4L2=true ;;
        --no-firewall) MOBILE_NO_FIREWALL=true ;;
        --ifuse) MOBILE_IFUSE=true ;;
        *)
            layer_usage >&2
            die "mobile: unknown flag '$arg'"
            ;;
        esac
    done
}

layer_precheck() {
    mobile_parse_args "$@"
    if $MOBILE_IFUSE && ! mobile_ifuse_safe; then
        die "$(mobile_ifuse_refusal)"
    fi
}

# mobile_apply_firewall — open KDE Connect's documented port range. haseen's
# base layer enables ufw with a DROP input policy, so without this the phone
# and the desktop never see each other.
mobile_apply_firewall() {
    if $MOBILE_NO_FIREWALL; then
        info "firewall: --no-firewall, so TCP/UDP $MOBILE_KDECONNECT_PORTS stay closed and KDE Connect will not pair"
        return 0
    fi
    if mobile_firewalld_active; then
        # firewalld is in charge (base/layer.sh defers to it too) and ships a
        # kdeconnect service definition, so use that rather than raw ports.
        # Only the home zone: a network firewalld treats as public stays shut.
        info "firewall: firewalld, adding its kdeconnect service to the home zone"
        run_root firewall-cmd --permanent --zone=home --add-service=kdeconnect
        run_root firewall-cmd --reload
        local zone
        zone="$(mobile_firewalld_default_zone)"
        [[ $zone == home ]] ||
            warn "firewalld's default zone is '$zone', not 'home': KDE Connect pairs only on a network in the home zone. Put your trusted connection there, e.g. nmcli connection modify <connection> connection.zone home"
        return 0
    fi
    if ! mobile_ufw_enabled; then
        warn "no enabled ufw or firewalld found; nothing to open for KDE Connect (TCP/UDP $MOBILE_KDECONNECT_PORTS)"
        return 0
    fi
    local proto
    for proto in tcp udp; do
        if mobile_ufw_rule_present "$proto"; then
            info "firewall: ufw already allows $MOBILE_KDECONNECT_PORTS/$proto"
        else
            info "firewall: opening $MOBILE_KDECONNECT_PORTS/$proto inbound for KDE Connect"
            run_root ufw allow "$MOBILE_KDECONNECT_PORTS/$proto"
        fi
    done
}

layer_apply() {
    mobile_parse_args "$@"
    if $MOBILE_V4L2; then
        pkg_install v4l2loopback-dkms
    fi
    if $MOBILE_IFUSE; then
        mobile_ifuse_safe || die "$(mobile_ifuse_refusal)"
        pkg_install ifuse
    fi
    mobile_apply_firewall

    # kdeconnectd autostarts from the package's own XDG entry and is D-Bus
    # activated; usbmuxd is started by its udev rule when an iPhone appears.
    # Neither needs `systemctl enable`, so the layer enables nothing.
    info "KDE Connect: pair from the phone app, or run: kdeconnect-cli --pair --name <device>"
    info "tray icon: run kdeconnect-indicator (the daemon itself starts on login)"
    info "iPhone: plug it in, unlock it, tap Trust, then run: idevicepair pair"
    mobile_limits
}

# mobile_status_pkgs LABEL PKG... — a "missing: LABEL PKG" line for each one
# that is absent. Returns 0 when all are present, 1 when none is, 2 when the
# set is half there: a half-installed stack is not a working one.
mobile_status_pkgs() {
    local label="$1" p have=0 miss=0
    shift
    for p in "$@"; do
        if pkg_installed "$p"; then
            have=$((have + 1))
        else
            echo "missing: $label $p"
            miss=$((miss + 1))
        fi
    done
    ((miss == 0)) && return 0
    ((have == 0)) && return 1
    return 2
}

# mobile_status_half LABEL DETAIL CODE — the verdict line for one half.
mobile_status_half() {
    case "$3" in
    0) echo "ok: $1 tooling ($2)" ;;
    1) echo "warn: no $1 tooling installed" ;;
    *) echo "warn: $1 tooling is only half installed; the packages above are missing" ;;
    esac
}

layer_status() {
    local rc=0 android=0 ios=0
    mobile_status_pkgs Android "${MOBILE_ANDROID_PKGS[@]}" || android=$?
    mobile_status_pkgs iOS "${MOBILE_IOS_PKGS[@]}" || ios=$?
    if ((android == 1 && ios == 1)); then
        echo "missing: no mobile packages installed"
        return 1
    fi
    mobile_status_half Android "adb, scrcpy, KDE Connect, MTP" "$android"
    mobile_status_half iOS "usbmuxd, libimobiledevice, gvfs" "$ios"
    ((android == 0)) || rc=2
    ((ios == 0)) || rc=2

    if mobile_firewalld_active; then
        echo "ok: firewalld is in charge of KDE Connect's ports"
    elif mobile_ufw_enabled; then
        local proto
        for proto in tcp udp; do
            if mobile_ufw_rule_present "$proto"; then
                echo "ok: ufw allows $MOBILE_KDECONNECT_PORTS/$proto (KDE Connect)"
            else
                echo "warn: ufw blocks $MOBILE_KDECONNECT_PORTS/$proto, so KDE Connect cannot pair"
                rc=2
            fi
        done
    else
        echo "ok: no firewall enabled, so KDE Connect's ports are reachable"
    fi

    if pkg_installed ifuse; then
        if mobile_ifuse_safe; then
            echo "ok: ifuse $(mobile_ifuse_version) installed (past the 1.2.0 corruption bug)"
        else
            echo "warn: ifuse $(mobile_ifuse_version) is installed; upstream calls 1.2.0 data-corrupting. Do not write through it."
            rc=2
        fi
    fi
    if pkg_installed v4l2loopback-dkms; then
        echo "ok: v4l2loopback-dkms installed (haseen mobile mirror --v4l2)"
    fi

    local portal
    portal="$(mobile_remote_desktop_portal)"
    if [[ -n $portal ]]; then
        echo "ok: $portal implements portal RemoteDesktop, so KDE Connect's Mousepad plugin can work"
    else
        echo "ok: no portal RemoteDesktop backend, so KDE Connect's Mousepad plugin stays broken (expected on Hyprland)"
    fi
    mobile_limits
    return "$rc"
}

# Only the firewall hole is undone: packages and pairings are the user's.
layer_remove() {
    if mobile_firewalld_active; then
        run_root firewall-cmd --permanent --zone=home --remove-service=kdeconnect
        run_root firewall-cmd --reload
        return 0
    fi
    local proto
    for proto in tcp udp; do
        mobile_ufw_rule_present "$proto" || continue
        run_root ufw delete allow "$MOBILE_KDECONNECT_PORTS/$proto"
    done
    info "packages, pairings and ~/.config/kdeconnect are left alone; remove them yourself if you want them gone"
}
