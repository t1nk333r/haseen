# shellcheck shell=bash
# haseen:covers share/haseen/shell/plugins/haseen.computer/**
# haseen:covers share/haseen/shell/Haseen/Sidecar.qml share/haseen/migrations/1794530533-computer-service.sh
# haseen:covers share/haseen/default/shell.json share/haseen/default/hypr/binds.lua share/haseen/default/menu.jsonc
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# The Your computer panel (plan 162) and its background history (plan 165).
# The test runs Computer.js under Qt's own
# engine: the history window, the graph scales, the point mapping and the
# smooth line, the temperature's word, the sizes, the uptime, the load, the
# thread count and the disk it picks. Then it loads the real Panel.qml under
# qs, offscreen on the software renderer, against a fake sidecar frame and a
# fixture /proc, and reads back what it says, what it asks the sidecar for
# and when it stops asking; and it reads the drawn graph's pixels at scales
# 1 and 1.25, where a Canvas or a layer would come out wrong (plan 156). Then
# it runs the service with the panel closed, opens the panel on the history
# the service kept, and closes it again: the service keeps asking and keeps
# the history.

P="$HASEEN_PATH/shell/plugins/haseen.computer"
QML_BIN=${QML_BIN:-/usr/lib/qt6/bin/qml}
QS_BIN=${QS_BIN:-/usr/bin/qs}

sandbox computer

# --- the plugin's shape --------------------------------------------------------
capture haseen-plugin-validate "$P"
assert_status "the manifest validates" 0 "$STATUS"
assert_eq "a service and a panel" "service panel" "$(jq -r '.kinds | join(" ")' "$P/manifest.json")"
assert_eq "the service answers the computer role" "computer" "$(jq -r '.provides | join(" ")' "$P/manifest.json")"
assert_eq "the service is on by default, last in services (owner, 2026-11-13)" "haseen.computer" \
    "$(jq -r '.services[-1]' "$HASEEN_PATH/default/shell.json")"
service="$(cat "$P/Service.qml")"
assert_contains "the service subscribes to the sidecar's stream" "$service" 'Sidecar.want(_key, "sysusage"'
assert_contains "the service asks for the temperature and the disks" "$service" "system: true"
assert_contains "the service lets go when it goes" "$service" "Component.onDestruction: Sidecar.drop(_key)"
assert_eq "the storage card shows / by default" "/" "$(jq -r '.settings.mount.default' "$P/manifest.json")"
assert_eq "on by default: not switched off in the shipped shell.json" "null" \
    "$(jq -r '.plugins["haseen.computer"].enabled' "$HASEEN_PATH/default/shell.json")"
panel="$(cat "$P/Panel.qml")"
assert_contains "the panel subscribes to the sidecar's stream" "$panel" 'Sidecar.want(_key, "sysusage"'
assert_contains "it asks for the temperature and the disks" "$panel" "system: true"
assert_contains "it asks only while shown, and only without the service" "$panel" "if (!visible || service) {"
assert_contains "it lets go when the panel goes" "$panel" "Component.onDestruction: Sidecar.drop(_key)"
assert_contains "it is gated on the sidecar's capability" "$panel" 'Sidecar.has("sysusage")'
assert_contains "system files are read under HASEEN_SYSROOT" "$panel" 'Quickshell.env("HASEEN_SYSROOT")'
assert_eq "no Timer, Canvas, layer or shader in the plugin" "" \
    "$(grep -nE 'Timer *\{|Canvas *\{|layer\.enabled|ShaderEffect|MultiEffect' "$P"/*.qml || true)"
assert_eq "no colour literal in the plugin" "" "$(grep -nE '#[0-9a-fA-F]{3,8}\b' "$P"/*.qml "$P"/*.js || true)"
assert_contains "the graph draws with QtQuick.Shapes" "$(cat "$P/Graph.qml")" "import QtQuick.Shapes"
assert_contains "the time graph is not mirrored" "$(cat "$P/Graph.qml")" "LayoutMirroring.enabled: false"
assert_contains "nothing is copied from pocket-dots" "$(cat "$P/Computer.js")" "reference only, nothing copied"

