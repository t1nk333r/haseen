import QtQuick
import Quickshell
import Quickshell.Io
import qs.Haseen
import qs.Haseen.Widgets
import "Model.js" as Model

// The capture toolbar (plan 150): the mode (screenshot, video, sound), what
// it captures, the delay or the sound's sources and format, and the capture
// button. The state and the capture itself are the haseen.capture service's
// (role `capture`), so a delay and a recording outlive this panel, which is
// freed when it closes. While a recording runs the toolbar is its elapsed
// time and a stop button.
//
// One cursor serves the keyboard and a game controller (Model.rows, .move):
// arrow keys or the D-pad move it, Tab and Shift+Tab walk every control,
// Enter or A presses the control under it. Space or Start captures,
// Ctrl+Space captures and opens the editor (screenshots), and Escape, B or
// a click outside closes the toolbar. Left and Right follow the screen in a
// right-to-left language, as the menu's do (architecture 5.8).
FocusScope {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    readonly property var service: {
        const entry = Plugins.roles.capture;
        return entry && entry.id === root.pluginId ? entry.instance : null;
    }
    // The service this toolbar told it is open, told again when it goes.
    property var openedService: null
    readonly property var state: service ? service.state : Model.initialState(settings)
    readonly property bool recording: service ? service.recording : false
    readonly property var rows: Model.rows(state, recording)
    property string cursor: Model.home(rows)
    // A control that left the toolbar (another mode's row) hands the cursor
    // back to the capture button.
    onRowsChanged: if (!rows.some(r => r.indexOf(cursor) >= 0))
        cursor = Model.home(rows)
    readonly property string keyHint: recording ? I18n.tr("Space stops · Esc closes") : state.mode === "screenshot" ? I18n.tr("Space captures · Ctrl+Space edits · Esc closes") : I18n.tr("Space records · Esc closes")

    readonly property color dim: Theme.subtle(Theme.surface)

    implicitWidth: Math.max(content.implicitWidth, Theme.space(300))
    implicitHeight: content.implicitHeight
    focus: true

    function close(): void {
        const win = QsWindow.window;
        if (win && typeof win.closeRequested === "function")
            win.closeRequested();
    }

    function screenDirection(direction: string): string {
        if (!I18n.rightToLeft)
            return direction;
        return direction === "left" ? "right" : direction === "right" ? "left" : direction;
    }

    function moveCursor(direction: string): void {
        cursor = Model.move(rows, cursor, screenDirection(direction));
    }

    function capture(edit: bool): void {
        if (!service)
            return;
        if (recording) {
            service.stop();
            return;
        }
        if (!Model.canCapture(state))
            return;
        if (service.capture(edit))
            close();
    }

    function press(id: string): void {
        if (!service)
            return;
        const result = Model.activate(state, id);
        if (!result)
            return;
        if (result.key !== undefined)
            service.change(result.key, result.value);
        else if (result.action === "stop")
            service.stop();
        else
            capture(result.action === "edit");
        cursor = id;
    }

    function pad(button: string): void {
        const action = Model.padAction(state, button, recording);
        if (!action)
            return;
        if (action.move)
            moveCursor(action.move);
        else if (action.press)
            press(cursor);
        else if (action.close)
            close();
        else if (action.change)
            service.change(action.change.key, action.change.value);
        else if (action.action === "stop")
            service.stop();
        else
            capture(false);
    }

    function tell(open: bool): void {
        if (open && service) {
            service.panelOpen = true;
            openedService = service;
        } else if (!open && openedService) {
            openedService.panelOpen = false;
            openedService = null;
        }
    }

    onServiceChanged: {
        tell(false);
        tell(true);
    }
    Component.onCompleted: {
        tell(true);
        forceActiveFocus();
    }
    Component.onDestruction: tell(false)

    Connections {
        target: root.service

        function onPadPressed(button: string): void {
            root.pad(button);
        }
    }

    Keys.onUpPressed: moveCursor("up")
    Keys.onDownPressed: moveCursor("down")
    Keys.onLeftPressed: moveCursor("left")
    Keys.onRightPressed: moveCursor("right")
    Keys.onTabPressed: moveCursor("next")
    Keys.onBacktabPressed: moveCursor("previous")
    Keys.onReturnPressed: press(cursor)
    Keys.onEnterPressed: press(cursor)
    Keys.onSpacePressed: event => capture((event.modifiers & Qt.ControlModifier) !== 0 && state.mode === "screenshot")

    component Choice: PanelButton {
        required property string controlId
        bordered: true
        opacity: enabled ? 1 : 0.5
        hasCursor: root.cursor === controlId
        onClicked: root.press(controlId)
        onHovered: isHovered => {
            if (isHovered)
                root.cursor = controlId;
        }
    }

    Column {
        id: content

        width: parent.width
        spacing: Theme.gap * 2

        // Without its service the toolbar can show nothing it could run.
        Text {
            visible: !root.service
            width: parent.width
            wrapMode: Text.Wrap
            text: I18n.tr("The capture service is not running. Enable it with: haseen plugin enable haseen.capture")
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.font.body
        }

        // --- a running recording -------------------------------------------
        Row {
            visible: root.service !== null && root.recording
            spacing: Theme.gap * 2

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: Theme.space(10)
                height: width
                radius: width / 2
                color: Theme.urgent
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.service && root.service.recordingKind === "audio" ? I18n.tr("Recording sound") : I18n.tr("Recording the screen")
                color: Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: Theme.font.body
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.service ? root.service.elapsed : ""
                color: Theme.foreground
                font.family: Theme.fontMono
                font.pixelSize: Theme.font.body
            }

            Choice {
                objectName: "captureStop"
                controlId: "stop"
                iconText: "\uf04d"
                text: I18n.tr("Stop")
            }
        }

        // --- the choices ---------------------------------------------------
        Column {
            visible: root.service !== null && !root.recording
            width: parent.width
            spacing: Theme.gap * 2

            Row {
                spacing: Theme.gap

                Repeater {
                    model: Model.MODES

                    Choice {
                        required property var modelData
                        objectName: "captureMode-" + modelData.id
                        controlId: "mode:" + modelData.id
                        iconText: modelData.glyph
                        text: I18n.tr(modelData.label)
                        selected: root.state.mode === modelData.id
                    }
                }
            }

            Row {
                visible: Model.targets(root.state.mode).length > 0
                spacing: Theme.gap

                Repeater {
                    model: Model.targets(root.state.mode)

                    Choice {
                        required property var modelData
                        objectName: "captureTarget-" + modelData.id
                        controlId: "target:" + modelData.id
                        text: I18n.tr(modelData.label)
                        selected: Model.currentTarget(root.state) === modelData.id
                    }
                }
            }

            Row {
                visible: root.state.mode !== "screenshot"
                spacing: Theme.gap

                Choice {
                    objectName: "captureDesktop"
                    controlId: "desktop"
                    iconText: "\uf028"
                    text: I18n.tr("Desktop audio")
                    selected: root.state.desktop
                }

                Choice {
                    objectName: "captureMic"
                    controlId: "mic"
                    iconText: "\uf130"
                    text: I18n.tr("Microphone")
                    selected: root.state.mic
                }
            }

            Row {
                visible: root.state.mode !== "audio"
                spacing: Theme.gap

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: I18n.tr("Delay")
                    color: root.dim
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.font.bodySmall
                }

                Repeater {
                    model: Model.DELAYS

                    Choice {
                        required property int modelData
                        objectName: "captureDelay-" + modelData
                        controlId: "delay:" + modelData
                        text: modelData === 0 ? I18n.tr("None") : I18n.tr("%1 s", modelData)
                        selected: root.state.delay === modelData
                    }
                }
            }

            Row {
                visible: root.state.mode === "audio"
                spacing: Theme.gap

                Repeater {
                    model: Model.FORMATS

                    Choice {
                        required property string modelData
                        objectName: "captureFormat-" + modelData
                        controlId: "format:" + modelData
                        text: modelData.toUpperCase()
                        selected: root.state.format === modelData
                    }
                }
            }

            Row {
                spacing: Theme.gap

                Choice {
                    objectName: "captureGo"
                    controlId: "capture"
                    iconText: root.state.mode === "screenshot" ? "\uf030" : "\uf111"
                    text: root.state.mode === "screenshot" ? I18n.tr("Capture") : I18n.tr("Record")
                    active: true
                    enabled: Model.canCapture(root.state)
                }

                Choice {
                    objectName: "captureEdit"
                    visible: root.state.mode === "screenshot"
                    controlId: "edit"
                    iconText: "\uf044"
                    text: I18n.tr("Edit")
                }
            }

            Text {
                visible: !Model.canCapture(root.state)
                text: I18n.tr("Choose desktop audio, the microphone or both")
                color: Theme.warning
                font.family: Theme.fontFamily
                font.pixelSize: Theme.font.bodySmall
            }
        }

        Text {
            visible: root.service !== null
            width: parent.width
            wrapMode: Text.Wrap
            text: root.service && root.service.controllers > 0 ? I18n.tr("%1  ·  %2", root.keyHint, I18n.tn("%1 controller", "%1 controllers", root.service.controllers)) : root.keyHint
            color: root.dim
            font.family: Theme.fontFamily
            font.pixelSize: Theme.font.caption
        }

        Text {
            visible: root.service !== null && root.service.controllerError !== "" && root.settings.controller === true
            width: parent.width
            wrapMode: Text.Wrap
            text: I18n.tr("Controller: %1", root.service ? root.service.controllerError : "")
            color: Theme.warning
            font.family: Theme.fontFamily
            font.pixelSize: Theme.font.caption
        }
    }

    // Test hook (settings.debugIpc): move the cursor and press as the keys
    // and the controller do, so a smoke test never injects input.
    IpcHandler {
        target: "haseen.capture"
        enabled: root.settings.debugIpc === true

        function move(direction: string): void {
            root.moveCursor(direction);
        }

        function press(): void {
            root.press(root.cursor);
        }

        function pad(button: string): void {
            root.pad(button);
        }

        function space(ctrl: bool): void {
            root.capture(ctrl && root.state.mode === "screenshot");
        }

        function state(): string {
            return JSON.stringify({
                cursor: root.cursor,
                rows: root.rows,
                state: root.state,
                recording: root.recording,
                hasService: root.service !== null
            });
        }
    }
}
