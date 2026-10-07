# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# Keyboard layout and lock keys (plans 079, 080): the haseen.osd kinds (mic,
# layout, Caps/Num Lock) and the haseen.kblayout bar widget. The manifests
# and defaults; the layout-name -> code mapping, the devices reader, the lock
# reader and the OSD kind model under the real Qt JS engine; the lock-key
# binds under a stub hl; and the widget, the Keyboard singleton and the OSD
# in the real Quickshell engine against a stub hyprctl serving fixture
# `hyprctl -j devices` output.

OSD="$HASEEN_PATH/shell/plugins/haseen.osd"
KBL="$HASEEN_PATH/shell/plugins/haseen.kblayout"
KEYBOARD_JS="$HASEEN_PATH/shell/Haseen/Keyboard.js"
DEFAULT="$HASEEN_PATH/default/shell.json"
FX="$FIXTURES/keyboard"

# --- manifests and defaults ----------------------------------------------------
sandbox keyboard
capture haseen plugin validate haseen.osd haseen.kblayout
assert_status "osd and kblayout validate" 0 "$STATUS"
assert_contains "osd ok" "$OUTPUT" "ok: haseen.osd (builtin:"
assert_contains "kblayout ok" "$OUTPUT" "ok: haseen.kblayout (builtin:"
assert_eq "osd kinds: mic and layout on, lock keys off" "true true false" \
    "$(jq -r '[.settings.mic.default, .settings.layout.default, .settings.lockKeys.default] | map(tostring) | join(" ")' "$OSD/manifest.json")"
assert_eq "osd stays a default service" "true" "$(jq '.services | index("haseen.osd") != null' "$DEFAULT")"
assert_eq "default shell.json leaves the osd kinds at their defaults" "null" "$(jq '.plugins["haseen.osd"]' "$DEFAULT")"
assert_eq "kblayout: a bar widget with a panel" "bar-widget panel" "$(jq -r '.kinds | join(" ")' "$KBL/manifest.json")"
assert_eq "kblayout is off by default" "false" "$(jq '.plugins["haseen.kblayout"].enabled' "$DEFAULT")"
assert_eq "kblayout is in no bar section by default" "false" \
    "$(jq '[.bar.left, .bar.center, .bar.right, .bar.overflow] | add | index("haseen.kblayout") != null' "$DEFAULT")"

# --- the models under the real Qt JS engine ------------------------------------
QML=/usr/lib/qt6/bin/qml
H="$SANDBOX/js"
mkdir -p "$H"
cat >"$H/Units.qml" <<EOF
import QtQuick
import "file://$KEYBOARD_JS" as K
import "file://$OSD/Osd.js" as O

