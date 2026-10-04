# shellcheck shell=bash disable=SC2034  # LAYER_* are read by lib/layers.sh
# layers/base — essentials, firewall, snapper sanity, pacman hygiene.
#
# This layer assumes a CachyOS (or Arch) install with nothing extra on it.
# It never touches pacman.conf, the CachyOS repos or the mirror list: pacman
# has no drop-in directory, so there is nothing haseen may own there.

LAYER_SUMMARY="essentials, ufw deny-incoming, NetworkManager, snapper sanity, paccache"
LAYER_REQUIRES=()
LAYER_CONFLICTS=()
LAYER_DISTROS=(cachyos arch omarchy)

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# Network services that already own the network. When one of them is enabled
# haseen leaves networking alone instead of adding a second manager.
BASE_OTHER_NETWORK_UNITS=(systemd-networkd.service connman.service iwd.service dhcpcd.service)

layer_usage() {
    cat <<'EOF'
  --bluetooth   also install bluez + bluez-utils and enable bluetooth.service
EOF
}

# --- probes (read-only) ------------------------------------------------------

# ufw_configured — ufw is set to start enabled with a dropping input policy.
# Both files are world-readable, so no root-only `ufw status` call is needed.
ufw_configured() {
    local conf defaults
    conf="$(sysroot_path /etc/ufw/ufw.conf)"
    defaults="$(sysroot_path /etc/default/ufw)"
    [[ -r $conf && -r $defaults ]] || return 1
    grep -Eq '^ENABLED=yes' "$conf" &&
        grep -Eq '^DEFAULT_INPUT_POLICY="?(DROP|REJECT)"?' "$defaults"
}

# network_owner — the unit that manages networking ("" when none is enabled).
network_owner() {
    local u
    for u in NetworkManager.service "${BASE_OTHER_NETWORK_UNITS[@]}"; do
        if unit_enabled "$u"; then
            echo "$u"
            return 0
        fi
    done
}

snapper_root_configured() { [[ -e $(sysroot_path /etc/snapper/configs/root) ]]; }

# --- apply steps -------------------------------------------------------------

base_network() {
    local owner
    owner="$(network_owner)"
    if [[ -n $owner ]]; then
        info "network: $owner is enabled; leaving networking as it is"
        return 0
    fi
    info "network: no network service enabled; installing NetworkManager"
    pkg_install networkmanager
    run_root systemctl enable --now NetworkManager.service
}

base_firewall() {
    if unit_enabled firewalld.service; then
        warn "firewalld is enabled; it stays in charge and haseen does not enable ufw on top of it"
        return 0
    fi
    if ufw_configured; then
        info "firewall: ufw already enabled with deny-incoming"
    else
        info "firewall: ufw default deny incoming, allow outgoing"
        run_root ufw default deny incoming
        run_root ufw default allow outgoing
        run_root ufw --force enable
    fi
    unit_enabled ufw.service || run_root systemctl enable --now ufw.service
}

base_paccache() {
    unit_enabled paccache.timer && return 0
    run_root systemctl enable --now paccache.timer
}

base_bluetooth() {
    pkg_install bluez bluez-utils
    unit_enabled bluetooth.service || run_root systemctl enable --now bluetooth.service
}

# Snapper is the CachyOS installer's job (snapper + btrfs-assistant when the
# root is btrfs). haseen only points out a missing root config.
base_snapper_check() {
    [[ $(root_fstype) == btrfs ]] || return 0
    if snapper_root_configured; then
        info "snapper: root config present"
    else
        warn "root is btrfs but snapper has no 'root' config. CachyOS's installer normally sets this up; see btrfs-assistant or 'snapper -c root create-config /'. haseen does not configure snapper."
    fi
}

# --- layer contract ----------------------------------------------------------

layer_status() {
    local rc=0 missing=() p out
    out="$(manifest_entries "$LAYER_DIR/packages.txt" repo)"
    while read -r p; do
        [[ -n $p ]] || continue
        pkg_installed "$p" || missing+=("$p")
    done <<<"$out"
    if ((${#missing[@]} > 0)); then
        echo "missing: packages ${missing[*]}"
        rc=1
    else
        echo "ok: packages"
    fi
    if unit_enabled firewalld.service; then
        echo "ok: firewall (firewalld)"
    elif ufw_configured && unit_enabled ufw.service; then
        echo "ok: firewall (ufw, deny incoming)"
    else
        echo "missing: ufw enabled with deny-incoming"
        rc=1
    fi
    local owner
    owner="$(network_owner)"
    if [[ -n $owner ]]; then echo "ok: network ($owner)"; else
        echo "missing: network service"
        rc=1
    fi
    if [[ $(root_fstype) == btrfs ]] && ! snapper_root_configured; then
        echo "warn: btrfs root without a snapper 'root' config"
        ((rc == 0)) && rc=2
    fi
    return "$rc"
}

layer_apply() {
    local bluetooth=false arg
    for arg in "$@"; do
        case "$arg" in
        --bluetooth) bluetooth=true ;;
        *) die "base: unknown option '$arg' (see: haseen layer list)" ;;
        esac
    done
    base_network
    base_firewall
    base_paccache
    if $bluetooth; then base_bluetooth; fi
    base_snapper_check
}
