# shellcheck shell=bash
# haseen:covers share/haseen/omarchy/{commands.tsv,dispatch,lib.sh,remove-lib.sh}
# haseen:covers share/haseen/omarchy/bin/omarchy bin/haseen-hw-match share/haseen/lib/hardware.sh
# haseen:covers share/haseen/omarchy/bin/omarchy-agent-account-*
# haseen:covers share/haseen/omarchy/bin/omarchy-*dictation*
# haseen:covers share/haseen/omarchy/bin/omarchy-hw-aarch64*
# haseen:covers share/haseen/omarchy/bin/omarchy-remove-ai-*
# haseen:covers share/haseen/omarchy/bin/omarchy-hyprland-workspace-layout-*
# haseen:covers share/haseen/omarchy/bin/omarchy-{agent-usage-grok,agent-usage-kimi}
# haseen:covers share/haseen/omarchy/bin/omarchy-{apply-n1x-gpu-memory,ascii,boot-direct}
# haseen:covers share/haseen/omarchy/bin/omarchy-branding-about-animation
# haseen:covers share/haseen/omarchy/bin/omarchy-capture-screenrecording-process
# haseen:covers share/haseen/omarchy/bin/omarchy-{chromium-add-feature,cmd-terminal-cwd,crash-mute}
# haseen:covers share/haseen/omarchy/bin/omarchy-{dev-notification-demo,font-cjk}
# haseen:covers share/haseen/omarchy/bin/omarchy-{hw-dell-xps13-sidecar-amps,hw-elgato-camlink-4k}
# haseen:covers share/haseen/omarchy/bin/omarchy-{hw-match-device-tree,hw-n1x,hw-platform,hw-vm}
# haseen:covers share/haseen/omarchy/bin/omarchy-{hw-x86,hyprland-corners}
# haseen:covers share/haseen/omarchy/bin/omarchy-{hyprland-window-transparency,i18n,input-method}
# haseen:covers share/haseen/omarchy/bin/omarchy-{install-ai-claude,install-camera}
# haseen:covers share/haseen/omarchy/bin/omarchy-{install-chromium-claude,install-service-microsoft}
# haseen:covers share/haseen/omarchy/bin/omarchy-{install-t3code-app,install-video-decode,language}
# haseen:covers share/haseen/omarchy/bin/omarchy-{launch-terminal,locale-generate,menu-select}
# haseen:covers share/haseen/omarchy/bin/omarchy-{mise-default-tools,n1x-probe}
# haseen:covers share/haseen/omarchy/bin/omarchy-{network-wifi-connected,remove-service-microsoft}
# haseen:covers share/haseen/omarchy/bin/omarchy-{remove-service-ssh-agent,security-functions}
# haseen:covers share/haseen/omarchy/bin/omarchy-{setup-input,setup-keyboard,sleep-disabled,system}
# haseen:covers share/haseen/omarchy/bin/omarchy-{system-lid-inhibit,theme-bg-intro}
# haseen:covers share/haseen/omarchy/bin/omarchy-{theme-set-fcitx5,theme-set-herdr-machines}
# haseen:covers share/haseen/omarchy/bin/omarchy-{theme-set-hunk,toggle-fullscreen-desktop}
# haseen:covers share/haseen/omarchy/bin/omarchy-{toggle-theme-sync,update-pacman}
# haseen:covers share/haseen/omarchy/bin/omarchy-{webapp-window-class,windows-key}
# haseen:covers share/haseen/omarchy/bin/omarchy-{system-logout,system-reboot,toggle-bar}
# haseen:covers share/haseen/omarchy/bin/omarchy-toggle-enabled
# haseen:covers share/haseen/omarchy/bin/omarchy-plymouth-set
# haseen:covers tests/fixtures/mkinitcpio-omarchy-4.5/**
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# haseen's answers to the commands Omarchy 4.5 adds, and to the 4.5 callers of
# older ones (plan 102). The platform detector and its predicates answer from
# fixture trees; ARM machines exist here only as fixtures. haseen's own
# commands are recorders in a fake tree (HASEEN_PATH=$FAKE/share/haseen).

OMA="$HASEEN_PATH/omarchy/bin"
export HASEEN_INLINE=1
unset OMARCHY_PATH OMARCHY_LANGUAGE_FILE

# box NAME — a sandbox with a fixture root (ROOT, HASEEN_SYSROOT), uname
# answering x86_64 unless MACHINE says otherwise, and a fake haseen tree
# whose bin/ holds recorders of the haseen commands named in RECORDERS.
RECORDERS=(haseen-install haseen-remove haseen-webapp-install haseen-webapp-remove haseen-system
    haseen-toggle-gaps haseen-toggle-bar haseen-toggle-workspace-layout haseen-menu-select
    haseen-notification-send haseen-update haseen-hw-match haseen-theme-current haseen-setup-ssh-agent)
box() {
    sandbox "$1"
    ROOT="$SANDBOX/root"
    LOG="$SANDBOX/calls"
    FAKE="$SANDBOX/fake"
    mkdir -p "$ROOT" "$FAKE/bin" "$FAKE/share/haseen"
    : >"$LOG"
    export HASEEN_SYSROOT="$ROOT"
    local d t
    for d in lib omarchy hardware layers default; do
        ln -s "$HASEEN_PATH/$d" "$FAKE/share/haseen/$d"
    done
    for t in "${RECORDERS[@]}"; do
        printf '#!/bin/sh\n{ printf %%s "${0##*/}"; for a in "$@"; do printf " [%%s]" "$a"; done; echo; } >>"%s"\n' \
            "$LOG" >"$FAKE/bin/$t"
        chmod +x "$FAKE/bin/$t"
    done
    stub uname 'case "$1" in -m) echo "${MACHINE:-x86_64}" ;; *) echo Linux ;; esac'
}
# fk NAME ARGS... — run haseen's answer NAME with the fake haseen tree.
fk() { env HASEEN_PATH="$FAKE/share/haseen" "$OMA/$1" "${@:2}"; }
calls() { cat "$LOG"; }
# rec NAME — a PATH stub that logs "NAME [arg]..." to the call log.
rec() { stub "$1" "{ printf %s '$1'; for a in \"\$@\"; do printf ' [%s]' \"\$a\"; done; echo; } >>'$LOG'"; }
# dt STRING... — the fixture's device-tree root compatible strings.
dt() {
    mkdir -p "$ROOT/proc/device-tree"
    printf '%s\0' "$@" >"$ROOT/proc/device-tree/compatible"
}
pci() {
    mkdir -p "$ROOT/sys/bus/pci/devices/$1"
    echo "$2" >"$ROOT/sys/bus/pci/devices/$1/vendor"
    echo "$3" >"$ROOT/sys/bus/pci/devices/$1/device"
}

