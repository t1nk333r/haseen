pragma Singleton
import QtQuick
import Quickshell

// Adapted from Omarchy shell/Commons/IpcRegistry.qml.
// MIT, Copyright (c) David Heinemeier Hansson.
// Which ShellIpc answers a target: registration order among live, enabled
// handlers, the same order Quickshell's own IPC registry uses.
Singleton {
    id: root

    property var handlers: []
    property int revision: 0

    function register(handler) {
        if (handlers.indexOf(handler) !== -1) return
        handlers = handlers.concat([handler])
        revision++
    }

    function unregister(handler) {
        handlers = handlers.filter(function(item) { return item !== handler })
        revision++
    }

    function refresh() { revision++ }

    function handlerFor(target) {
        revision // Track enabled/target changes even when the array stays intact.
        for (var i = 0; i < handlers.length; i++) {
            var handler = handlers[i]
            if (handler && handler.enabled && handler.target === target) return handler
        }
        return null
    }
}
