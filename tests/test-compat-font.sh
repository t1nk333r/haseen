# shellcheck shell=bash
# haseen:covers share/haseen/default/shell.json share/haseen/shell/Compat/**
# haseen:covers share/haseen/shell/Haseen/**
# haseen:covers share/haseen/shell/{Common,Commons,Modules,Services,Ui,Widgets}
# haseen:covers tools/smoke-session.conf
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# Omarchy plugins draw Nerd Font codepoints as plain text in the bar font
# (t1nk33r.omaprayers: "\ueed3" through WidgetButton). Omarchy's family is
# the fontconfig `monospace` alias, so the compat Style and bar facade must
# hand out the monospace. Since plan 115 Theme's own text family is the user's
# monospace too (owner, 2026-10-25), and compat Style takes Theme.font's.
style="$HASEEN_PATH/shell/Compat/Omarchy/Commons/Style.qml"
host="$HASEEN_PATH/shell/Compat/OmarchyHost.qml"
assert_contains "compat Style.fontFamily is Theme.font.family" "$(cat "$style")" "property string fontFamily: Theme.font.family"
assert_contains "compat Style.resolvedFontFamily is Theme.font.resolvedFamily" "$(cat "$style")" "property string resolvedFontFamily: Theme.font.resolvedFamily"
assert_contains "compat Style.menuFontFamily is Theme.font.menuFamily" "$(cat "$style")" "property string menuFontFamily: Theme.font.menuFamily"
assert_contains "Theme's text family is the monospace token" "$(cat "$HASEEN_PATH/shell/Haseen/Theme.qml")" "readonly property string fontFamily: fontMono"
assert_contains "bar facade fontFamily is the monospace token" "$(cat "$host")" "property string fontFamily: Theme.fontMono"
assert_contains "the Omarchy bar host adopts its widget's text" "$(cat "$host")" "BarFonts {"
assert_contains "so does the DMS bar host" "$(cat "$HASEEN_PATH/shell/Compat/DmsHost.qml")" "BarFonts {"
assert_not_contains "no compat family falls back to the sans token" "$(cat "$style" "$host")" "Family: Theme.fontFamily"

QS_BIN=${QS_BIN:-/usr/bin/qs}
if [[ ! -x $QS_BIN ]]; then
    echo "  skip: Quickshell not installed; engine font scenario not run" >&2
else
    sandbox compat-font
    XDG_RUNTIME_DIR="$(mktemp -d "${TMPDIR:-/tmp}/haseen-compat-font.XXXXXX")"
    export XDG_RUNTIME_DIR
    trap 'rm -rf "$XDG_RUNTIME_DIR"' EXIT
    chmod 700 "$XDG_RUNTIME_DIR"
    mkdir -p "$HOME/.config/haseen"
    unset DISPLAY WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE DBUS_SESSION_BUS_ADDRESS
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
import qs.Commons
import qs.Ui
ShellRoot {
    WidgetButton { id: button; text: "\ueed3" }
    Component.onCompleted: {
        console.log("RESULT " + JSON.stringify({
            mono: Theme.fontMono, sans: Theme.fontFamily,
            style: Style.font.family, button: button.fontFamily
        }));
        Qt.quit();
    }
}
QML
    capture env QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME='' QT_QUICK_BACKEND=software QT_NO_XDG_DESKTOP_PORTAL=1 \
        timeout 30 dbus-run-session --config-file="$REPO/tools/smoke-session.conf" -- "$QS_BIN" -p "$harness"
    result="$(sed -n 's/^.*RESULT //p' <<<"$OUTPUT")"
    if [[ -n $result ]]; then
        assert_eq "engine: Style.font.family follows Theme.fontMono" true "$(jq '.style == .mono' <<<"$result")"
        assert_eq "engine: WidgetButton without a bar uses the monospace family" true "$(jq '.button == .mono' <<<"$result")"
        assert_eq "engine: the text family is the monospace (plan 115)" true "$(jq '.mono == .sans' <<<"$result")"
    else
        _fail "font probe result not produced" "$OUTPUT"
    fi

    # Plan 141: a plugin's bar widget draws its text at the bar's size and
    # font, whatever it asks for. Compat/BarFonts.qml walks the widget's
    # visual children; a WidgetButton with a bar adopts the size through
    # adoptBarFont(), so a plugin measuring button.fontSize measures what is
    # drawn. A Text inside a component that owns a fontSize follows it (a
    # plugin's squeezed line). Icons take the bar's icon size and keep their
    # family; Arabic keeps its; text outside the visual tree (a popout) is
    # not touched.
    harness="$SANDBOX/bar-fonts"
    mkdir -p "$harness"
    for module in Haseen Compat Ui Commons; do
        ln -s "$HASEEN_PATH/shell/$module" "$harness/$module"
    done
    cat >"$harness/shell.qml" <<'QML'
import QtQuick
import Quickshell
import qs.Haseen
import qs.Commons
import qs.Ui
import qs.Compat as Compat

