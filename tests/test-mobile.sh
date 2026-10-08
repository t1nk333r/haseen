# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# mobile layer and commands: the package set, KDE Connect's firewall range,
# the ifuse refusal, the USB probe, dry-run purity, and what each command does
# with no phone attached.

PLAIN="$FIXTURES/mobile-plain"
APPLIED="$FIXTURES/mobile-applied"

# mobile_layer FIXTURE_DIR VERB ARGS... — the mobile layer alone through the
# real runner. `haseen layer apply mobile` would also resolve base and
# desktop, which belong to other slices and are tested there.
mobile_layer() {
    local fx="$1" verb="$2"
    shift 2
    capture env HASEEN_SYSROOT="$fx" bash -c 'source "$HASEEN_PATH/lib/layers.sh"; verb=$1; shift; "layer_run_$verb" mobile "$@"' _ "$verb" "$@"
}

# mobile_minpath — a PATH without /usr/bin, so the "not installed" branches are
# reachable on a machine that really does have adb and libimobiledevice. Only
# the handful of tools the commands actually call is linked in.
mobile_minpath() {
    local d="$SANDBOX/minbin" t p
    mkdir -p "$d"
    for t in bash env sed grep awk head tail tr wc basename dirname mkdir readlink cat; do
        p="$(PATH=/usr/bin:/bin command -v "$t")" || continue
        ln -sf "$p" "$d/$t"
    done
    printf '%s\n' "$SANDBOX/stubs:$REPO/bin:$d"
}

# --- apply: packages, in the manifest's order -------------------------------
sandbox mobile-apply
DRY_RUN=true mobile_layer "$PLAIN" apply
assert_status "apply exit" 0 "$STATUS"
assert_dry_pure "apply" "$OUTPUT"
assert_contains "apply installs the whole set in one pacman call" "$OUTPUT" \
    "DRYRUN: sudo pacman -S --needed android-tools android-udev scrcpy kdeconnect gvfs-mtp android-file-transfer usbmuxd libimobiledevice gvfs-afc gvfs-gphoto2"
assert_not_contains "apply never installs ifuse" "$OUTPUT" "ifuse"
assert_not_contains "apply never installs waydroid" "$OUTPUT" "waydroid"
assert_not_contains "apply never installs gsconnect" "$OUTPUT" "gsconnect"
assert_not_contains "apply never installs jmtpfs" "$OUTPUT" "jmtpfs"
assert_not_contains "v4l2loopback is opt-in" "$OUTPUT" "v4l2loopback"
assert_contains "apply marks the layer applied" "$OUTPUT" "DRYRUN: write /var/lib/haseen/layers/mobile"

# --- apply: KDE Connect's firewall range ------------------------------------
assert_contains "apply opens the tcp range" "$OUTPUT" "DRYRUN: sudo ufw allow 1714:1764/tcp"
assert_contains "apply opens the udp range" "$OUTPUT" "DRYRUN: sudo ufw allow 1714:1764/udp"
assert_contains "apply says why the hole is needed" "$OUTPUT" "inbound for KDE Connect"
assert_not_contains "apply enables no units" "$OUTPUT" "systemctl enable"

DRY_RUN=true mobile_layer "$PLAIN" apply --no-firewall
assert_status "--no-firewall exit" 0 "$STATUS"
assert_not_contains "--no-firewall opens nothing" "$OUTPUT" "ufw allow"
assert_contains "--no-firewall says pairing will fail" "$OUTPUT" "KDE Connect will not pair"

# A host with ufw already carrying the rules converges to a no-op.
DRY_RUN=true mobile_layer "$APPLIED" apply
assert_status "re-apply exit" 0 "$STATUS"
assert_dry_pure "re-apply" "$OUTPUT"
assert_not_contains "re-apply installs nothing" "$OUTPUT" "pacman -S"
assert_not_contains "re-apply re-opens nothing" "$OUTPUT" "ufw allow"
assert_contains "re-apply reports the existing rule" "$OUTPUT" "ufw already allows 1714:1764/tcp"

# firewalld, when it is the firewall in charge, gets its own service.
cp -a "$PLAIN" "$SANDBOX/firewalld"
mkdir -p "$SANDBOX/firewalld/etc/systemd/system/multi-user.target.wants"
: >"$SANDBOX/firewalld/etc/systemd/system/multi-user.target.wants/firewalld.service"
DRY_RUN=true mobile_layer "$SANDBOX/firewalld" apply
assert_contains "firewalld service added" "$OUTPUT" "DRYRUN: sudo firewall-cmd --permanent --zone=home --add-service=kdeconnect"
assert_contains "firewalld reloaded" "$OUTPUT" "DRYRUN: sudo firewall-cmd --reload"
assert_not_contains "firewalld host does not get ufw rules" "$OUTPUT" "ufw allow"

