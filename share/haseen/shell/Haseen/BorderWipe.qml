pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// The border wipe (plan 069): a theme whose colors.toml has `border_wipe`
// wants the active border's gradient to turn. Hyprland's borderangle animation
// does it up to 10 s a turn; slower, haseen-sidecar does (stream `borderwipe`).
// This holds the subscription while the current theme asks, so the daemon is
// not started for a theme that does not; the daemon decides the rest (native
// or its own loop, paused or running).
//
// shell.qml reads `wanted` once to create the singleton. A theme switch
// replaces colors.toml, which the watch sees.
Singleton {
    id: root

    readonly property string colorsPath: Paths.userState + "/current/theme/colors.toml"
    property bool wanted: false
    // borderwipe.Status from the daemon: state, reason, secondsPerTurn.
    readonly property var status: Sidecar.streams.borderwipe || null

    onWantedChanged: {
        if (wanted)
            Sidecar.want("border-wipe", "borderwipe", {
                signature: Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || ""
            });
        else
            Sidecar.drop("border-wipe");
    }

    FileView {
        path: root.colorsPath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.wanted = /^\s*border_wipe\s*=/m.test(text())
        onLoadFailed: root.wanted = false
    }
}
