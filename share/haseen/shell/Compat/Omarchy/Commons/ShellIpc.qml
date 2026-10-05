import QtQml
import Quickshell.Io

// Adapted from Omarchy shell/Commons/ShellIpc.qml.
// MIT, Copyright (c) David Heinemeier Hansson.
// A real IpcHandler, so Quickshell reads each declared function's parameter
// types and parses wire arguments itself: `select 0` reaches a `bool` as false,
// while a `string` parameter keeps "0" (src/io/ipc.cpp IpcValueSlot::setString).
// Quickshell also owns target arbitration: instances created per screen share
// one target, the first registration answers, and destroying or disabling it
// promotes the next. IpcRegistry only mirrors that order for lookups.
IpcHandler {
    id: handler

    onEnabledChanged: IpcRegistry.refresh()
    onTargetChanged: IpcRegistry.refresh()
    Component.onCompleted: IpcRegistry.register(handler)
    Component.onDestruction: IpcRegistry.unregister(handler)
}