# No firewall at all: say so rather than pretending a hole was opened.
cp -a "$PLAIN" "$SANDBOX/nofw"
rm -f "$SANDBOX/nofw/etc/ufw/ufw.conf"
DRY_RUN=true mobile_layer "$SANDBOX/nofw" apply
assert_contains "no firewall is reported" "$OUTPUT" "no enabled ufw or firewalld found"
assert_not_contains "no firewall: nothing opened" "$OUTPUT" "ufw allow"

# --- the ifuse refusal ------------------------------------------------------
DRY_RUN=true mobile_layer "$PLAIN" apply --ifuse
assert_status "--ifuse refused" 1 "$STATUS"
assert_contains "--ifuse names the version offered" "$OUTPUT" "the repositories offer 1.2.0-1"
assert_contains "--ifuse quotes upstream" "$OUTPUT" \
    'upstream says "Version 1.2.0 has a serious bug that results in data corruption"'
assert_contains "--ifuse points at the alternative" "$OUTPUT" "gvfs-gphoto2 gives you photos and videos"
assert_not_contains "--ifuse plans nothing at all" "$OUTPUT" "DRYRUN:"
assert_dry_pure "--ifuse" "$OUTPUT"

# An unknown available version is refused too: data loss is not a coin flip.
cp -a "$PLAIN" "$SANDBOX/ifuse-unknown"
rm -f "$SANDBOX/ifuse-unknown/var/lib/pacman/sync/ifuse.version"
DRY_RUN=true mobile_layer "$SANDBOX/ifuse-unknown" apply --ifuse
assert_status "unknown ifuse version refused" 1 "$STATUS"
assert_contains "unknown ifuse version message" "$OUTPUT" "the repositories offer an unknown version"

# Once the repositories ship the fixed 1.2.1, --ifuse installs it.
cp -a "$PLAIN" "$SANDBOX/ifuse-fixed"
printf '1.2.1-1\n' >"$SANDBOX/ifuse-fixed/var/lib/pacman/sync/ifuse.version"
DRY_RUN=true mobile_layer "$SANDBOX/ifuse-fixed" apply --ifuse
assert_status "fixed ifuse accepted" 0 "$STATUS"
assert_contains "fixed ifuse installed" "$OUTPUT" "DRYRUN: sudo pacman -S --needed ifuse"

# --- opt-in v4l2loopback and bad flags --------------------------------------
DRY_RUN=true mobile_layer "$PLAIN" apply --v4l2
assert_status "--v4l2 exit" 0 "$STATUS"
assert_contains "--v4l2 installs the dkms module" "$OUTPUT" "DRYRUN: sudo pacman -S --needed v4l2loopback-dkms"
DRY_RUN=true mobile_layer "$PLAIN" apply --waydroid
assert_status "unknown flag refused" 1 "$STATUS"
assert_contains "unknown flag named" "$OUTPUT" "mobile: unknown flag '--waydroid'"
assert_not_contains "unknown flag plans nothing" "$OUTPUT" "DRYRUN:"
assert_contains "unknown flag prints the layer's flags" "$OUTPUT" "mobile layer flags (after --):"
assert_contains "unknown flag: waydroid is not one of them" "$OUTPUT" "--no-firewall"

# --- the honesty block is in the layer output, not only in a plan -----------
DRY_RUN=true mobile_layer "$PLAIN" apply
for claim in \
    "iPhone notification mirroring" \
    "Apple publishes no third-party API" \
    "Arbitrary iOS filesystem access" \
    "AirDrop" \
    "KDE Connect's Mousepad plugin" \
    "org.freedesktop.impl.portal.RemoteDesktop" \
    "Android backup" \
    "adb backup\` is deprecated"; do
    assert_contains "apply states: $claim" "$OUTPUT" "$claim"
done

# --- status -----------------------------------------------------------------
mobile_layer "$PLAIN" status
assert_status "status: not applied" 1 "$STATUS"
assert_contains "status: nothing installed" "$OUTPUT" "missing: no mobile packages installed"
assert_contains "status: names a missing Android package" "$OUTPUT" "missing: Android kdeconnect"
assert_contains "status: names a missing iOS package" "$OUTPUT" "missing: iOS libimobiledevice"