ShellRoot {
    QtObject {
        id: fakeBar
        property string fontFamily: Theme.fontMono
        property bool vertical: false
        property int barSize: 30
        property color barForeground: Theme.foreground
        property color urgent: Theme.urgent
        function hideTooltip(t) {}
        function showTooltip(t, s) {}
    }
    Item {
        id: widget
        property Text detached: Text { text: "panel"; font.pixelSize: 7 }
        WidgetButton { id: cell; bar: fakeBar; text: "42%"; fontSize: Style.font.caption; fontFamily: "Serif" }
        WidgetButton { id: iconCell; bar: fakeBar; text: ""; fontSize: Style.font.title }
        WidgetButton { id: helper; text: "x"; fontSize: cell.fontSize * 0.5 }
        Item {
            id: squeezed
            property real fontSize: cell.fontSize - 2
            Text { id: squeezedText; text: "1h 05m"; font.family: Theme.fontMono; font.pixelSize: squeezed.fontSize }
        }
        Text { id: small; text: "12:30"; font.family: "Serif"; font.pixelSize: Style.font.caption }
        Text { id: glyph; text: "󰈷"; font.family: "Symbols Nerd Font"; font.pixelSize: 20 }
        Text { id: arabic; text: "الفجر"; font.family: "Noto Naskh Arabic"; font.pixelSize: Style.font.bodySmall }
        Loader { id: late; active: false; sourceComponent: Text { text: "late"; font.pixelSize: 6 } }
        TextMetrics { id: metrics; font.pixelSize: cell.fontSize; text: "100%" }
    }
    Compat.BarFonts { id: fonts; target: widget }
    function report() {
        const before = small.font.pixelSize, beforeFamily = small.font.family;
        small.text = "";
        console.log("RESULT " + JSON.stringify({
            body: Theme.font.body, icon: Theme.barMetrics.iconFont, mono: Theme.fontMono,
            cell: cell.fontSize, cellFamily: cell.fontFamily, iconCell: iconCell.fontSize,
            helper: helper.fontSize, squeezed: squeezedText.font.pixelSize, small: before, smallFamily: beforeFamily, smallIcon: small.font.pixelSize,
            glyph: glyph.font.pixelSize, glyphFamily: glyph.font.family,
            arabic: arabic.font.pixelSize, arabicFamily: arabic.font.family,
            late: late.item ? late.item.font.pixelSize : -1, metrics: metrics.font.pixelSize,
            detached: widget.detached.font.pixelSize
        }));
        Qt.quit();
    }
    Component.onCompleted: {
        late.active = true;
        Qt.callLater(() => Qt.callLater(report));
    }
}
QML
    capture env QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME='' QT_QUICK_BACKEND=software QT_NO_XDG_DESKTOP_PORTAL=1 \
        timeout 30 dbus-run-session --config-file="$REPO/tools/smoke-session.conf" -- "$QS_BIN" -p "$harness"
    result="$(sed -n 's/^.*RESULT //p' <<<"$OUTPUT")"
    if [[ -n $result ]]; then
        assert_eq "bar: a caption WidgetButton draws at the text size" true "$(jq '.cell == .body' <<<"$result")"
        assert_eq "bar: in the bar font, not the plugin's" true "$(jq '.cellFamily == .mono' <<<"$result")"
        assert_eq "bar: an icon WidgetButton draws at the bar's icon size" true "$(jq '.iconCell == .icon' <<<"$result")"
        assert_eq "bar: a button without a bar follows its owner's size" true "$(jq '.helper == (.body * 0.5)' <<<"$result")"
        assert_eq "bar: a Text in a component with a fontSize follows that fontSize" true "$(jq '.squeezed == (.body - 2)' <<<"$result")"
        assert_eq "bar: a plugin's own Text takes the text size" true "$(jq '.small == .body' <<<"$result")"
        assert_eq "bar: in the bar font" true "$(jq '.smallFamily == .mono' <<<"$result")"
        assert_eq "bar: and the icon size when it turns into an icon" true "$(jq '.smallIcon == .icon' <<<"$result")"
        assert_eq "bar: an nf-md icon (a surrogate pair) is an icon" true "$(jq '.glyph == .icon' <<<"$result")"
        assert_eq "bar: an icon keeps its family" '"Symbols Nerd Font"' "$(jq '.glyphFamily' <<<"$result")"
        assert_eq "bar: Arabic takes the text size" true "$(jq '.arabic == .body' <<<"$result")"
        assert_eq "bar: and keeps its family" '"Noto Naskh Arabic"' "$(jq '.arabicFamily' <<<"$result")"
        assert_eq "bar: a child a Loader adds later is adopted" true "$(jq '.late == .body' <<<"$result")"
        assert_eq "bar: TextMetrics at button.fontSize measures the drawn size" true "$(jq '.metrics == .body' <<<"$result")"
        assert_eq "bar: text outside the visual tree is untouched" 7 "$(jq '.detached' <<<"$result")"
    else
        _fail "bar font probe result not produced" "$OUTPUT"
    fi
fi