# --- the platform detector and its predicates -------------------------------------
box omarchy45-platform
assert_eq "x86 answers x86" "x86" "$("$OMA/omarchy-hw-platform")"
capture "$OMA/omarchy-hw-aarch64-qualcomm"
assert_status "not a Snapdragon on x86" 1 "$STATUS"
capture "$OMA/omarchy-hw-x86"
assert_status "hw-x86 on x86" 0 "$STATUS"
capture "$OMA/omarchy-hw-aarch64"
assert_status "hw-aarch64 on x86" 1 "$STATUS"
assert_eq "an ARM machine without a family is aarch64" "aarch64" "$(MACHINE=aarch64 "$OMA/omarchy-hw-platform")"
dt qcom,x1e80100-crd qcom,x1e80100
assert_eq "a qcom device tree is a Snapdragon" "aarch64-qualcomm" "$(MACHINE=aarch64 "$OMA/omarchy-hw-platform")"
capture env MACHINE=aarch64 "$OMA/omarchy-hw-aarch64-qualcomm"
assert_status "and the Snapdragon predicate says yes" 0 "$STATUS"
capture env MACHINE=aarch64 "$OMA/omarchy-hw-aarch64-n1x"
assert_status "and the N1x predicate no" 1 "$STATUS"
capture "$OMA/omarchy-hw-platform"
assert_status "a qcom device tree on an x86 CPU contradicts itself" 1 "$STATUS"
assert_contains "and says so" "$OUTPUT" "contradictory platform identity"
dt apple,j314s apple,arm-platform
assert_eq "an apple device tree is Apple Silicon" "aarch64-apple" "$(MACHINE=aarch64 "$OMA/omarchy-hw-platform")"
dt qcom,x apple,y
capture env MACHINE=aarch64 "$OMA/omarchy-hw-platform"
assert_status "Apple and Qualcomm at once is refused" 1 "$STATUS"
rm -r "$ROOT/proc/device-tree"
mkdir -p "$ROOT/sys/bus/acpi/devices/NVDA0200:00"
assert_eq "ACPI NVDA0200 is an N1x" "aarch64-n1x" "$(MACHINE=aarch64 "$OMA/omarchy-hw-platform")"
capture env MACHINE=aarch64 "$OMA/omarchy-hw-aarch64-n1x"
assert_status "the N1x predicate says yes" 0 "$STATUS"
capture env MACHINE=aarch64 "$OMA/omarchy-hw-n1x"
assert_status "and so does its old name" 0 "$STATUS"
rm -r "$ROOT/sys/bus/acpi"
pci 0000:01:00.0 0x10de 0x2e06
assert_eq "the GB20B GPU is an N1x too" "aarch64-n1x" "$(MACHINE=aarch64 "$OMA/omarchy-hw-platform")"
rm -r "$ROOT/sys/bus/pci"
pci 0000:01:00.0 0x10de 0x2e12
assert_eq "PCI 10de:2e12 is a GB10 desktop" "aarch64-gb10" "$(MACHINE=aarch64 "$OMA/omarchy-hw-platform")"
capture env MACHINE=aarch64 "$OMA/omarchy-hw-aarch64-gb10"
assert_status "the GB10 predicate says yes" 0 "$STATUS"
pci 0000:02:00.0 0x10de 0x2e06
capture env MACHINE=aarch64 "$OMA/omarchy-hw-platform"
assert_status "an N1x and a GB10 at once is refused" 1 "$STATUS"
rm -r "$ROOT/sys/bus/pci"
# An image being built (no systemd as PID 1 in this root) is named by its
# manifest; a booted one never reads it.
mkdir -p "$ROOT/var/lib/omarchy/image"
chmod 755 "$ROOT/var/lib/omarchy/image"
printf 'format=1\nplatform=generic-aarch64\n' >"$ROOT/var/lib/omarchy/image/target"
chmod 644 "$ROOT/var/lib/omarchy/image/target"
assert_eq "an image build reads its manifest" "aarch64" "$(MACHINE=aarch64 "$OMA/omarchy-hw-platform")"
capture "$OMA/omarchy-hw-platform"
assert_status "a manifest naming ARM on an x86 CPU is refused" 1 "$STATUS"
mkdir -p "$ROOT/run/systemd/system"
assert_eq "a booted root answers from its hardware" "x86" "$("$OMA/omarchy-hw-platform")"
rm -r "$ROOT/var/lib/omarchy" "$ROOT/run"
capture bash "$OMA/omarchy-hw-platform"
assert_status "a launch without -p is refused" 126 "$STATUS"
capture bash "$OMA/omarchy-hw-aarch64-gb10"
assert_status "so is a predicate's" 126 "$STATUS"
# Omarchy's mkinitcpio drop-in runs `command -v omarchy-hw-platform` on every
# initramfs build, as root, with whatever PATH and environment it has (often
# no HOME): haseen's sits first and must answer.
# shellcheck disable=SC2016  # expands in the inner shell
capture env -i PATH="$OMA:/usr/bin:/bin" bash -c 'd=$(command -v omarchy-hw-platform) && [ "$d" = "$1/omarchy-hw-platform" ] && "$d"' _ "$OMA"
assert_eq "found first on PATH, without HOME, it answers" "x86" "$OUTPUT"
capture env -u HOME "$OMA/omarchy-hw-x86"
assert_status "a predicate that sources haseen's library answers without HOME" 0 "$STATUS"

box omarchy45-predicates
capture "$OMA/omarchy-hw-match-device-tree" qcom,x1e80100
assert_status "no device tree: no match" 1 "$STATUS"
dt Qcom,X1E80100-CRD qcom,x1e80100
capture "$OMA/omarchy-hw-match-device-tree" other qcom,x1e80100-crd
assert_status "a compatible string matches, case folded" 0 "$STATUS"
capture "$OMA/omarchy-hw-match-device-tree" qcom
assert_status "a prefix is not a match" 1 "$STATUS"
mkdir -p "$ROOT/sys/bus/usb/devices/1-2" "$ROOT/sys/class/dmi/id"
echo "USB Keyboard" >"$ROOT/sys/bus/usb/devices/1-2/product"
capture "$OMA/omarchy-hw-elgato-camlink-4k"
assert_status "no Cam Link" 1 "$STATUS"
echo "Cam Link 4K" >"$ROOT/sys/bus/usb/devices/1-2/product"
capture "$OMA/omarchy-hw-elgato-camlink-4k"
assert_status "a Cam Link 4K" 0 "$STATUS"
echo "QEMU" >"$ROOT/sys/class/dmi/id/sys_vendor"
capture "$OMA/omarchy-hw-vm"
assert_status "a hypervisor's firmware is a VM" 0 "$STATUS"
echo "Dell Inc." >"$ROOT/sys/class/dmi/id/sys_vendor"
capture "$OMA/omarchy-hw-vm"
assert_status "a Dell is not" 1 "$STATUS"
ln -sf "$REPO/bin/haseen-hw-match" "$FAKE/bin/haseen-hw-match"
echo "XPS 13 DX13260" >"$ROOT/sys/class/dmi/id/product_name"
echo "0E53" >"$ROOT/sys/class/dmi/id/product_sku"
capture fk omarchy-hw-dell-xps13-sidecar-amps
assert_status "the DX13260 with SKU 0E53" 0 "$STATUS"
echo "0E54" >"$ROOT/sys/class/dmi/id/product_sku"
capture fk omarchy-hw-dell-xps13-sidecar-amps
assert_status "another SKU" 1 "$STATUS"
capture "$OMA/omarchy-sleep-disabled"
assert_status "sleep on" 1 "$STATUS"
mkdir -p "$ROOT/etc/systemd/sleep.conf.d"
: >"$ROOT/etc/systemd/sleep.conf.d/omarchy-sleep-disabled.conf"
capture "$OMA/omarchy-sleep-disabled"
assert_status "Omarchy's sleep-disabled drop-in" 0 "$STATUS"
# Root reads only the live machine: a fixture root in its environment is
# ignored, as Omarchy's match-device-tree ignores its fixture variables for
# root (plan 102). Root here is a user namespace's.
if command -v unshare >/dev/null && timeout 10 unshare --user --map-root-user true </dev/null >/dev/null 2>&1; then
    stub systemd-detect-virt "echo \"systemd-detect-virt \$*\" >>'$LOG'; exit 1"
    echo "QEMU" >"$ROOT/sys/class/dmi/id/sys_vendor"
    capture "$OMA/omarchy-hw-vm"
    assert_status "a fixture's hypervisor strings answer for a user" 0 "$STATUS"
    : >"$LOG"
    capture timeout 10 unshare --user --map-root-user "$OMA/omarchy-hw-vm"
    assert_status "for root they are ignored" 1 "$STATUS"
    assert_eq "and the live probe answers" "systemd-detect-virt --vm --quiet" "$(calls)"
    capture "$OMA/omarchy-hw-match-device-tree" qcom,x1e80100
    assert_status "a fixture's device tree answers for a user" 0 "$STATUS"
    if [[ -e /proc/device-tree/compatible || -e /sys/firmware/devicetree/base/compatible ]]; then
        echo "  skip: this host has a device tree of its own, so root's answer is the host's" >&2
    else
        capture timeout 10 unshare --user --map-root-user "$OMA/omarchy-hw-match-device-tree" qcom,x1e80100
        assert_status "for root it is ignored: this host has no device tree" 1 "$STATUS"
    fi
