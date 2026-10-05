import QtQuick
import Quickshell
import Quickshell.Io

// The greeter's colours. Named GreeterPalette because QtQuick already has a
// `Palette` value type, and the shorter name silently resolves to that one. Deliberately **not** `qs.Haseen.Theme`: that pulls in
// Config, Paths and the plugin registry, all of which read the logged-in
// user's files, and the greeter runs as `greeter` with none of them. A login
// screen that cannot start is a machine you cannot log into.
//
// It reads the system theme tokens if an administrator put them where the
// greeter can see them, and otherwise uses the built-in dark values.
QtObject {
    id: root

    readonly property string tokensFile: "/var/lib/haseen/greeter/theme.json"

    property color background: "#171717"
    property color surface: "#1f1f1f"
    property color surfaceAlt: "#2a2a2a"
    property color foreground: "#ccd0cf"
    property color muted: "#757864"
    property color accent: "#f25623"
    property color urgent: "#e06c75"
    property color border: "#3a3a3a"
    property string fontFamily: "Inter"
    property int fontSize: 14
    property int radius: 8
    property int gap: 6
    property int borderWidth: 1

    function apply(text: string): void {
        let tokens = {};
        try {
            tokens = JSON.parse(text);
        } catch (e) {
            return;
        }
        for (const key of ["background", "surface", "surfaceAlt", "foreground", "muted", "accent", "urgent", "border"])
            if (typeof tokens[key] === "string" && tokens[key] !== "")
                root[key] = tokens[key];
        if (typeof tokens.fontFamily === "string" && tokens.fontFamily !== "")
            fontFamily = tokens.fontFamily;
        for (const key of ["fontSize", "radius", "gap", "borderWidth"])
            if (typeof tokens[key] === "number")
                root[key] = tokens[key];
    }

    property FileView tokens: FileView {
        path: root.tokensFile
        printErrors: false
        onLoaded: root.apply(text())
    }
}