# The key and the menu row the owner asked for (owner, 2026-11-12).
assert_contains "SUPER + SHIFT + D opens the panel" "$(cat "$HASEEN_PATH/default/hypr/binds.lua")" \
    'b("SUPER + SHIFT + D", "Your computer", ipc("panel", "toggle", "haseen.computer"))'
menu_row="$(grep '"trigger.computer"' "$HASEEN_PATH/default/menu.jsonc")"
assert_contains "the menu's Trigger opens the panel" "$menu_row" '"action":"haseen shell ipc panel toggle haseen.computer"'
# The row shows unless the user switched the plugin off; no shell.json at all
# is the default, on.
guard="$(sed 's/.*"when":"\(.*\)","action".*/\1/; s/\\"/"/g' <<<"$menu_row")"
mkdir -p "$XDG_CONFIG_HOME/haseen"
rm -f "$XDG_CONFIG_HOME/haseen/shell.json"
assert_status "the row shows without a shell.json" 0 "$(bash -c "$guard" && echo 0 || echo 1)"
echo '{"plugins":{"haseen.computer":{"settings":{"mount":"/home"}}}}' >"$XDG_CONFIG_HOME/haseen/shell.json"
assert_status "the row shows while the plugin is on" 0 "$(bash -c "$guard" && echo 0 || echo 1)"
echo '{"plugins":{"haseen.computer":{"enabled":false}}}' >"$XDG_CONFIG_HOME/haseen/shell.json"
assert_status "the row hides once the plugin is off" 1 "$(bash -c "$guard" && echo 0 || echo 1)"
rm -f "$XDG_CONFIG_HOME/haseen/shell.json"

if [[ ! -x $QML_BIN ]]; then
    echo "  (no $QML_BIN: Computer.js and the panel were not exercised)" >&2
    return 0
fi

# --- migration ------------------------------------------------------------------
MIGRATION=1794530533-computer-service.sh
run_migration() {
    capture env HASEEN_PATH="$HASEEN_PATH" HASEEN_MIGRATION="$MIGRATION" \
        bash -Eeuo pipefail "$HASEEN_PATH/migrations/$MIGRATION"
}
CFG="$XDG_CONFIG_HOME/haseen/shell.json"
printf '{"services":["haseen.pager","me.svc"],"plugins":{"me.svc":{"enabled":true}}}\n' >"$CFG"
run_migration
assert_status "migration exits 0" 0 "$STATUS"
assert_eq "migration: appended to a user's own services" '["haseen.pager","me.svc","haseen.computer"]' "$(jq -c .services "$CFG")"
assert_eq "migration: the rest of shell.json survives" "true" "$(jq '.plugins["me.svc"].enabled' "$CFG")"
after="$(cat "$CFG")"
run_migration
assert_eq "migration: a re-run is a no-op" "$after" "$(cat "$CFG")"
printf '{"services":["haseen.computer"],"plugins":{"haseen.computer":{"enabled":false}}}\n' >"$CFG"
before="$(cat "$CFG")"
run_migration
assert_eq "migration: a user's own off stays off" "$before" "$(cat "$CFG")"
printf '{"bar":{"left":[]}}\n' >"$CFG"
before="$(cat "$CFG")"
run_migration
assert_eq "migration: no own services list, nothing written" "$before" "$(cat "$CFG")"
rm -f "$CFG"
run_migration
assert_status "migration without a shell.json exits 0" 0 "$STATUS"
assert_eq "migration: no shell.json, none written" no "$([[ -e $CFG ]] && echo yes || echo no)"