Window {
    property int failures: 0

    function eq(name, expected, actual) {
        const e = JSON.stringify(expected), a = JSON.stringify(actual);
        if (e === a)
            console.warn("UNIT-PASS " + name);
        else {
            failures++;
            console.warn("UNIT-FAIL " + name + " expected " + e + " got " + a);
        }
    }

    function fixture(name) {
        const xhr = new XMLHttpRequest();
        xhr.open("GET", "file://$FX/" + name, false);
        xhr.send();
        return xhr.responseText;
    }

    Component.onCompleted: {
        try {
            run();
        } catch (e) {
            failures++;
            console.warn("UNIT-FAIL exception " + e);
        }
        Qt.exit(failures > 0 ? 1 : 0);
    }

    function run() {
        // layout name -> code
        eq("code: English variants", ["EN", "EN", "EN", "EN"],
           ["English (US)", "English (UK)", "English (Dvorak)", "English (US, intl., with dead keys)"].map(K.codeFromName));
        eq("code: Arabic and every xkb Arabic variant", Array(15).fill("AR"),
           ["Arabic", "Arabic (AZERTY)", "Arabic (AZERTY, Eastern Arabic numerals)", "Arabic (Algeria)",
            "Arabic (Buckwalter)", "Arabic (Eastern Arabic numerals)", "Arabic (Egypt)", "Arabic (Iraq)",
            "Arabic (Macintosh)", "Arabic (Macintosh, phonetic)", "Arabic (Morocco)", "Arabic (OLPC)",
            "Arabic (Pakistan)", "Arabic (Syria)", "Arabic (QWERTY, Eastern Arabic numerals)"].map(K.codeFromName));
        eq("code: languages whose code is not their first letters", ["FA", "HE", "DE", "EL", "UK", "SV", "CS", "JA"],
           ["Persian", "Hebrew", "German (no dead keys)", "Greek", "Ukrainian", "Swedish", "Czech", "Japanese"].map(K.codeFromName));
        eq("code: an unknown language falls back to its first two letters", "KL", K.codeFromName("Klingon (pIqaD)"));
        eq("code: nothing to show", ["", "", ""], ["", "   ", undefined].map(K.codeFromName));
        eq("xkb code: names whose language differs", ["EN", "EN", "AR", "AR", "AR", "FA", "HE", "DE", "DE"],
           ["us", "gb", "ara", "eg", "ma", "ir", "il", "de", "ch"].map(K.codeFromXkb));
        eq("xkb code: the rest are their first two letters", ["FR", "RU", "TR"], ["fr", "ru", "tr"].map(K.codeFromXkb));

        // activelayout payloads
        eq("event: keyboard and layout", { keyboard: "at-kbd", layout: "Arabic" }, K.parseLayoutEvent("at-kbd,Arabic"));
        eq("event: a description with a comma stays whole",
           { keyboard: "at-kbd", layout: "Arabic (AZERTY, Eastern Arabic numerals)" },
           K.parseLayoutEvent("at-kbd,Arabic (AZERTY, Eastern Arabic numerals)"));
        eq("event: junk", [null, null, null], ["", "nocomma", ",Arabic"].map(K.parseLayoutEvent));

        // devices
        const two = K.readDevices(fixture("devices-two.json"));
        eq("devices: the main keyboard", "at-translated-set-2-keyboard", two.main);
        eq("devices: its layouts", [{ layout: "us", variant: "", code: "EN" }, { layout: "ara", variant: "", code: "AR" }], two.layouts);
        eq("devices: the active layout", [0, "English (US)"], [two.index, two.layout]);
        eq("devices: every keyboard is the baseline",
           { "power-button": "English (US)", "at-translated-set-2-keyboard": "English (US)" }, two.known);
        eq("devices: one layout", 1, K.readDevices(fixture("devices-one.json")).layouts.length);
        eq("devices: variants follow their layout",
           ["ara/", "ara/buckwalter"], K.readDevices(fixture("devices-three.json")).layouts.slice(1).map(l => l.layout + "/" + l.variant));
        eq("devices: no main flag -> the first keyboard", ["wooting-60he", "DE"],
           (d => [d.main, d.layouts[0].code])(K.readDevices(fixture("devices-nomain.json"))));
        eq("devices: no keyboards", { main: "", layouts: [], index: -1, layout: "", known: {} }, K.readDevices(fixture("devices-none.json")));
        eq("devices: unreadable output", "", K.readDevices("hyprctl: no instance").main);

        // the lock-key reader
        eq("locks: the main keyboard, not the first", { caps: false, num: true }, K.lockState(fixture("devices-two.json")));
        eq("locks: caps on", { caps: true, num: true }, K.lockState(fixture("devices-caps.json")));
        eq("locks: num off", { caps: true, num: false }, K.lockState(fixture("devices-num-off.json")));
        eq("locks: no main flag -> the first keyboard", { caps: true, num: false }, K.lockState(fixture("devices-nomain.json")));
        eq("locks: no keyboard, no reading", [null, null], [K.lockState(fixture("devices-none.json")), K.lockState("{")]);

        // layout events against the baseline
        const base = { "at-kbd": "English (US)", "power-button": "English (US)" };
        const sw = K.layoutEvent(base, "at-kbd,Arabic");
        eq("layout event: a known keyboard switching", [true, "Arabic"], [sw.switched, sw.layout]);
        eq("layout event: the baseline follows", "Arabic", sw.known["at-kbd"]);
        eq("layout event: the input is not changed", "English (US)", base["at-kbd"]);
        eq("layout event: a reload repeats the same layout", false, K.layoutEvent(base, "power-button,English (US)").switched);
        eq("layout event: a new keyboard only seeds", [false, "English (US)"],
           (r => [r.switched, r.known["usb-kbd"]])(K.layoutEvent(base, "usb-kbd,English (US)")));
        eq("layout event: junk changes nothing", [false, base], (r => [r.switched, r.known])(K.layoutEvent(base, "junk")));

        // the OSD kind model
        eq("kinds: defaults", { volume: true, brightness: true, mic: true, layout: true, lockKeys: false }, O.kinds({}));
        eq("kinds: no settings at all", O.kinds({}), O.kinds(undefined));
        eq("kinds: each one is a setting", { volume: false, brightness: false, mic: false, layout: false, lockKeys: true },
           O.kinds({ volume: false, brightness: false, mic: false, layout: false, lockKeys: true }));
        eq("kinds: lock keys need a real true", false, O.kinds({ lockKeys: "true" }).lockKeys);
        eq("mic glyphs", ["\uf130", "\uf131"], [O.micGlyph(false), O.micGlyph(true)]);
        eq("level card clamps", [1, 0, true], (c => [c.value, O.levelCard("x", -2, false).value, O.levelCard("x", 0.5, true).dim])(O.levelCard("x", 3, false)));
        eq("layout card: the code in the glyph cell, the name as the line",
           { glyph: "", text: "AR", label: "Arabic (Buckwalter)", value: 0, dim: false }, O.layoutCard("Arabic (Buckwalter)", "AR"));
        eq("lock cards", [["Caps Lock on", false], ["Num Lock off", true]],
           [O.lockCard({ key: "caps", on: true }), O.lockCard({ key: "num", on: false })].map(c => [c.label, c.dim]));
        eq("lock changes: caps", [{ key: "caps", on: true }], O.lockChanges({ caps: false, num: true }, { caps: true, num: true }));
        eq("lock changes: num", [{ key: "num", on: false }], O.lockChanges({ caps: true, num: true }, { caps: true, num: false }));
        eq("lock changes: nothing changed (Compose on the Caps key)", [], O.lockChanges({ caps: false, num: true }, { caps: false, num: true }));
        eq("lock changes: no baseline says what Caps Lock is", [{ key: "caps", on: false }], O.lockChanges(null, { caps: false, num: true }));
        eq("lock changes: no reading", [], O.lockChanges({ caps: false, num: true }, null));
    }
}
EOF
if [[ -x $QML ]]; then
    set +e
    units="$(QML_XHR_ALLOW_FILE_READ=1 QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 NO_AT_BRIDGE=1 timeout 60 "$QML" "$H/Units.qml" 2>&1)"
    rc=$?
    set -e
    assert_status "qml unit runner exits 0" 0 "$rc"
    while read -r line; do
        assert_eq "js: ${line#*UNIT-FAIL }" "" "fail"
    done < <(grep 'UNIT-FAIL' <<<"$units" || true)
    assert_eq "js unit count" "43" "$(grep -c 'UNIT-PASS' <<<"$units")"
