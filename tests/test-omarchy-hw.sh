# shellcheck shell=bash
# haseen:covers bin/haseen-{font-list,font-set,hardware-laptop-display,hardware-mirror-display,hook}
# haseen:covers bin/haseen-{layer-apply,menu-select,notification-send,shell-ipc,system}
# haseen:covers bin/haseen-{theme-current,theme-list,theme-set,toggle-gaps,toggle-one-window-ratio}
# haseen:covers bin/haseen-hibernation-* share/haseen/layers/base/lib.sh
# haseen:covers share/haseen/layers/theme/theme-lib.sh
# haseen:covers share/haseen/lib/{boot,catalog,hardware,hibernate,layers,ledger,packages}.sh
# haseen:covers share/haseen/lib/{preflight,screen,shellrc,terminal}.sh
# haseen:covers share/haseen/omarchy/bin/omarchy-games-* share/haseen/omarchy/bin/omarchy-hw-*
# haseen:covers share/haseen/omarchy/bin/omarchy-hyprland-*
# haseen:covers share/haseen/omarchy/bin/omarchy-{capture-webcam-list,file-select,font-current}
# haseen:covers share/haseen/omarchy/bin/omarchy-{git-url-check,hibernation-remove}
# haseen:covers share/haseen/omarchy/bin/omarchy-{hibernation-setup,hook,hook-install,menu-file}
# haseen:covers share/haseen/omarchy/lib.sh bin/haseen-hw-match share/haseen/hardware/quirks.tsv
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# haseen's answers to Omarchy's hardware predicates (omarchy-hw-*), Hyprland
# commands (omarchy-hyprland-*), hibernation, hook, font, file chooser, git
# URL and retro-game commands (plan 093, g2). Hardware is read from fixture
# trees through HASEEN_SYSROOT; Hyprland is a hyprctl that answers queries
# from fixture JSON and records everything else.

OMA="$HASEEN_PATH/omarchy/bin"

MINE=(omarchy-file-select omarchy-font-current omarchy-games-retro-cores omarchy-games-retro-install
    omarchy-git-url-check omarchy-hibernation-remove omarchy-hibernation-setup omarchy-hook
    omarchy-hook-install omarchy-hw-asus-expertbook-b9406 omarchy-hw-asus-rog
    omarchy-hw-asus-zenbook-ux5406aa omarchy-hw-clamshell omarchy-hw-dell-xps-haptic-touchpad
    omarchy-hw-dell-xps-oled omarchy-hw-dell-xps13-dx13260-ptl omarchy-hw-display
    omarchy-hw-external-monitors omarchy-hw-fingerprint omarchy-hw-framework16 omarchy-hw-hybrid-gpu
    omarchy-hw-intel omarchy-hw-intel-ptl omarchy-hw-intel-sof omarchy-hw-laptop
    omarchy-hw-laptop-closed omarchy-hw-nvidia omarchy-hw-nvidia-display omarchy-hw-nvidia-gsp
    omarchy-hw-nvidia-without-gsp omarchy-hw-recover-internal-monitor omarchy-hw-surface
    omarchy-hw-touchpad omarchy-hw-touchscreen omarchy-hw-vulkan omarchy-hw-webcam
    omarchy-hyprland-focus-app omarchy-hyprland-monitor-clamshell
    omarchy-hyprland-monitor-external-active omarchy-hyprland-monitor-focused
    omarchy-hyprland-monitor-internal omarchy-hyprland-monitor-internal-mirror
    omarchy-hyprland-monitor-laptop omarchy-hyprland-monitor-modeless omarchy-hyprland-monitor-scaling
    omarchy-hyprland-monitor-watch omarchy-hyprland-reload-guard omarchy-hyprland-session-lock-stranded
    omarchy-hyprland-session-locked omarchy-hyprland-toggle omarchy-hyprland-toggle-disabled
    omarchy-hyprland-toggle-enabled omarchy-hyprland-window-close-all omarchy-hyprland-window-pop
    omarchy-hyprland-window-tiled-fullscreen-toggle omarchy-hyprland-window-transparency-toggle
    omarchy-hyprland-window-width)

# box NAME — a sandbox whose system files are the fixture tree ROOT
# (HASEEN_SYSROOT), so no predicate reads this machine. The live probes the
# commands use answer from files under $SANDBOX instead: lspci (lspci.txt),
# pgrep (pgrep.txt), fc-match (fc-match.txt), v4l2-ctl (v4l2.txt, where
# /dev/video0 alone can capture). supergfxctl must never run on a fixture.
box() {
    sandbox "$1"
    ROOT="$SANDBOX/root"
    mkdir -p "$ROOT" "$SANDBOX/hypr"
    export HASEEN_SYSROOT="$ROOT"
    TOGGLES="$HOME/.local/state/haseen/toggles/hypr"
    FLAGS="$HOME/.local/state/haseen/flags"
    stub lspci "cat '$SANDBOX/lspci.txt' 2>/dev/null; exit 0"
    stub pgrep "cat '$SANDBOX/pgrep.txt' 2>/dev/null"
    stub fc-match "cat '$SANDBOX/fc-match.txt' 2>/dev/null"
    stub supergfxctl 'echo "STUB-CALLED: supergfxctl $*" >&2; exit 97'
    stub v4l2-ctl "case \$1 in
--list-devices) cat '$SANDBOX/v4l2.txt' 2>/dev/null ;;
--device) [ \"\$2\" = /dev/video0 ] && printf 'Driver Info:\n\tDevice Caps      : 0x04200001\n\t\tVideo Capture\n' ;;
esac
exit 0"
    # hyprctl answers its queries from $SANDBOX/hypr/<name>.json (no file:
    # exit 1, as when Hyprland does not answer) and getoption with false. Any
    # other call is a change: logged to hypr.log and marked STUB-CALLED, so a
    # dry run that reaches it fails its purity check.
    stub hyprctl "d='$SANDBOX/hypr'
args=\"\$*\"
case \"\$args\" in --instance\\ *) set -- \$args; shift 2; args=\"\$*\" ;; esac
answer() { [ -f \"\$d/\$1.json\" ] || exit 1; cat \"\$d/\$1.json\"; exit 0; }
case \"\$args\" in
'status -j') answer status ;;
'monitors -j' | '-j monitors' | 'monitors all -j') answer monitors ;;
'clients -j') answer clients ;;
'activewindow -j') answer active ;;
'devices -j') answer devices ;;
'-j getoption '*) echo '{\"bool\": false}'; exit 0 ;;
esac
echo \"hyprctl \$args\" >>'$SANDBOX/hypr.log'
echo \"STUB-CALLED: hyprctl \$args\" >&2
exit 0"
}

# hj NAME JSON — what hyprctl answers for NAME (status, monitors, clients,
# active, devices).
hj() { printf '%s\n' "$2" >"$SANDBOX/hypr/$1.json"; }
hlog() { cat "$SANDBOX/hypr.log" 2>/dev/null; }

dmi() {
    mkdir -p "$ROOT/sys/class/dmi/id"
    printf '%s\n' "$2" >"$ROOT/sys/class/dmi/id/$1"
}

# pci SLOT VENDOR CLASS [DEVICE [BOOT_VGA]] — a PCI device in the fixture.
pci() {
    local d="$ROOT/sys/bus/pci/devices/$1"
    mkdir -p "$d"
    echo "$2" >"$d/vendor"
    echo "$3" >"$d/class"
    echo "${4:-0x0000}" >"$d/device"
    [[ -z ${5:-} ]] || echo "$5" >"$d/boot_vga"
}

# is LABEL EXPECTED NAME [ARGS...] — NAME exits EXPECTED and runs nothing stubbed.
is() {
    local label=$1 want=$2
    shift 2
    capture "$OMA/$1" "${@:2}"
    if [[ $STATUS == "$want" && $OUTPUT != *STUB-CALLED* ]]; then
        _pass
    else
        _fail "$label" "exit $STATUS (want $want): ${OUTPUT:0:600}"
    fi
}

