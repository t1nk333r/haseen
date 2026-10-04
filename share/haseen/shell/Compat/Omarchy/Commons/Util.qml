pragma Singleton

import QtQuick
import Quickshell

// qs.Commons.Util for Omarchy plugins (architecture 5.4). Pure helpers.
//
// Adapted from Omarchy's shell/Commons/Util.qml
// (MIT, Copyright (c) David Heinemeier Hansson). The bar-layout normalisers
// belong to Omarchy's bar host and are left out.
Singleton {
    function clamp(value: var, min: real, max: real): real {
        const n = Number(value);
        if (!isFinite(n))
            return min;
        return Math.max(min, Math.min(max, n));
    }

    function clampAlpha(value: var): real {
        return clamp(value, 0, 1);
    }

    // One notch is one step even when a mouse reports more than 120 units;
    // touchpad deltas accumulate.
    function wheelSteps(accumulator: real, delta: real): var {
        delta = Math.max(-120, Math.min(120, delta));
        if (accumulator * delta < 0)
            accumulator = 0;
        const total = accumulator + delta;
        const steps = total < 0 ? Math.ceil(total / 120) : Math.floor(total / 120);
        return {
            steps: steps,
            remainder: total - steps * 120
        };
    }

    function alpha(c: var, opacity: var): color {
        const a = clampAlpha(opacity);
        if (!c)
            return Qt.rgba(0, 0, 0, a);
        if (typeof c === "string")
            c = Qt.color(c);
        return Qt.rgba(c.r, c.g, c.b, a);
    }

    function fileUrl(path: var): string {
        if (!path)
            return "";
        return "file://" + String(path).split("/").map(encodeURIComponent).join("/");
    }

    function isVideoPath(path: var): bool {
        return /\.(mp4|m4v|mov|webm|mkv|avi)$/i.test(String(path || ""));
    }

    function shellQuote(value: var): string {
        return "'" + String(value || "").replace(/'/g, "'\\''") + "'";
    }

    function execDetached(command: var): void {
        Quickshell.execDetached(["bash", "-lc", String(command)]);
    }

    // argv without shell interpretation: the args land in "$@" only.
    function execArgv(argv: var): void {
        Quickshell.execDetached(["bash", "-lc", 'exec "$@"', "bash"].concat(argv));
    }

    function isPlainObject(value: var): bool {
        return value !== null && typeof value === "object" && !Array.isArray(value);
    }

    function canonicalWidgetId(id: var): string {
        return String(id || "");
    }

    function decodeBase64(value: var): string {
        const s = String(value || "");
        if (!s)
            return "";
        try {
            return Qt.atob(s);
        } catch (e) {
            return "";
        }
    }

    function cloneJson(value: var): var {
        return JSON.parse(JSON.stringify(value === undefined ? null : value));
    }

    // Last output line as waybar-style JSON ({text, class, tooltip}).
    function parseModuleJson(raw: var): var {
        const text = String(raw || "").trim();
        if (!text)
            return {};
        const lines = text.split("\n");
        try {
            return JSON.parse(lines[lines.length - 1]);
        } catch (e) {
            return {
                text: text
            };
        }
    }

    function editsFilter(event: var, text: var): bool {
        if (!text)
            return false;
        if (event.modifiers & (Qt.AltModifier | Qt.MetaModifier))
            return false;
        if (event.key === Qt.Key_U)
            return event.modifiers === Qt.ControlModifier;
        return event.key === Qt.Key_Backspace;
    }

    function editedFilter(event: var, text: var): string {
        if (event.key === Qt.Key_U)
            return "";
        if (event.modifiers & Qt.ControlModifier)
            return text.replace(/\s+$/, "").replace(/\S+$/, "");
        return text.slice(0, -1);
    }
}