else
    _fail "qml runner missing: $QML"
fi

# --- the lock-key binds under a stub hl -------------------------------------------
if command -v lua >/dev/null; then
    stub_lua="$SANDBOX/hl-stub.lua"
    cat >"$stub_lua" <<'EOF'
local function proxy(name)
  return setmetatable({}, {
    __index = function(_, k) return proxy(name .. "." .. k) end,
    __call = function(_, ...) return { dsp = name, args = { ... } } end,
  })
end
hl = setmetatable({
  dsp = proxy("dsp"),
  bind = function(keys, d, opts)
    if keys == "code:66" or keys == "code:77" then
      local flags = {}
      for _, f in ipairs({ "non_consuming", "release", "ignore_mods", "locked", "repeating" }) do
        if opts and opts[f] then table.insert(flags, f) end
      end
      print("BIND " .. keys .. " -> " .. d.args[1] .. " [" .. table.concat(flags, ",") .. "] " .. tostring(opts.description))
    end
  end,
}, { __index = function() return function() end end })
haseen = { path = os.getenv("HASEEN_PATH") }
EOF
    capture lua -e "dofile('$stub_lua')" -e "
local function q(v) return \"'\" .. tostring(v):gsub(\"'\", \"'\\\\''\") .. \"'\" end
function haseen.ipc(t, f, ...) local p = { 'haseen', 'shell', 'ipc', t, f } for _, a in ipairs({ ... }) do table.insert(p, q(a)) end return table.concat(p, ' ') end
function haseen.launch(c) return c end
function haseen.bind(keys, description, dispatcher, options)
  local opts = options or {}
  opts.description = description
  if type(dispatcher) == 'string' then dispatcher = hl.dsp.exec_cmd(dispatcher) end
  return hl.bind(keys, dispatcher, opts)