else
    echo "  skip: no user namespaces here, so the root path of hw-vm and hw-match-device-tree is not exercised" >&2
fi

# --- non-Apple ARM steps: nothing on x86, the real step on the hardware -------------
box omarchy45-arm
capture "$OMA/omarchy-apply-n1x-gpu-memory"
assert_status "the N1x GPU step does nothing on x86" 0 "$STATUS"
assert_eq "and says nothing" "" "$OUTPUT"
mkdir -p "$ROOT/sys/bus/acpi/devices/NVDA0200:00" "$ROOT/sys/firmware/efi/efivars"
var="$ROOT/sys/firmware/efi/efivars/EXPOSED_DISP_FRM-4b086294-0740-4f71-a7b5-85a329c7ec5f"
printf '\x07\x00\x00\x00\x00\xfa\x00\x00\x00\x00\x00\x20\x00\x00\x00\x00\x00\x00\x00\x00\x01\x00\x00\x00\x00' >"$var"
capture env MACHINE=aarch64 "$OMA/omarchy-apply-n1x-gpu-memory" --dry-run
assert_status "on an N1x the shipped reservation is resized" 0 "$STATUS"
assert_dry_pure "omarchy-apply-n1x-gpu-memory" "$OUTPUT"
assert_contains "through root, keeping the variable immutable around the write" "$OUTPUT" "DRYRUN: sudo chattr -i $var"
assert_contains "one write of attributes and data" "$OUTPUT" "DRYRUN: sudo dd if="
printf '\x07\x00\x00\x00\x00\x10\x00\x00\x00\x00\x00\x20\x00\x00\x00\x00\x00\x00\x00\x00\x01\x00\x00\x00\x01' >"$var"
capture env MACHINE=aarch64 "$OMA/omarchy-apply-n1x-gpu-memory"
assert_contains "an already resized reservation is left" "$OUTPUT" "already set to 4 GiB"
printf '\x07\x00\x00\x00\x00\xfa\x00\x00\x09' >"$var"
capture env MACHINE=aarch64 "$OMA/omarchy-apply-n1x-gpu-memory"
assert_status "an unknown layout is left alone" 1 "$STATUS"
rm -r "$ROOT/sys/bus/acpi"
capture "$OMA/omarchy-n1x-probe" --dry-run
assert_dry_pure "omarchy-n1x-probe" "$OUTPUT"
assert_contains "the probe goes to haseen's log" "$OUTPUT" "/var/log/haseen-n1x-probe.log"
FLAGSF="$HOME/.config/chromium-flags.conf"
capture "$OMA/omarchy-chromium-add-feature" Bad-Name
assert_status "a feature is one word" 1 "$STATUS"
capture "$OMA/omarchy-chromium-add-feature" WebRtcPipeWireCamera
assert_status "no flags file: nothing to do" 0 "$STATUS"
assert_eq "and none is made" "no" "$([[ -e $FLAGSF ]] && echo yes || echo no)"
mkdir -p "$HOME/.config"
printf -- '--ozone-platform=wayland' >"$FLAGSF"
"$OMA/omarchy-chromium-add-feature" WebRtcPipeWireCamera
assert_eq "a feature starts a list on a line of its own" $'--ozone-platform=wayland\n--enable-features=WebRtcPipeWireCamera' "$(<"$FLAGSF")"
"$OMA/omarchy-chromium-add-feature" AcceleratedVideoDecoder
assert_eq "a second one joins the list" $'--ozone-platform=wayland\n--enable-features=WebRtcPipeWireCamera,AcceleratedVideoDecoder' "$(<"$FLAGSF")"
before="$(<"$FLAGSF")"
"$OMA/omarchy-chromium-add-feature" WebRtcPipeWireCamera
assert_eq "a feature already on is not added twice" "$before" "$(<"$FLAGSF")"
capture "$OMA/omarchy-install-camera"
assert_eq "the camera step does nothing off a Snapdragon" "$before" "$(<"$FLAGSF")"
capture "$OMA/omarchy-install-video-decode"
assert_eq "nor does the video-decode step" "no" "$([[ -e $HOME/.config/mpv/mpv.conf ]] && echo yes || echo no)"
dt qcom,x1e80100
printf -- '--ozone-platform=wayland\n' >"$FLAGSF"
capture env MACHINE=aarch64 "$OMA/omarchy-install-camera"
assert_contains "on a Snapdragon the camera feature goes on" "$(<"$FLAGSF")" "--enable-features=WebRtcPipeWireCamera"
capture env MACHINE=aarch64 "$OMA/omarchy-install-video-decode" --dry-run
assert_dry_pure "omarchy-install-video-decode" "$OUTPUT"
assert_contains "mpv gets the decoder fallback" "$OUTPUT" "hwdec=auto-safe,v4l2m2m-copy"
capture env MACHINE=aarch64 "$OMA/omarchy-install-video-decode"
assert_eq "mpv.conf is written when there is none" $'# Fall back to the Snapdragon video chip\'s decoder (Omarchy)\nhwdec=auto-safe,v4l2m2m-copy' "$(<"$HOME/.config/mpv/mpv.conf")"
assert_contains "Chromium gets ANGLE on GLES" "$(<"$FLAGSF")" "--use-angle=gles-egl"
assert_contains "and the decoder feature" "$(<"$FLAGSF")" "AcceleratedVideoDecoder"
printf 'hwdec=vaapi\n' >"$HOME/.config/mpv/mpv.conf"
capture env MACHINE=aarch64 "$OMA/omarchy-install-video-decode"
assert_eq "a global hwdec the user set stays" "hwdec=vaapi" "$(<"$HOME/.config/mpv/mpv.conf")"
# The lid inhibitor: only an in-use USB-C display on a laptop whose logind
# ignores a docked lid.
mkdir -p "$ROOT/sys/class/drm/card1-USB-1" "$ROOT/sys/class/drm/card1-eDP-1" "$ROOT/proc/self" "$ROOT/sys/class/dmi/id"
echo connected >"$ROOT/sys/class/drm/card1-USB-1/status"
echo connected >"$ROOT/sys/class/drm/card1-eDP-1/status"
echo 10 >"$ROOT/sys/class/dmi/id/chassis_type"
echo '0::/user.slice/user-1000.slice/user@1000.service/app.slice/watch.service' >"$ROOT/proc/self/cgroup"
stub hyprctl 'echo "[{\"name\":\"USB-1\",\"disabled\":false}]"'
stub busctl 'echo "s \"ignore\""'
stub systemctl 'exit 3'
capture "$OMA/omarchy-system-lid-inhibit" --dry-run
assert_dry_pure "omarchy-system-lid-inhibit" "$OUTPUT"
assert_contains "the inhibitor is haseen's unit, bound to its watcher" "$OUTPUT" \
    "DRYRUN: systemd-run --user --quiet --collect --unit=haseen-lid-inhibit.service --description=haseen clamshell lid inhibitor --property=PartOf=graphical-session.target --property=BindsTo=watch.service"
echo disconnected >"$ROOT/sys/class/drm/card1-USB-1/status"
capture "$OMA/omarchy-system-lid-inhibit" --dry-run
assert_eq "an HDMI or DisplayPort dock needs nothing" "" "$OUTPUT"

