# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }

QS_BIN=${QS_BIN:-/usr/bin/qs}
QML_BIN=${QML_BIN:-/usr/lib/qt6/bin/qml}

sandbox clock-dayname

# --- Qt JS formatter behavior -------------------------------------------------
if [[ ! -x $QML_BIN ]]; then
    _fail "day-name formatter runs in Qt's JS engine" "$QML_BIN is unavailable"
else
    units="$SANDBOX/DayName.qml"
    cat >"$units" <<EOF
import QtQuick
import "file://$HASEEN_PATH/shell/Haseen/ClockDayName.js" as DayName

Window {
    property int failures: 0

    function eq(name, expected, actual) {
        if (expected === actual)
            console.warn("DAYNAME-PASS " + name);
        else {
            failures++;
            console.warn("DAYNAME-FAIL " + name + " expected " + JSON.stringify(expected) + " got " + JSON.stringify(actual));
        }
    }

    Component.onCompleted: {
        try {
            eq("unset follows an existing long day name", "dddd HH:mm", DayName.effectiveFormat("dddd HH:mm", undefined, false));
            eq("unset leaves a time-only format alone", "HH:mm", DayName.effectiveFormat("HH:mm", undefined, false));
            eq("on prefixes a horizontal time-only format", "dddd HH:mm", DayName.effectiveFormat("HH:mm", true, false));
            eq("on does not duplicate dddd", "dddd HH:mm", DayName.effectiveFormat("dddd HH:mm", true, false));
            eq("on does not duplicate ddd", "ddd HH:mm", DayName.effectiveFormat("ddd HH:mm", true, false));
            eq("off removes dddd and its space", "HH:mm", DayName.effectiveFormat("dddd HH:mm", false, false));
            eq("off removes ddd and its comma separator", "HH:mm", DayName.effectiveFormat("ddd, HH:mm", false, false));
            eq("off trims a trailing ddd", "HH:mm", DayName.effectiveFormat("HH:mm ddd", false, false));
            eq("on prefixes a vertical format on its own line", "dddd\\nHH\\nmm", DayName.effectiveFormat("HH\\nmm", true, true));
            eq("off removes a vertical day line", "HH\\nmm", DayName.effectiveFormat("dddd\\nHH\\nmm", false, true));
            eq("day-name detection recognizes ddd and dddd", true, DayName.hasDayName("ddd HH:mm") && DayName.hasDayName("dddd HH:mm"));
            eq("quoted day letters are not a token", false, DayName.hasDayName("'dddd' HH:mm"));
            eq("off preserves quoted day letters", "'ddd' HH:mm", DayName.effectiveFormat("'ddd' HH:mm", false, false));
            eq("unset visibility follows an existing day token", true, DayName.isShown("ddd HH:mm", undefined));
            eq("explicit off overrides a day token", false, DayName.isShown("dddd HH:mm", false));
            eq("five d characters include a day-name token", true, DayName.hasDayName("ddddd HH:mm"));
            eq("on does not duplicate the five-d Qt token", "ddddd HH:mm", DayName.effectiveFormat("ddddd HH:mm", true, false));
            eq("off preserves the numeric day in a five-d token", "d HH:mm", DayName.effectiveFormat("ddddd HH:mm", false, false));
            eq("six d characters include a day-name token", true, DayName.hasDayName("dddddd HH:mm"));
            eq("on does not duplicate the six-d Qt token", "dddddd HH:mm", DayName.effectiveFormat("dddddd HH:mm", true, false));
            eq("off preserves the numeric day in a six-d token", "dd HH:mm", DayName.effectiveFormat("dddddd HH:mm", false, false));
            eq("off preserves time-only trailing punctuation", "HH:mm -", DayName.effectiveFormat("HH:mm -", false, false));
            eq("off strips an Arabic comma separator", "HH:mm", DayName.effectiveFormat("dddd، HH:mm", false, false));
            eq("an escaped apostrophe does not hide a day token", true, DayName.hasDayName("\x27\x27dddd HH:mm"));
            eq("off preserves quoted text and numeric dates", "\x27dddd\x27 dd/MM/yyyy HH:mm", DayName.effectiveFormat("dddd, \x27dddd\x27 dd/MM/yyyy HH:mm", false, false));
            eq("Qt decomposes five d characters as long name plus numeric day", "Thursday8 12:18", Qt.formatDateTime(new Date(2026, 9, 8, 12, 18), "ddddd HH:mm"));
            eq("Qt decomposes six d characters as long name plus padded numeric day", "Thursday08 12:18", Qt.formatDateTime(new Date(2026, 9, 8, 12, 18), "dddddd HH:mm"));
            eq("Arabic localized day token", new Date(2026, 9, 8, 12, 18).toLocaleString(Qt.locale("ar_EG"), "dddd HH:mm"), new Date(2026, 9, 8, 12, 18).toLocaleString(Qt.locale("ar_EG"), DayName.effectiveFormat("HH:mm", true, false)));
            console.warn("QT-FORMAT five-d=" + Qt.formatDateTime(new Date(2026, 9, 8, 12, 18), "ddddd HH:mm"));
            console.warn("QT-FORMAT six-d=" + Qt.formatDateTime(new Date(2026, 9, 8, 12, 18), "dddddd HH:mm"));
        } catch (e) {
            failures++;
            console.warn("DAYNAME-FAIL exception " + e);
        }
        Qt.exit(failures > 0 ? 1 : 0);
    }
}
EOF
    capture env QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME='' QT_QUICK_BACKEND=software QT_NO_XDG_DESKTOP_PORTAL=1 \
        QT_FORCE_STDERR_LOGGING=1 NO_AT_BRIDGE=1 timeout 60 "$QML_BIN" "$units"
    assert_status "day-name formatter runs in Qt's JS engine" 0 "$STATUS"
    assert_eq "all formatter cases pass" 28 "$(grep -c 'DAYNAME-PASS' <<<"$OUTPUT" || true)"
    assert_not_contains "formatter cases have no mismatches" "$OUTPUT" "DAYNAME-FAIL"