end
dofile(haseen.path .. '/default/hypr/binds.lua')"
    assert_status "binds.lua loads" 0 "$STATUS"
    assert_contains "Caps Lock: a non-consuming release bind that asks the OSD" "$OUTPUT" \
        "BIND code:66 -> haseen shell ipc osd lockkeys [non_consuming,release,ignore_mods] Caps Lock OSD"
    assert_contains "Num Lock: the same" "$OUTPUT" \
        "BIND code:77 -> haseen shell ipc osd lockkeys [non_consuming,release,ignore_mods] Num Lock OSD"
else
    _fail "lua missing"
fi

# --- the widget, Keyboard and the OSD in the real engine ---------------------------
QS_BIN=${QS_BIN:-/usr/bin/qs}
if [[ ! -x $QS_BIN ]]; then
    echo "  skip: qs missing; engine scenarios not run" >&2
else
    # kb_run NAME DEVICES OSD_SETTINGS — the harness against a stub hyprctl
    # that serves $SANDBOX/devices.json and logs its argv; the harness swaps
    # devices.json itself between steps (cp), as a key press would change it.
    kb_run() {
        sandbox "keyboard-engine-$1"
        local harness="$SANDBOX/shell"
        mkdir -p "$harness"
        for module in Haseen Compat Ui Commons; do
            ln -s "$HASEEN_PATH/shell/$module" "$harness/$module"
        done
        ln -s "$HASEEN_PATH/shell/plugins" "$harness/plugins"
        cp "$FX/$2" "$SANDBOX/devices.json"
        stub hyprctl "printf '%s\n' \"\$*\" >>'$SANDBOX/hyprctl.log'
[ \"\$*\" = '-j devices' ] && exec cat '$SANDBOX/devices.json'
exit 0"
        stub qs "printf '%s\n' \"\$*\" >>'$SANDBOX/qs.log'; exit 0"
        cat >"$harness/shell.qml" <<QML
import QtQuick
import Quickshell
import qs.Haseen
import "plugins/haseen.kblayout" as Kbl
import "plugins/haseen.osd" as Osd
ShellRoot {
    id: shellRoot

    property var states: []

    function snap(): var {
        return {
            visible: widget.visible,
            width: widget.implicitWidth,
            text: widget.text,
            main: Keyboard.mainKeyboard,
            layouts: Keyboard.layouts.length,
            shown: osd.shown,
            card: osd.card,
            locks: osd._locks
        };
    }

    function swap(name: string): void {
        Quickshell.execDetached(["cp", "$FX/" + name, "$SANDBOX/devices.json"]);
    }

    FloatingWindow {
        implicitWidth: 200
        implicitHeight: 40
        visible: true

        Kbl.Widget {
            id: widget
            pluginId: "haseen.kblayout"
            height: 28
        }
    }

    Osd.Service {
        id: osd
        pluginId: "haseen.osd"
        settings: JSON.parse(Quickshell.env("OSD_SETTINGS"))
    }

    // The reads at startup land; a switch event, a reload burst and a click.
    Timer {
        interval: 1500
        running: true
        onTriggered: {
            shellRoot.states.push(shellRoot.snap());
            Keyboard.layoutEvent("at-translated-set-2-keyboard,Arabic");
            Keyboard.layoutEvent("power-button,English (US)");
            shellRoot.states.push(shellRoot.snap());
            widget.clicked(Qt.LeftButton);
            widget.clicked(Qt.RightButton);
            shellRoot.swap("devices-caps.json");
            caps.start();
        }
    }

    Timer {
        id: caps
        interval: 600
        onTriggered: {
            osd.lockKeys();
            num.start();
        }
    }

    Timer {
        id: num
        interval: 800
        onTriggered: {
            shellRoot.states.push(shellRoot.snap());
            shellRoot.swap("devices-num-off.json");
            numRead.start();
        }
    }

    Timer {
        id: numRead
        interval: 600
        onTriggered: {
            osd.lockKeys();
            last.start();
        }
    }

    Timer {
        id: last
        interval: 800
        onTriggered: {
            shellRoot.states.push(shellRoot.snap());
            console.warn("RESULT " + JSON.stringify(shellRoot.states));
            Qt.quit();
        }
    }
}
QML
        capture env QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QT_NO_XDG_DESKTOP_PORTAL=1 \
            OSD_SETTINGS="$3" timeout 60 "$QS_BIN" -p "$harness"
        RESULT="$(sed -n 's/^.*RESULT //p' <<<"$OUTPUT" | head -1)"
        HYPRCTL="$(cat "$SANDBOX/hyprctl.log" 2>/dev/null || true)"
        QSLOG="$(cat "$SANDBOX/qs.log" 2>/dev/null || true)"
    }
    s() { jq -c ".[$1]$2" <<<"$RESULT"; }

    # Two layouts, lock keys on.
    kb_run two devices-two.json '{"lockKeys": true}'
    assert_status "the harness completes in the real engine" 0 "$STATUS"
    assert_eq "us,ara: the widget shows EN" '"EN"' "$(s 0 .text)"
    assert_eq "us,ara: the widget takes room" "true" "$(jq '.[0] | .visible and .width > 0' <<<"$RESULT")"
    assert_eq "the main keyboard and its layouts come from one devices read" '["at-translated-set-2-keyboard",2]' \
        "$(jq -c '.[0] | [.main, .layouts]' <<<"$RESULT")"
    assert_eq "startup flashes no OSD (the lock read is only the baseline)" "false" "$(s 0 .shown)"
    assert_eq "the lock baseline" '{"caps":false,"num":true}' "$(s 0 .locks)"
    assert_eq "an activelayout switch: the widget shows AR" '"AR"' "$(s 1 .text)"
    assert_eq "an activelayout switch: the OSD shows the code and the name" \
        '{"glyph":"","text":"AR","label":"Arabic","value":0,"dim":false}' "$(s 1 .card)"
    assert_eq "an activelayout switch shows the OSD" "true" "$(s 1 .shown)"
    assert_contains "a click switches the main keyboard to the next layout" "$HYPRCTL" "switchxkblayout main next"
    assert_not_contains "a right click with two layouts opens no list" "$QSLOG" "panel toggle"
    assert_eq "Caps Lock pressed: one read, the OSD says so" '["Caps Lock on",false]' "$(jq -c '.[2].card | [.label, .dim]' <<<"$RESULT")"
    assert_eq "Num Lock released: the OSD says it is off" '["Num Lock off",true]' "$(jq -c '.[3].card | [.label, .dim]' <<<"$RESULT")"
    assert_eq "devices reads: Keyboard once, the lock baseline, one per key" "4" "$(grep -cx -- '-j devices' <<<"$HYPRCTL")"

    # One layout, lock keys off (the default).
    kb_run one devices-one.json '{}'
    assert_status "the harness completes with one layout" 0 "$STATUS"
    assert_eq "one layout: the widget takes no room" '[false,0]' "$(jq -c '.[0] | [.visible, .width]' <<<"$RESULT")"
    assert_eq "lock keys off: lockkeys reads nothing (only Keyboard's read)" "1" "$(grep -cx -- '-j devices' <<<"$HYPRCTL")"
    assert_eq "lock keys off: no lock card" "null" "$(s 3 .locks)"

    # Three layouts: a right click opens the list.
    kb_run three devices-three.json '{"layout": false}'
    assert_status "the harness completes with three layouts" 0 "$STATUS"
    assert_eq "three layouts: the active one is the Arabic variant" '"AR"' "$(s 0 .text)"
    assert_contains "three layouts: a right click opens the list" "$QSLOG" "call panel toggle haseen.kblayout"
    assert_eq "layout kind off: a switch shows no OSD" "false" "$(s 1 .shown)"
fi
