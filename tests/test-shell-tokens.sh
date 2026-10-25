# shellcheck shell=bash
# haseen:covers share/haseen/shell/Haseen/{Theme,Config}.qml share/haseen/shell/Haseen/BorderGeometry.js
# haseen:covers share/haseen/shell/Haseen/Widgets/** share/haseen/shell/{PanelPopup.qml,PanelPlacement.js}
# haseen:covers share/haseen/shell/Compat/Omarchy/Commons/{Style,Color}.qml
# haseen:covers share/haseen/shell/Compat/Omarchy/Commons/BorderGeometry.js
# haseen:covers share/haseen/themed/shell.json.tpl share/haseen/default/shell.json
# haseen:covers share/haseen/layers/theme/theme-lib.sh bin/haseen-theme-set
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# Plan 115: the shell's tokens are Omarchy 4.5's. shell.json carries the
# values Omarchy's default/themed/shell.toml.tpl renders (pinned below from
# v4.5.0-rc1), Theme derives Omarchy's type scale, spacing, state tokens and
# surfaces from them, its radius and edge gap follow Hyprland's rounding and
# half its gaps_out on start and on `configreloaded` (never polled), the font
# is the user's monospace, the compat Style and Color are Theme's, and the
# screen frame is off by default.

TPL="$HASEEN_PATH/themed/shell.json.tpl"

# --- the template carries Omarchy's shell.toml.tpl, key for key ---------------
# Omarchy default/themed/shell.toml.tpl@v4.5.0-rc1, its uncommented keys in
# file order as section.key and the value it renders (lines 7-235).
OMARCHY_SHELL_TOML='bar.background	{{ background }}
bar.background-alpha	1.0
bar.text	{{ foreground }}
bar.active	{{ red }}
bar.scale-with-font	true
bar.size-horizontal	26
bar.size-vertical	28
hyprland.active-border	{{ shell_gradient hyprland_active_border accent }}
hyprland.active-border-foreground	{{ shell_gradient hyprland_active_border foreground }}
controls.normal-color	{{ foreground }}
controls.normal-fill-alpha	0.04
controls.normal-border	{{ foreground }}
controls.normal-border-width	1
controls.normal-border-alpha	0.4
controls.hover-cursor-color	{{ foreground }}
controls.hover-cursor-fill-alpha	0.08
controls.hover-cursor-border	{{ foreground }}
controls.hover-cursor-border-width	1
controls.hover-cursor-border-alpha	0.25
controls.focus-color	{{ foreground }}
controls.focus-fill-alpha	0.08
controls.focus-border	{{ foreground }}
controls.focus-border-width	1
controls.focus-border-alpha	0.25
controls.selected-color	{{ foreground }}
controls.selected-fill-alpha	0.18
controls.selected-border	{{ foreground }}
controls.selected-border-width	0
controls.selected-border-alpha	1.0
controls.pressed-fill-alpha	0.22
controls.selection-fill-alpha	0.35
spacing.scale	1.0
spacing.scale-with-font	true
font.base-size	12
popups.background	{{ background }}
popups.background-alpha	1.0
popups.text	{{ foreground }}
popups.border	hyprland.active-border
popups.border-alpha	1.0
tooltip.background	{{ background }}
tooltip.background-alpha	0.97
tooltip.text	{{ foreground }}
tooltip.border	hyprland.active-border-foreground
tooltip.border-alpha	1.0
notifications.background	{{ background }}
notifications.background-alpha	1.0
notifications.text	{{ foreground }}
notifications.border	hyprland.active-border
notifications.border-alpha	1.0
notifications.countdown	{{ accent }}
launcher.background	{{ background }}
launcher.background-alpha	0.95
launcher.text	{{ foreground }}
launcher.border	hyprland.active-border-foreground
launcher.border-alpha	1.0
launcher.scrim	{{ background }}
launcher.scrim-alpha	0.5
launcher.selected-background	{{ foreground }}
launcher.selected-background-alpha	0.08
launcher.selected-text	{{ accent }}
launcher.selected-border	hyprland.active-border-foreground
launcher.selected-border-alpha	0.25
menu.background	{{ background }}
menu.background-alpha	1.0
menu.text	{{ foreground }}
menu.border	hyprland.active-border-foreground
menu.border-alpha	1.0
menu.scrim	{{ background }}
menu.scrim-alpha	0.5
menu.selected-background	{{ foreground }}
menu.selected-background-alpha	0.08
menu.selected-text	{{ accent }}
menu.selected-border	hyprland.active-border-foreground
menu.selected-border-alpha	0.25
polkit.background	{{ background }}
polkit.background-alpha	1.0
polkit.text	{{ foreground }}
polkit.text-error	{{ red }}
polkit.border	hyprland.active-border
polkit.border-error	{{ red }}
polkit.border-alpha	1.0
polkit.scrim	{{ background }}
polkit.scrim-alpha	0.5
polkit.accent	{{ accent }}
lock.background	{{ background }}
lock.background-alpha	0.8
lock.text	{{ foreground }}
lock.placeholder	{{ mix foreground background 34% }}
lock.text-error	{{ red }}
lock.border	hyprland.active-border
lock.border-active	hyprland.active-border
lock.border-error	{{ red }}
lock.border-alpha	1.0
lock.selection	{{ accent }}
lock.selection-alpha	0.45
image-picker.text	{{ foreground }}
image-picker.selected-border	{{ accent }}
image-picker.selected-border-alpha	1.0
image-picker.unselected-border	{{ foreground }}
image-picker.unselected-border-alpha	0.28'
tpl_values="$(sed -n '/"shellValues": {/,/^  }/p' "$TPL" | sed -n 's/^    "\([^"]*\)": "\([^"]*\)",\{0,1\}$/\1\t\2/p')"
assert_eq "shellValues are Omarchy's shell.toml.tpl keys and values, in order" "$OMARCHY_SHELL_TOML" "$tpl_values"
assert_contains "the shell's font is the user's monospace (owner, 2026-10-25)" "$(cat "$TPL")" '"fontFamily": "{{ font_mono }}",'
assert_contains "the base size is Omarchy's [font] base-size" "$(cat "$TPL")" '"fontSize": 12,'