# --- Computer.js, under the Qt JS engine -----------------------------------------
units="$SANDBOX/units"
mkdir -p "$units"
cat >"$units/Units.qml" <<EOF
import QtQuick
import "file://$P/Computer.js" as C
Item {
    function out(k, v) { console.warn("RESULT " + k + " " + JSON.stringify(v)); }
    Component.onCompleted: {
        // 40 samples 3 s apart: the window keeps the last 31 (0 to 90 s old).
        let h = [];
        for (let i = 0; i < 40; i++)
            h = C.push(h, i * 3000, i);
        out("window", [h.length, h[0].t, h[h.length - 1].v, C.WINDOW_MS, C.INTERVAL_MS]);
        out("skips", [C.push([], 0, -1).length, C.push([], 0, NaN).length, C.push([], 0, undefined).length, C.push(null, 5, 0).length]);
        const fresh = C.push([], 1000, 5);
        out("immutable", [C.push(fresh, 2000, 6) !== fresh, fresh.length]);
        // The clock stepped back an hour: what was recorded "later" goes.
        out("clockBack", C.push([{ t: 3600000, v: 1 }, { t: 3603000, v: 2 }], 3000, 3).map(s => s.t));
        out("ceiling", [C.ceiling([]), C.ceiling([{ t: 0, v: 7 }]), C.ceiling([{ t: 0, v: 10 }]), C.ceiling([{ t: 0, v: 34 }]), C.ceiling([{ t: 0, v: 51 }]), C.ceiling([{ t: 0, v: 140 }])]);
        out("tempRange", [C.tempRange([]), C.tempRange([{ t: 0, v: 40 }]), C.tempRange([{ t: 0, v: 40 }, { t: 1, v: 62 }]), C.tempRange([{ t: 0, v: 1 }])]);
        // Newest on the right edge, a sample 45 s older half-way, the top
        // and bottom kept inside the pad.
        const pts = C.points([{ t: 0, v: 100 }, { t: 45000, v: 0 }, { t: 90000, v: 50 }], 300, 110, 0, 100, C.WINDOW_MS, 5);
        out("points", pts);
        out("pointsEdge", [C.points([], 300, 100, 0, 100).length, C.points([{ t: 0, v: 1 }], 0, 100, 0, 100).length,
            C.points([{ t: 0, v: 200 }], 100, 100, 0, 100, 0, 0)[0].y, C.points([{ t: -200000, v: 1 }, { t: 0, v: 1 }], 100, 100, 0, 100)[0].x]);
        out("line", [C.linePath([]), C.linePath([{ x: 1, y: 2 }]), C.linePath([{ x: 0, y: 10 }, { x: 30, y: 10 }])]);
        // The curve never leaves the band its samples span: a monotone cubic.
        const zig = [{ x: 0, y: 90 }, { x: 10, y: 90 }, { x: 20, y: 10 }, { x: 30, y: 90 }, { x: 40, y: 88 }];
        const ys = C.linePath(zig).match(/-?[0-9.]+/g).map(Number).filter((v, i) => i % 2 === 1);
        out("monotone", [Math.min(...ys) >= 10, Math.max(...ys) <= 90]);
        out("area", [C.areaPath([{ x: 0, y: 1 }], 50), C.areaPath([{ x: 0, y: 10 }, { x: 30, y: 20 }], 50).endsWith("L 30 50 L 0 50 Z")]);
        out("temp", [C.tempWord(40), C.tempWord(59.9), C.tempWord(60), C.tempWord(79), C.tempWord(80), C.tempWord(-1), C.tempLevel(undefined), C.tempLevel(95)]);
        out("gib", [C.gib(16148070), C.gib(6815744), C.gib(52009370), C.gib(-1), C.gib(undefined)]);
        out("uptime", [C.uptime("64680.12 100.00\n"), C.uptime("59"), C.uptime("90000"), C.uptime(""), C.uptime("x")]);
        out("load", [C.loadAverage("1.35 0.98 0.80 2/1234 5678\n"), C.loadAverage(""), C.loadAverage("-3")]);
        out("cpus", [C.cpuCount("0-7\n"), C.cpuCount("0-3,5,7-8"), C.cpuCount("0"), C.cpuCount(""), C.cpuCount("3-1")]);
        const disks = [{ mount: "/boot" }, { mount: "/" }, { mount: "/home" }];
        out("disk", [C.pickDisk(disks, "/home").mount, C.pickDisk(disks, "/").mount, C.pickDisk(disks, "").mount, C.pickDisk(disks, "/nowhere").mount,
            C.pickDisk([{ mount: "/boot" }], "/"), C.pickDisk(null, "/")]);
        Qt.quit();
    }
}
EOF
capture env QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 NO_AT_BRIDGE=1 timeout 60 "$QML_BIN" "$units/Units.qml"
assert_status "the unit runner exits 0" 0 "$STATUS"
r() { sed -n "s/^.*RESULT $1 //p" <<<"$OUTPUT" | head -1; }
assert_eq "the window keeps 90 s of samples" '[31,27000,39,90000,3000]' "$(r window)"
assert_eq "unknown readings are not recorded" '[0,0,0,1]' "$(r skips)"
assert_eq "each push makes a new history" '[true,1]' "$(r immutable)"
assert_eq "samples from after a clock step back are dropped" '[3000]' "$(r clockBack)"
assert_eq "the scale steps 10, 25, 50, 100" '[10,10,10,50,100,100]' "$(r ceiling)"
assert_eq "the temperature range is whole tens, 20 °C or more" \
    '[{"lo":30,"hi":50},{"lo":30,"hi":50},{"lo":30,"hi":70},{"lo":0,"hi":20}]' "$(r tempRange)"
