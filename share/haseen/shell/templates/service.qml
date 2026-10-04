import QtQuick
import Quickshell

// @ID@: service. Created once when listed in shell.json `services`.
// Declare "provides": ["launcher"] (or lock, notifications) in the manifest
// and define the matching functions (toggle, lock, clear, toggleDnd) to
// answer those IPC calls.
Scope {
    id: root

    // Every entry gets these from the host (docs/architecture.md 5.2).
    property string pluginId
    property var settings: ({})
    property var screen: null

    Component.onCompleted: console.info(root.pluginId + ": started")
}
