pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "Ink.js" as Ink
import "BorderGeometry.js" as Geometry

// Shell tokens (architecture 7) from current/theme/shell.json, rendered by
// `haseen theme set`. Every key has a built-in fallback, so a missing, partial
// or broken file never breaks the bar. Values of the wrong type fall back too.
// The fallbacks are the default theme's rendered shell.json (`haseen`, plan
// 066; its palette is HANCORE's Greek Noir, MIT, Copyright (c) 2026 HANCORE,
// see NOTICE.md; tests/test-theme-haseen.sh keeps them in step), so a missing
// file still looks like haseen.
//
// Plan 115: the look is Omarchy 4.5's. Its vocabulary and values come from
// Omarchy's shell/Commons/Style.qml and Color.qml (MIT, Copyright (c) David
// Heinemeier Hansson, see NOTICE.md): `shellValues` is the flat
// "section.key" dictionary Omarchy's default/themed/shell.toml.tpl renders
// (here inside shell.json, from share/haseen/themed/shell.json.tpl), and the
// surface groups (popups, menu, lock, …), state tokens, spacing and type
// scale below are derived from it exactly as Omarchy derives them. `radius`
// mirrors Hyprland's decoration:rounding and `gapsOut` is half of
// general:gaps_out, read on start and on every Hyprland `configreloaded`
// (which `haseen theme set` triggers through `hyprctl reload`); nothing polls.
// The font is the user's monospace (owner, 2026-10-25): what `haseen font set`
// stored, else the theme's font_mono.
Singleton {
    id: root

    property var tokens: ({})

    readonly property var fallback: ({
            mode: "dark",
            background: "#171717",
            surface: "#171717",
            surfaceAlt: "#252626",
            foreground: "#CCD0CF",
            muted: "#525252",
            accent: "#F25623",
            accentFg: "#171717",
            urgent: "#aeab94",
            warning: "#757864",
            success: "#F25623",
            border: "#5f6161",
            selection: "#383838",
            fontFamily: "JetBrainsMono Nerd Font",
            fontMono: "JetBrainsMono Nerd Font",
            fontSize: 12,
            radius: 6,
            gap: 6,
            borderWidth: 1
        })

    readonly property var _numeric: ["fontSize", "radius", "gap", "borderWidth"]
    readonly property var _text: ["mode", "fontFamily", "fontMono"]

    function token(key: string): var {
        const v = tokens[key];
        if (_numeric.indexOf(key) >= 0)
            return (typeof v === "number" && isFinite(v) && v >= 0) ? v : fallback[key];
        if (_text.indexOf(key) >= 0)
            return (typeof v === "string" && v.length > 0) ? v : fallback[key];
        return (typeof v === "string" && /^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/.test(v)) ? v : fallback[key];
    }

    readonly property string mode: token("mode")
    readonly property color background: token("background")
    // The card a panel lives in: Omarchy's [popups] background (opaque at
    // its default alpha 1.0). surfaceAlt, border and selection are the
    // foreground over it at Omarchy's hover-cursor fill (0.08), normal border
    // (0.4) and selected fill (0.18) alphas, rendered opaque so a widget that
    // measures contrast against them (subtle()) still can.
    readonly property color surface: token("surface")
    readonly property color surfaceAlt: token("surfaceAlt")
    readonly property color foreground: token("foreground")
    readonly property color muted: token("muted")
    readonly property color accent: token("accent")
    readonly property color accentFg: token("accentFg")
    readonly property color urgent: token("urgent")
    readonly property color warning: token("warning")
    readonly property color success: token("success")
    readonly property color border: token("border")
    readonly property color selection: token("selection")
    // One family for text and icons, as Omarchy's Style.font.family is the
    // system monospace (a Nerd Font): the user's choice from `haseen font set`
    // (shell.json fontMono). fontFamily used to be the theme's sans (Inter);
    // reading fontMono here also covers a shell.json rendered before plan 115.
    // Arabic falls through fontconfig's lang rules to Noto (plan 047).
    readonly property string fontMono: token("fontMono")
    readonly property string fontFamily: fontMono
    // Omarchy's [font] base-size: the body size every font.* token scales from.
    readonly property int fontSize: font.baseSize
    // Shell corner radius: Hyprland's decoration:rounding once it answered,
    // else the theme's radius token (no Hyprland, or before the first read).
    readonly property int radius: _hyprRounding >= 0 ? _hyprRounding : token("radius")
    readonly property int cornerRadius: radius
    // A spacing step (Omarchy's spacing.md, 6 px): margins and gaps inside
    // panels. Not the edge gap, which follows Hyprland: see gapsOut.
    readonly property int gap: token("gap")
    readonly property int borderWidth: token("borderWidth")

    // Normal-state text and glyphs of bar widgets. It is the foreground, or
    // while the bar is transparent the colour FrameTextColor.qml picks for the
    // wallpaper under the bar (plan 015). Panels keep using foreground.
    property color barForeground: foreground

    // Secondary text on an opaque `bg` (descriptions, subtitles): the
    // foreground at Omarchy's description alpha, raised until it reads at 3:1
    // on bg (Ink.js). Never muted: muted on selection drops below 1.5:1 in
    // most stock themes. A translucent row tint goes through over() first.
    function subtle(bg: color): color {
        return Qt.alpha(foreground, Ink.readableAlpha(foreground, bg, Ink.SUBTLE, Ink.MIN_RATIO));
    }

    // fg at alpha painted over an opaque bg, as one opaque colour.
    function over(fg: color, alpha: real, bg: color): color {
        const c = Ink.over(fg, alpha, bg);
        return Qt.rgba(c.r, c.g, c.b, 1);
    }

    // ------------------------------------------------------------ Hyprland
    // Omarchy's Style.qml:13-19,33-34,360-367,369-399,464-504: cornerRadius
    // mirrors decoration:rounding, gapsOut is half of general:gaps_out (the
    // window gap feels cavernous as the distance from a panel to the screen
    // edge) and reduceMotion follows animations:enabled. -1 = not read yet.
    property int _hyprRounding: -1
    property int _hyprGapsOut: -1
    // Omarchy's default before Hyprland answers (Style.qml:34).
    readonly property int gapsOut: _hyprGapsOut >= 0 ? _hyprGapsOut : 5
    property bool reduceMotion: false

    // ms, or 0 while Hyprland's animations are off (`haseen toggle
    // animations`), so nothing is drawn in between.
    function duration(ms: real): real {
        return reduceMotion ? 0 : ms;
    }

    // Not under Hyprland (a test, a greeter session): hyprctl has nothing to
    // ask, so nothing runs and the fallbacks stay.
    function refresh(): void {
        if (!Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE"))
            return;
        roundingProc.running = true;
        gapsOutProc.running = true;
        animationsProc.running = true;
    }

    function applyRoundingJson(raw: string): void {
        try {
            const n = Number(JSON.parse(raw || "{}").int);
            if (isFinite(n) && n >= 0)
                _hyprRounding = Math.round(n);
        } catch (e) {
            // hyprctl missing or Hyprland not running: keep the previous value.
        }
    }

    function applyGapsOutJson(raw: string): void {
        try {
            const json = JSON.parse(raw || "{}");
            const parts = String(json.css || "").match(/-?\d+(?:\.\d+)?/g) || [];
            const n = parts.length > 0 ? Number(parts[0]) : Number(json.int);
            if (isFinite(n) && n >= 0)
                _hyprGapsOut = Math.max(0, Math.round(n / 2));
        } catch (e) {}
    }

    function applyAnimationsJson(raw: string): void {
        try {
            reduceMotion = JSON.parse(raw || "{}").bool === false;
        } catch (e) {}
    }

    Process {
        id: roundingProc

        command: ["hyprctl", "-j", "getoption", "decoration:rounding"]
        stdout: StdioCollector {
            onStreamFinished: root.applyRoundingJson(text)
        }
    }

    Process {
        id: gapsOutProc

        command: ["hyprctl", "-j", "getoption", "general:gaps_out"]
        stdout: StdioCollector {
            onStreamFinished: root.applyGapsOutJson(text)
        }
    }

    Process {
        id: animationsProc

        command: ["hyprctl", "-j", "getoption", "animations:enabled"]
        stdout: StdioCollector {
            onStreamFinished: root.applyAnimationsJson(text)
        }
    }

    // A reload is a theme, a toggle or the user's own config landing, and
    // Hyprland announces it once the new values are in effect.
    Connections {
        target: Hyprland

        function onRawEvent(event: var): void {
            if (event && String(event.name) === "configreloaded")
                root.refresh();
        }
    }

    Component.onCompleted: refresh()

    // ------------------------------------------------------------ shell values
    // Omarchy's Color.qml:28-77: the flat dictionary and its readers.
    readonly property var shellValues: {
        const v = tokens.shellValues;
        return (v && typeof v === "object" && !Array.isArray(v)) ? v : {};
    }

    function pick(key: string, fallback: var): var {
        const v = shellValues[key];
        return (typeof v === "string" && v.length > 0) ? v : fallback;
    }

    function pickAlpha(key: string, fallback: real): real {
        const v = shellValues[key];
        if (typeof v !== "string" || v.length === 0)
            return fallback;
        const n = Number(v);
        return isFinite(n) ? Geometry.clampAlpha(n) : fallback;
    }

    function firstColorToken(value: var): string {
        const parts = String(value || "").trim().split(/\s+/);
        for (const p of parts) {
            if (!/^-?\d+(?:\.\d+)?deg$/.test(p))
                return p;
        }
        return String(value || "");
    }

    function roleColor(role: string): var {
        if (role === "foreground" || role === "text")
            return foreground;
        if (role === "accent")
            return accent;
        if (role === "urgent")
            return urgent;
        if (role === "muted")
            return muted;
        if (role === "background")
            return background;
        if (role === "transparent")
            return Qt.rgba(0, 0, 0, 0);
        return undefined;
    }

    // A value as one colour: a role, a "section.key" reference followed
    // through shellValues, or a hex/rgb()/rgba()/0xAARRGGBB literal; a
    // gradient gives its first stop.
    function flatColor(value: var, fallback: var): var {
        const seen = {};
        let tok = firstColorToken(value);
        let role = tok.toLowerCase();
        while (shellValues[role] && shellValues[role] !== tok) {
            if (seen[role])
                return fallback;
            seen[role] = true;
            tok = firstColorToken(shellValues[role]);
            role = tok.toLowerCase();
        }
        const r = roleColor(role);
        if (r !== undefined)
            return r;
        const c = Geometry.canonicalColor(tok, 1);
        if (typeof c === "string" && c === tok && tok.charAt(0) !== "#")
            return fallback;
        return c;
    }

    function alpha(c: var, a: real): color {
        const x = typeof c === "string" ? Qt.color(c) : c;
        return Qt.rgba(x.r, x.g, x.b, Geometry.clampAlpha(a));
    }

    function composed(colorKey: string, alphaKey: string, colorFallback: var, alphaFallback: real): color {
        return alpha(flatColor(pick(colorKey, colorFallback), colorFallback), pickAlpha(alphaKey, alphaFallback));
    }

    function _resolveRef(raw: var): string {
        let s = String(raw || "").trim();
        const seen = {};
        while (/^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(s) && !seen[s]) {
            seen[s] = true;
            const next = shellValues[s];
            if (next === undefined || next === null || String(next).length === 0)
                break;
            s = String(next).trim();
        }
        return s;
    }

    function _cssColor(value: var, opacity: real): var {
        if (value && typeof value === "object" && value.r !== undefined)
            return Qt.rgba(value.r, value.g, value.b, (value.a === undefined ? 1 : value.a) * opacity);
        const r = roleColor(String(value || "").trim().toLowerCase());
        if (r !== undefined)
            return _cssColor(r, opacity);
        return Geometry.canonicalColor(String(value || "").trim(), opacity);
    }

    // A border as { color, width, gradient: { colors, angle, enabled } }:
    // Omarchy's Border.surfaceSpec (Border.qml:106-150, uniform widths only)
    // and controlSpec (Border.qml:204-215). A gradient keeps its stops' own
    // alphas times the section's border alpha.
    function _borderValue(raw: string, fallbackColor: var, opacity: real): var {
        const s = raw.length > 0 ? raw : "";
        const parts = s.length > 0 ? s.split(/\s+/) : [];
        const colors = [];
        let angle = 0;
        for (const p of parts) {
            const m = p.match(/^(-?\d+(?:\.\d+)?)deg$/);
            if (m)
                angle = Number(m[1]);
            else
                colors.push(_cssColor(p, opacity));
        }
        if (colors.length === 0)
            colors.push(_cssColor(fallbackColor, opacity));
        return {
            color: colors[0],
            gradient: { colors: colors, angle: isFinite(angle) ? angle : 0, enabled: colors.length > 1 }
        };
    }

    function surfaceSpec(section: string, key: string, fallbackColor: var, fallbackWidth: int): var {
        const r = _borderValue(_resolveRef(shellValues[section + "." + key]), fallbackColor, pickAlpha(section + "." + key + "-alpha", 1.0));
        const w = Geometry.parseWidthSpec(shellValues[section + "." + (key === "border" ? "border-width" : key + "-width")], fallbackWidth);
        return { color: r.color, width: w.top, gradient: r.gradient };
    }

    function controlSpec(state: string, fg: var, accentColor: var): var {
        const prefix = state === "hover" || state === "hot" ? "hover-cursor" : (state || "normal");
        const col = prefix === "focus" ? focusStateColor(fg, accentColor) : prefix === "hover-cursor" ? hoverStateColor(fg, accentColor) : prefix === "selected" ? selectedStateColor(fg, accentColor) : normalStateColor(fg, accentColor);
        const a = prefix === "focus" ? focusBorderAlpha : prefix === "hover-cursor" ? hoverBorderAlpha : prefix === "selected" ? selectedBorderAlpha : normalBorderAlpha;
        const w = prefix === "focus" ? focusBorderWidth : prefix === "hover-cursor" ? hoverBorderWidth : prefix === "selected" ? selectedBorderWidth : normalBorderWidth;
        const r = _borderValue(_resolveRef(controls(prefix + "-border", "")), col, a);
        return { color: r.color, width: w, gradient: r.gradient };
    }

    // ------------------------------------------------------------ surfaces
    // Omarchy's Color.qml:79-137 groups, with its fallbacks.
    readonly property QtObject bar: QtObject {
        readonly property color background: root.composed("bar.background", "bar.background-alpha", root.background, 1.0)
        readonly property color text: root.flatColor(root.pick("bar.text", root.foreground), root.foreground)
        readonly property color active: root.flatColor(root.pick("bar.active", root.urgent), root.urgent)
    }
    readonly property QtObject popups: QtObject {
        readonly property color background: root.composed("popups.background", "popups.background-alpha", root.background, 1.0)
        readonly property color text: root.flatColor(root.pick("popups.text", root.foreground), root.foreground)
        readonly property color border: root.composed("popups.border", "popups.border-alpha", root.accent, 1.0)
        // Omarchy's PopupCard/KeyboardPanel border: max(1, space(2)) wide
        // unless [popups] border-width is set (PopupCard.qml:18).
        readonly property var borderSpec: root.surfaceSpec("popups", "border", root.accent, Math.max(1, root.space(2)))
    }
    readonly property QtObject tooltip: QtObject {
        readonly property color background: root.composed("tooltip.background", "tooltip.background-alpha", root.background, 1.0)
        readonly property color text: root.flatColor(root.pick("tooltip.text", root.foreground), root.foreground)
        readonly property color border: root.composed("tooltip.border", "tooltip.border-alpha", root.foreground, 1.0)
        readonly property var borderSpec: root.surfaceSpec("tooltip", "border", root.foreground, Math.max(1, root.normalBorderWidth))
    }
    readonly property QtObject notifications: QtObject {
        readonly property color background: root.composed("notifications.background", "notifications.background-alpha", root.background, 1.0)
        readonly property color text: root.flatColor(root.pick("notifications.text", root.foreground), root.foreground)
        readonly property color border: root.composed("notifications.border", "notifications.border-alpha", root.accent, 1.0)
        readonly property color countdown: root.flatColor(root.pick("notifications.countdown", root.accent), root.accent)
        readonly property var borderSpec: root.surfaceSpec("notifications", "border", root.accent, Math.max(1, root.space(2)))
    }
    readonly property QtObject menu: QtObject {
        readonly property color background: root.composed("menu.background", "menu.background-alpha", root.background, 1.0)
        readonly property color text: root.flatColor(root.pick("menu.text", root.foreground), root.foreground)
        readonly property color border: root.composed("menu.border", "menu.border-alpha", root.foreground, 1.0)
        readonly property color scrim: root.composed("menu.scrim", "menu.scrim-alpha", root.background, 0.5)
        readonly property color selectedBackground: root.composed("menu.selected-background", "menu.selected-background-alpha", root.foreground, 0.08)
        readonly property color selectedText: root.flatColor(root.pick("menu.selected-text", root.accent), root.accent)
        readonly property color selectedBorder: root.composed("menu.selected-border", "menu.selected-border-alpha", root.foreground, 0.0)
        readonly property var borderSpec: root.surfaceSpec("menu", "border", root.foreground, Math.max(1, root.space(2)))
    }
    // Omarchy's [launcher] (shell.toml.tpl:154-170; its Color.qml reads it in
    // the launcher plugin): [menu]'s tokens with the card at 0.95.
    readonly property QtObject launcher: QtObject {
        readonly property color background: root.composed("launcher.background", "launcher.background-alpha", root.background, 0.95)
        readonly property color text: root.flatColor(root.pick("launcher.text", root.foreground), root.foreground)
        readonly property color border: root.composed("launcher.border", "launcher.border-alpha", root.foreground, 1.0)
        readonly property color scrim: root.composed("launcher.scrim", "launcher.scrim-alpha", root.background, 0.5)
        readonly property color selectedBackground: root.composed("launcher.selected-background", "launcher.selected-background-alpha", root.foreground, 0.08)
        readonly property color selectedText: root.flatColor(root.pick("launcher.selected-text", root.accent), root.accent)
        readonly property color selectedBorder: root.composed("launcher.selected-border", "launcher.selected-border-alpha", root.foreground, 0.25)
        readonly property var borderSpec: root.surfaceSpec("launcher", "border", root.foreground, Math.max(1, root.space(2)))
    }
    readonly property QtObject polkit: QtObject {
        readonly property color background: root.composed("polkit.background", "polkit.background-alpha", root.background, 1.0)
        readonly property color text: root.flatColor(root.pick("polkit.text", root.foreground), root.foreground)
        readonly property color textError: root.flatColor(root.pick("polkit.text-error", root.urgent), root.urgent)
        readonly property color border: root.composed("polkit.border", "polkit.border-alpha", root.accent, 1.0)
        readonly property color borderError: root.composed("polkit.border-error", "polkit.border-alpha", root.urgent, 1.0)
        readonly property color accent: root.flatColor(root.pick("polkit.accent", root.accent), root.accent)
        readonly property color scrim: root.composed("polkit.scrim", "polkit.scrim-alpha", root.background, 0.5)
    }
    readonly property QtObject lock: QtObject {
        readonly property color background: root.composed("lock.background", "lock.background-alpha", root.background, 0.8)
        readonly property color text: root.flatColor(root.pick("lock.text", root.foreground), root.foreground)
        readonly property color placeholder: root.shellValues["lock.placeholder"] ? root.flatColor(root.shellValues["lock.placeholder"], root.alpha(root.foreground, 0.66)) : root.alpha(root.foreground, 0.66)
        readonly property color textError: root.flatColor(root.pick("lock.text-error", root.urgent), root.urgent)
        readonly property color border: root.composed("lock.border", "lock.border-alpha", root.foreground, 1.0)
        readonly property color borderActive: root.composed("lock.border-active", "lock.border-alpha", root.accent, 1.0)
        readonly property color borderError: root.composed("lock.border-error", "lock.border-alpha", root.urgent, 1.0)
        readonly property color selection: root.composed("lock.selection", "lock.selection-alpha", root.accent, 0.45)
    }
    readonly property QtObject imagePicker: QtObject {
        readonly property color text: root.flatColor(root.pick("image-picker.text", root.foreground), root.foreground)
        readonly property color selectedBorder: root.composed("image-picker.selected-border", "image-picker.selected-border-alpha", root.accent, 1.0)
        readonly property color unselectedBorder: root.composed("image-picker.unselected-border", "image-picker.unselected-border-alpha", root.foreground, 0.28)
    }
    // A 1 px divider between panel sections: Omarchy's PanelSeparator
    // (Ui/PanelSeparator.qml:12,18), the foreground at 0.12 over the card.
    readonly property color separator: over(foreground, 0.12, popups.background)

    // ------------------------------------------------------------ state tokens
    // Omarchy's Style.qml:36-201. normal = idle chrome, hover-cursor = mouse
    // hover or a panel's keyboard cursor, selected = the chosen/current one,
    // focus = Qt activeFocus (hover-cursor's look unless a theme differs).
    function controls(key: string, fallback: var): var {
        const v = shellValues["controls." + key];
        return v === undefined || v === null ? fallback : v;
    }

    function _controlNum(key: string, fallback: real): real {
        const n = Number(controls(key, NaN));
        return isFinite(n) ? n : fallback;
    }

    function _controlString(key: string, fallback: string): string {
        const v = controls(key, "");
        const s = typeof v === "string" ? v.trim() : "";
        return s.length > 0 ? s : fallback;
    }

    readonly property string normalColorToken: _controlString("normal-color", "foreground")
    readonly property string hoverColorToken: _controlString("hover-cursor-color", "foreground")
    readonly property string selectedColorToken: _controlString("selected-color", "foreground")
    readonly property string pressedColorToken: _controlString("pressed-color", hoverColorToken)
    readonly property string focusColorToken: _controlString("focus-color", hoverColorToken)
    readonly property string selectionColorToken: _controlString("selection-color", "foreground")

    readonly property int normalBorderWidth: Math.max(0, Math.round(_controlNum("normal-border-width", 1)))
    readonly property int hoverBorderWidth: Math.max(0, Math.round(_controlNum("hover-cursor-border-width", normalBorderWidth)))
    readonly property int selectedBorderWidth: Math.max(0, Math.round(_controlNum("selected-border-width", 0)))
    readonly property int focusBorderWidth: Math.max(0, Math.round(_controlNum("focus-border-width", hoverBorderWidth)))

    readonly property real normalFillAlpha: Geometry.clampAlpha(_controlNum("normal-fill-alpha", 0.04))
    readonly property real hoverFillAlpha: Geometry.clampAlpha(_controlNum("hover-cursor-fill-alpha", 0.08))
    readonly property real selectedFillAlpha: Geometry.clampAlpha(_controlNum("selected-fill-alpha", 0.18))
    readonly property real pressedFillAlpha: Geometry.clampAlpha(_controlNum("pressed-fill-alpha", 0.22))
    readonly property real focusFillAlpha: Geometry.clampAlpha(_controlNum("focus-fill-alpha", hoverFillAlpha))
    readonly property real selectionFillAlpha: Geometry.clampAlpha(_controlNum("selection-fill-alpha", 0.35))

    readonly property real normalBorderAlpha: Geometry.clampAlpha(_controlNum("normal-border-alpha", 0.4))
    readonly property real hoverBorderAlpha: Geometry.clampAlpha(_controlNum("hover-cursor-border-alpha", 0.25))
    readonly property real selectedBorderAlpha: Geometry.clampAlpha(_controlNum("selected-border-alpha", 1.0))
    readonly property real focusBorderAlpha: Geometry.clampAlpha(_controlNum("focus-border-alpha", hoverBorderAlpha))

    function resolveStateColor(tok: var, fg: var, accentColor: var, urgentColor: var, fb: var): var {
        const s = String(tok || "").trim();
        const role = s.toLowerCase();
        if (role === "foreground" || role === "text")
            return fg || foreground;
        if (role === "accent")
            return accentColor || accent;
        if (role === "urgent")
            return urgentColor || urgent;
        if (role === "background")
            return background;
        if (role === "transparent")
            return Qt.rgba(0, 0, 0, 0);
        const c = Geometry.canonicalColor(s, 1);
        return (typeof c === "string" && c.charAt(0) !== "#") ? (fb || fg || foreground) : c;
    }

    function normalStateColor(fg: var, a: var, u: var): var {
        return resolveStateColor(normalColorToken, fg, a, u, fg || foreground);
    }
    function hoverStateColor(fg: var, a: var, u: var): var {
        return resolveStateColor(hoverColorToken, fg, a, u, fg || foreground);
    }
    function selectedStateColor(fg: var, a: var, u: var): var {
        return resolveStateColor(selectedColorToken, fg, a, u, fg || foreground);
    }
    function pressedStateColor(fg: var, a: var, u: var): var {
        return resolveStateColor(pressedColorToken, fg, a, u, hoverStateColor(fg, a, u));
    }
    function focusStateColor(fg: var, a: var, u: var): var {
        const role = String(focusColorToken || "").trim().toLowerCase();
        if (role === "hover" || role === "hover-cursor" || role === "inherit")
            return hoverStateColor(fg, a, u);
        return resolveStateColor(focusColorToken, fg, a, u, hoverStateColor(fg, a, u));
    }
    function selectionStateColor(fg: var, a: var, u: var): var {
        return resolveStateColor(selectionColorToken, fg, a, u, fg || foreground);
    }

    function normalFillFor(fg: var, a: var, u: var): color {
        return alpha(normalStateColor(fg, a, u), normalFillAlpha);
    }
    function hoverFillFor(fg: var, a: var, u: var): color {
        return alpha(hoverStateColor(fg, a, u), hoverFillAlpha);
    }
    function selectedFillFor(fg: var, a: var, u: var): color {
        return alpha(selectedStateColor(fg, a, u), selectedFillAlpha);
    }
    function pressedFillFor(fg: var, a: var, u: var): color {
        return alpha(pressedStateColor(fg, a, u), pressedFillAlpha);
    }
    function focusFillFor(fg: var, a: var, u: var): color {
        return alpha(focusStateColor(fg, a, u), focusFillAlpha);
    }
    function selectionFillFor(fg: var, a: var, u: var): color {
        return alpha(selectionStateColor(fg, a, u), selectionFillAlpha);
    }
    function normalBorderFor(fg: var, a: var, u: var): color {
        return alpha(normalStateColor(fg, a, u), normalBorderAlpha);
    }
    function hoverBorderFor(fg: var, a: var, u: var): color {
        return alpha(hoverStateColor(fg, a, u), hoverBorderAlpha);
    }
    function selectedBorderFor(fg: var, a: var, u: var): color {
        return alpha(selectedStateColor(fg, a, u), selectedBorderAlpha);
    }
    function focusBorderFor(fg: var, a: var, u: var): color {
        return alpha(focusStateColor(fg, a, u), focusBorderAlpha);
    }

    // focus > hover > normal, as every Omarchy form control paints itself.
    function controlFill(focused: bool, hot: bool, fg: var, a: var): color {
        return focused ? focusFillFor(fg, a) : hot ? hoverFillFor(fg, a) : normalFillFor(fg, a);
    }
    function controlBorder(focused: bool, hot: bool, fg: var, a: var): color {
        return focused ? focusBorderFor(fg, a) : hot ? hoverBorderFor(fg, a) : normalBorderFor(fg, a);
    }
    function controlBorderWidth(focused: bool, hot: bool): int {
        return focused ? focusBorderWidth : hot ? hoverBorderWidth : normalBorderWidth;
    }

    readonly property color normalFill: normalFillFor(foreground, accent, urgent)
    readonly property color hoverFill: hoverFillFor(foreground, accent, urgent)
    readonly property color selectedFill: selectedFillFor(foreground, accent, urgent)
    readonly property color pressedFill: pressedFillFor(foreground, accent, urgent)
    readonly property color focusFillColor: focusFillFor(foreground, accent, urgent)
    readonly property color normalBorderColor: normalBorderFor(foreground, accent, urgent)
    readonly property color hoverBorderColor: hoverBorderFor(foreground, accent, urgent)
    readonly property color selectedBorderColor: selectedBorderFor(foreground, accent, urgent)
    readonly property color focusBorderColor: focusBorderFor(foreground, accent, urgent)
    readonly property color selectedAccentFill: alpha(accent, selectedFillAlpha)
    readonly property color selectionFill: selectionFillFor(foreground, accent, urgent)

    // ------------------------------------------------------------ typography
    // Omarchy's Style.qml:279-341: base-size is the rem root; every token is
    // a multiple of it unless [font] pins that token.
    function _shellNum(key: string): real {
        const v = shellValues[key];
        if (v === undefined || v === null || v === "")
            return NaN;
        return Number(v);
    }

    function _bool(key: string, fallback: bool): bool {
        const v = shellValues[key];
        if (v === undefined || v === null)
            return fallback;
        const s = String(v).trim().toLowerCase();
        if (["true", "1", "yes", "on"].indexOf(s) >= 0)
            return true;
        if (["false", "0", "no", "off"].indexOf(s) >= 0)
            return false;
        return fallback;
    }

    readonly property int fontBaseSize: {
        const n = Math.round(_shellNum("font.base-size"));
        return isFinite(n) && n >= 1 ? n : Math.max(1, Math.round(token("fontSize")));
    }
    readonly property real fontScale: Math.max(1 / 12, fontBaseSize / 12)

    function fontPx(mult: real): int {
        return Math.max(1, Math.round(fontBaseSize * mult));
    }

    function fontToken(key: string, fb: int): int {
        const n = _shellNum("font." + key);
        return (isFinite(n) && n > 0) ? Math.round(n) : fb;
    }

    readonly property QtObject font: QtObject {
        readonly property string family: root.fontFamily
        readonly property string resolvedFamily: root.fontMono
        readonly property string menuFamily: root.fontFamily
        readonly property int baseSize: root.fontBaseSize
        readonly property int caption: root.fontToken("caption", root.fontPx(0.833))
        readonly property int bodySmall: root.fontToken("body-small", root.fontPx(0.917))
        readonly property int body: root.fontToken("body", root.fontPx(1.0))
        readonly property int subtitle: root.fontToken("subtitle", root.fontPx(1.083))
        readonly property int title: root.fontToken("title", root.fontPx(1.167))
        readonly property int heading: root.fontToken("heading", root.fontPx(1.333))
        readonly property int display: root.fontToken("display", root.fontPx(2.0))
        readonly property int displayLarge: root.fontToken("display-large", root.fontPx(2.333))
        readonly property int iconSmall: root.fontToken("icon-small", bodySmall)
        readonly property int icon: root.fontToken("icon", title)
        readonly property int iconLarge: root.fontToken("icon-large", root.fontPx(1.5))
    }

    // ------------------------------------------------------------ spacing
    // Omarchy's Style.qml:203-263: Omarchy's pixel values times [spacing]
    // scale (and the font scale while scale-with-font is on).
    readonly property real spacingScale: {
        const n = _shellNum("spacing.scale");
        return isFinite(n) && n >= 0 ? n : 1.0;
    }
    readonly property real effectiveSpacingScale: spacingScale * (_bool("spacing.scale-with-font", true) ? fontScale : 1)

    function spaceReal(px: var): real {
        const n = Number(px);
        if (!isFinite(n) || n <= 0)
            return 0;
        return n * effectiveSpacingScale;
    }

    function space(px: var): int {
        const n = spaceReal(px);
        if (n <= 0)
            return 0;
        return Math.max(1, Math.round(n));
    }

    function spacingToken(key: string, fb: real): int {
        const n = _shellNum("spacing." + key);
        return (isFinite(n) && n >= 0) ? Math.round(n) : space(fb);
    }

    readonly property QtObject spacing: QtObject {
        readonly property real scale: root.effectiveSpacingScale
        readonly property int hairline: root.space(1)
        readonly property int xxs: root.spacingToken("xxs", 2)
        readonly property int xs: root.spacingToken("xs", 3)
        readonly property int sm: root.spacingToken("sm", 4)
        readonly property int md: root.spacingToken("md", 6)
        readonly property int lg: root.spacingToken("lg", 8)
        readonly property int xl: root.spacingToken("xl", 10)
        readonly property int xxl: root.spacingToken("xxl", 12)
        readonly property int xxxl: root.spacingToken("xxxl", 14)
        readonly property int huge: root.spacingToken("huge", 18)
        readonly property int controlGap: root.spacingToken("control-gap", 8)
        readonly property int controlPaddingX: root.spacingToken("control-padding-x", 10)
        readonly property int controlPaddingY: root.spacingToken("control-padding-y", 6)
        readonly property int inputPaddingY: root.spacingToken("input-padding-y", 7)
        readonly property int controlHeight: root.spacingToken("control-height", 28)
        readonly property int popupRowHeight: root.spacingToken("popup-row-height", 28)
        readonly property int dropdownWidth: root.spacingToken("dropdown-width", 240)
        readonly property int searchableDropdownWidth: root.spacingToken("searchable-dropdown-width", 260)
        readonly property int numberFieldWidth: root.spacingToken("number-field-width", 120)
        readonly property int searchablePopupMinHeight: root.spacingToken("searchable-popup-min-height", 220)
        readonly property int rowGap: root.spacingToken("row-gap", 8)
        readonly property int rowPaddingX: root.spacingToken("row-padding-x", 12)
        readonly property int labelGap: root.spacingToken("label-gap", 4)
        readonly property int panelGap: root.spacingToken("panel-gap", 14)
        readonly property int panelPadding: root.spacingToken("panel-padding", 18)
        readonly property int popupPadding: root.spacingToken("popup-padding", 14)
    }

    // ------------------------------------------------------------ bar metrics
    // Omarchy's Style.qml:298-304,343-358, for the bar (plan 116): sizes at
    // base-size 12, grown with the font while [bar] scale-with-font is on.
    // The bar's own thickness stays shell.json's bar.height (Config).
    function barToken(key: string, fb: real): int {
        const n = _shellNum("bar." + key);
        let base = (isFinite(n) && n > 0) ? n : fb;
        if (_bool("bar.scale-with-font", true))
            base *= fontScale;
        return Math.max(1, Math.round(base));
    }

    readonly property QtObject barMetrics: QtObject {
        readonly property int sizeHorizontal: root.barToken("size-horizontal", 26)
        readonly property int sizeVertical: root.barToken("size-vertical", 28)
        readonly property int iconSlot: root.barToken("icon-slot", 27)
        readonly property int iconCanvas: root.barToken("icon-canvas", 16)
        readonly property int iconFont: root.barToken("icon-font", 13)
        readonly property int iconSize: Math.min(iconCanvas, root.barToken("icon-size", 12))
        readonly property int statusSlot: root.barToken("status-slot", 21)
    }

    FileView {
        path: Paths.themeTokens
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const parsed = JSON.parse(text());
                root.tokens = (parsed && typeof parsed === "object" && !Array.isArray(parsed)) ? parsed : {};
            } catch (e) {
                console.warn("haseen: theme tokens unreadable, using fallbacks:", e.message);
                root.tokens = {};
            }
        }
        onLoadFailed: root.tokens = {}
    }
}