# --- shared plumbing --------------------------------------------------------------------
box omarchy45-i18n
I18N="$ROOT/usr/share/omarchy/default/i18n"
capture "$OMA/omarchy-i18n" system.rebooting
assert_eq "without Omarchy's catalogs the key itself is printed" "system.rebooting" "$OUTPUT"
mkdir -p "$I18N/en" "$I18N/da"
printf '{"system.rebooting":"Rebooting","tailscale.received":"Received %%1 from %%2"}\n' >"$I18N/en/cli.json"
printf '{"system.rebooting":"Genstarter"}\n' >"$I18N/da/cli.json"
printf '{"en":{"locale":"en_US.UTF-8","name":"English","englishName":"English"},"da":{"locale":"da_DK.UTF-8","name":"Dansk","englishName":"Danish","decimal":","}}\n' >"$I18N/locales.json"
cat >"$I18N/plural.jq" <<'JQ'
def plural_pick($language; $count): if ($count == 1) then .one else .other end;
def localize_number($decimal; $zero): if (type == "string" and test("^-?[0-9]+[.][0-9]+$")) then sub("[.]"; $decimal) else . end;
JQ
assert_eq "an English string with its arguments" "Received a.txt from box" "$("$OMA/omarchy-i18n" tailscale.received a.txt box)"
mkdir -p "$HOME/.config/omarchy"
echo da >"$HOME/.config/omarchy/language"
assert_eq "Omarchy's chosen language" "Genstarter" "$("$OMA/omarchy-i18n" system.rebooting)"
assert_eq "a missing translation falls back to English" "Received x from y" "$("$OMA/omarchy-i18n" tailscale.received x y)"
assert_eq "--number writes the language's decimal separator" "13,1" "$("$OMA/omarchy-i18n" --number 13.1)"
capture "$OMA/omarchy-i18n"
assert_status "no key is a usage error" 1 "$STATUS"
assert_eq "omarchy-language reads the same choice" "da" "$("$OMA/omarchy-language")"
assert_eq "and the locale" "da_DK.UTF-8" "$("$OMA/omarchy-language" locale)"
assert_contains "and the list" "$("$OMA/omarchy-language" list)" $'Dansk\tda\tDanish'
capture "$OMA/omarchy-language" ar
assert_status "setting a language is refused" 1 "$STATUS"
assert_contains "with how to set the system's" "$OUTPUT" "localectl set-locale"
rm "$HOME/.config/omarchy/language"
assert_eq "no choice is English" "en" "$("$OMA/omarchy-language")"
printf '# comment\n#da_DK.UTF-8 UTF-8\nen_US.UTF-8 UTF-8\n' >"$ROOT/etc-locale.gen"
mkdir -p "$ROOT/etc"
mv "$ROOT/etc-locale.gen" "$ROOT/etc/locale.gen"
capture "$OMA/omarchy-locale-generate" da --dry-run
assert_dry_pure "omarchy-locale-generate" "$OUTPUT"
assert_contains "a commented locale is uncommented as root" "$OUTPUT" "DRYRUN: sudo sed -i -E s/^#(da_DK(\\.UTF-8)? UTF-8)/\\1/ /etc/locale.gen"
assert_contains "then generated" "$OUTPUT" "DRYRUN: sudo locale-gen da_DK.UTF-8"
capture "$OMA/omarchy-locale-generate" 'da;rm'
assert_status "only a registry code selects a locale" 1 "$STATUS"
capture "$OMA/omarchy-locale-generate" xx
assert_status "an unknown code" 1 "$STATUS"

box omarchy45-sourced
capture bash -c 'source "$1"; declare -F sheen_build compose_frame; type run >/dev/null 2>&1 && echo leaked; echo "rc=$?"' _ "$OMA/omarchy-branding-about-animation"
assert_contains "sourced, the About sheen defines Omarchy's helpers" "$OUTPUT" "sheen_build"
assert_not_contains "and nothing of haseen's" "$OUTPUT" "leaked"
capture "$OMA/omarchy-branding-about-animation"
assert_status "run, it is a library" 64 "$STATUS"
capture bash -c 'source "$1"; echo "rc=$?"; declare -F | grep -c omarchy_security || true' _ "$OMA/omarchy-security-functions"
assert_contains "sourced, Omarchy's security library fails closed" "$OUTPUT" "rc=1"
assert_contains "and says why" "$OUTPUT" "not available under haseen"
assert_contains "and defines nothing" "$OUTPUT" $'rc=1\n0'

box omarchy45-plumbing
mkdir -p "$ROOT/proc/4321" "$ROOT/proc/4322"
ln -s /usr/bin/gpu-screen-recorder "$ROOT/proc/4321/exe"
ln -s /usr/bin/gpu-screen-reco-fake "$ROOT/proc/4322/exe"
stub pgrep 'printf "4321\n4322\n"'
capture "$OMA/omarchy-capture-screenrecording-process"
assert_status "a recorder runs" 0 "$STATUS"
capture "$OMA/omarchy-capture-screenrecording-process" --pid 4322
assert_status "a look-alike is not a recorder" 1 "$STATUS"
capture "$OMA/omarchy-capture-screenrecording-process" --signal INT --dry-run
assert_contains "the recorder is signalled" "$OUTPUT" "DRYRUN: kill -INT 4321"
assert_not_contains "and only the recorder" "$OUTPUT" "4322"
capture "$OMA/omarchy-capture-screenrecording-process" --signal TERM
assert_status "only INT or KILL" 2 "$STATUS"
stub pgrep 'exit 1'
capture "$OMA/omarchy-capture-screenrecording-process"
assert_status "no recorder" 1 "$STATUS"
assert_eq "a web app's window class" "chrome-app.hey.com__imbox-Default" "$("$OMA/omarchy-webapp-window-class" "https://user@APP.hey.com:443/imbox?x=1#y")"
assert_eq "a bare host" "chrome-example.org__-Default" "$("$OMA/omarchy-webapp-window-class" https://example.org)"
mkdir -p "$ROOT/sys/class/net/wlan0/wireless"
stub ip 'echo "1.1.1.1 via 192.0.2.1 dev wlan0 src 192.0.2.10 uid 1000"'
stub busctl 'case "$*" in *GetDeviceByIpIface*) echo "o \"/org/freedesktop/NetworkManager/Devices/3\"" ;; *State*) echo "${NM_STATE:-u 100}" ;; esac'
capture "$OMA/omarchy-network-wifi-connected"
assert_status "the default route over activated Wi-Fi" 0 "$STATUS"
capture env NM_STATE="u 70" "$OMA/omarchy-network-wifi-connected"
assert_status "a Wi-Fi device still connecting" 1 "$STATUS"
stub ip 'echo "1.1.1.1 via 192.0.2.1 dev enp1s0 src 192.0.2.10"'
capture "$OMA/omarchy-network-wifi-connected"
assert_status "a wired route" 1 "$STATUS"
mkdir -p "$ROOT/sys/firmware/acpi/tables"
printf 'MSDM\x00\x00junkAB1CD-EF2GH-IJ3KL-MN4OP-QR5STmore' >"$ROOT/sys/firmware/acpi/tables/MSDM"
assert_eq "the firmware's Windows key" "AB1CD-EF2GH-IJ3KL-MN4OP-QR5ST" "$("$OMA/omarchy-windows-key")"
rm "$ROOT/sys/firmware/acpi/tables/MSDM"
capture "$OMA/omarchy-windows-key"
assert_status "no MSDM table" 1 "$STATUS"
stub efibootmgr 'printf "BootCurrent: 0001\nBoot0001* Limine\tHD(1)\nBoot0003* haseen\tHD(1)/File(EFI)\nBoot0004  Omarchy\tHD(1)\n"'
capture "$OMA/omarchy-boot-direct"
assert_status "haseen's active direct-boot entry counts" 0 "$STATUS"
assert_eq "--number lists haseen's and Omarchy's, active or not" $'0003\n0004' "$("$OMA/omarchy-boot-direct" --number)"
stub efibootmgr 'printf "Boot0001* Limine\tHD(1)\nBoot0004  Omarchy\tHD(1)\n"'
capture "$OMA/omarchy-boot-direct"
assert_status "an inactive entry is not booted" 1 "$STATUS"
stub efibootmgr 'exit 1'
capture "$OMA/omarchy-boot-direct"
assert_status "an unreadable list is not 'no direct boot'" 2 "$STATUS"
stub pgrep 'exit 1'
capture "$OMA/omarchy-theme-set-hunk" --dry-run
assert_eq "no hunk running: nothing to nudge" "" "$OUTPUT"
stub pgrep 'echo 77'
capture "$OMA/omarchy-theme-set-hunk" --dry-run
assert_contains "running hunks get SIGWINCH" "$OUTPUT" "DRYRUN: pkill -WINCH -x hunk"
assert_dry_pure "omarchy-theme-set-hunk" "$OUTPUT"