# fake_bin NAME... — a tree whose bin/ holds recorders for these haseen
# commands (they log "name [arg]..." to fake.log); `fake` runs a script with
# HASEEN_PATH pointing at it.
fake_bin() {
    FAKE="$SANDBOX/fake"
    mkdir -p "$FAKE/bin" "$FAKE/share/haseen"
    [[ -e $FAKE/share/haseen/lib ]] || ln -s "$HASEEN_PATH/lib" "$FAKE/share/haseen/lib"
    [[ -e $FAKE/share/haseen/omarchy ]] || ln -s "$HASEEN_PATH/omarchy" "$FAKE/share/haseen/omarchy"
    local t
    for t in "$@"; do
        printf '#!/bin/sh\nprintf %%s "${0##*/}" >>"%s"; for a in "$@"; do printf " [%%s]" "$a" >>"%s"; done; echo >>"%s"\n' \
            "$SANDBOX/fake.log" "$SANDBOX/fake.log" "$SANDBOX/fake.log" >"$FAKE/bin/$t"
        chmod +x "$FAKE/bin/$t"
    done
}
fake() { env HASEEN_PATH="$FAKE/share/haseen" "$OMA/$1" "${@:2}"; }
flog() { cat "$SANDBOX/fake.log" 2>/dev/null; }

# --- every script: help, notice ---------------------------------------------------
box omarchy-g2-help
bad="" notice=""
for name in "${MINE[@]}"; do
    capture "$OMA/$name" --help
    [[ $STATUS == 0 && $OUTPUT == *Usage* && $OUTPUT != *STUB-CALLED* ]] || bad+="$name($STATUS) "
    [[ -x $OMA/$name && ! -L $OMA/$name ]] || bad+="$name(not a script) "
    tr -s ' \n#' ' ' <"$OMA/$name" | grep -q 'MIT, Copyright (c) David Heinemeier Hansson' || notice+="$name "
done
assert_eq "every g2 script answers --help and runs nothing" "" "$bad"
assert_eq "every g2 script names Omarchy's MIT notice" "" "$notice"

# --- DMI models -------------------------------------------------------------------
box omarchy-hw-dmi
dmi sys_vendor "ASUSTeK COMPUTER INC."
dmi product_family "ROG Zephyrus G14"
dmi product_name "ROG Zephyrus G14 GA403UV"
is "asus-rog on an ASUS ROG" 0 omarchy-hw-asus-rog
is "framework16 on an ASUS" 1 omarchy-hw-framework16
is "surface on an ASUS" 1 omarchy-hw-surface
dmi product_family "Vivobook"
dmi product_name "Vivobook S 16"
is "asus-rog on another ASUS" 1 omarchy-hw-asus-rog
dmi sys_vendor Framework
dmi product_family Laptop
dmi product_name "Laptop 16 (AMD Ryzen 7040 Series)"
is "framework16 on a Laptop 16" 0 omarchy-hw-framework16
dmi product_name "Laptop 13 (AMD Ryzen 7040Series)"
is "framework16 on a Laptop 13" 1 omarchy-hw-framework16
dmi sys_vendor "Microsoft Corporation"
dmi product_family "Surface"
dmi product_name "Surface Laptop 5"
is "surface on a Surface" 0 omarchy-hw-surface
dmi sys_vendor "To be filled by O.E.M."
is "surface with a placeholder vendor" 1 omarchy-hw-surface

# --- Panther Lake models ---------------------------------------------------------
box omarchy-hw-ptl
ptl='00:02.0 VGA compatible controller: Intel Corporation Panther Lake [Intel Graphics] (rev 04)'
printf '00:1f.3 Multimedia audio controller: Intel Corporation Panther Lake cAVS\n' >"$SANDBOX/lspci.txt"
is "intel-ptl: a Panther Lake audio device is no GPU" 1 omarchy-hw-intel-ptl
printf '%s\n' "$ptl" >"$SANDBOX/lspci.txt"
is "intel-ptl with a Panther Lake GPU" 0 omarchy-hw-intel-ptl
for spec in "omarchy-hw-asus-expertbook-b9406|ASUS ExpertBook B9406CAA" \
    "omarchy-hw-asus-zenbook-ux5406aa|Zenbook S 14 UX5406AA" \
    "omarchy-hw-dell-xps13-dx13260-ptl|XPS 13 DX13260"; do
    name=${spec%%|*}
    dmi product_name "${spec#*|}"
    is "${name#omarchy-hw-} on its model with Panther Lake" 0 "$name"
done
dmi product_name "XPS 13 9345"
is "dx13260-ptl on another XPS" 1 omarchy-hw-dell-xps13-dx13260-ptl
dmi product_name "XPS 13 DX13260"
printf '00:02.0 VGA compatible controller: Intel Corporation Lunar Lake [Intel Arc Graphics 130V / 140V]\n' >"$SANDBOX/lspci.txt"
is "intel-ptl on Lunar Lake" 1 omarchy-hw-intel-ptl
is "dx13260-ptl without Panther Lake" 1 omarchy-hw-dell-xps13-dx13260-ptl

# --- Dell XPS touchpad and panel --------------------------------------------------
box omarchy-hw-xps
dmi sys_vendor "Dell Inc."
dmi product_name "XPS 13 9350"
is "xps-haptic-touchpad without its I2C device" 1 omarchy-hw-dell-xps-haptic-touchpad
mkdir -p "$ROOT/sys/bus/i2c/devices/i2c-VEN_06CB:00"
is "xps-haptic-touchpad with it" 0 omarchy-hw-dell-xps-haptic-touchpad
dmi product_name "Latitude 7450"
is "xps-haptic-touchpad on a Latitude" 1 omarchy-hw-dell-xps-haptic-touchpad
dmi product_name "XPS 13 9350"
printf '%s\n' "$ptl" >"$SANDBOX/lspci.txt"
is "xps-oled without an eDP EDID" 1 omarchy-hw-dell-xps-oled
mkdir -p "$ROOT/sys/class/drm/card1-eDP-1"
printf '\x00\xff\xff\xff\xff\xff\xff\x00\x30\xe4\x00\x00' >"$ROOT/sys/class/drm/card1-eDP-1/edid"
is "xps-oled with an LG Display panel" 0 omarchy-hw-dell-xps-oled
printf '\x00\xff\xff\xff\xff\xff\xff\x00\x4d\x10\x00\x00' >"$ROOT/sys/class/drm/card1-eDP-1/edid"
is "xps-oled with another panel" 1 omarchy-hw-dell-xps-oled