fi

# --- calendar toggle and clock update in Quickshell --------------------------
if [[ ! -x $QS_BIN ]] || ! command -v dbus-run-session >/dev/null; then
    _fail "calendar toggle runs in Quickshell" "qs or dbus-run-session is unavailable"
else
    mkdir -p "$XDG_CONFIG_HOME/haseen"
    cfg="$XDG_CONFIG_HOME/haseen/shell.json"
    printf '%s\n' '{"plugins":{"haseen.clock":{"settings":{"format":"dddd HH:mm"}}}}' >"$cfg"

    FAKE="$SANDBOX/fake"
    mkdir -p "$FAKE/share/haseen" "$FAKE/bin"
    for entry in "$HASEEN_PATH"/*; do ln -s "$entry" "$FAKE/share/haseen/${entry##*/}"; done
    cat >"$FAKE/bin/haseen-plugin-settings" <<EOF
#!/usr/bin/env bash
sleep 1
exec "$REPO/bin/haseen-plugin-settings" "\$@"
EOF
    chmod +x "$FAKE/bin/haseen-plugin-settings"

    harness="$SANDBOX/shell"
    mkdir -p "$harness"
    for module in Haseen Compat Ui Commons; do
        ln -s "$HASEEN_PATH/shell/$module" "$harness/$module"
    done
    ln -s "$HASEEN_PATH/shell/plugins" "$harness/plugins"
    cat >"$harness/shell.qml" <<'QML'
import QtQuick
import Quickshell
import "plugins/haseen.calendar" as Calendar
import Quickshell.Io
import qs.Haseen
import "plugins/haseen.clock" as Clock
import QtTest