box omarchy45-mise
mkdir -p "$ROOT/etc/mise/conf.d"
printf '[settings]\nx = 1\n\n[tools]\nnode = "lts"\n"npm:@openai/codex" = "latest"\nclaude = "latest"\n' >"$ROOT/etc/mise/conf.d/omarchy-tools.toml"
rec mise
assert_eq "Omarchy's declared tools" $'node\nnpm:@openai/codex\nclaude' "$("$OMA/omarchy-mise-default-tools" list)"
capture "$OMA/omarchy-mise-default-tools" declares claude
assert_status "claude is declared" 0 "$STATUS"
capture "$OMA/omarchy-mise-default-tools" declares grok
assert_status "grok is not" 1 "$STATUS"
capture "$OMA/omarchy-mise-default-tools" disable --dry-run
assert_dry_pure "mise disable" "$OUTPUT"
assert_eq "a dry run writes nothing" "no" "$([[ -e $HOME/.config/mise/miserc.toml ]] && echo yes || echo no)"
mkdir -p "$HOME/.config/mise"
printf 'mine = 1' >"$HOME/.config/mise/miserc.toml"
"$OMA/omarchy-mise-default-tools" disable
assert_eq "disable adds the one line, after a newline" $'mine = 1\nignored_config_paths = ["/etc/mise/conf.d/omarchy-tools.toml"]' \
    "$(<"$HOME/.config/mise/miserc.toml")"
capture "$OMA/omarchy-mise-default-tools" declares claude
assert_status "opted out, nothing is declared" 1 "$STATUS"
assert_contains "and the shims are rebuilt" "$(calls)" "mise [reshim]"
"$OMA/omarchy-mise-default-tools" enable
assert_eq "enable takes only that line out" "mine = 1" "$(<"$HOME/.config/mise/miserc.toml")"
printf 'ignored_config_paths = ["/etc/x.toml"]\n' >"$HOME/.config/mise/miserc.toml"
capture "$OMA/omarchy-mise-default-tools" disable
assert_status "a list of the user's own is theirs to edit" 1 "$STATUS"
assert_eq "and stays as it was" 'ignored_config_paths = ["/etc/x.toml"]' "$(<"$HOME/.config/mise/miserc.toml")"

box omarchy45-crash-mute
MUTES="$HOME/.local/state/haseen/toggles/crash-ignore"
assert_eq "nothing muted" "No programs muted. Crashes all notify." "$("$OMA/omarchy-crash-mute")"
capture "$OMA/omarchy-crash-mute" /usr/bin/hyprland --dry-run
assert_contains "a dry mute plans the flag" "$OUTPUT" "DRYRUN: write $MUTES/hyprland"
assert_eq "and writes nothing" "no" "$([[ -e $MUTES ]] && echo yes || echo no)"
assert_eq "a path is muted by its name" "Muted crash notifications for hyprland." "$("$OMA/omarchy-crash-mute" /usr/bin/hyprland)"
assert_eq "the list names it" "hyprland" "$("$OMA/omarchy-crash-mute")"
assert_eq "toggle unmutes" "Crash notifications for hyprland are back on." "$("$OMA/omarchy-crash-mute" hyprland toggle)"
capture "$OMA/omarchy-crash-mute" ..
assert_status "not a program name" 1 "$STATUS"
capture "$OMA/omarchy-crash-mute" foot sideways
assert_status "not an action" 1 "$STATUS"

# --- theme publishers and desktop settings ----------------------------------------------
box omarchy45-theme
mkdir -p "$HOME/.local/state/haseen/current/theme" "$ROOT/usr/share/fcitx5/themes/default" "$HOME/.config/fcitx5/conf"
echo "[InputPanel]" >"$HOME/.local/state/haseen/current/theme/fcitx5-theme.conf"
: >"$ROOT/usr/share/fcitx5/themes/default/arrow.svg"
stub busctl 'exit 0'
THEMEDIR="$HOME/.local/share/fcitx5/themes/haseen"
capture "$OMA/omarchy-theme-set-fcitx5"
assert_eq "without --activate and no theme directory: nothing" "no" "$([[ -e $THEMEDIR ]] && echo yes || echo no)"
capture "$OMA/omarchy-theme-set-fcitx5" --activate --dry-run
assert_dry_pure "omarchy-theme-set-fcitx5" "$OUTPUT"
printf 'Theme=default\nFont="Sans 10"\n' >"$HOME/.config/fcitx5/conf/classicui.conf"
"$OMA/omarchy-theme-set-fcitx5" --activate
assert_eq "the theme lands in haseen's fcitx5 theme" "[InputPanel]" "$(<"$THEMEDIR/theme.conf")"
assert_eq "with fcitx5's packaged glyphs" "$ROOT/usr/share/fcitx5/themes/default/arrow.svg" "$(readlink "$THEMEDIR/arrow.svg")"
assert_eq "a stock theme choice becomes haseen's" $'Theme=haseen\nFont="Sans 10"\nDarkTheme=haseen' "$(<"$HOME/.config/fcitx5/conf/classicui.conf")"
printf 'Theme=nord\n' >"$HOME/.config/fcitx5/conf/classicui.conf"
"$OMA/omarchy-theme-set-fcitx5" --activate
assert_eq "a theme of the user's own stays" $'Theme=nord\nDarkTheme=haseen' "$(<"$HOME/.config/fcitx5/conf/classicui.conf")"
TOG="$HOME/.local/state/haseen/toggles/hypr"
stub hyprctl 'echo "hyprctl $*" >>"'"$LOG"'"'
assert_eq "corners follow the theme by default" "theme" "$(fk omarchy-hyprland-corners)"
capture fk omarchy-hyprland-corners sharp --dry-run
assert_dry_pure "corners" "$OUTPUT"
fk omarchy-hyprland-corners sharp
assert_contains "sharp is a rounding 0 toggle" "$(<"$TOG/corners-sharp.lua")" "rounding = 0"
assert_eq "and is reported" "sharp" "$(fk omarchy-hyprland-corners)"
fk omarchy-hyprland-corners rounded
assert_eq "rounded replaces sharp" "no" "$([[ -e $TOG/corners-sharp.lua ]] && echo yes || echo no)"
assert_contains "Hyprland reloads" "$(calls)" "hyprctl reload"
fk omarchy-hyprland-corners theme
assert_eq "theme removes both" "theme" "$(fk omarchy-hyprland-corners)"
capture fk omarchy-hyprland-corners round
assert_status "an unknown choice" 1 "$STATUS"
stub hyprctl 'case "$*" in "activeworkspace -j") echo "{\"id\":2,\"tiledLayout\":\"scrolling\"}" ;; "workspaces -j") echo "[{\"id\":3,\"tiledLayout\":\"dwindle\"}]" ;; "getoption general.layout -j") echo "{\"str\":\"dwindle\"}" ;; esac'
assert_eq "the active workspace's layout" "scrolling" "$("$OMA/omarchy-hyprland-workspace-layout-current")"
assert_eq "a workspace's by id" "dwindle" "$("$OMA/omarchy-hyprland-workspace-layout-current" 3)"
assert_eq "the default layout is Hyprland's" "dwindle" "$("$OMA/omarchy-hyprland-workspace-layout-default")"
capture "$OMA/omarchy-hyprland-workspace-layout-default" dwindle
assert_status "the default it already is succeeds" 0 "$STATUS"
capture "$OMA/omarchy-hyprland-workspace-layout-default" scrolling
assert_status "another default is refused" 1 "$STATUS"
assert_contains "with the per-workspace way" "$OUTPUT" "The haseen way: haseen toggle workspace-layout scrolling"
capture "$OMA/omarchy-hyprland-workspace-layout-default" floating
assert_status "floating is refused" 1 "$STATUS"
assert_eq "windows are opaque" "opaque" "$("$OMA/omarchy-hyprland-window-transparency")"
capture "$OMA/omarchy-hyprland-window-transparency" opaque
assert_status "opaque is accepted" 0 "$STATUS"
capture "$OMA/omarchy-hyprland-window-transparency" glassy
assert_status "glassy is refused (blur)" 1 "$STATUS"
assert_contains "and says why" "$OUTPUT" "never uses blur"
capture "$OMA/omarchy-theme-bg-intro" status
assert_status "intros are off" 1 "$STATUS"
capture "$OMA/omarchy-theme-bg-intro" disable
assert_status "disabling them succeeds" 0 "$STATUS"
capture "$OMA/omarchy-theme-bg-intro" enable
assert_status "enabling them is refused" 1 "$STATUS"
# Theme sync to herdr machines: off by default, the flag in haseen's store.
stub herdr 'printf "1\tbox\tbox.example\tw\tenabled\n2\told\told.example\tw\tdisabled\n"'
printf '#!/bin/sh\necho nord\n' >"$FAKE/bin/haseen-theme-current"
stub ssh 'echo "STUB-CALLED: ssh $*" >&2; exit 97'
capture fk omarchy-theme-set-herdr-machines --available
assert_status "a herdr machine to sync to" 0 "$STATUS"
capture fk omarchy-theme-set-herdr-machines
assert_eq "sync off: nothing is sent" "" "$OUTPUT"
fk omarchy-toggle-theme-sync >/dev/null
assert_eq "the toggle sets haseen's flag" "yes" "$([[ -e $HOME/.local/state/haseen/toggles/omarchy/herdr-theme-sync ]] && echo yes || echo no)"
capture fk omarchy-theme-set-herdr-machines --dry-run
assert_dry_pure "herdr sync" "$OUTPUT"
assert_eq "on: the theme goes to each enabled machine" "DRYRUN: ssh box.example: omarchy theme set nord" "$OUTPUT"
fk omarchy-toggle-theme-sync >/dev/null
assert_eq "and toggles back off" "no" "$([[ -e $HOME/.local/state/haseen/toggles/omarchy/herdr-theme-sync ]] && echo yes || echo no)"