# --- rendered for themes with and without a gradient active border -----------
token_sandbox() {
    sandbox "$1"
    stub pgrep 'exit 1'
    unset HYPRLAND_INSTANCE_SIGNATURE HASEEN_THEME_HEADLESS
    export HASEEN_THEME_FETCH=0 XDG_RUNTIME_DIR="$SANDBOX/run"
    mkdir -p "$XDG_RUNTIME_DIR" && chmod 700 "$XDG_RUNTIME_DIR"
    SJ="$HOME/.local/state/haseen/current/theme/shell.json"
}
sv() { jq -r --arg k "$1" '.shellValues[$k]' "$SJ"; }

token_sandbox shell-tokens-render
for case in "tokyo-night|#7aa2f7|#a9b1d6" "catppuccin-latte|#1e66f5|#4c4f69" \
    "solitude|rgba(798186ee) rgba(caccccee)|rgba(798186ee) rgba(caccccee)" \
    "hackerman|rgba(26a269ee) rgba(2ec27eee) 45deg|rgba(26a269ee) rgba(2ec27eee) 45deg"; do
    IFS='|' read -r t border fgborder <<<"$case"
    capture haseen theme set "$t"
    assert_status "$t renders" 0 "$STATUS"
    assert_eq "$t: hyprland.active-border is its Hyprland border or accent" "$border" "$(sv hyprland.active-border)"
    assert_eq "$t: active-border-foreground falls back to foreground" "$fgborder" "$(sv hyprland.active-border-foreground)"
    assert_eq "$t: popups bordered with the active border" "hyprland.active-border" "$(sv popups.border)"
    assert_eq "$t: fontFamily = fontMono" "$(jq -r .fontMono "$SJ")" "$(jq -r .fontFamily "$SJ")"
    if [[ $t == tokyo-night ]]; then
        assert_eq "lock.placeholder = mix foreground background 34%" "#787e9a" "$(sv lock.placeholder)"
        assert_eq "the background tokens are Omarchy's, filled in" "#1a1b26 1.0 #a9b1d6" "$(sv popups.background) $(sv popups.background-alpha) $(sv bar.text)"
    fi