assert_eq "points run with time, inside the pad" \
    '[{"x":0,"y":5},{"x":150,"y":105},{"x":300,"y":55}]' "$(r points)"
assert_eq "no points without data or room; clamped values and ages" '[0,0,0,0]' "$(r pointsEdge)"
assert_eq "the line's path" '["","M 1 2 L 1 2","M 0 10 C 10 10 20 10 30 10"]' "$(r line)"
assert_eq "the curve does not swing past its samples" '[true,true]' "$(r monotone)"
assert_eq "the fill closes down to the floor" '["",true]' "$(r area)"
assert_eq "Cool under 60, Warm to 79, Hot from 80" '["Cool","Cool","Warm","Warm","Hot","",-1,2]' "$(r temp)"
assert_eq "KiB to GiB, one decimal" '[15.4,6.5,49.6,-1,-1]' "$(r gib)"
assert_eq "uptime in days, hours and minutes" \
    '[{"days":0,"hours":17,"minutes":58,"totalMinutes":1078},{"days":0,"hours":0,"minutes":0,"totalMinutes":0},{"days":1,"hours":1,"minutes":0,"totalMinutes":1500},null,null]' \
    "$(r uptime)"
assert_eq "the one-minute load" '[1.35,-1,-1]' "$(r load)"
assert_eq "threads from the online CPU list" '[8,7,1,0,0]' "$(r cpus)"
assert_eq "the disk at the setting, else the root" '["/home","/","/","/",null,null]' "$(r disk)"

# --- the panel under qs ----------------------------------------------------------
if [[ ! -x $QS_BIN ]] || ! command -v dbus-run-session >/dev/null; then
    echo "  skip: qs or dbus-run-session missing; the panel was not loaded" >&2
    return 0
