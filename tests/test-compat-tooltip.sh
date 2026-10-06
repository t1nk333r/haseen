# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# The bar facade's tooltip for Omarchy widgets behaves like upstream Bar.qml:
# it appears only after 400 ms of hover, re-checks the hover when it would
# appear, drops as soon as the pointer leaves, and never sits on top of the
# widget's own open panel (t1nk33r.agents on io: the tooltip stayed drawn over
# the panel the click had just opened).
QS_BIN=${QS_BIN:-/usr/bin/qs}
if [[ ! -x $QS_BIN ]]; then
    echo "  skip: Quickshell not installed; tooltip scenario not run" >&2
else
    sandbox compat-tooltip
    XDG_RUNTIME_DIR="$(mktemp -d "${TMPDIR:-/tmp}/haseen-compat-tooltip.XXXXXX")"
    export XDG_RUNTIME_DIR
    trap 'rm -rf "$XDG_RUNTIME_DIR"' EXIT
    chmod 700 "$XDG_RUNTIME_DIR"
    unset DISPLAY WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE DBUS_SESSION_BUS_ADDRESS
    plugin="$HOME/.config/omarchy/plugins/me.tip"
    mkdir -p "$HOME/.config/haseen" "$plugin"
    cat >"$plugin/manifest.json" <<'JSON'
{"schemaVersion":1,"id":"me.tip","name":"Tip","version":"1.0.0","kinds":["bar-widget"],"entryPoints":{"barWidget":"Widget.qml"}}
JSON
    # A widget the probe can hover without a pointer, plus a child item with no
    # tooltipHovered of its own (a plugin's custom target).
    cat >"$plugin/Widget.qml" <<'QML'
import QtQuick
Item {
    property var bar
    property var settings
    property string moduleName
    property bool tooltipHovered: false
    property alias plain: plainTarget
    implicitWidth: 12
    implicitHeight: 12
    Item { id: plainTarget; width: 4; height: 4 }
}
QML
    printf '%s\n' '{"bar":{"left":[],"center":[],"right":[]},"plugins":{"me.tip":{"enabled":true}}}' >"$HOME/.config/haseen/shell.json"
    harness="$SANDBOX/shell"
    mkdir -p "$harness"
    for module in Haseen Compat Ui Commons; do
        ln -s "$HASEEN_PATH/shell/$module" "$harness/$module"
    done
    ln -s "$HASEEN_PATH/shell/plugins" "$harness/plugins"
    cat >"$harness/shell.qml" <<'QML'
import QtQuick
import Quickshell
import qs.Haseen
import qs.Compat as Compat
ShellRoot {
    id: probe
    property var result: ({})
    property int step: 0
    property double mark: 0
    readonly property var host: loader.item
    readonly property var bar: host ? host.barApi : null
    readonly property var widget: host ? host.widget : null
    function since() { return Date.now() - mark; }
    function show(target) { mark = Date.now(); bar.showTooltip(target, "Limits: 3"); }
    function finish() { console.log("RESULT " + JSON.stringify(result)); Qt.quit(); }
    LazyLoader {
        id: loader
        active: Plugins.ready
        Compat.OmarchyHost { pluginId: "me.tip"; kind: "bar-widget" }
    }
    Timer {
        interval: 25
        repeat: true
        running: true
        onTriggered: {
            if (!probe.widget) return;
            const w = probe.widget, b = probe.bar, r = probe.result;
            switch (probe.step) {
            case 0:
                w.tooltipHovered = true; probe.show(w);
                r.immediate = b.tooltipVisible; probe.step = 1; break;
            case 1:
                if (probe.since() < 200) break;
                r.at200ms = b.tooltipVisible; probe.step = 2; break;
            case 2:
                if (probe.since() < 500) break;
                r.at500ms = b.tooltipVisible;
                w.tooltipHovered = false;
                r.afterLeave = b.tooltipVisible;
                // Left before the delay ran out: the reveal re-checks the hover.
                w.tooltipHovered = true; probe.show(w); w.tooltipHovered = false;
                probe.step = 3; break;
            case 3:
                if (probe.since() < 500) break;
                r.leftDuringDelay = b.tooltipVisible;
                w.tooltipHovered = true; probe.show(w); probe.step = 4; break;
            case 4:
                if (probe.since() < 500) break;
                r.beforeOpen = b.tooltipVisible;
                r.requested = b.requestPopout(w);   // the widget's own panel opens
                r.whenOpened = b.tooltipVisible;
                probe.show(w);                      // hover re-enters while it is open
                probe.step = 5; break;
            case 5:
                if (probe.since() < 500) break;
                r.whileOpen = b.tooltipVisible;
                b.releasePopout(w); probe.show(w); probe.step = 6; break;
            case 6:
                if (probe.since() < 500) break;
                r.afterClose = b.tooltipVisible;
                probe.mark = Date.now(); b.showTooltip(w, ""); probe.step = 7; break;
            case 7:
                if (probe.since() < 500) break;
                r.emptyText = b.tooltipVisible;
                probe.show(w.plain); probe.step = 8; break;
            case 8:
                if (probe.since() < 500) break;
                r.plainTarget = b.tooltipVisible;
                b.hideTooltip(w.plain);
                r.afterHide = b.tooltipVisible;
                probe.finish();
            }
        }
    }
}
QML
    capture env QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME='' QT_QUICK_BACKEND=software QT_NO_XDG_DESKTOP_PORTAL=1 \
        timeout 30 dbus-run-session --config-file="$REPO/tools/smoke-session.conf" -- "$QS_BIN" -p "$harness"
    result="$(sed -n 's/^.*RESULT //p' <<<"$OUTPUT")"
    if [[ -n $result ]]; then
        assert_eq "no tooltip the moment the hover starts" false "$(jq -r .immediate <<<"$result")"
        assert_eq "still none 200 ms into the hover" false "$(jq -r .at200ms <<<"$result")"
        assert_eq "shown once the hover has lasted 400 ms" true "$(jq -r .at500ms <<<"$result")"
        assert_eq "gone as soon as the pointer leaves" false "$(jq -r .afterLeave <<<"$result")"
        assert_eq "a hover that ended inside the delay shows nothing" false "$(jq -r .leftDuringDelay <<<"$result")"
        assert_eq "shown before the widget's panel opens" true "$(jq -r .beforeOpen <<<"$result")"
        assert_eq "the widget's panel takes the popout" true "$(jq -r .requested <<<"$result")"
        assert_eq "hidden the moment the widget's panel opens" false "$(jq -r .whenOpened <<<"$result")"
        assert_eq "hovering the mark keeps it hidden while the panel is open" false "$(jq -r .whileOpen <<<"$result")"
        assert_eq "shown again after the panel closes" true "$(jq -r .afterClose <<<"$result")"
        assert_eq "empty text shows nothing" false "$(jq -r .emptyText <<<"$result")"
        assert_eq "a target without tooltipHovered still gets its tooltip" true "$(jq -r .plainTarget <<<"$result")"
        assert_eq "hideTooltip removes it" false "$(jq -r .afterHide <<<"$result")"
    else
        _fail "tooltip result not produced" "$OUTPUT"
    fi
fi