done
# `haseen font set` reaches the shell's text, not only its icons.
mkdir -p "$HOME/.config/haseen"
printf 'Fira Code\n' >"$HOME/.config/haseen/font"
capture haseen theme set tokyo-night
assert_eq "the user's font is the shell's text font" "Fira Code Fira Code" "$(jq -r '"\(.fontFamily) \(.fontMono)"' "$SJ")"
rm -f "$HOME/.config/haseen/font"

# --- the engine --------------------------------------------------------------
QS_BIN=${QS_BIN:-/usr/bin/qs}
if [[ ! -x $QS_BIN ]] || ! command -v python3 >/dev/null; then
    echo "  skip: qs or python3 missing; Theme was not run in the engine" >&2
else
    # A short private runtime dir: Hyprland's socket path must fit 108 bytes.
    RUNTIME="$(mktemp -d "${TMPDIR:-/tmp}/hst.XXXXXX")"
    chmod 700 "$RUNTIME"
    # Hyprland's event socket (socket2) sends `configreloaded` at second
    # $1; the request socket answers every query with an empty list.
    cat >"$RUNTIME/hypr.py" <<'PY'
import os, socket, sys, threading, time
d, at = sys.argv[1], float(sys.argv[2])
def serve(name, handler):
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.bind(os.path.join(d, name))
    s.listen(8)
    while True:
        c, _ = s.accept()
        threading.Thread(target=handler, args=(c,), daemon=True).start()
def events(c):
    if at > 0:
        time.sleep(at)
        c.sendall(b"configreloaded>>\n")
    time.sleep(60)
def requests(c):
    c.recv(4096)
    c.sendall(b"[]")
    c.close()