mobile_layer "$APPLIED" status
assert_status "status: healthy" 0 "$STATUS"
assert_contains "status: android ok" "$OUTPUT" "ok: Android tooling (adb, scrcpy, KDE Connect, MTP)"
assert_contains "status: ios ok" "$OUTPUT" "ok: iOS tooling (usbmuxd, libimobiledevice, gvfs)"
assert_contains "status: tcp rule" "$OUTPUT" "ok: ufw allows 1714:1764/tcp (KDE Connect)"
assert_contains "status: udp rule" "$OUTPUT" "ok: ufw allows 1714:1764/udp (KDE Connect)"
assert_contains "status: v4l2 noted" "$OUTPUT" "ok: v4l2loopback-dkms installed"
assert_contains "status: mousepad verdict comes from the portal file" "$OUTPUT" \
    "no portal RemoteDesktop backend, so KDE Connect's Mousepad plugin stays broken"
assert_contains "status repeats the limits" "$OUTPUT" "Not possible"

# Half the set installed is degraded, never "ok": this is exactly what a host
# that had android-tools and usbmuxd before the layer existed looks like.
cp -a "$APPLIED" "$SANDBOX/halfpkgs"
rm -rf "$SANDBOX/halfpkgs/var/lib/pacman/local/kdeconnect-26.08.0-1" \
    "$SANDBOX/halfpkgs/var/lib/pacman/local/scrcpy-4.1-2"
mobile_layer "$SANDBOX/halfpkgs" status
assert_status "status: half-installed is degraded" 2 "$STATUS"
assert_contains "status: half-installed Android named" "$OUTPUT" "warn: Android tooling is only half installed"
assert_not_contains "status: half-installed never claims ok" "$OUTPUT" "ok: Android tooling"
assert_contains "status: the other half is still ok" "$OUTPUT" "ok: iOS tooling"

# A half-open firewall is degraded, not healthy.
cp -a "$APPLIED" "$SANDBOX/halfopen"
grep -v -- '-p udp --dport 1714:1764' "$APPLIED/etc/ufw/user.rules" >"$SANDBOX/halfopen/etc/ufw/user.rules"
mobile_layer "$SANDBOX/halfopen" status
assert_status "status: missing udp rule is degraded" 2 "$STATUS"
assert_contains "status: missing udp rule named" "$OUTPUT" "warn: ufw blocks 1714:1764/udp"

# An installed 1.2.0 ifuse (from before this layer, or by hand) is called out.
cp -a "$APPLIED" "$SANDBOX/has-ifuse"
mkdir -p "$SANDBOX/has-ifuse/var/lib/pacman/local/ifuse-1.2.0-1"
printf '%%NAME%%\nifuse\n' >"$SANDBOX/has-ifuse/var/lib/pacman/local/ifuse-1.2.0-1/desc"
mobile_layer "$SANDBOX/has-ifuse" status
assert_status "status: unsafe ifuse is degraded" 2 "$STATUS"
assert_contains "status: unsafe ifuse named" "$OUTPUT" "warn: ifuse 1.2.0-1 is installed"
assert_contains "status: unsafe ifuse reason" "$OUTPUT" "upstream calls 1.2.0 data-corrupting"

# A host whose portal does implement RemoteDesktop gets the opposite verdict.
cp -a "$APPLIED" "$SANDBOX/has-rd"
printf '[portal]\nInterfaces=org.freedesktop.impl.portal.RemoteDesktop;\n' \
    >"$SANDBOX/has-rd/usr/share/xdg-desktop-portal/portals/gnome.portal"
mobile_layer "$SANDBOX/has-rd" status
assert_contains "status: RemoteDesktop backend detected" "$OUTPUT" "ok: gnome implements portal RemoteDesktop"

# --- remove ------------------------------------------------------------------
DRY_RUN=true mobile_layer "$APPLIED" remove
assert_status "remove exit" 0 "$STATUS"
assert_dry_pure "remove" "$OUTPUT"
assert_contains "remove closes tcp" "$OUTPUT" "DRYRUN: sudo ufw delete allow 1714:1764/tcp"
assert_contains "remove closes udp" "$OUTPUT" "DRYRUN: sudo ufw delete allow 1714:1764/udp"
assert_not_contains "remove keeps packages" "$OUTPUT" "pacman -R"

