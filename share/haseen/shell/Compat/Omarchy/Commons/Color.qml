pragma Singleton

import QtQuick
import Quickshell
import qs.Haseen

// qs.Commons.Color for Omarchy plugins (architecture 5.4), backed by the
// haseen Theme tokens instead of Omarchy's colors.toml/shell.toml.
//
// The property names and surface groups follow Omarchy's
// shell/Commons/Color.qml (MIT, Copyright (c) David Heinemeier Hansson).
// Omarchy's palette roles map one to one: foreground, background, accent,
// urgent, muted. Popup-like surfaces use Theme.surface and Theme.border.
Singleton {
    id: root

    readonly property color foreground: Theme.foreground
    readonly property color background: Theme.background
    readonly property color accent: Theme.accent
    readonly property color urgent: Theme.urgent
    readonly property color muted: Theme.muted

    readonly property string currentThemePath: Paths.themeTokens.replace(/\/shell\.json$/, "")
    // Border reads the upstream flat token vocabulary, but values come only
    // from haseen's watched Theme singleton, never Omarchy files or polling.
    readonly property var shellValues: ({
        "popups.border": Theme.border,
        "popups.border-width": Theme.borderWidth,
        "tooltip.border": Theme.border,
        "tooltip.border-width": Theme.borderWidth,
        "notifications.border": Theme.accent,
        "notifications.border-width": Theme.borderWidth,
        "menu.border": Theme.border,
        "menu.border-width": Theme.borderWidth,
        "hyprland.active-border": Theme.accent,
        "hyprland.active-border-width": Theme.borderWidth
    })

    readonly property QtObject lock: QtObject {
        readonly property color background: Util.alpha(Theme.background, 0.8)
        readonly property color text: Theme.foreground
        readonly property color placeholder: Util.alpha(Theme.foreground, 0.66)
        readonly property color textError: Theme.urgent
        readonly property color border: Theme.border
        readonly property color borderActive: Theme.accent
        readonly property color borderError: Theme.urgent
        readonly property color selection: Util.alpha(Theme.accent, 0.45)
    }

    readonly property QtObject bar: QtObject {
        readonly property color background: Theme.background
        readonly property color text: Theme.foreground
        readonly property color active: Theme.urgent
    }
    readonly property QtObject popups: QtObject {
        readonly property color background: Theme.surface
        readonly property color text: Theme.foreground
        readonly property color border: Theme.border
    }
    readonly property QtObject tooltip: QtObject {
        readonly property color background: Theme.surface
        readonly property color text: Theme.foreground
        readonly property color border: Theme.border
    }
    readonly property QtObject notifications: QtObject {
        readonly property color background: Theme.surface
        readonly property color text: Theme.foreground
        readonly property color border: Theme.accent
        readonly property color countdown: Theme.accent
    }
    readonly property QtObject menu: QtObject {
        readonly property color background: Theme.surface
        readonly property color text: Theme.foreground
        readonly property color border: Theme.border
        readonly property color scrim: Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, 0.5)
        readonly property color selectedBackground: Theme.selection
        readonly property color selectedText: Theme.accent
        readonly property color selectedBorder: Qt.rgba(0, 0, 0, 0)
    }

    // Omarchy resolves palette role names ("accent", "text", …) to colours.
    function flatColor(value: var, fallback: var): var {
        const role = String(value || "").trim().toLowerCase();
        if (role === "foreground" || role === "text")
            return root.foreground;
        if (role === "accent")
            return root.accent;
        if (role === "urgent")
            return root.urgent;
        if (role === "muted")
            return root.muted;
        if (role === "background")
            return root.background;
        if (role === "transparent")
            return Qt.rgba(0, 0, 0, 0);
        return fallback;
    }
}