# --- installers and removers --------------------------------------------------------------
box omarchy45-install
capture fk omarchy-install-service-microsoft --dry-run
assert_eq "six web apps through haseen webapp install" 6 "$(grep -c '^haseen-webapp-install ' "$LOG")"
assert_contains "Outlook among them" "$(calls)" "haseen-webapp-install [Microsoft Outlook] [https://outlook.office.com/mail/] [https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/microsoft-outlook.png] [--dry-run]"
: >"$LOG"
capture fk omarchy-install-ai-claude --dry-run
assert_contains "Claude desktop through the repository order" "$(calls)" "haseen-install [aur] [claude-desktop] [--dry-run]"
assert_dry_pure "install-ai-claude" "$OUTPUT"
: >"$LOG"
capture fk omarchy-install-t3code-app stable --dry-run
assert_eq "T3 Code stable is haseen's catalogue entry" "haseen-install [app] [t3-code] [--dry-run]" "$(calls)"
capture fk omarchy-install-t3code-app nightly
assert_status "the nightly AppImage is refused" 1 "$STATUS"
mkdir -p "$ROOT/usr/share/chromium/extensions"
capture "$OMA/omarchy-install-chromium-claude" --dry-run
assert_dry_pure "install-chromium-claude" "$OUTPUT"
assert_eq "one extension file per browser, as root" 3 "$(grep -c '^DRYRUN: write /usr/share/.*/extensions/fcoeoabgfenejglbffodgkkbkcdhcgfn.json (mode 0644):' <<<"$OUTPUT")"
for d in chromium google-chrome microsoft-edge; do
    mkdir -p "$ROOT/usr/share/$d/extensions"
    echo '{ "external_update_url": "https://clients2.google.com/service/update2/crx" }' >"$ROOT/usr/share/$d/extensions/fcoeoabgfenejglbffodgkkbkcdhcgfn.json"
done
capture "$OMA/omarchy-install-chromium-claude" --dry-run
assert_eq "already in place: nothing" "" "$OUTPUT"
: >"$LOG"
stub fcitx5-configtool 'exit 0'
capture fk omarchy-setup-input mozc --dry-run
assert_contains "an input method's engine through haseen install" "$(calls)" "haseen-install [package] [fcitx5-mozc] [--dry-run]"
assert_contains "then fcitx5's tool opens" "$OUTPUT" "DRYRUN: setsid -f fcitx5-configtool"
capture fk omarchy-setup-input klingon
assert_status "an unknown method" 1 "$STATUS"
capture fk omarchy-setup-keyboard --dry-run
assert_contains "keyboard layouts are fcitx5's" "$OUTPUT" "DRYRUN: setsid -f fcitx5-configtool"
rec fcitx5-remote
"$OMA/omarchy-input-method" cycle back
assert_eq "cycling switches fcitx5 between its two" "fcitx5-remote [-t]" "$(grep fcitx5-remote "$LOG")"
capture "$OMA/omarchy-input-method" configure --seed
assert_status "configure rewrites fcitx5 and is refused" 1 "$STATUS"
assert_eq "no CJK forms chosen" "default" "$("$OMA/omarchy-font-cjk")"
mkdir -p "$HOME/.config/fontconfig/conf.d"
echo '<match><edit><string><family>Noto Sans CJK JP</family></string></edit></match>' >"$HOME/.config/fontconfig/conf.d/50-omarchy-input-method.conf"
assert_eq "Omarchy's choice is read" "jp" "$("$OMA/omarchy-font-cjk")"
capture "$OMA/omarchy-font-cjk" kr
assert_status "choosing is refused" 1 "$STATUS"

box omarchy45-remove
mkdir -p "$HOME/.config/Claude" "$HOME/.cache/Claude" "$HOME/.claude"
mkdir -p "$ROOT/var/lib/pacman/local/claude-desktop-1.0-1"
printf '%%NAME%%\nclaude-desktop\n' >"$ROOT/var/lib/pacman/local/claude-desktop-1.0-1/desc"
capture fk omarchy-remove-ai-claude --dry-run
assert_dry_pure "remove-ai-claude" "$OUTPUT"
assert_contains "the app is stopped first" "$OUTPUT" "DRYRUN: pkill -x claude-desktop"
assert_contains "the package goes through haseen remove" "$(calls)" "haseen-remove [package] [claude-desktop]"
assert_contains "its data is asked about" "$OUTPUT" "DRYRUN: ask 'Also delete its settings and caches"
assert_not_contains "never Claude Code's" "$OUTPUT" "$HOME/.claude "
: >"$LOG"
stub pkill 'exit 0'
capture fk omarchy-remove-ai-claude --yes </dev/null
assert_eq "--yes removes the package and keeps the data" "yes" "$([[ -d $HOME/.config/Claude ]] && echo yes || echo no)"
capture fk omarchy-remove-ai-claude --purge --yes </dev/null
assert_eq "--purge deletes it" "no" "$([[ -d $HOME/.config/Claude || -d $HOME/.cache/Claude ]] && echo yes || echo no)"
assert_eq "and leaves Claude Code's" "yes" "$([[ -d $HOME/.claude ]] && echo yes || echo no)"
: >"$LOG"
mkdir -p "$HOME/.ollama"
capture fk omarchy-remove-ai-ollama --dry-run
assert_dry_pure "remove-ai-ollama" "$OUTPUT"
assert_contains "the service is stopped as root" "$OUTPUT" "DRYRUN: sudo systemctl disable --now ollama.service"
mkdir -p "$HOME/my-models"
echo "$HOME/my-models" >"$HOME/.lmstudio-home-pointer"
capture fk omarchy-remove-ai-lm-studio --dry-run
assert_contains "LM Studio's relocated models are asked about too" "$OUTPUT" "$HOME/my-models"
mkdir -p "$HOME/.config/uwsm/env.d" "$HOME/.config/environment.d"
: >"$HOME/.config/uwsm/env.d/61-haseen-ssh-agent"
: >"$HOME/.config/environment.d/90-gcr-ssh-agent.conf"
stub systemctl 'case "$*" in "--user show-environment") echo "SSH_AUTH_SOCK=$XDG_RUNTIME_DIR/gcr/ssh" ;; *) echo "systemctl $*" >>"'"$LOG"'" ;; esac'
capture "$OMA/omarchy-remove-service-ssh-agent"
assert_eq "haseen's and Omarchy's exports go" "no no" \
    "$([[ -e $HOME/.config/uwsm/env.d/61-haseen-ssh-agent ]] && echo yes || echo no) $([[ -e $HOME/.config/environment.d/90-gcr-ssh-agent.conf ]] && echo yes || echo no)"