# --- haseen mobile status ----------------------------------------------------
sandbox mobile-status
MINPATH="$(mobile_minpath)"

capture haseen mobile status --help
assert_status "status --help exit" 0 "$STATUS"
assert_contains "status --help explains the usb probe" "$OUTPUT" "/sys/bus/usb/devices"
assert_contains "status --help warns about the adb server" "$OUTPUT" "starts the local adb server when one is not already running"
capture haseen mobile status extra-arg
assert_status "status rejects arguments" 2 "$STATUS"

# Nothing installed, nothing plugged in: a clean, complete answer.
capture env HASEEN_SYSROOT="$PLAIN" PATH="$MINPATH" haseen mobile status
assert_status "status: empty host exits 0" 0 "$STATUS"
assert_dry_pure "status: empty host" "$OUTPUT"
assert_contains "status: no usb phone" "$OUTPUT" "(no phone on the USB bus)"
assert_contains "status: adb missing" "$OUTPUT" "adb: android-tools not installed"
assert_contains "status: kdeconnect missing" "$OUTPUT" "kdeconnect: not installed"
assert_contains "status: libimobiledevice missing" "$OUTPUT" "idevice: libimobiledevice not installed"
assert_contains "status: limits printed" "$OUTPUT" "Not possible"

# Tools installed, phones on the bus, nothing paired.
stub adb 'echo "List of devices attached"'
stub kdeconnect-cli 'exit 0'
stub idevice_id 'exit 0'
capture env HASEEN_SYSROOT="$APPLIED" haseen mobile status
assert_status "status: devices on the bus exits 0" 0 "$STATUS"
assert_contains "status: iPhone seen on usb" "$OUTPUT" "ios          05ac:12a8  Apple Inc. iPhone"
assert_contains "status: adb-mode Android seen on usb" "$OUTPUT" "android-adb  18d1:4ee7  Google Pixel 8"
assert_contains "status: mtp-mode Android seen on usb" "$OUTPUT" "android-mtp  2717:ff40  Xiaomi Redmi Note"
assert_not_contains "status: root hub is not a phone" "$OUTPUT" "1d6b"
assert_contains "status: adb sees nothing" "$OUTPUT" "adb: no device"
assert_contains "status: kdeconnect unpaired" "$OUTPUT" "kdeconnect: no paired device"
assert_contains "status: no ios device" "$OUTPUT" "idevice: no device"

# Paired and trusted.
stub adb 'echo "List of devices attached"; echo "1A2B3C4D	device"'
stub kdeconnect-cli '[ "$1" = "-a" ] && { echo "pixel: Pixel 8"; exit 0; }; echo "pixel: Pixel 8"'
stub idevice_id 'echo 00008110-001234567890ABCD'
stub idevicename 'echo "Owner iPhone"'
stub idevicepair 'exit 0'
capture env HASEEN_SYSROOT="$APPLIED" haseen mobile status
assert_contains "status: adb device listed" "$OUTPUT" "adb: 1A2B3C4D"
assert_contains "status: kdeconnect device listed" "$OUTPUT" "kdeconnect: pixel: Pixel 8"
assert_contains "status: ios device paired" "$OUTPUT" "idevice: 00008110-001234567890ABCD Owner iPhone — paired"
stub idevicepair 'exit 1'
capture env HASEEN_SYSROOT="$APPLIED" haseen mobile status
assert_contains "status: untrusted ios device" "$OUTPUT" "not paired (unlock it, tap Trust"

# --- haseen mobile mirror -----------------------------------------------------
sandbox mobile-mirror
MINPATH="$(mobile_minpath)"

capture haseen mobile mirror --help
assert_status "mirror --help exit" 0 "$STATUS"
assert_contains "mirror --help names the v4l2 prerequisite" "$OUTPUT" "v4l2loopback-dkms package"
assert_contains "mirror --help is honest about iOS" "$OUTPUT" "iOS has no equivalent"
capture haseen mobile mirror --nonsense
assert_status "mirror rejects unknown flags" 2 "$STATUS"

capture env PATH="$MINPATH" haseen mobile mirror
assert_status "mirror without scrcpy" 1 "$STATUS"
assert_contains "mirror without scrcpy points at the layer" "$OUTPUT" "scrcpy is not installed. Run: haseen layer apply mobile"