threading.Thread(target=serve, args=(".socket2.sock", events), daemon=True).start()
threading.Thread(target=serve, args=(".socket.sock", requests), daemon=True).start()
time.sleep(60)
PY
    # hyprctl answers getoption from $HYPR_VALUES: "ROUNDING GAPS ANIMATIONS".
    hypr_stub() {
        stub hyprctl 'read -r r g a <"$HYPR_VALUES"
case "$*" in
*decoration:rounding*) echo "{\"option\":\"decoration:rounding\",\"int\":$r,\"set\":true}" ;;
*general:gaps_out*) echo "{\"option\":\"general:gaps_out\",\"css\":\"$g $g $g $g\",\"set\":true}" ;;
*animations:enabled*) echo "{\"option\":\"animations:enabled\",\"bool\":$a}" ;;
*) exit 1 ;;
esac'
    }
    harness() {
        H="$SANDBOX/shell"
        rm -rf "$H"
        mkdir -p "$H"
        local m
        for m in Haseen Compat Ui Commons plugins; do ln -s "$HASEEN_PATH/shell/$m" "$H/$m"; done
        cat >"$H/shell.qml"
    }
    # qs_run EVENT_AT — run the harness with a Hyprland that reloads at
    # EVENT_AT seconds (0: never); RESULT lines land in OUTPUT.
    qs_run() {
        local sig=hst$$ pid status=0
        rm -rf "$RUNTIME/hypr" "$RUNTIME/run"
        mkdir -p "$RUNTIME/hypr/$sig" "$RUNTIME/run"
        chmod 700 "$RUNTIME/run"
        ln -s "$RUNTIME/hypr" "$RUNTIME/run/hypr"
        setsid python3 -I "$RUNTIME/hypr.py" "$RUNTIME/hypr/$sig" "$1" >/dev/null 2>&1 &
        pid=$!
        local i
        for i in $(seq 50); do [[ -S $RUNTIME/hypr/$sig/.socket2.sock ]] && break; sleep 0.1; done
        setsid env XDG_RUNTIME_DIR="$RUNTIME/run" HYPRLAND_INSTANCE_SIGNATURE="$sig" HYPR_VALUES="$HYPR_VALUES" \
            QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME='' QT_QUICK_BACKEND=software \
            timeout -k 5 40 "$QS_BIN" -p "$H" >"$SANDBOX/qs.out" 2>&1 &
        local group=$!
        wait "$group" || status=$?
        kill -- -"$group" 2>/dev/null || true
        kill -- -"$pid" 2>/dev/null || kill "$pid" 2>/dev/null || true
        OUTPUT="$(cat "$SANDBOX/qs.out")"
        RESULT="$(sed -n 's/^.*RESULT //p' <<<"$OUTPUT" | tail -n1)"
        [[ -n $RESULT ]] || _fail "the token harness produced a result (exit $status)" "$OUTPUT"
    }
    r() { jq -r "$1" <<<"$RESULT"; }

    # 1. tokyo-night, Hyprland at rounding 7 and gaps_out 10, then a reload
    # to rounding 3 and gaps_out 4. The values change before the event is
    # sent: Theme must not see them until Hyprland announces the reload.
    token_sandbox shell-tokens-engine
    capture haseen theme set tokyo-night
    hypr_stub
    HYPR_VALUES="$SANDBOX/hypr-values"
    printf '7 10 true\n' >"$HYPR_VALUES"
    harness <<QML
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Haseen
import qs.Haseen.Widgets
import qs.Commons as Commons
ShellRoot {
    id: probe
    property var result: ({})
    property int step: 0
    readonly property var t: Theme
    function snap() {
        return {
            radius: Theme.radius, cornerRadius: Theme.cornerRadius, gapsOut: Theme.gapsOut,
            reduce: Theme.reduceMotion, d140: Theme.duration(140)
        };
    }
    Item {
        id: holder
        PanelSurface { id: card; Rectangle { width: 100; height: 50 } }
        PanelSurface { id: bare; bordered: false; Rectangle { width: 100; height: 50 } }
        Pill { id: pill; text: "2.4 GHz" }
        TrackBar { id: track; width: 200 }
        PanelSwitch { id: sw }
        PanelButton { id: button; text: "Go"; bordered: true }
    }
    Timer {
        interval: 100
        repeat: true
        running: true
        onTriggered: {
            if (probe.step === 0 && Theme.radius === 7 && Object.keys(Theme.tokens).length > 0) {
                const f = Theme.font, s = Theme.spacing;
                probe.result.before = probe.snap();
                probe.result.font = [f.caption, f.bodySmall, f.body, f.subtitle, f.title, f.heading, f.display, f.displayLarge, f.iconSmall, f.icon, f.iconLarge];
                probe.result.family = [Theme.fontFamily, Theme.fontMono, f.family, Theme.fontSize, f.baseSize];
                probe.result.spacing = [s.hairline, s.xxs, s.xs, s.sm, s.md, s.lg, s.xl, s.xxl, s.xxxl, s.huge, s.controlGap, s.controlPaddingX, s.controlPaddingY, s.inputPaddingY, s.controlHeight, s.popupRowHeight, s.rowGap, s.rowPaddingX, s.labelGap, s.panelGap, s.panelPadding, s.popupPadding];
                probe.result.alphas = [Theme.normalFillAlpha, Theme.hoverFillAlpha, Theme.selectedFillAlpha, Theme.pressedFillAlpha, Theme.focusFillAlpha, Theme.selectionFillAlpha, Theme.normalBorderAlpha, Theme.hoverBorderAlpha, Theme.selectedBorderAlpha, Theme.focusBorderAlpha];
                probe.result.widths = [Theme.normalBorderWidth, Theme.hoverBorderWidth, Theme.selectedBorderWidth, Theme.focusBorderWidth];
                probe.result.fills = [String(Theme.normalFill), String(Theme.hoverFill), String(Theme.selectedFill), String(Theme.normalBorderColor), String(Theme.hoverBorderColor)];
                probe.result.popups = [String(Theme.popups.background), String(Theme.popups.border), Theme.popups.borderSpec.width, Theme.popups.borderSpec.gradient.enabled];
                probe.result.menu = [String(Theme.menu.border), String(Theme.menu.selectedBackground), String(Theme.menu.scrim)];
                probe.result.lock = [String(Theme.lock.background), String(Theme.lock.selection)];
                probe.result.bar = [Theme.barMetrics.sizeHorizontal, Theme.barMetrics.sizeVertical, Theme.barMetrics.iconSlot];
                probe.result.card = [card.implicitWidth, card.implicitHeight, card.border.width, String(card.color), card.radius, bare.implicitWidth];
                probe.result.controls = [pill.verticalPadding, pill.horizontalPadding, pill.reservedBorder, track.implicitHeight, track.knobSize, sw.trackWidth, sw.trackHeight, button.border.width];
                probe.result.compat = {
                    radius: Commons.Style.cornerRadius === Theme.radius, gaps: Commons.Style.gapsOut === Theme.gapsOut,
                    font: Commons.Style.font === Theme.font, spacing: Commons.Style.spacing === Theme.spacing,
                    family: Commons.Style.font.family, base: Commons.Style.fontBaseSize,
                    hover: String(Commons.Style.hoverFill) === String(Theme.hoverFill),
                    selected: String(Commons.Style.selectedFillFor(Theme.foreground, Theme.accent)) === String(Theme.selectedFill),
                    overrides: Commons.Style.styleOverrides["normal-border-width"],
                    values: Commons.Color.shellValues === Theme.shellValues,
                    popups: String(Commons.Color.popups.background) === String(Theme.popups.background),
                    border: String(Commons.Color.popups.border) === String(Theme.popups.border),
                    space: Commons.Style.space(10) === Theme.space(10)
                };
                probe.result.frame = [Config.frameEnabled, Config.frameRadius];
                writer.running = true;
                probe.step = 1;
            } else if (probe.step === 1 && !writer.running) {
                // Written, the event still 1 s away: nothing has changed.
                probe.result.unannounced = probe.snap();
                probe.step = 2;
            } else if (probe.step === 2 && Theme.radius === 3) {
                probe.result.after = probe.snap();
                probe.result.frameAfter = Config.frameRadius;
                console.log("RESULT " + JSON.stringify(probe.result));
                Qt.quit();
            }
        }
    }
    Process {
        id: writer
        command: ["sh", "-c", "printf '3 4 false\\\\n' >'$HYPR_VALUES'"]
    }
    Timer {
        interval: 15000
        running: true
        onTriggered: {
            console.log("RESULT " + JSON.stringify(probe.result));
            Qt.quit();
        }
    }
}
QML
    qs_run 2.5
    assert_eq "radius mirrors decoration:rounding" "7 7" "$(r '"\(.before.radius) \(.before.cornerRadius)"')"
    assert_eq "gapsOut is half of gaps_out" "5" "$(r .before.gapsOut)"
    assert_eq "animations on: durations as given" "false 140" "$(r '"\(.before.reduce) \(.before.d140)"')"
    assert_eq "no re-read before Hyprland announces a reload (no polling)" "7 5" "$(r '"\(.unannounced.radius) \(.unannounced.gapsOut)"')"
    assert_eq "configreloaded re-reads rounding and gaps_out" "3 2" "$(r '"\(.after.radius) \(.after.gapsOut)"')"
    assert_eq "and animations: off means duration 0" "true 0" "$(r '"\(.after.reduce) \(.after.d140)"')"
    assert_eq "Omarchy's type scale (Style.qml:329-340)" "[10,11,12,13,14,16,24,28,11,14,18]" "$(r '.font | tojson')"
    assert_eq "one family for text and icons: the user's monospace" '["JetBrainsMono Nerd Font","JetBrainsMono Nerd Font","JetBrainsMono Nerd Font",12,12]' "$(r '.family | tojson')"
    assert_eq "Omarchy's spacing scale (Style.qml:236-262)" "[1,2,3,4,6,8,10,12,14,18,8,10,6,7,28,28,8,12,4,14,18,14]" "$(r '.spacing | tojson')"
    assert_eq "Omarchy's state alphas (shell.toml.tpl:34-65)" "[0.04,0.08,0.18,0.22,0.08,0.35,0.4,0.25,1,0.25]" "$(r '.alphas | tojson')"
    assert_eq "Omarchy's state border widths" "[1,1,0,1]" "$(r '.widths | tojson')"
    assert_eq "fills and borders are the foreground at those alphas" '["#0aa9b1d6","#14a9b1d6","#2ea9b1d6","#66a9b1d6","#40a9b1d6"]' "$(r '.fills | tojson')"
    assert_eq "popups: background card, accent (active) border 2 px, flat" '["#1a1b26","#7aa2f7",2,false]' "$(r '.popups | tojson')"
    assert_eq "menu: foreground border, 0.08 selected row, 0.5 scrim" '["#a9b1d6","#14a9b1d6","#801a1b26"]' "$(r '.menu | tojson')"
    assert_eq "lock: 0.8 background, 0.45 accent selection" '["#cc1a1b26","#737aa2f7"]' "$(r '.lock | tojson')"
    assert_eq "bar metrics at base 12 (Style.qml:344-357)" "[26,28,27]" "$(r '.bar | tojson')"
    assert_eq "card: content + 2 x (14 padding + 2 border), Hyprland's radius" '[132,82,2,"#1a1b26",7,128]' "$(r '.card | tojson')"
    assert_eq "pill padding 8/10 + 1 px border, slider 22 with a 14 knob, switch 42x22, bordered button 1 px" "[8,10,1,22,14,42,22,1]" "$(r '.controls | tojson')"
    for k in radius gaps font spacing hover selected values popups border space; do
        assert_eq "compat Style/Color agree with Theme: $k" "true" "$(r ".compat.$k")"
    done
    assert_eq "compat font family and base" "JetBrainsMono Nerd Font 12" "$(r '"\(.compat.family) \(.compat.base)"')"
    assert_eq "compat [controls] overrides keep Omarchy's flat keys" "1" "$(r .compat.overrides)"
    assert_eq "no frame by default; its radius would be the windows'" "false 7" "$(r '.frame | join(" ")')"
    assert_eq "an enabled frame follows the windows' radius live" "3" "$(r .frameAfter)"

    # 2. A gradient active border (solitude) draws through BorderRing; no
    # hyprctl: the theme's radius token and Omarchy's 5 px edge gap stay.
    token_sandbox shell-tokens-gradient
    capture haseen theme set solitude
    HYPR_VALUES="$SANDBOX/none"
    harness <<'QML'