# --- backlight ----------------------------------------------------------------------
box omarchy-hw-backlight
bl="$ROOT/sys/class/backlight"
is "hw-display without a backlight" 1 omarchy-hw-display
mkdir -p "$bl/acpi_video0" "$bl/intel_backlight"
capture "$OMA/omarchy-hw-display"
assert_eq "hw-display prefers intel_backlight to acpi_video" "intel_backlight" "$OUTPUT"
mkdir -p "$bl/amdgpu_bl1"
capture "$OMA/omarchy-hw-display"
assert_eq "hw-display prefers amdgpu_bl first" "amdgpu_bl1" "$OUTPUT"
rm -rf "${bl:?}"/*
mkdir -p "$bl/nvidia_0"
capture "$OMA/omarchy-hw-display"
assert_eq "hw-display falls back to the only device" "nvidia_0" "$OUTPUT"

# --- connectors, lid, laptop, clamshell ---------------------------------------------
box omarchy-hw-lid
drm="$ROOT/sys/class/drm"
mkdir -p "$drm/card1-eDP-1" "$drm/card1-HDMI-A-1" "$drm/card1-DP-1"
echo connected >"$drm/card1-eDP-1/status"
echo disconnected >"$drm/card1-HDMI-A-1/status"
echo disconnected >"$drm/card1-DP-1/status"
is "external-monitors: the laptop panel does not count" 1 omarchy-hw-external-monitors
is "laptop: no lid and no chassis" 1 omarchy-hw-laptop
dmi chassis_type 10
is "laptop: a notebook chassis" 0 omarchy-hw-laptop
dmi chassis_type 3
is "laptop: a desktop chassis" 1 omarchy-hw-laptop
lid="$ROOT/proc/acpi/button/lid/LID0"
mkdir -p "$lid"
echo "state:      open" >"$lid/state"
is "laptop: an ACPI lid" 0 omarchy-hw-laptop
is "laptop-closed: the lid is open" 1 omarchy-hw-laptop-closed
is "clamshell: the lid is open" 1 omarchy-hw-clamshell
echo "state:      closed" >"$lid/state"
is "laptop-closed: the lid is closed" 0 omarchy-hw-laptop-closed
is "clamshell: closed with no external monitor" 1 omarchy-hw-clamshell
echo connected >"$drm/card1-HDMI-A-1/status"
is "external-monitors: HDMI connected" 0 omarchy-hw-external-monitors
is "clamshell: closed with HDMI connected" 0 omarchy-hw-clamshell

# --- fingerprint readers --------------------------------------------------------------
box omarchy-hw-fingerprint
usb="$ROOT/sys/bus/usb/devices"
mkdir -p "$usb/1-1" "$usb/1-2/1-2:1.0" "$ROOT/sys/bus/usb/drivers/btusb"
echo 046d >"$usb/1-1/idVendor"
echo "USB Receiver" >"$usb/1-1/product"
is "fingerprint: a receiver is no reader" 1 omarchy-hw-fingerprint
echo 06cb >"$usb/1-2/idVendor"
ln -s "$ROOT/sys/bus/usb/drivers/btusb" "$usb/1-2/1-2:1.0/driver"
is "fingerprint: a reader vendor's device a kernel driver owns is not a reader" 1 omarchy-hw-fingerprint
rm "$usb/1-2/1-2:1.0/driver"
is "fingerprint: a reader vendor's device with no kernel driver" 0 omarchy-hw-fingerprint
rm -rf "$usb/1-2"
mkdir -p "$usb/3-4"
echo "ELAN:ARM-M4" >"$usb/3-4/product"
is "fingerprint: a reader named by its product string" 0 omarchy-hw-fingerprint

# --- GPUs, CPU, audio DSP, Vulkan ---------------------------------------------------------
box omarchy-hw-gpu
is "nvidia: no GPU" 1 omarchy-hw-nvidia
is "nvidia-display: nothing claims boot_vga" 0 omarchy-hw-nvidia-display
pci 0000:00:02.0 0x8086 0x030000 0x7d51 1
is "hybrid-gpu: one display GPU (and no supergfxctl on a fixture)" 1 omarchy-hw-hybrid-gpu
is "nvidia-display: only Intel" 1 omarchy-hw-nvidia-display
pci 0000:01:00.0 0x10de 0x030200 0x2684 0
is "nvidia: an NVIDIA GPU" 0 omarchy-hw-nvidia
is "hybrid-gpu: two display GPUs" 0 omarchy-hw-hybrid-gpu
is "nvidia-gsp: Ada has GSP firmware" 0 omarchy-hw-nvidia-gsp
is "nvidia-without-gsp: Ada" 1 omarchy-hw-nvidia-without-gsp
is "nvidia-display: Intel drives the display" 1 omarchy-hw-nvidia-display
echo 1 >"$ROOT/sys/bus/pci/devices/0000:01:00.0/boot_vga"
echo 0 >"$ROOT/sys/bus/pci/devices/0000:00:02.0/boot_vga"
is "nvidia-display: NVIDIA drives the display" 0 omarchy-hw-nvidia-display
echo 0x1b80 >"$ROOT/sys/bus/pci/devices/0000:01:00.0/device"
is "nvidia-gsp: Pascal has none" 1 omarchy-hw-nvidia-gsp
is "nvidia-without-gsp: Pascal" 0 omarchy-hw-nvidia-without-gsp
is "intel-sof: no audio DSP" 1 omarchy-hw-intel-sof
pci 0000:00:1f.3 0x8086 0x040380 0xe428
is "intel-sof: an Intel audio DSP" 0 omarchy-hw-intel-sof
mkdir -p "$ROOT/proc"
printf 'processor\t: 0\nvendor_id\t: AuthenticAMD\n' >"$ROOT/proc/cpuinfo"
is "intel: an AMD CPU" 1 omarchy-hw-intel
printf 'processor\t: 0\nvendor_id\t: GenuineIntel\n' >"$ROOT/proc/cpuinfo"
is "intel: an Intel CPU" 0 omarchy-hw-intel
mkdir -p "$ROOT/usr/share/vulkan/icd.d"
is "vulkan: no ICD" 1 omarchy-hw-vulkan
touch "$ROOT/usr/share/vulkan/icd.d/intel_icd.x86_64.json"
is "vulkan: an ICD manifest" 0 omarchy-hw-vulkan

# --- webcam, touchpad, touchscreen ---------------------------------------------------
box omarchy-hw-input
is "webcam: v4l2-ctl lists nothing" 1 omarchy-hw-webcam
printf 'Virtual: loopback (platform:v4l2loopback-000):\n\t/dev/video2\n' >"$SANDBOX/v4l2.txt"
is "webcam: a device that cannot capture" 1 omarchy-hw-webcam
printf 'Integrated Camera: Integrated C (usb-0000:00:14.0-8):\n\t/dev/video0\n\t/dev/video1\n\t/dev/media0\n' >"$SANDBOX/v4l2.txt"
is "webcam: a capture-capable camera" 0 omarchy-hw-webcam
is "touchpad: Hyprland does not answer" 1 omarchy-hw-touchpad
hj devices '{"mice":[{"name":"logitech-usb-receiver"},{"name":"elan0676:00-04f3:3195-touchpad"}],"touch":[],"tablets":[]}'
capture "$OMA/omarchy-hw-touchpad"
assert_eq "touchpad: the touchpad among the mice" "elan0676:00-04f3:3195-touchpad" "$OUTPUT"
is "touchscreen: none" 1 omarchy-hw-touchscreen
hj devices '{"mice":[{"name":"logitech-usb-receiver"}],"touch":[{"name":"elan9008:00-04f3:2c82"}],"tablets":[]}'
capture "$OMA/omarchy-hw-touchscreen"
assert_eq "touchscreen: the touch device" "elan9008:00-04f3:2c82" "$OUTPUT"
is "touchpad: none" 1 omarchy-hw-touchpad

# --- recover-internal-monitor ----------------------------------------------------------
box omarchy-hw-recover
mkdir -p "$TOGGLES" "$FLAGS" "$ROOT/sys/class/drm/card1-HDMI-A-1"
touch "$TOGGLES/laptop-display-off.lua" "$FLAGS/clamshell-display-off"
echo connected >"$ROOT/sys/class/drm/card1-HDMI-A-1/status"
capture "$OMA/omarchy-hw-recover-internal-monitor" --dry-run
assert_eq "recover-internal-monitor: an external monitor keeps the panel off" "" "$OUTPUT"
echo disconnected >"$ROOT/sys/class/drm/card1-HDMI-A-1/status"
capture "$OMA/omarchy-hw-recover-internal-monitor" --dry-run
assert_dry_pure "recover-internal-monitor" "$OUTPUT"
assert_contains "recover-internal-monitor: the dry run plans the panel's return" "$OUTPUT" \
    "DRYRUN: rm -f $TOGGLES/laptop-display-off.lua $FLAGS/clamshell-display-off"
[[ -f $TOGGLES/laptop-display-off.lua ]] && _pass || _fail "recover-internal-monitor: the dry run removed the toggle"
capture "$OMA/omarchy-hw-recover-internal-monitor"
[[ ! -e $TOGGLES/laptop-display-off.lua && ! -e $FLAGS/clamshell-display-off ]] && _pass ||
    _fail "recover-internal-monitor: alone, the panel comes back at the next start"

# --- Hyprland queries ---------------------------------------------------------------------
box omarchy-hyprland-query
both='[{"name":"eDP-1","focused":false,"disabled":false,"width":2880,"height":1800,"solitaryBlockedBy":["WINDOWED"]},
       {"name":"HDMI-A-1","focused":true,"disabled":false,"width":2560,"height":1440,"solitaryBlockedBy":[]}]'
is "modeless: Hyprland does not answer" 2 omarchy-hyprland-monitor-modeless
is "session-locked: Hyprland does not answer" 2 omarchy-hyprland-session-locked
hj monitors "$both"
is "external-active: HDMI enabled" 0 omarchy-hyprland-monitor-external-active
capture "$OMA/omarchy-hyprland-monitor-focused"
assert_eq "monitor-focused prints the focused output" "HDMI-A-1" "$OUTPUT"
capture "$OMA/omarchy-hyprland-monitor-laptop"
assert_eq "monitor-laptop prints the built-in output" "eDP-1" "$OUTPUT"
is "modeless: every monitor has a mode" 1 omarchy-hyprland-monitor-modeless
is "session-locked: unlocked" 1 omarchy-hyprland-session-locked
is "session-lock-stranded: unlocked" 1 omarchy-hyprland-session-lock-stranded 4242
hj monitors '[{"name":"eDP-1","disabled":false,"width":2880,"height":1800,"solitaryBlockedBy":["LOCK"]},
              {"name":"HDMI-A-1","disabled":true,"width":0,"height":0,"solitaryBlockedBy":["LOCK"]}]'
is "external-active: a disabled external monitor" 1 omarchy-hyprland-monitor-external-active
is "modeless: a disabled monitor at 0x0 does not count" 1 omarchy-hyprland-monitor-modeless
is "session-locked: locked" 0 omarchy-hyprland-session-locked
is "session-lock-stranded: no locker runs" 0 omarchy-hyprland-session-lock-stranded 4242
echo 4242 >"$SANDBOX/pgrep.txt"
is "session-lock-stranded: only the caller runs" 0 omarchy-hyprland-session-lock-stranded 4242
printf '4242\n999\n' >"$SANDBOX/pgrep.txt"
is "session-lock-stranded: another locker runs" 2 omarchy-hyprland-session-lock-stranded 4242
hj monitors '[{"name":"eDP-1","disabled":false,"width":0,"height":0,"solitaryBlockedBy":["WORKSPACE"]}]'
is "modeless: an enabled monitor at 0x0" 0 omarchy-hyprland-monitor-modeless
is "session-locked: no monitor has a workspace yet" 2 omarchy-hyprland-session-locked
hj monitors '[{"name":"HDMI-A-1","focused":true,"disabled":false,"width":2560,"height":1440}]'
capture "$OMA/omarchy-hyprland-monitor-laptop"
assert_eq "monitor-laptop: no built-in output prints nothing" "0:" "$STATUS:$OUTPUT"

# --- Hyprland window dispatches ------------------------------------------------------------
box omarchy-hyprland-window
hj clients '[{"address":"0xa1","class":"firefox","initialClass":"firefox","initialTitle":"a","focusHistoryID":3,"size":[900,700]},
             {"address":"0xb2","class":"firefox","initialClass":"firefox","initialTitle":"b","focusHistoryID":1,"size":[900,700]},
             {"address":"0xc3","class":"foot","initialClass":"org.omarchy.agent","initialTitle":"claude","focusHistoryID":0,"size":[1000,800]}]'
capture "$OMA/omarchy-hyprland-focus-app" firefox --dry-run
assert_dry_pure "focus-app" "$OUTPUT"
assert_eq "focus-app: the most recently focused match (legacy dispatcher)" \
    "DRYRUN: hyprctl dispatch focuswindow address:0xb2" "$OUTPUT"
capture "$OMA/omarchy-hyprland-focus-app" claude --dry-run
assert_contains "focus-app: an agent window by its launch title" "$OUTPUT" "address:0xc3"
is "focus-app: nothing matches" 1 omarchy-hyprland-focus-app chromium --dry-run
hj status '{"configProvider":"lua"}'
capture "$OMA/omarchy-hyprland-focus-app" FIREFOX
assert_contains "focus-app: a Lua Hyprland gets the Lua dispatcher" "$(hlog)" \
    'hyprctl dispatch hl.dsp.focus({ window = "address:0xb2" })'
rm -f "$SANDBOX/hypr/status.json" "$SANDBOX/hypr.log"
capture "$OMA/omarchy-hyprland-window-close-all" --dry-run
assert_dry_pure "window-close-all" "$OUTPUT"
assert_contains "close-all: asks each window to close" "$OUTPUT" "DRYRUN: hyprctl dispatch closewindow address:0xa1
DRYRUN: hyprctl dispatch closewindow address:0xb2
DRYRUN: hyprctl dispatch closewindow address:0xc3"
assert_contains "close-all: then workspace 1" "$OUTPUT" "DRYRUN: hyprctl dispatch workspace 1"
hj active '{"address":"0xc3","class":"foot","initialClass":"org.omarchy.agent","title":"claude","fullscreenClient":2,"pinned":false,"size":[1000,800],"workspace":{"id":3,"name":"3"}}'
capture "$OMA/omarchy-hyprland-window-tiled-fullscreen-toggle" --dry-run
assert_dry_pure "tiled-fullscreen-toggle" "$OUTPUT"
assert_eq "tiled-fullscreen: a fullscreen client goes back" "DRYRUN: hyprctl dispatch fullscreenstate 0 0" "$OUTPUT"
capture "$OMA/omarchy-hyprland-window-transparency-toggle" --dry-run
assert_dry_pure "transparency-toggle" "$OUTPUT"
assert_eq "transparency: the focused window's opaque property" \
    "DRYRUN: hyprctl dispatch setprop address:0xc3 opaque toggle" "$OUTPUT"
capture "$OMA/omarchy-hyprland-window-pop" --dry-run
assert_dry_pure "window-pop" "$OUTPUT"
assert_contains "window-pop: floats, sizes, centres, pins, raises and tags" "$OUTPUT" \
    "DRYRUN: hyprctl dispatch togglefloating address:0xc3
DRYRUN: hyprctl dispatch resizeactive exact 1300 900 address:0xc3
DRYRUN: hyprctl dispatch centerwindow address:0xc3
DRYRUN: hyprctl dispatch pin address:0xc3
DRYRUN: hyprctl dispatch alterzorder top address:0xc3
DRYRUN: hyprctl dispatch tagwindow +pop address:0xc3"
capture "$OMA/omarchy-hyprland-window-pop" 640 480 10 20 --dry-run
assert_contains "window-pop: an explicit place" "$OUTPUT" "DRYRUN: hyprctl dispatch moveactive 10 20 address:0xc3"
is "window-pop: a size must be a number" 1 omarchy-hyprland-window-pop wide 480
hj active '{"address":"0xc3","class":"foot","fullscreenClient":0,"pinned":true,"size":[1000,800],"workspace":{"id":3,"name":"3"}}'
capture "$OMA/omarchy-hyprland-window-tiled-fullscreen-toggle" --dry-run
assert_eq "tiled-fullscreen: a tiled window goes client fullscreen" "DRYRUN: hyprctl dispatch fullscreenstate 0 2" "$OUTPUT"
capture "$OMA/omarchy-hyprland-window-pop" --dry-run
assert_contains "window-pop: a popped window is tiled again" "$OUTPUT" "DRYRUN: hyprctl dispatch pin address:0xc3
DRYRUN: hyprctl dispatch togglefloating address:0xc3
DRYRUN: hyprctl dispatch tagwindow -pop address:0xc3"
capture "$OMA/omarchy-hyprland-window-tiled-fullscreen-toggle"
assert_eq "tiled-fullscreen: alone, it dispatches" "hyprctl dispatch fullscreenstate 0 2" "$(hlog)"
hj active '{}'
is "transparency: no focused window" 1 omarchy-hyprland-window-transparency-toggle --dry-run

# --- window-width ----------------------------------------------------------------------------
box omarchy-hyprland-window-width
fake_bin haseen-notification-send
widths="$HOME/.local/state/haseen/windows"
hj active '{"address":"0xd4","class":"foot","size":[1000,800],"workspace":{"id":3,"name":"3"}}'
hj clients '[{"address":"0xd4","class":"foot","size":[1000,800]}]'
capture "$OMA/omarchy-hyprland-window-width" save --dry-run
assert_dry_pure "window-width save" "$OUTPUT"
assert_contains "window-width save: the width file is planned" "$OUTPUT" "DRYRUN: write $widths/workspace-3-foot.width:
    | 1000"
[[ ! -e $widths ]] && _pass || _fail "window-width save: the dry run wrote the width"
capture "$OMA/omarchy-hyprland-window-width" restore --dry-run
assert_status "window-width restore: nothing saved" 1 "$STATUS"
assert_contains "window-width restore: says so" "$OUTPUT" "DRYRUN: notify: No saved width found for foot on workspace 3"
capture fake omarchy-hyprland-window-width save
assert_eq "window-width save keeps the width" "1000" "$(cat "$widths/workspace-3-foot.width" 2>/dev/null)"
assert_contains "window-width save tells the user" "$(flog)" "haseen-notification-send [Saved width for foot on workspace 3]"
echo 800 >"$widths/workspace-3-foot.width"
capture "$OMA/omarchy-hyprland-window-width" restore --dry-run
assert_dry_pure "window-width restore" "$OUTPUT"
assert_eq "window-width restore: one relative resize back" \
    "DRYRUN: hyprctl dispatch resizeactive -200 0 address:0xd4" "$OUTPUT"
is "window-width: an unknown action" 1 omarchy-hyprland-window-width grow

# --- monitor-scaling ----------------------------------------------------------------------------
box omarchy-hyprland-scaling
hj monitors '[{"name":"eDP-1","focused":true,"disabled":false,"width":2880,"height":1800,"scale":1.6,"refreshRate":60}]'
capture "$OMA/omarchy-hyprland-monitor-scaling"
assert_eq "scaling prints the focused monitor's scale" "1.6" "$OUTPUT"
capture "$OMA/omarchy-hyprland-monitor-scaling" 2 --dry-run
assert_status "scaling 2 dry run" 0 "$STATUS"
assert_dry_pure "scaling" "$OUTPUT"
assert_contains "scaling: applied live" "$OUTPUT" \
    'DRYRUN: hyprctl eval hl.monitor({ output = "eDP-1", mode = "2880x1800@60", position = "auto", scale = 2 })'
assert_contains "scaling: kept in haseen's toggle" "$OUTPUT" "DRYRUN: write $TOGGLES/monitor-scale-eDP-1.lua:"
assert_contains "scaling: GDK follows" "$OUTPUT" 'hl.env("GDK_SCALE", "2")'
[[ ! -e $TOGGLES/monitor-scale-eDP-1.lua ]] && _pass || _fail "scaling: the dry run wrote the toggle"
capture "$OMA/omarchy-hyprland-monitor-scaling" up --dry-run
assert_contains "scaling up from 1.6 is 2" "$OUTPUT" "scale = 2 })"
capture "$OMA/omarchy-hyprland-monitor-scaling" down --dry-run
assert_contains "scaling down from 1.6 is 1.25" "$OUTPUT" "scale = 1.25 })"
is "scaling: 5 is out of range" 1 omarchy-hyprland-monitor-scaling 5
capture "$OMA/omarchy-hyprland-monitor-scaling" 2
assert_contains "scaling: alone, it evaluates the monitor rule" "$(hlog)" 'hyprctl eval hl.monitor({ output = "eDP-1"'
assert_contains "scaling: and keeps it" "$(cat "$TOGGLES/monitor-scale-eDP-1.lua" 2>/dev/null)" "scale = 2 })"

# --- toggles -------------------------------------------------------------------------------------
box omarchy-hyprland-toggle
fake_bin haseen-toggle-gaps haseen-toggle-one-window-ratio haseen-hardware-mirror-display haseen-hardware-laptop-display
capture fake omarchy-hyprland-toggle window-no-gaps
assert_eq "toggle window-no-gaps prints the new state" "on" "$OUTPUT"
assert_eq "toggle window-no-gaps is haseen toggle gaps" "haseen-toggle-gaps [on]" "$(flog)"
mkdir -p "$TOGGLES"
touch "$TOGGLES/no-gaps.lua"
capture fake omarchy-hyprland-toggle window-no-gaps
assert_eq "toggle window-no-gaps again turns it off" "off" "$OUTPUT"
: >"$SANDBOX/fake.log"
capture fake omarchy-hyprland-toggle internal-monitor-disable on
assert_eq "internal-monitor-disable on turns the laptop display off" "haseen-hardware-laptop-display [off]" "$(flog)"
: >"$SANDBOX/fake.log"
capture fake omarchy-hyprland-toggle single-window-aspect-ratio off --dry-run
assert_eq "toggle passes --dry-run on" "haseen-toggle-one-window-ratio [off] [--dry-run]" "$(flog)"
capture fake omarchy-hyprland-toggle internal-monitor-mirror on
assert_contains "internal-monitor-mirror is haseen hardware mirror-display" "$(flog)" "haseen-hardware-mirror-display [on]"
is "toggle: an unknown flag" 1 omarchy-hyprland-toggle nonsense
assert_contains "toggle: says so" "$OUTPUT" "Flag not found: nonsense"
is "toggle: an unknown action" 1 omarchy-hyprland-toggle window-no-gaps sideways
is "toggle-enabled: no-gaps on" 0 omarchy-hyprland-toggle-enabled window-no-gaps
is "toggle-disabled: no-gaps on" 1 omarchy-hyprland-toggle-disabled window-no-gaps
is "toggle-enabled: mirroring off" 1 omarchy-hyprland-toggle-enabled internal-monitor-mirror
is "toggle-disabled: mirroring off" 0 omarchy-hyprland-toggle-disabled internal-monitor-mirror
is "toggle-enabled: an unusable name" 2 omarchy-hyprland-toggle-enabled ../flags
is "toggle-disabled: no name" 2 omarchy-hyprland-toggle-disabled
hj monitors '[{"name":"eDP-1","disabled":false},{"name":"HDMI-A-1","disabled":false}]'
capture "$OMA/omarchy-hyprland-toggle" internal-monitor-disable --dry-run
assert_dry_pure "toggle internal-monitor-disable" "$OUTPUT"
assert_contains "toggle: haseen's laptop display is turned off in the plan" "$OUTPUT" "DRYRUN: write $TOGGLES/laptop-display-off.lua:"
[[ ! -e $TOGGLES/laptop-display-off.lua ]] && _pass || _fail "toggle: the dry run turned the display off"

# --- laptop display: internal, mirror, clamshell ---------------------------------------------------
box omarchy-hyprland-laptop-display
fake_bin haseen-hardware-laptop-display haseen-hardware-mirror-display haseen-notification-send
hj monitors '[{"name":"eDP-1","disabled":false},{"name":"HDMI-A-1","disabled":false}]'
capture "$OMA/omarchy-hyprland-monitor-internal" off --dry-run
assert_dry_pure "monitor-internal off" "$OUTPUT"
assert_contains "monitor-internal off: haseen's toggle is planned" "$OUTPUT" "DRYRUN: write $TOGGLES/laptop-display-off.lua:"
[[ ! -e $TOGGLES/laptop-display-off.lua ]] && _pass || _fail "monitor-internal: the dry run turned the display off"
capture fake omarchy-hyprland-monitor-internal off
assert_contains "monitor-internal off is haseen hardware laptop-display off" "$(flog)" "haseen-hardware-laptop-display [off]"
mkdir -p "$TOGGLES"
touch "$TOGGLES/laptop-display-off.lua"
: >"$SANDBOX/fake.log"
capture fake omarchy-hyprland-monitor-internal off
assert_eq "monitor-internal off: already off, nothing to do" "" "$(flog)"
capture fake omarchy-hyprland-monitor-internal toggle
assert_contains "monitor-internal toggle turns it back on" "$(flog)" "haseen-hardware-laptop-display [on]"
capture "$OMA/omarchy-hyprland-monitor-internal" on --dry-run
assert_dry_pure "monitor-internal on" "$OUTPUT"
assert_contains "monitor-internal on: the toggle goes" "$OUTPUT" "DRYRUN: rm -f $TOGGLES/laptop-display-off.lua"
capture "$OMA/omarchy-hyprland-monitor-internal" recover --dry-run
assert_eq "monitor-internal recover: an external monitor keeps it off" "" "$OUTPUT"
rm -f "$TOGGLES/laptop-display-off.lua"
capture "$OMA/omarchy-hyprland-monitor-internal" on --dry-run
assert_eq "monitor-internal on: an enabled panel only wakes" 'DRYRUN: hyprctl dispatch hl.dsp.dpms({ action = "enable" })' "$OUTPUT"
is "monitor-internal: an unknown action" 1 omarchy-hyprland-monitor-internal sideways
capture "$OMA/omarchy-hyprland-monitor-internal-mirror" on --dry-run
assert_dry_pure "internal-mirror on" "$OUTPUT"
assert_contains "internal-mirror on: haseen's mirror rule is planned" "$OUTPUT" \
    'hl.monitor({ output = "HDMI-A-1", mode = "preferred", position = "auto", scale = 1, mirror = "eDP-1" })'
: >"$SANDBOX/fake.log"
capture fake omarchy-hyprland-monitor-internal-mirror on
assert_contains "internal-mirror on is haseen hardware mirror-display on" "$(flog)" "haseen-hardware-mirror-display [on]"
touch "$TOGGLES/mirror-display.lua"
: >"$SANDBOX/fake.log"
capture fake omarchy-hyprland-monitor-internal-mirror recover
assert_eq "internal-mirror recover: an external monitor keeps the mirror" "" "$(flog)"
hj monitors '[{"name":"eDP-1","disabled":false}]'
capture fake omarchy-hyprland-monitor-internal-mirror recover
assert_eq "internal-mirror recover: alone again, it extends quietly" "haseen-hardware-mirror-display [off]" "$(flog)"
touch "$TOGGLES/laptop-display-off.lua"
capture "$OMA/omarchy-hyprland-monitor-internal" recover --dry-run
assert_dry_pure "monitor-internal recover" "$OUTPUT"
assert_contains "monitor-internal recover: alone again, the panel comes back" "$OUTPUT" "DRYRUN: rm -f $TOGGLES/laptop-display-off.lua"

box omarchy-hyprland-clamshell
fake_bin haseen-hardware-laptop-display haseen-hardware-mirror-display haseen-notification-send
lid="$ROOT/proc/acpi/button/lid/LID0"
mkdir -p "$lid" "$ROOT/sys/class/drm/card1-HDMI-A-1"
echo "state:      closed" >"$lid/state"
echo connected >"$ROOT/sys/class/drm/card1-HDMI-A-1/status"
hj monitors '[{"name":"eDP-1","disabled":false},{"name":"HDMI-A-1","disabled":false}]'
capture "$OMA/omarchy-hyprland-monitor-clamshell" --dry-run
assert_status "clamshell dry run" 0 "$STATUS"
assert_dry_pure "clamshell" "$OUTPUT"
assert_contains "clamshell: closed and docked turns the panel off" "$OUTPUT" "DRYRUN: write $TOGGLES/laptop-display-off.lua:"
assert_contains "clamshell: and marks it as its own doing" "$OUTPUT" "DRYRUN: write $FLAGS/clamshell-display-off:"
[[ ! -e $FLAGS/clamshell-display-off ]] && _pass || _fail "clamshell: the dry run wrote its mark"
capture fake omarchy-hyprland-monitor-clamshell
assert_eq "clamshell: haseen hardware laptop-display off" "haseen-hardware-laptop-display [off]" "$(flog)"
[[ -f $FLAGS/clamshell-display-off ]] && _pass || _fail "clamshell: the mark is written"
mkdir -p "$TOGGLES"
touch "$TOGGLES/laptop-display-off.lua"
: >"$SANDBOX/fake.log"
capture fake omarchy-hyprland-monitor-clamshell
assert_eq "clamshell: an already-off panel is left alone" "" "$(flog)"
echo "state:      open" >"$lid/state"
capture fake omarchy-hyprland-monitor-clamshell
assert_eq "clamshell: an open lid brings its panel back" "haseen-hardware-laptop-display [on]" "$(flog)"
[[ ! -e $FLAGS/clamshell-display-off ]] && _pass || _fail "clamshell: the mark goes with it"
: >"$SANDBOX/fake.log"
capture fake omarchy-hyprland-monitor-clamshell
assert_eq "clamshell: a panel turned off by hand stays off" "" "$(flog)"

# --- reload-guard -------------------------------------------------------------------------------------
box omarchy-hyprland-reload-guard
is "reload-guard paused: nothing held" 1 omarchy-hyprland-reload-guard paused
mkdir -p "$ROOT/run/omarchy/hyprland-reload-guard"
touch "$ROOT/run/omarchy/hyprland-reload-guard/abc_1"
is "reload-guard paused: Omarchy's pause counts" 0 omarchy-hyprland-reload-guard paused
rm -rf "$ROOT/run/omarchy"
run_dir="$ROOT/run/user/1000"
mkdir -p "$run_dir/hypr/abc_123_1"
capture "$OMA/omarchy-hyprland-reload-guard" pause --dry-run
assert_status "reload-guard pause dry run" 0 "$STATUS"
assert_dry_pure "reload-guard pause" "$OUTPUT"
assert_contains "reload-guard pause: the settings are saved" "$OUTPUT" \
    "DRYRUN: write /run/haseen/hyprland-reload-guard/abc_123_1 (mode 0600):
    | $run_dir	false	false"
assert_contains "reload-guard pause: auto-reload goes off" "$OUTPUT" \
    "DRYRUN: XDG_RUNTIME_DIR=$run_dir hyprctl --instance abc_123_1 eval hl.config({ misc = { disable_autoreload = true }, debug = { suppress_errors = true } })"
mkdir -p "$ROOT/run/haseen/hyprland-reload-guard"
printf '%s\ttrue\tfalse\n' "$run_dir" >"$ROOT/run/haseen/hyprland-reload-guard/abc_123_1"
is "reload-guard paused: haseen's pause" 0 omarchy-hyprland-reload-guard paused
capture "$OMA/omarchy-hyprland-reload-guard" pause --dry-run
assert_not_contains "reload-guard pause: an existing save is kept" "$OUTPUT" "DRYRUN: write"
capture "$OMA/omarchy-hyprland-reload-guard" resume --dry-run
assert_dry_pure "reload-guard resume" "$OUTPUT"
assert_contains "reload-guard resume: one reload" "$OUTPUT" "DRYRUN: XDG_RUNTIME_DIR=$run_dir hyprctl --instance abc_123_1 reload"
assert_contains "reload-guard resume: the saved settings come back" "$OUTPUT" \
    "eval hl.config({ misc = { disable_autoreload = true }, debug = { suppress_errors = false } })"
assert_contains "reload-guard resume: the save goes" "$OUTPUT" "DRYRUN: sudo rm -f /run/haseen/hyprland-reload-guard/abc_123_1"
[[ -f $ROOT/run/haseen/hyprland-reload-guard/abc_123_1 ]] && _pass || _fail "reload-guard: the dry run removed the save"
rm -f "$ROOT/run/haseen/hyprland-reload-guard/abc_123_1"
stub dead-hyprctl 'echo "Couldn'"'"'t connect to /run/user/1000/hypr/abc_123_1/.socket.sock. (3)"'
capture env HYPRCTL="$SANDBOX/stubs/dead-hyprctl" "$OMA/omarchy-hyprland-reload-guard" pause --dry-run
assert_eq "reload-guard pause: a dead instance is skipped" "0:" "$STATUS:$OUTPUT"
is "reload-guard: an unknown verb" 1 omarchy-hyprland-reload-guard hold

# --- monitor-watch ------------------------------------------------------------------------------------
box omarchy-hyprland-watch
stub socat 'printf "monitoraddedv2>>2,HDMI-A-1,Dell U2723QE\n"'
lid="$ROOT/proc/acpi/button/lid/LID0"
mkdir -p "$lid" "$ROOT/sys/class/drm/card1-HDMI-A-1"
echo "state:      closed" >"$lid/state"
echo connected >"$ROOT/sys/class/drm/card1-HDMI-A-1/status"
hj monitors '[{"name":"eDP-1","disabled":false,"width":2880,"height":1800},{"name":"HDMI-A-1","disabled":false,"width":3840,"height":2160}]'
capture "$OMA/omarchy-hyprland-monitor-watch" --dry-run
assert_status "monitor-watch: no Hyprland session" 1 "$STATUS"
assert_contains "monitor-watch: says so" "$OUTPUT" "no Hyprland session"
capture timeout 30 env HYPRLAND_INSTANCE_SIGNATURE=abc_123_1 "$OMA/omarchy-hyprland-monitor-watch" --dry-run
assert_status "monitor-watch dry run ends with Hyprland's event stream" 0 "$STATUS"
assert_dry_pure "monitor-watch" "$OUTPUT"
assert_contains "monitor-watch: a docked closed laptop is reconciled (as a plan)" "$OUTPUT" "DRYRUN: write $TOGGLES/laptop-display-off.lua:"
[[ ! -e $TOGGLES/laptop-display-off.lua && ! -e $FLAGS/clamshell-display-off ]] && _pass ||
    _fail "monitor-watch: the dry run changed the display"
assert_eq "monitor-watch: nothing reached Hyprland" "" "$(hlog)"

# --- hibernation --------------------------------------------------------------------------------------
box omarchy-hibernation-setup
fake_bin haseen-hibernation-setup haseen-system
capture fake omarchy-hibernation-setup --dry-run
assert_status "hibernation-setup: no hibernation support is no error" 0 "$STATUS"
assert_contains "hibernation-setup: says so" "$OUTPUT" "Hibernation is not supported on your system"
assert_eq "hibernation-setup: nothing set up" "" "$(flog)"
mkdir -p "$ROOT/sys/power" "$ROOT/proc"
echo 3355443200 >"$ROOT/sys/power/image_size"
printf 'Filename\tType\tSize\tUsed\tPriority\n' >"$ROOT/proc/swaps"
capture fake omarchy-hibernation-setup --dry-run
assert_dry_pure "hibernation-setup" "$OUTPUT"
assert_eq "hibernation-setup is haseen hibernation setup" "haseen-hibernation-setup [--dry-run]" "$(flog)"
assert_contains "hibernation-setup: the reboot is offered" "$OUTPUT" "DRYRUN: ask 'Reboot to enable hibernation?'"
: >"$SANDBOX/fake.log"
capture fake omarchy-hibernation-setup --force --no-rebuild --dry-run
assert_eq "hibernation-setup: --force is --yes, --no-rebuild stays" \
    "haseen-hibernation-setup [--yes] [--no-rebuild] [--dry-run]" "$(flog)"
assert_not_contains "hibernation-setup --force: no reboot offer" "$OUTPUT" "Reboot"

box omarchy-hibernation-remove
capture env BOOTLOADER=limine "$OMA/omarchy-hibernation-remove" --dry-run
assert_contains "hibernation-remove: nothing set up" "$OUTPUT" "Hibernation is not set up"
mkdir -p "$ROOT/etc/mkinitcpio.conf.d" "$ROOT/etc/limine-entry-tool.d" "$ROOT/etc/kernel" "$ROOT/swap" "$ROOT/proc"
cat >"$ROOT/etc/fstab" <<'EOF'
UUID=abcd / btrfs subvol=/@,rw,noatime 0 0

# haseen: hibernation image area
UUID=abcd /swap btrfs subvol=/@swap,rw,noatime 0 0
# haseen: hibernation swapfile
/swap/swapfile none swap defaults,pri=0 0 0
EOF
touch "$ROOT/swap/swapfile" "$ROOT/etc/mkinitcpio.conf.d/haseen-resume.conf"
echo 'KERNEL_CMDLINE[default]+=" resume=UUID=abcd resume_offset=533760"' >"$ROOT/etc/limine-entry-tool.d/haseen-resume.conf"
echo "quiet resume=UUID=abcd resume_offset=533760 rw" >"$ROOT/etc/kernel/cmdline"
printf 'Filename\tType\tSize\tUsed\tPriority\n/swap/swapfile\tfile\t33554428\t0\t-2\n' >"$ROOT/proc/swaps"
fstab_before="$(cat "$ROOT/etc/fstab")"
capture env BOOTLOADER=limine "$OMA/omarchy-hibernation-remove" --dry-run
assert_status "hibernation-remove dry run" 0 "$STATUS"
assert_dry_pure "hibernation-remove" "$OUTPUT"
assert_contains "hibernation-remove: swap goes off first" "$OUTPUT" "DRYRUN: sudo swapoff /swap/swapfile"
assert_contains "hibernation-remove: the swapfile goes" "$OUTPUT" "DRYRUN: sudo rm -f /swap/swapfile"
assert_contains "hibernation-remove: fstab keeps only the root line" "$OUTPUT" "DRYRUN: write /etc/fstab (mode 0644):
    | UUID=abcd / btrfs subvol=/@,rw,noatime 0 0
[*] unmounting /swap"
assert_contains "hibernation-remove: the empty @swap subvolume goes" "$OUTPUT" \
    "DRYRUN: sudo btrfs subvolume delete <a temporary directory>/@swap"
assert_contains "hibernation-remove: the resume hook goes" "$OUTPUT" "DRYRUN: sudo rm -f /etc/mkinitcpio.conf.d/haseen-resume.conf"
assert_contains "hibernation-remove: Limine's resume= goes" "$OUTPUT" "DRYRUN: sudo rm -f /etc/limine-entry-tool.d/haseen-resume.conf"
assert_contains "hibernation-remove: /etc/kernel/cmdline loses resume=" "$OUTPUT" "DRYRUN: write /etc/kernel/cmdline (mode 0644):
    | quiet rw"
assert_contains "hibernation-remove: the initramfs is rebuilt" "$OUTPUT" "mkinitcpio"
assert_eq "hibernation-remove: the dry run leaves fstab" "$fstab_before" "$(cat "$ROOT/etc/fstab")"
touch "$ROOT/swap/notes.txt"
capture env BOOTLOADER=limine "$OMA/omarchy-hibernation-remove" --dry-run
assert_contains "hibernation-remove: a swap subvolume holding more is kept" "$OUTPUT" "keeping the @swap subvolume"
assert_not_contains "hibernation-remove: and not deleted" "$OUTPUT" "btrfs subvolume delete"

# --- hooks ---------------------------------------------------------------------------------------------
box omarchy-hook
hooks="$HOME/.config/haseen/hooks"
mkdir -p "$hooks"
printf '#!/bin/bash\necho "ran $*" >"%s/ran"\n' "$SANDBOX" >"$hooks/post-update"
capture "$OMA/omarchy-hook" post-update one two
assert_status "hook: runs" 0 "$STATUS"
assert_eq "hook: the user's hook ran with the arguments" "ran one two" "$(cat "$SANDBOX/ran" 2>/dev/null)"
is "hook: no name is a usage error" 1 omarchy-hook
fake_bin haseen-hook
capture fake omarchy-hook theme-set dark
assert_eq "hook is haseen hook run" "haseen-hook [run] [theme-set] [dark]" "$(flog)"
printf '#!/bin/bash\necho hi\n' >"$SANDBOX/myhook"
capture "$OMA/omarchy-hook-install" theme-set "$SANDBOX/myhook" --dry-run
assert_status "hook-install dry run" 0 "$STATUS"
assert_dry_pure "hook-install" "$OUTPUT"
[[ ! -e $hooks/theme-set.d/myhook ]] && _pass || _fail "hook-install: the dry run installed the hook"
capture "$OMA/omarchy-hook-install" theme-set "$SANDBOX/myhook"
[[ -x $hooks/theme-set.d/myhook ]] && _pass || _fail "hook-install: the hook lands, executable, in theme-set.d"
: >"$SANDBOX/fake.log"
capture fake omarchy-hook-install post-update "$SANDBOX/myhook"
assert_eq "hook-install is haseen hook install --yes" "haseen-hook [install] [post-update] [$SANDBOX/myhook] [--yes]" "$(flog)"
is "hook-install: a missing file" 1 omarchy-hook-install theme-set "$SANDBOX/nope"
assert_contains "hook-install: says so" "$OUTPUT" "Hook file not found"

# --- fonts ----------------------------------------------------------------------------------------------
box omarchy-font
fake_bin
printf '#!/bin/sh\ncat "%s/family.txt" 2>/dev/null\n' "$SANDBOX" >"$FAKE/bin/haseen-font-current"
chmod +x "$FAKE/bin/haseen-font-current"
echo "JetBrains Mono" >"$SANDBOX/family.txt"
echo "Iosevka,Iosevka Term" >"$SANDBOX/fc-match.txt"
capture fake omarchy-font-current
assert_eq "font-current: the family chosen with haseen font set" "JetBrains Mono" "$OUTPUT"
rm "$SANDBOX/family.txt"
capture fake omarchy-font-current
assert_eq "font-current: else fontconfig's monospace, first alias" "Iosevka" "$OUTPUT"

# --- git URLs ---------------------------------------------------------------------------------------------
box omarchy-git-url
is "git-url-check: https" 0 omarchy-git-url-check https://github.com/owner/theme.git
is "git-url-check: scp-like ssh" 0 omarchy-git-url-check git@github.com:owner/theme.git
is "git-url-check: nothing" 1 omarchy-git-url-check
is "git-url-check: a git option" 1 omarchy-git-url-check --upload-pack=touch
assert_contains "git-url-check: says why" "$OUTPUT" "names a git option or transport helper"
is "git-url-check: a transport helper" 1 omarchy-git-url-check 'ext::sh -c touch% /tmp/x'
is "git-url-check: ftp" 1 omarchy-git-url-check ftp://example.com/theme.git
assert_contains "git-url-check: names the transport" "$OUTPUT" "names the 'ftp' transport"

# --- file chooser -------------------------------------------------------------------------------------------
box omarchy-file-select
stub python3 'exit 3'
stub zenity "printf '%s\n' \"\$*\" >'$SANDBOX/zenity.args'; cat '$SANDBOX/zenity.out' 2>/dev/null; exit \$(cat '$SANDBOX/zenity.status' 2>/dev/null || echo 0)"
echo "$HOME/Pictures/a.png" >"$SANDBOX/zenity.out"
capture "$OMA/omarchy-file-select" --title Pick --extensions "png .JPG"
assert_eq "file-select prints the pick" "0:$HOME/Pictures/a.png" "$STATUS:$OUTPUT"
assert_eq "file-select: zenity without a portal, filtered both cases" \
    "--file-selection --title=Pick --timeout=600 --file-filter=*.png *.PNG *.jpg *.JPG" "$(cat "$SANDBOX/zenity.args")"
capture "$OMA/omarchy-file-select" --multiple --directory --extensions png
assert_contains "file-select: several directories" "$(cat "$SANDBOX/zenity.args")" "--multiple"
assert_not_contains "file-select: a directory takes no filter" "$(cat "$SANDBOX/zenity.args")" "--file-filter"
echo 1 >"$SANDBOX/zenity.status"
is "file-select: cancelled" 1 omarchy-file-select
echo 9 >"$SANDBOX/zenity.status"
is "file-select: the chooser failed" 2 omarchy-file-select
is "file-select: an unknown option" 2 omarchy-file-select --bogus

# --- retro games ------------------------------------------------------------------------------------------------
box omarchy-games
cores="$HOME/.var/app/org.libretro.RetroArch/config/retroarch/cores"
mkdir -p "$ROOT/usr/lib/libretro" "$cores" "$ROOT/usr/bin" "$HOME/Games/roms"
capture "$OMA/omarchy-games-retro-cores"
assert_eq "retro-cores: none installed" "0:" "$STATUS:$OUTPUT"
touch "$ROOT/usr/lib/libretro/snes9x_libretro.so" "$ROOT/usr/lib/libretro/other_libretro.so" "$cores/mgba_libretro.so"
capture "$OMA/omarchy-games-retro-cores"
assert_eq "retro-cores: the preferred ones from the package and the Flatpak" \
    "Nintendo Game Boy Advance (mgba)
Nintendo SNES / SFC (snes9x)" "$OUTPUT"
printf '#!/bin/sh\n' >"$ROOT/usr/bin/retroarch"
chmod +x "$ROOT/usr/bin/retroarch"
game="$HOME/Games/roms/super metroid (USA).sfc"
touch "$game"
stub update-desktop-database 'echo "STUB-CALLED: update-desktop-database $*" >&2'
apps="$HOME/.local/share/applications"
capture "$OMA/omarchy-games-retro-install" snes9x "$game" --dry-run
assert_status "retro-install dry run" 0 "$STATUS"
assert_dry_pure "retro-install" "$OUTPUT"
assert_contains "retro-install: the launcher is planned" "$OUTPUT" "DRYRUN: write $apps/super-metroid.desktop:"
assert_contains "retro-install: named after the game" "$OUTPUT" "    | Name=Super Metroid"
assert_contains "retro-install: the package's RetroArch runs the core" "$OUTPUT" \
    "    | Exec=retroarch -L \"/usr/lib/libretro/snes9x_libretro.so\" \"$game\""
[[ ! -e $apps/super-metroid.desktop ]] && _pass || _fail "retro-install: the dry run wrote the launcher"
is "retro-install: a Flatpak core without the Flatpak" 1 omarchy-games-retro-install mgba "$game" --dry-run
assert_contains "retro-install: says how to get RetroArch" "$OUTPUT" "haseen install app retroarch"
mkdir -p "$HOME/.local/share/flatpak/app/org.libretro.RetroArch"
capture "$OMA/omarchy-games-retro-install" mgba "$game" --dry-run
assert_contains "retro-install: a Flatpak core runs in the Flatpak" "$OUTPUT" \
    "    | Exec=flatpak run org.libretro.RetroArch -L \"$cores/mgba_libretro.so\" \"$game\""
is "retro-install: an unknown core" 1 omarchy-games-retro-install nope "$game"
assert_contains "retro-install: says so" "$OUTPUT" "Core not found: nope"
is "retro-install: a missing game" 1 omarchy-games-retro-install snes9x "$HOME/Games/roms/none.sfc"
stub update-desktop-database 'exit 0'
fake_bin haseen-notification-send
capture fake omarchy-games-retro-install snes9x "$game"
assert_status "retro-install writes the launcher" 0 "$STATUS"
[[ -x $apps/super-metroid.desktop ]] && _pass || _fail "retro-install: the launcher is executable"
assert_contains "retro-install: the launcher runs the game" "$(cat "$apps/super-metroid.desktop" 2>/dev/null)" \
    "Exec=retroarch -L \"/usr/lib/libretro/snes9x_libretro.so\" \"$game\""
assert_contains "retro-install: and says so" "$(flog)" "haseen-notification-send [Super Metroid installed]"