stub scrcpy 'echo "STUB-CALLED: scrcpy $*" >&2; exit 97'
stub adb 'echo "List of devices attached"'
capture env HASEEN_SYSROOT="$APPLIED" haseen mobile mirror --dry-run
assert_status "mirror with no phone" 1 "$STATUS"
assert_contains "mirror with no phone explains" "$OUTPUT" "no Android device: plug the phone in"
assert_dry_pure "mirror with no phone" "$OUTPUT"

stub adb 'echo "List of devices attached"; echo "1A2B3C4D	unauthorized"'
capture env HASEEN_SYSROOT="$APPLIED" haseen mobile mirror --dry-run
assert_status "mirror with an unauthorised phone" 1 "$STATUS"
assert_contains "mirror names the authorisation prompt" "$OUTPUT" "has not authorised this computer"

stub adb 'echo "List of devices attached"; echo "1A2B3C4D	device"'
capture env HASEEN_SYSROOT="$APPLIED" haseen mobile mirror --dry-run
assert_status "mirror dry-run" 0 "$STATUS"
assert_dry_pure "mirror dry-run" "$OUTPUT"
assert_eq "mirror runs plain scrcpy" "DRYRUN: scrcpy" "$OUTPUT"

capture env HASEEN_SYSROOT="$APPLIED" haseen mobile mirror --dry-run -- --max-fps=30
assert_eq "mirror passes extra args through" "DRYRUN: scrcpy --max-fps=30" "$OUTPUT"

stub adb 'echo "List of devices attached"; echo "1A2B3C4D	device"; echo "9Z8Y7X	device"'
capture env HASEEN_SYSROOT="$APPLIED" haseen mobile mirror --dry-run
assert_status "mirror refuses to guess between phones" 1 "$STATUS"
assert_contains "mirror asks for --serial" "$OUTPUT" "pick one with --serial ID"
capture env HASEEN_SYSROOT="$APPLIED" haseen mobile mirror --serial 9Z8Y7X --dry-run
assert_eq "mirror honours --serial" "DRYRUN: scrcpy --serial 9Z8Y7X" "$OUTPUT"
capture env HASEEN_SYSROOT="$APPLIED" haseen mobile mirror --serial nope --dry-run
assert_status "mirror checks the serial" 1 "$STATUS"
assert_contains "mirror names the unknown serial" "$OUTPUT" "device 'nope' is not in adb's list"

stub adb 'echo "List of devices attached"; echo "1A2B3C4D	device"'
# The prerequisite is checked, not assumed: mobile-plain has no v4l2loopback.
capture env HASEEN_SYSROOT="$PLAIN" haseen mobile mirror --v4l2 --dry-run
assert_status "mirror --v4l2 without the module package" 1 "$STATUS"
assert_contains "mirror --v4l2 names the package" "$OUTPUT" "needs the v4l2loopback-dkms package"
assert_contains "mirror --v4l2 gives the fix" "$OUTPUT" "haseen layer apply mobile -- --v4l2"
assert_dry_pure "mirror --v4l2 refusal" "$OUTPUT"

# mobile-applied has the package and an existing loopback node at video2.
capture env HASEEN_SYSROOT="$APPLIED" haseen mobile mirror --v4l2 --dry-run
assert_status "mirror --v4l2 dry-run" 0 "$STATUS"
assert_contains "mirror --v4l2 finds the loopback node" "$OUTPUT" "webcam sink: /dev/video2"
assert_contains "mirror --v4l2 sinks to it" "$OUTPUT" "DRYRUN: scrcpy --v4l2-sink=/dev/video2"
assert_not_contains "mirror --v4l2 does not reload a loaded module" "$OUTPUT" "modprobe"

# Several loopback nodes (cameras with no hardware behind them): the first is
# the sink, and listing the rest must not kill the command (SIGPIPE).
cp -a "$APPLIED" "$SANDBOX/many-loopback"
rm -rf "$SANDBOX/many-loopback/sys/class/video4linux/"video{0,1}/device
capture env HASEEN_SYSROOT="$SANDBOX/many-loopback" haseen mobile mirror --v4l2 --dry-run
assert_status "mirror --v4l2 with three loopback nodes" 0 "$STATUS"
assert_contains "mirror --v4l2 takes the first loopback node" "$OUTPUT" "webcam sink: /dev/video0"