import QtQuick
import Quickshell
import qs.Haseen
import qs.Haseen.Widgets
ShellRoot {
    id: probe
    FloatingWindow {
        implicitWidth: 300
        implicitHeight: 200
        visible: true
        PanelSurface { id: card; Rectangle { width: 120; height: 60; color: "transparent" } }
    }
    Timer {
        interval: 1500
        running: true
        onTriggered: {
            const spec = Theme.popups.borderSpec;
            const ring = card.children.find(c => c.item !== undefined);
            console.log("RESULT " + JSON.stringify({
                gradient: spec.gradient.enabled, stops: spec.gradient.colors.map(c => String(c)),
                native: card.border.width, ring: !!(ring && ring.item), radius: Theme.radius, gapsOut: Theme.gapsOut,
                size: [card.implicitWidth, card.implicitHeight]
            }));
            Qt.quit();
        }
    }
}
QML
    qs_run 0
    assert_eq "solitude: the active border is a gradient" "true" "$(r .gradient)"
    assert_eq "with Hyprland's stops and alphas" '["#ee798186","#eecacccc"]' "$(r '.stops | tojson')"
    assert_eq "drawn by BorderRing, not Rectangle.border" "0 true" "$(r '"\(.native) \(.ring)"')"
    assert_eq "no Hyprland: the radius token and Omarchy's edge gap" "6 5" "$(r '"\(.radius) \(.gapsOut)"')"
    assert_eq "the ring keeps the card's 2 px inset" "[152,92]" "$(r '.size | tojson')"

    # 3. A shell.json from before plan 115 (fontFamily Inter, no
    # shellValues): the text font is still fontMono, every Omarchy value
    # falls back to Omarchy's default, and a user's own frame.enabled wins.
    token_sandbox shell-tokens-old
    mkdir -p "$(dirname "$SJ")" "$HOME/.config/haseen"
    printf '{"mode":"dark","background":"#101010","foreground":"#e0e0e0","accent":"#3366ff","fontFamily":"Inter","fontMono":"Mono Old","fontSize":11,"radius":6}\n' >"$SJ"
    printf '{"frame":{"enabled":true,"radius":20}}\n' >"$HOME/.config/haseen/shell.json"
    HYPR_VALUES="$SANDBOX/none"
    harness <<'QML'