assert_contains "the socket is disabled" "$(calls)" "systemctl --user disable --now gcr-ssh-agent.socket"
assert_contains "and the manager forgets the socket path" "$(calls)" "systemctl --user unset-environment SSH_AUTH_SOCK"
: >"$LOG"
mkdir -p "$HOME/.local/share/applications"
printf '[Desktop Entry]\nExec=helium --app=https://word.cloud.microsoft/\n' >"$HOME/.local/share/applications/Microsoft Word.desktop"
capture fk omarchy-remove-service-microsoft --dry-run
assert_eq "only the installed Microsoft web app is removed" "haseen-webapp-remove [--dry-run] [Microsoft Word]" "$(calls)"

box omarchy45-dictation
rec voxtype
capture "$OMA/omarchy-default-dictation"
assert_status "no backend yet" 1 "$STATUS"
capture "$OMA/omarchy-dictation-use" voxtype --dry-run
assert_contains "a dry choice writes nothing" "$OUTPUT" "DRYRUN:"
"$OMA/omarchy-dictation-use" voxtype
assert_eq "the backend lives in haseen's state" "voxtype" "$(<"$HOME/.local/state/haseen/dictation-backend")"
assert_eq "and is read back" "voxtype" "$("$OMA/omarchy-default-dictation")"
"$OMA/omarchy-dictation" toggle
assert_eq "dictation goes to Voxtype's adapter" "voxtype [record] [toggle]" "$(calls)"
capture "$OMA/omarchy-dictation" loud
assert_status "an unknown action" 1 "$STATUS"
capture "$OMA/omarchy-default-dictation" superwhisper
assert_status "Superwhisper has no installer under haseen" 1 "$STATUS"
capture "$OMA/omarchy-install-dictation-superwhisper"
assert_status "and its installer is refused" 1 "$STATUS"
# shellcheck disable=SC2088  # the message names the path as the user writes it
assert_contains "naming the plugin directory it would write" "$OUTPUT" "~/.config/omarchy/plugins"

# --- agents --------------------------------------------------------------------------------
box omarchy45-agents
# The Grok and Kimi collectors read these; the sandbox clears the agents'
# variables the older collectors read, and only this file runs the new ones.
unset GROK_HOME
for var in $(compgen -e | grep -E '^KIMI_' || true); do
    unset "$var"
done
BIN="$SANDBOX/agent-bin"
mkdir -p "$BIN"
printf '#!/bin/sh\necho "claude ${CLAUDE_CONFIG_DIR:-primary} $*"\n' >"$BIN/claude"
chmod +x "$BIN/claude"
assert_eq "no registry: the primary account" "claude primary --version" "$(PATH="$BIN:$PATH" "$OMA/omarchy-agent-account-exec" claude --version)"
assert_eq "an explicit home wins" "claude /work --version" "$(CLAUDE_CONFIG_DIR=/work PATH="$BIN:$PATH" "$OMA/omarchy-agent-account-exec" claude --version)"
assert_eq "a session's pinned home" "claude /pinned -p" "$(OMARCHY_AGENT_CLAUDE_HOME=/pinned PATH="$BIN:$PATH" "$OMA/omarchy-agent-account-exec" claude -p)"
assert_eq "home prints nothing for the primary account" "" "$("$OMA/omarchy-agent-account-home" claude)"
capture "$OMA/omarchy-agent-account-exec" nope
assert_status "an unknown agent" 1 "$STATUS"
rec mise
capture "$OMA/omarchy-agent-account-exec" grok --help-me
assert_status "a CLI that is not installed and not declared fails" 1 "$STATUS"
assert_contains "with how to install it" "$OUTPUT" "mise use -g grok"
assert_eq "and never edits the user's mise config" "" "$(calls)"
capture "$OMA/omarchy-agent-account-list"
assert_status "without Omarchy's accounts the list is refused" 1 "$STATUS"
assert_contains "and says so" "$OUTPUT" "No haseen equivalent: haseen keeps one account per agent"
mkdir -p "$ROOT/usr/share/omarchy/bin"
printf '#!/bin/sh\necho "omarchy list $*"\n' >"$ROOT/usr/share/omarchy/bin/omarchy-agent-account-list"
chmod +x "$ROOT/usr/share/omarchy/bin/omarchy-agent-account-list"
assert_eq "with Omarchy installed its own copy answers" "omarchy list claude --json" "$("$OMA/omarchy-agent-account-list" claude --json)"
assert_eq "a dry run prints the call" "DRYRUN: $ROOT/usr/share/omarchy/bin/omarchy-agent-account-list claude" \
    "$(DRY_RUN=true "$OMA/omarchy-agent-account-list" claude)"
# --dry-run is haseen's flag: it prints the call and runs nothing, and never
# reaches Omarchy's copy, which takes none (plan 102).
ran="$SANDBOX/omarchy-copy-ran"
printf '#!/bin/sh\necho "$*" >>"%s"\nexit 97\n' "$ran" >"$ROOT/usr/share/omarchy/bin/omarchy-agent-account-remove"
chmod +x "$ROOT/usr/share/omarchy/bin/omarchy-agent-account-remove"
capture "$OMA/omarchy-agent-account-remove" claude work --dry-run
assert_status "a pass-through's --dry-run succeeds" 0 "$STATUS"
assert_eq "and prints the call without the flag" "DRYRUN: $ROOT/usr/share/omarchy/bin/omarchy-agent-account-remove claude work" "$OUTPUT"
assert_eq "Omarchy's command never runs" "no" "$([[ -e $ran ]] && echo yes || echo no)"
assert_eq "after --, --dry-run is the command's own" "omarchy list -- --dry-run" "$("$OMA/omarchy-agent-account-list" -- --dry-run)"
ln -s "$OMA/omarchy-agent-account-use" "$ROOT/usr/share/omarchy/bin/omarchy-agent-account-use"
capture "$OMA/omarchy-agent-account-use" claude next
assert_status "haseen's own copy is never taken for Omarchy's" 1 "$STATUS"
stub ssh 'echo "STUB-CALLED: ssh $*" >&2; exit 97'
for n in omarchy-agent-account-copy omarchy-agent-account-transfer; do
    capture "$OMA/$n" host.example claude
    assert_status "$n is refused" 1 "$STATUS"
    assert_dry_pure "$n never reaches SSH" "$OUTPUT"
done
capture "$OMA/omarchy-agent-usage-grok" --help
assert_status "the Grok collector takes --help" 0 "$STATUS"
capture env KIMI_USAGE_URL=http://127.0.0.1:9/usages "$OMA/omarchy-agent-usage-kimi"
assert_eq "with no Kimi sign-in the record still prints as JSON" "kimi" "$(jq -r .id <<<"$OUTPUT" 2>/dev/null)"
capture "$OMA/omarchy-agent-usage-grok"
assert_eq "and the Grok record" "grok" "$(jq -r .id <<<"$OUTPUT" 2>/dev/null)"
assert_eq "the collectors' caches are haseen's" "no" "$([[ -e $HOME/.cache/omarchy ]] && echo yes || echo no)"

