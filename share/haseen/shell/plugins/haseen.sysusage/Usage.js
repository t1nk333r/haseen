.pragma library

// Formatting for haseen.sysusage. The parsing that used to live here (/proc,
// GPU sysfs, top output) moved into haseen-sidecar when the plugin stopped
// polling from QML (plan 032); core/internal/sysusage owns it and its tests.
// No Qt or Quickshell types, so tests/test-widgets-a.sh runs this headless
// under /usr/lib/qt6/bin/qml.

// KiB -> "3.4 GiB" / "512 MiB".
function formatKiB(kib) {
    if (!(kib >= 0))
        return "?";
    if (kib >= 1048576)
        return (kib / 1048576).toFixed(1) + " GiB";
    return Math.round(kib / 1024) + " MiB";
}