ShellRoot {
    id: shell
    property var panel: calendarLoader.item
    function find(item, name) {
        if (item.objectName === name)
            return item;
        for (const child of item.children) {
            const hit = find(child, name);
            if (hit)
                return hit;
        }
        return null;
    }

    function clickDayName(): bool {
        const toggle = find(panel, "clockDayNameToggle");
        if (!toggle)
            return false;
        toggle.clicked();
        return true;
    }

    function keyboardToggle(): bool {
        return events.keyClick(Qt.Key_Tab, 0, -1) && events.keyClick(Qt.Key_Space, 0, -1);
    }

    Window {
        width: 420
        height: 560
        visible: true
        Component.onCompleted: requestActivate()

        Loader {
            id: calendarLoader
            sourceComponent: Calendar.Panel {
                pluginId: "haseen.calendar"
                settings: ({ debugIpc: true })
            }
        }

        Item {
            TestEvent {
                id: events
            }
        }
    }
    Window {
        width: 240
        height: 40
        visible: false

        Clock.Widget {
            id: clock
            pluginId: "haseen.clock"
            settings: Plugins.settingsFor("haseen.clock")
            vertical: Config.barVertical
        }

    }
    IpcHandler {
        target: "dayNameTest"

        function state(): string {
            const config = Plugins.settingsFor("haseen.clock");
            const toggle = find(panel, "clockDayNameToggle");
            return JSON.stringify({
                dayNameShown: panel ? panel.dayNameShown : null,
                setting: config.showDayName,
                format: clock.format,
                toggle: toggle ? toggle.text : "missing",
                focused: toggle ? toggle.activeFocus : false
            });
        }
        function closePanel(): bool { calendarLoader.active = false; return true; }
        function openPanel(): bool { calendarLoader.active = true; return true; }
        function vertical(): bool { Config.setRuntime(["bar", "position"], "left"); return true; }

        function click(): bool {
            return clickDayName();
        }

        function keyboardToggle(): bool {
            return shell.keyboardToggle();
        }
    }
}
QML

    qs_runtime="$(mktemp -d /tmp/clock-dayname.XXXXXX)"
    chmod 0700 "$qs_runtime"
    setsid env -u WAYLAND_DISPLAY XDG_RUNTIME_DIR="$qs_runtime" QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME='' QT_QUICK_BACKEND=software \
        QT_NO_XDG_DESKTOP_PORTAL=1 HASEEN_PATH="$FAKE/share/haseen" \
        timeout 120 dbus-run-session --config-file="$REPO/tools/smoke-session.conf" -- "$QS_BIN" -p "$harness" \
        >"$SANDBOX/qs.log" 2>&1 &
    qs_pid=$!

    cleanup_clock_dayname() {
        kill -- -"$qs_pid" 2>/dev/null || true
        wait "$qs_pid" 2>/dev/null || true
        rm -rf -- "$qs_runtime"
    }
    trap cleanup_clock_dayname EXIT

    ipc() { XDG_RUNTIME_DIR="$qs_runtime" "$QS_BIN" -p "$harness" ipc call "$@" 2>/dev/null; }
    state() { ipc dayNameTest state; }
    until_state() {
        local label=$1 condition=$2 current="" i
        for ((i = 0; i < 100; i++)); do
            current="$(state || true)"
            if [[ -n $current ]] && jq -e "$condition" <<<"$current" >/dev/null 2>&1; then
                _pass
                return 0
            fi
            sleep 0.1
        done
        _fail "$label" "state: $(jq -c . <<<"$current" 2>/dev/null || echo "$current")$(printf '\n')$(tail -n 20 "$SANDBOX/qs.log")"
    }
    until_saved() {
        local label=$1 expected=$2 i
        for ((i = 0; i < 100; i++)); do
            if [[ $(jq -r 'if .plugins["haseen.clock"].settings | has("showDayName") then .plugins["haseen.clock"].settings.showDayName else "absent" end' "$cfg") == "$expected" ]]; then
                _pass
                return 0
            fi
            sleep 0.1
        done
        _fail "$label" "saved config: $(jq -c . "$cfg")$(printf '\n')$(tail -n 20 "$SANDBOX/qs.log")"
    }

    until_state "unset setting initially reflects the existing day name" \
        '.dayNameShown == true and .setting == null and .format == "dddd HH:mm" and .toggle == "On"'
    ipc dayNameTest click >/dev/null
    until_state "turning the pill off updates the live bar format" \
        '.dayNameShown == false and .setting == false and .format == "HH:mm" and .toggle == "Off"'
    until_saved "turning the pill off persists showDayName=false" false
    assert_eq "persisting the setting preserves the source format" "dddd HH:mm" \
        "$(jq -r '.plugins["haseen.clock"].settings.format' "$cfg")"

    ipc dayNameTest keyboardToggle >/dev/null
    until_state "turning the pill on updates the live bar format" \
        '.dayNameShown == true and .setting == true and .format == "dddd HH:mm" and .toggle == "On" and .focused == true'
    until_saved "turning the pill on persists showDayName=true" true
    ipc dayNameTest click >/dev/null
    ipc dayNameTest click >/dev/null
    until_saved "first queued Off value reaches disk" false
    sleep 0.2
    current="$(state)"
    assert_eq "queued latest On remains live while earlier Off reloads" true "$(jq -r .dayNameShown <<<"$current")"
    assert_eq "toggle remains On while newest value is pending" "On" "$(jq -r .toggle <<<"$current")"
    until_saved "latest queued On value eventually persists" true

    ipc dayNameTest vertical >/dev/null
    until_state "vertical clock gains separate day line" '.dayNameShown == true and .format == "dddd\nHH\nmm"'
    ipc dayNameTest click >/dev/null
    until_state "vertical toggle removes day line live" '.dayNameShown == false and .format == "HH\nmm"'
    until_saved "vertical Off persists" false

    ipc dayNameTest click >/dev/null
    ipc dayNameTest closePanel >/dev/null
    assert_eq "panel closes before delayed preference write" false "$(jq -r '.plugins["haseen.clock"].settings.showDayName' "$cfg")"
    until_saved "closing panel preserves the accepted setting write" true
    ipc dayNameTest openPanel >/dev/null
    until_state "reopened panel reflects the persisted day name" '.dayNameShown == true and .setting == true and .toggle == "On"'

    cleanup_clock_dayname
    trap - EXIT
fi