import QtQuick
import Quickshell
import qs.Haseen
ShellRoot {
    // Singletons load their files on first use; wait for both reads.
    Component.onCompleted: console.log("start " + Theme.mode + " " + Config.frameEnabled)
    Timer {
        interval: 100
        repeat: true
        running: true
        onTriggered: {
            if (Object.keys(Theme.tokens).length === 0 || Config.user.frame === undefined)
                return;
            console.log("RESULT " + JSON.stringify({
                family: Theme.fontFamily, base: Theme.fontSize, body: Theme.font.body,
                popups: [String(Theme.popups.background), String(Theme.popups.border), Theme.popups.borderSpec.width],
                hover: String(Theme.hoverFill), frame: [Config.frameEnabled, Config.frameRadius]
            }));
            Qt.quit();
        }
    }
}
QML
    qs_run 0
    assert_eq "an old shell.json still draws text in fontMono" "Mono Old" "$(r .family)"
    assert_eq "its fontSize is the base until shellValues come" "11 11" "$(r '"\(.base) \(.body)"')"
    assert_eq "surfaces fall back as Omarchy's Color.qml does" '["#101010","#3366ff",2]' "$(r '.popups | tojson')"
    assert_eq "state fills fall back to Omarchy's alphas" "#14e0e0e0" "$(r .hover)"
    assert_eq "the user's frame.enabled and frame.radius win" "true 20" "$(r '.frame | join(" ")')"
    rm -rf "$RUNTIME"
fi

# --- the frame is off by default (plan 115) ------------------------------------
assert_eq "default shell.json: frame off" "false" "$(jq -r .frame.enabled "$HASEEN_PATH/default/shell.json")"
assert_contains "Config: on only when shell.json says so" "$(cat "$HASEEN_PATH/shell/Haseen/Config.qml")" "frameEnabled: frame.enabled === true"

# --- static rules ---------------------------------------------------------------
# One geometry for native and compat borders: the copies differ only in their
# header comment.
body() { sed -n '/^\.pragma library$/,$p' "$1"; }
assert_eq "Haseen/BorderGeometry.js and the compat copy share one body" \
    "$(body "$HASEEN_PATH/shell/Compat/Omarchy/Commons/BorderGeometry.js")" "$(body "$HASEEN_PATH/shell/Haseen/BorderGeometry.js")"
assert_not_contains "Theme reads Hyprland on events, never on a timer" "$(cat "$HASEEN_PATH/shell/Haseen/Theme.qml")" "Timer {"
assert_contains "panels sit gapsOut off the bar, as Omarchy's" "$(cat "$HASEEN_PATH/shell/PanelPopup.qml")" "Theme.gapsOut, Plugins.settingsFor(pluginId).placement)"
