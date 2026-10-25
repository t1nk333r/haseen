pragma Singleton

import QtQuick
import Quickshell
import qs.Haseen

// qs.Commons.Color for Omarchy plugins (architecture 5.4), backed by the
// haseen Theme tokens instead of Omarchy's colors.toml/shell.toml.
//
// The property names and surface groups follow Omarchy's
// shell/Commons/Color.qml (MIT, Copyright (c) David Heinemeier Hansson).
// Since plan 115 Theme derives the same groups from the same values
// (shellValues, rendered from Omarchy's shell.toml.tpl), so every colour here
// is Theme's: one source of truth for native panels and Omarchy plugins.
Singleton {
    id: root

    readonly property color foreground: Theme.foreground
    readonly property color background: Theme.background
    readonly property color accent: Theme.accent
    readonly property color urgent: Theme.urgent
    readonly property color muted: Theme.muted

    readonly property string currentThemePath: Paths.themeTokens.replace(/\/shell\.json$/, "")
    // Border reads the upstream flat token vocabulary; values come only from
    // haseen's watched Theme singleton, never Omarchy files or polling.
    readonly property var shellValues: Theme.shellValues

    readonly property QtObject bar: Theme.bar
    readonly property QtObject popups: Theme.popups
    readonly property QtObject tooltip: Theme.tooltip
    readonly property QtObject notifications: Theme.notifications
    readonly property QtObject menu: Theme.menu
    readonly property QtObject polkit: Theme.polkit
    readonly property QtObject lock: Theme.lock
    readonly property QtObject imagePicker: Theme.imagePicker

    function pick(key, fallback) {
        return Theme.pick(key, fallback);
    }

    function pickAlpha(key, fallback) {
        return Theme.pickAlpha(key, fallback);
    }

    // Omarchy resolves palette role names ("accent", "text", …), shell value
    // references and colour literals to colours.
    function flatColor(value: var, fallback: var): var {
        return Theme.flatColor(value, fallback);
    }

    function composed(colorKey, alphaKey, colorFallback, alphaFallback) {
        return Theme.composed(colorKey, alphaKey, colorFallback, alphaFallback);
    }
}