# --- the three answers a 4.5 caller broke ----------------------------------------------
box omarchy45-callers
rec foot
rec setsid
mkdir -p "$ROOT/proc/321/task/321" "$ROOT/proc/654" "$ROOT/etc" "$SANDBOX/work"
echo "600 654" >"$ROOT/proc/321/task/321/children"
ln -s "$SANDBOX/work" "$ROOT/proc/654/cwd"
ln -s "$(readlink -f /bin/bash)" "$ROOT/proc/654/exe"
readlink -f /bin/bash >"$ROOT/etc/shells"
stub hyprctl 'exit 1'
assert_eq "cwd of the terminal whose pid is given, newest child" "$(readlink -f "$SANDBOX/work")" "$("$OMA/omarchy-cmd-terminal-cwd" 321)"
"$OMA/omarchy-launch-terminal" --pid=321
assert_eq "SUPER + RETURN's --pid picks the directory and never reaches the terminal" \
    "setsid [foot] [--working-directory=$(readlink -f "$SANDBOX/work")]" "$(calls)"
: >"$LOG"
"$OMA/omarchy-launch-terminal" --pid=321 htop
assert_eq "a command after it still runs" "setsid [foot] [--working-directory=$(readlink -f "$SANDBOX/work")] [-e] [htop]" "$(calls)"
: >"$LOG"
fk omarchy-hyprland-workspace-layout-toggle back
assert_eq "SUPER + ALT + L's back is the same step" "haseen-toggle-workspace-layout [toggle]" "$(calls)"
: >"$LOG"
fk omarchy-hyprland-workspace-layout-toggle --dry-run
assert_eq "a plain toggle" "haseen-toggle-workspace-layout [toggle] [--dry-run]" "$(calls)"
: >"$LOG"
fk omarchy-menu-select Format jpg png -- --width 400
assert_eq "a pick passes through with its width" "haseen-menu-select [Format] [jpg] [png] [--width] [400]" "$(calls)"
: >"$LOG"
capture fk omarchy-menu-select Inputs a b -- --multiple --width 620 --selected a --on-change '["x"]' --change-key k
assert_status "multiple selection exits 2, as typing_setup expects of a menu that cannot open" 2 "$STATUS"
assert_contains "and says so" "$OUTPUT" "--multiple is not available under haseen"
assert_eq "and never shows the flags as options" "" "$(calls)"
capture fk omarchy-menu-select Inputs a -- --bogus
assert_status "an unknown menu flag" 2 "$STATUS"

# --- the splash and an mkinitcpio configuration that does not evaluate ----------
# omarchy-plymouth-set reads whether the plymouth hook is missing from HOOKS,
# so a configuration that does not source (Omarchy 4.5's drop-in returns 1
# when its detector cannot place the machine) stops it before it writes,
# instead of reading as "missing" and adding a second drop-in (plan 101's
# boot_hooks_known, plan 102).
box omarchy45-plymouth
cp -a "$FIXTURES/mkinitcpio-omarchy-4.5/." "$ROOT/"
mkdir -p "$ROOT/usr/bin" "$ROOT/proc" "$ROOT/etc/plymouth"
printf '#!/bin/sh\nexit 0\n' >"$ROOT/usr/bin/plymouth-set-default-theme"
chmod +x "$ROOT/usr/bin/plymouth-set-default-theme"
printf 'BOOT_IMAGE=/vmlinuz-linux root=/dev/mapper/root rw quiet splash\n' >"$ROOT/proc/cmdline"
logo="$SANDBOX/logo.png"
: >"$logo"
stub omarchy-hw-platform 'echo x86'
capture "$OMA/omarchy-plymouth-set" 1a1b26 c0caf5 "$logo" --dry-run
assert_status "Omarchy 4.5's layout, placed: the splash is planned" 0 "$STATUS"
assert_dry_pure "omarchy-plymouth-set" "$OUTPUT"
assert_not_contains "its HOOKS already hold plymouth: no second drop-in" "$OUTPUT" "haseen-plymouth.conf"
stub omarchy-hw-platform 'exit 1'
capture "$OMA/omarchy-plymouth-set" 1a1b26 c0caf5 "$logo" --dry-run
assert_status "a configuration that does not evaluate stops it" 1 "$STATUS"
assert_contains "and says what to fix" "$OUTPUT" "fix mkinitcpio's configuration first"
assert_not_contains "before any drop-in is planned" "$OUTPUT" "haseen-plymouth.conf"
assert_not_contains "or anything written" "$OUTPUT" "DRYRUN:"

# --- session, update and router ------------------------------------------------------------
box omarchy45-system
capture fk omarchy-system reboot --execute --dry-run
assert_contains "Omarchy 4.5's system reboot reaches haseen system reboot" "$OUTPUT" "/haseen-system reboot"
: >"$LOG"
fk omarchy-system logout --inhibited >/dev/null
assert_eq "logout, its internal phase dropped" "haseen-system [logout]" "$(calls)"
capture fk omarchy-system hibernate
assert_status "only Omarchy's three verbs" 2 "$STATUS"
mkdir -p "$ROOT/run/systemd/system"
capture fk omarchy-update-pacman -Syu --noconfirm --dry-run
assert_dry_pure "update-pacman" "$OUTPUT"
assert_eq "an upgrade runs as root in a PID 1 scope" "DRYRUN: sudo env HASEEN_UPDATE_PACMAN=1 systemd-run --scope --quiet --collect pacman -Syu --noconfirm" "$OUTPUT"
capture env LC_ALL=C HASEEN_PATH="$FAKE/share/haseen" "$OMA/omarchy-update-pacman" -Su --dry-run
assert_contains "LC_ALL passes through" "$OUTPUT" "LC_ALL=C systemd-run"
for args in "-S foo" "-Syu --overwrite *" "-Rns foo" ""; do
    # shellcheck disable=SC2086  # each case is a word list
    capture fk omarchy-update-pacman $args --dry-run
    assert_status "pacman $args is refused" 1 "$STATUS"
done
assert_dry_pure "refused transactions" "$OUTPUT"
: >"$LOG"
printf '#!/bin/sh\necho "{\\"hidden\\":false}"\n' >"$FAKE/bin/haseen-shell-ipc"
chmod +x "$FAKE/bin/haseen-shell-ipc"
fk omarchy-toggle-fullscreen-desktop --dry-run >/dev/null
assert_contains "neither half on: the bar hides" "$(calls)" "haseen-toggle-bar [--dry-run]"
assert_contains "and the gaps go" "$(calls)" "haseen-toggle-gaps [on] [--dry-run]"
capture fk omarchy-toggle-fullscreen-desktop sideways
assert_status "an unknown action" 1 "$STATUS"
FAKE_OMA() { env HASEEN_PATH="$FAKE/share/haseen" "$OMA/omarchy" "$@"; }
: >"$LOG"
FAKE_OMA up -y >/dev/null
assert_eq "omarchy up is omarchy update" "haseen-update [-y]" "$(calls)"
capture FAKE_OMA agent account
assert_status "omarchy agent account lists the group" 0 "$STATUS"
assert_contains "of account commands" "$OUTPUT" "omarchy-agent-account-use"
assert_not_contains "instead of running omarchy-agent with 'account'" "$OUTPUT" "Unexpected argument"
: >"$LOG"
FAKE_OMA hyprland workspace layout toggle back >/dev/null
assert_eq "a longer command still takes its argument" "haseen-toggle-workspace-layout [toggle]" "$(calls)"
capture FAKE_OMA update aur
assert_contains "a word after a flags-only command names its group" "$OUTPUT" "omarchy-update-aur-pkgs"
capture FAKE_OMA system lid
assert_status "a command that takes words still takes one that starts a group" 2 "$STATUS"
assert_contains "so omarchy-system answers it" "$OUTPUT" "Usage: omarchy-system"
