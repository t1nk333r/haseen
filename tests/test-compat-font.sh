# shellcheck shell=bash
# Omarchy plugins draw Nerd Font codepoints as plain text in the bar font
# (t1nk33r.omaprayers: "\ueed3" through WidgetButton). Omarchy's family is
# the fontconfig `monospace` alias, so the compat Style and bar facade must
# hand out Theme.fontMono, never the sans Theme.fontFamily.
style="$HASEEN_PATH/shell/Compat/Omarchy/Commons/Style.qml"
host="$HASEEN_PATH/shell/Compat/OmarchyHost.qml"
for prop in fontFamily resolvedFontFamily menuFontFamily; do
    assert_contains "compat Style.$prop is the monospace token" "$(cat "$style")" "property string $prop: Theme.fontMono"
done
assert_contains "bar facade fontFamily is the monospace token" "$(cat "$host")" "property string fontFamily: Theme.fontMono"
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
        assert_eq "engine: monospace differs from sans default" true "$(jq '.mono != .sans' <<<"$result")"
    else
        _fail "font probe result not produced" "$OUTPUT"
    fi
fi