fi
# A copy of share/haseen without a sidecar binary, so a daemon a developer
# built into the checkout cannot start and answer in place of the fake frames.
hp="$SANDBOX/haseen"
mkdir -p "$hp"
for e in "$HASEEN_PATH"/*; do
    [[ $(basename "$e") == sidecar ]] || ln -s "$e" "$hp/$(basename "$e")"
done
root="$SANDBOX/root"
mkdir -p "$root/proc" "$root/sys/devices/system/cpu"
printf '64680.12 100.00\n' >"$root/proc/uptime"
printf '1.35 0.98 0.80 2/1234 5678\n' >"$root/proc/loadavg"
printf '0-7\n' >"$root/sys/devices/system/cpu/online"
harness="$SANDBOX/shell"
mkdir -p "$harness"
for module in Haseen Compat Ui Commons plugins; do
    ln -s "$HASEEN_PATH/shell/$module" "$harness/$module"
done
cat >"$harness/shell.qml" <<'QML'
import QtQuick
import Quickshell
import qs.Haseen
import qs.Haseen.Widgets
import "plugins/haseen.computer" as Computer

ShellRoot {
    id: shell

    readonly property string out: Quickshell.env("COMPUTER_OUT")
    readonly property bool rtl: Quickshell.env("COMPUTER_RTL") === "1"
    property int step: 0
    property var panel: loader.item

    // A sysusage frame with `system`, as haseen-sidecar sends it.
    function sample(cpu, mem, temp): var {
        return {
            cpu: cpu,
            mem: { totalKiB: 16148070, usedKiB: Math.round(16148070 * mem / 100), availableKiB: 0, percent: mem, swapTotalKiB: 0, swapUsedKiB: 0 },
            gpu: -1,
            cpuTempC: temp,
            cpuFreqMHz: 2400,
            net: { rxBps: 0, txBps: 0 },
            disks: [
                { mount: "/boot", device: "/dev/nvme0n1p1", fstype: "vfat", totalKiB: 1048576, usedKiB: 102400, availKiB: 946176, percent: 9.8 },
                { mount: "/", device: "/dev/nvme0n1p2", fstype: "btrfs", totalKiB: 184654234, usedKiB: 132644864, availKiB: 52009370, percent: 76 }
            ]
        };
    }

    // Every visible text in the panel, in order, glyphs left out.
    function texts(item, acc): var {
        if (!item || !item.visible)
            return acc;
        if (typeof item.text === "string" && item.text !== "" && item.font !== undefined && item.glyph === undefined)
            acc.push(item.text);
        for (const c of item.children)
            texts(c, acc);
        return acc;
    }

    function find(item, name): var {
        if (!item)
            return null;
        if (item.objectName === name)
            return item;
        for (const c of item.children) {
            const f = find(c, name);
            if (f)
                return f;
        }
        return null;
    }

    function rect(name): var {
        const it = find(panel, name);
        if (!it)
            return null;
        const p = it.mapToItem(surface, 0, 0);
        return { x: p.x, y: p.y, w: it.width, h: it.height, visible: it.visible };
    }

    function state(): string {
        return JSON.stringify({
            consumers: Object.keys(Sidecar._consumers).map(k => Sidecar._consumers[k]),
            texts: panel ? texts(panel, []) : [],
            cpu: panel ? panel.cpuHistory.length : -1,
            temp: panel ? panel.tempHistory.length : -1,
            usage: rect("usageCard"),
            tempCard: rect("tempCard"),
            cpuGraph: rect("cpuGraph"),
            tempGraph: rect("tempGraph"),
            accent: String(Theme.accent),
            software: surface.GraphicsInfo.api === GraphicsInfo.Software,
            size: [surface.width, surface.height]
        });
    }

    FloatingWindow {
        implicitWidth: surface.implicitWidth
        implicitHeight: surface.implicitHeight
        visible: true
        color: "transparent"

        // As PanelPopup hosts a panel: in the Omarchy card, mirrored for a
        // right-to-left language.
        PanelSurface {
            id: surface

            LayoutMirroring.enabled: shell.rtl
            LayoutMirroring.childrenInherit: true

            Loader {
                id: loader

                sourceComponent: Computer.Panel {
                    pluginId: "haseen.computer"
                    settings: Plugins.settingsFor("haseen.computer")
                }
            }
        }
    }

    // Each tick prints the state, then acts. Printed at 0: nothing from the
    // daemon yet; then 87 s of history on a fake clock and the daemon's live
    // frame. At 1: that frame, and the panel is drawn. At 3: the sensor has
    // stopped answering. At 4: the panel has closed.
    Timer {
        interval: 700
        repeat: true
        running: true
        onTriggered: {
            console.warn("STATE " + shell.step + " " + shell.state());
            if (shell.step === 0) {
                const now = Date.now();
                const cpu = [12, 34, 18, 9, 22, 15, 11, 8, 14, 10, 9, 12, 25, 24, 26, 23, 25, 24, 26, 25, 24, 25, 25, 24, 22, 13, 9, 16, 21];
                for (let i = 0; i < cpu.length; i++)
                    shell.panel.record(shell.sample(cpu[i], 41 + (i % 3) * 0.3, i === 4 || i === 24 ? 62 : 40 + (i % 4)), now - (cpu.length - i) * 3000);
                Sidecar.capabilities = ["sysusage"];
                Sidecar.streams = { sysusage: shell.sample(7.2, 42.2, 40.4) };
            } else if (shell.step === 1) {
                if (shell.out !== "")
                    surface.grabToImage(r => r.saveToFile(shell.out));
            } else if (shell.step === 2) {
                Sidecar.streams = { sysusage: shell.sample(8, 42.2, -1) };
            } else if (shell.step === 3) {
                loader.active = false;
            } else {
                Qt.quit();
            }
            shell.step++;
        }
    }
}
QML

# panel_run SCALE PNG [rtl] -> OUTPUT, STATUS; state N FILTER reads step N.
# Its own process group and its output in a file, as in test-widgets-b.sh:
# a stuck run fails here instead of hanging the suite. No system bus, so no
# battery joins the subtitle.
panel_run() {
    local run
    run="$(mktemp -d "$SANDBOX/run.XXXXXX")"
    chmod 700 "$run"
    setsid env XDG_RUNTIME_DIR="$run" HASEEN_PATH="$hp" HASEEN_SYSROOT="$root" \
        DBUS_SYSTEM_BUS_ADDRESS=unix:path=/nonexistent QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME='' \
        QT_QUICK_BACKEND=software QT_NO_XDG_DESKTOP_PORTAL=1 QT_SCALE_FACTOR="$1" \
        COMPUTER_OUT="$2" COMPUTER_RTL="$([[ ${3:-} == rtl ]] && echo 1 || echo 0)" \
        timeout -k 5 60 dbus-run-session --config-file="$REPO/tools/smoke-session.conf" -- "$QS_BIN" -p "$harness" \
        >"$SANDBOX/panel.out" 2>&1 &
    local group=$!
    STATUS=0
    wait "$group" || STATUS=$?
    kill -- -"$group" 2>/dev/null || true
    OUTPUT="$(cat "$SANDBOX/panel.out")"
    if [[ $STATUS == 0 ]]; then _pass; else _fail "the panel harness completes at scale $1 ${3:-} (exit $STATUS)" "$OUTPUT"; fi
}
state() { sed -n "s/^.*STATE $1 //p" <<<"$OUTPUT" | head -1 | jq -r "$2"; }

# strips PNG RECT_JSON SCALE ACCENT -> how many of 10 vertical strips of the
# graph hold the accent: the line crosses the whole graph, newest dot included.
strips() {
    local png=$1 x y w h n=0 i sx
    read -r x y w h < <(jq -r --argjson s "$3" '[.x, .y, .w, .h] | map(. * $s | floor) | @tsv' <<<"$2")
    for i in $(seq 0 9); do
        sx=$((x + w * i / 10))
        if [[ $(magick "$png" -crop "$((w / 10))x${h}+${sx}+${y}" +repage -fuzz 12% -fill white -opaque "$4" \
            -fill black +opaque white -format '%[fx:maxima.r]' info: 2>/dev/null) == 1 ]]; then
            n=$((n + 1))
        fi
    done
    echo "$n"
}

panel_run 1 "$SANDBOX/panel-1.png"
assert_eq "drawn on the software renderer" "true" "$(state 1 .software)"
assert_eq "it asks the sidecar for system samples every 3 s while open" \
    '[{"stream":"sysusage","params":{"intervalMs":3000,"gpu":"off","system":true}}]' "$(state 0 '.consumers | tojson')"
assert_contains "no daemon: it says so" "$(state 0 '.texts | join("|")')" "haseen-sidecar is not running"
assert_eq "no daemon: no cards" "false" "$(state 0 .usage.visible)"
assert_eq "the header, the readings and the notes" \
    "Your computer|Uptime 17 h 58 min|Processor|7 %|load 1.35 · 8 threads|last 90 s|50 %|Memory|42 %|6.5 of 15.4 GiB|50 %|Temperature|Cool|40 °C|Storage|76 %|49.6 GiB free of 176.1" \
    "$(state 1 '.texts | join("|")')"
assert_eq "the history holds 87 s of fake clock and the live frame" "30 30" "$(state 1 '"\(.cpu) \(.temp)"')"
assert_eq "the processor card is on the left in English" "true" "$(state 1 '.usage.x < .tempCard.x')"
assert_contains "an unknown temperature says so" "$(state 3 '.texts | join("|")')" "Temperature|Unknown|Storage"
assert_eq "an unknown temperature draws no graph and records nothing" "false 30 31" "$(state 3 '"\(.tempGraph.visible) \(.temp) \(.cpu)"')"
assert_eq "closed, it asks for nothing" "[]" "$(state 4 '.consumers | tojson')"

if ! command -v magick >/dev/null; then
    echo "  (magick missing: the graph's pixels were not read back)" >&2
else
    accent="$(state 1 .accent)"
    assert_eq "scale 1: the processor line crosses its whole graph" 10 "$(strips "$SANDBOX/panel-1.png" "$(state 1 .cpuGraph)" 1 "$accent")"
    assert_eq "scale 1: the temperature line too" 10 "$(strips "$SANDBOX/panel-1.png" "$(state 1 .tempGraph)" 1 "$accent")"
    panel_run 1.25 "$SANDBOX/panel-125.png"
    assert_eq "scale 1.25: the picture is the whole panel" \
        "$(state 1 '.size | map(. * 1.25 | floor) | "\(.[0])x\(.[1])"')" "$(magick identify -format '%wx%h' "$SANDBOX/panel-125.png")"
    assert_eq "scale 1.25: the processor line crosses its whole graph" 10 "$(strips "$SANDBOX/panel-125.png" "$(state 1 .cpuGraph)" 1.25 "$accent")"
    assert_eq "scale 1.25: the temperature line too" 10 "$(strips "$SANDBOX/panel-125.png" "$(state 1 .tempGraph)" 1.25 "$accent")"
fi

# Arabic, right to left: the strings come from the catalog and the cards
# swap sides; the graphs keep time running to the right.
mkdir -p "$XDG_CONFIG_HOME/haseen"
echo ar >"$XDG_CONFIG_HOME/haseen/language"
panel_run 1 "$SANDBOX/panel-ar.png" rtl
rm -f "$XDG_CONFIG_HOME/haseen/language"
assert_contains "Arabic: the title" "$(state 1 '.texts | join("|")')" "حاسوبك"
assert_contains "Arabic: the storage line reads right to left" "$(state 1 '.texts | join("|")')" "متاح 49.6 GiB من 176.1"
assert_eq "Arabic: the processor card is on the right" "true" "$(state 1 '.usage.x > .tempCard.x')"
if command -v magick >/dev/null; then
    assert_eq "Arabic: the processor line still crosses its graph" 10 "$(strips "$SANDBOX/panel-ar.png" "$(state 1 .cpuGraph)" 1 "$accent")"
fi

# --- the service keeps the history while the panel is closed (plan 165) ------
# The service runs from the start, the panel closed: 29 samples on a fake
# clock and the daemon's live frame land in its history. Then the panel opens
# on that history, adds no subscription of its own, and closes; the service
# still asks and still holds the 30 samples.
svch="$SANDBOX/service-shell"
mkdir -p "$svch"
for module in Haseen Compat Ui Commons plugins; do
    ln -s "$HASEEN_PATH/shell/$module" "$svch/$module"
done
cat >"$svch/shell.qml" <<'QML'
import QtQuick
import Quickshell
import qs.Haseen
import qs.Haseen.Widgets
import "plugins/haseen.computer" as Computer

ShellRoot {
    id: shell

    property int step: 0
    property var panel: loader.item

    function sample(cpu, temp): var {
        return {
            cpu: cpu,
            mem: { totalKiB: 16148070, usedKiB: 6815744, availableKiB: 0, percent: 42.2, swapTotalKiB: 0, swapUsedKiB: 0 },
            gpu: -1,
            cpuTempC: temp,
            disks: [{ mount: "/", device: "/dev/nvme0n1p2", fstype: "btrfs", totalKiB: 184654234, usedKiB: 132644864, availKiB: 52009370, percent: 76 }]
        };
    }

    function state(): string {
        return JSON.stringify({
            consumers: Object.keys(Sidecar._consumers).length,
            service: svc.cpuHistory.length,
            panel: panel ? panel.cpuHistory.length : -1,
            panelTemp: panel ? panel.tempHistory.length : -1,
            uses: panel ? panel.service === svc : null
        });
    }

    // As ServiceHost does for a manifest's `provides`.
    Computer.Service {
        id: svc
        pluginId: "haseen.computer"
        Component.onCompleted: Plugins.registerRole("computer", "haseen.computer", svc)
    }

    FloatingWindow {
        implicitWidth: 600
        implicitHeight: 400
        visible: true
        color: "transparent"

        Loader {
            id: loader

            active: false
            sourceComponent: Computer.Panel {
                pluginId: "haseen.computer"
                settings: Plugins.settingsFor("haseen.computer")
            }
        }
    }

    // 0: record, panel closed. 1: open it. 2: closed again.
    Timer {
        interval: 700
        repeat: true
        running: true
        onTriggered: {
            if (shell.step === 0) {
                const now = Date.now();
                for (let i = 0; i < 29; i++)
                    svc.record(shell.sample(10 + i, 40 + (i % 4)), now - (29 - i) * 3000);
                Sidecar.capabilities = ["sysusage"];
                Sidecar.streams = { sysusage: shell.sample(7.2, 40.4) };
            } else if (shell.step === 1) {
                loader.active = true;
            } else if (shell.step === 3) {
                loader.active = false;
            } else if (shell.step === 5) {
                Qt.quit();
            }
            console.warn("STATE " + shell.step + " " + shell.state());
            shell.step++;
        }
    }
}
QML
run="$(mktemp -d "$SANDBOX/run.XXXXXX")"
chmod 700 "$run"
setsid env XDG_RUNTIME_DIR="$run" HASEEN_PATH="$hp" HASEEN_SYSROOT="$root" \
    DBUS_SYSTEM_BUS_ADDRESS=unix:path=/nonexistent QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME='' \
    QT_QUICK_BACKEND=software QT_NO_XDG_DESKTOP_PORTAL=1 \
    timeout -k 5 60 dbus-run-session --config-file="$REPO/tools/smoke-session.conf" -- "$QS_BIN" -p "$svch" \
    >"$SANDBOX/service.out" 2>&1 &
group=$!
STATUS=0
wait "$group" || STATUS=$?
kill -- -"$group" 2>/dev/null || true
OUTPUT="$(cat "$SANDBOX/service.out")"
assert_status "the service harness completes" 0 "$STATUS"
assert_eq "panel closed: the service asks the sidecar and keeps 30 samples" '1 30 -1' "$(state 0 '"\(.consumers) \(.service) \(.panel)"')"
assert_eq "panel open: it draws the service's history at once, with no subscription of its own" \
    '1 30 30 true' "$(state 2 '"\(.consumers) \(.service) \(.panel) \(.uses)"')"
assert_eq "panel open: the temperature history too" 30 "$(state 2 .panelTemp)"
assert_eq "panel closed again: the service still asks and keeps the history" '1 30' "$(state 4 '"\(.consumers) \(.service)"')"
assert_not_contains "no QML error from the plugin" "$OUTPUT" "plugins/haseen.computer/"
