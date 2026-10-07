pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// qs.Services.CavaService for DankMaterialShell plugins (architecture 5.4):
// six audio-spectrum levels from cava, while at least one plugin holds a
// reference (qs.Common.Ref). Adapted from DankMaterialShell's
// quickshell/Services/CavaService.qml (MIT, Copyright (c) 2025 Avenge Media
// LLC): the same cava configuration and ASCII raw output, read line by line
// as cava writes them (no polling). Without cava installed, cavaAvailable
// stays false and values stay zero. The configuration goes to the user's
// runtime directory instead of /tmp.
Singleton {
    id: root

    property list<int> values: Array(6).fill(0)
    property int refCount: 0
    property bool cavaAvailable: false
    readonly property string _confPath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/haseen/dms-cava.conf"

    Process {
        id: cavaCheck

        command: ["sh", "-c", "command -v cava"]
        onExited: exitCode => root.cavaAvailable = exitCode === 0
    }

    Component.onCompleted: cavaCheck.running = true

    Process {
        id: cavaProcess

        running: root.cavaAvailable && root.refCount > 0
        command: ["sh", "-c", `mkdir -p "$(dirname '${root._confPath}')" && cat <<'CAVACONF' > '${root._confPath}'
[general]
framerate=25
bars=6
autosens=0
sensitivity=30
sleep_timer=3
lower_cutoff_freq=50
higher_cutoff_freq=12000

[output]
method=raw
raw_target=/dev/stdout
data_format=ascii
channels=mono
mono_option=average

[smoothing]
noise_reduction=35
integral=90
gravity=95
ignore=2
monstercat=1.5
CAVACONF
exec cava -p '${root._confPath}' < /dev/null`]

        onRunningChanged: {
            if (!running)
                root.values = Array(6).fill(0);
        }

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                if (root.refCount <= 0 || data.length === 0)
                    return;
                const parts = data.split(";");
                if (parts.length < 6)
                    return;
                const points = [0, 1, 2, 3, 4, 5].map(i => parseInt(parts[i], 10) || 0);
                if (points.every((v, i) => v === root.values[i]))
                    return;
                root.values = points;
            }
        }
    }
}
