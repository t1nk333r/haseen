# shellcheck shell=bash
# wireless-regdom — persist the wireless regulatory domain, taken from the
# system timezone.
#
# Adapted from Omarchy install/hardware/set-wireless-regdom.sh (MIT, Copyright
# (c) David Heinemeier Hansson): write the domain rather than `iw reg set`, so
# live Wi-Fi state is untouched and the setting survives a reboot.

regdom_file=/etc/conf.d/wireless-regdom
src="$(sysroot_path "$regdom_file")"

if [[ ! -f $src ]]; then
    info "hw wireless-regdom: no $regdom_file (wireless-regdb is not installed)"
    return 0
fi
if grep -q '^WIRELESS_REGDOM=' "$src"; then
    info "hw wireless-regdom: already set in $regdom_file"
    return 0
fi

timezone=""
localtime="$(sysroot_path /etc/localtime)"
if [[ -e $localtime ]]; then
    timezone="$(readlink -f "$localtime" || true)"
    timezone="${timezone#*/usr/share/zoneinfo/}"
fi

# A zone like "Europe/Berlin" has no country code in it, so the zone table maps
# it; "US/Pacific" and friends already start with one.
country="${timezone%%/*}"
zone_tab="$(sysroot_path /usr/share/zoneinfo/zone.tab)"
if [[ ! $country =~ ^[A-Z]{2}$ && -n $timezone && -f $zone_tab ]]; then
    country="$(awk -v tz="$timezone" '$3 == tz { print $1; exit }' "$zone_tab")"
fi

if [[ ! $country =~ ^[A-Z]{2}$ ]]; then
    warn "hw wireless-regdom: no country for timezone '${timezone:-unknown}'; left unset"
    return 0
fi

echo "WIRELESS_REGDOM=\"$country\"" | append_root_file "$regdom_file"
info "hw wireless-regdom: $country (from $timezone)"