# Package present, module not loaded: load it, and predict the index it takes.
cp -a "$APPLIED" "$SANDBOX/no-loopback"
rm -rf "$SANDBOX/no-loopback/sys/class/video4linux/video2"
capture env HASEEN_SYSROOT="$SANDBOX/no-loopback" haseen mobile mirror --v4l2 --dry-run
assert_status "mirror --v4l2 with no node" 0 "$STATUS"
assert_dry_pure "mirror --v4l2 with no node" "$OUTPUT"
assert_contains "mirror loads v4l2loopback through run_root" "$OUTPUT" \
    "DRYRUN: sudo modprobe v4l2loopback exclusive_caps=1 card_label=haseen-phone"
assert_contains "mirror predicts the next free index" "$OUTPUT" "webcam sink: /dev/video2"
capture env HASEEN_SYSROOT="$APPLIED" haseen mobile mirror --v4l2=/dev/video9 --dry-run
assert_contains "mirror honours an explicit sink" "$OUTPUT" "DRYRUN: scrcpy --v4l2-sink=/dev/video9"

# --- haseen mobile backup -----------------------------------------------------
sandbox mobile-backup
MINPATH="$(mobile_minpath)"

capture haseen mobile backup --help
assert_status "backup --help exit" 0 "$STATUS"
assert_contains "backup --help refuses to fake Android" "$OUTPUT" "There is no Android equivalent"
assert_contains "backup --help says why adb backup is out" "$OUTPUT" "deprecated"
assert_contains "backup --help offers the Android alternative" "$OUTPUT" "aft-mtp-mount"
assert_contains "backup --help documents restore" "$OUTPUT" "restore <DIR>"
assert_contains "backup --help flags the broken list subcommand" "$OUTPUT" "issues/1058"
capture haseen mobile backup --nonsense
assert_status "backup rejects unknown flags" 2 "$STATUS"
capture haseen mobile backup one two
assert_status "backup rejects two directories" 2 "$STATUS"

capture env PATH="$MINPATH" haseen mobile backup --dry-run
assert_status "backup without libimobiledevice" 1 "$STATUS"
assert_contains "backup points at the layer" "$OUTPUT" "libimobiledevice is not installed. Run: haseen layer apply mobile"

stub idevicebackup2 'echo "STUB-CALLED: idevicebackup2 $*" >&2; exit 97'
stub idevice_id 'exit 0'
capture haseen mobile backup --dry-run
assert_status "backup with no iPhone" 1 "$STATUS"
assert_contains "backup with no iPhone explains" "$OUTPUT" "no iOS device: plug in an unlocked iPhone"
assert_dry_pure "backup with no iPhone" "$OUTPUT"

stub idevice_id 'echo 00008110-001234567890ABCD'
stub idevicepair 'exit 1'
capture haseen mobile backup --dry-run
assert_status "backup with an untrusted iPhone" 1 "$STATUS"
assert_contains "backup names the Trust prompt" "$OUTPUT" "tap Trust on the phone"

stub idevicepair 'exit 0'
stub idevicename 'echo "Owner iPhone"'
capture haseen mobile backup --dry-run
assert_status "backup dry-run" 0 "$STATUS"
assert_dry_pure "backup dry-run" "$OUTPUT"
assert_contains "backup default destination" "$OUTPUT" "DRYRUN: mkdir -p $HOME/Backups/ios"
assert_contains "backup runs idevicebackup2 --full" "$OUTPUT" \
    "DRYRUN: idevicebackup2 --udid 00008110-001234567890ABCD backup --full $HOME/Backups/ios"
assert_contains "backup prints the restore command" "$OUTPUT" "Restore with: idevicebackup2 --udid"
capture haseen mobile backup "$SANDBOX/elsewhere" --dry-run
assert_contains "backup honours a directory argument" "$OUTPUT" "backup --full $SANDBOX/elsewhere"

stub idevice_id 'echo 00008110-001234567890ABCD; echo 00008120-00FEDCBA098765'
capture haseen mobile backup --dry-run
assert_status "backup refuses to guess between iPhones" 1 "$STATUS"
assert_contains "backup asks for --udid" "$OUTPUT" "pick one with --udid UDID"
capture haseen mobile backup --udid 00008120-00FEDCBA098765 --dry-run
assert_contains "backup honours --udid" "$OUTPUT" "--udid 00008120-00FEDCBA098765 backup --full"
capture haseen mobile backup --udid nope --dry-run
assert_status "backup checks the udid" 1 "$STATUS"
assert_contains "backup names the unknown udid" "$OUTPUT" "device 'nope' is not attached"

# --- the router sees all three ------------------------------------------------
capture haseen mobile
for c in status mirror backup; do
    assert_contains "router lists mobile $c" "$OUTPUT" "haseen mobile $c"
done
