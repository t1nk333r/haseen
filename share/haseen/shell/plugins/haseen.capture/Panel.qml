import QtQuick
import Quickshell
import Quickshell.Io
import qs.Haseen
import qs.Haseen.Widgets
import "Model.js" as Model

// The capture toolbar (plan 150): a floating bar near the bottom of the
// screen, after the DMS ScreenCapture Toolbar the owner used (its look, none
// of its code: it has no license, plan 052), drawn in the theme's colours
// and font. Start to end: the mode (screenshot, video, sound), what it
// captures (for sound, its sources), the capture button, the options gear
// and close. The gear opens a card above the bar with the mode's options: a
// screenshot's delay and editor, a video's sound and delay, a sound's
// format. A hint under the bar names the control under the cursor and the
// keys. While a recording runs the bar is its elapsed time and a stop button.
//
// The state and the capture itself are the haseen.capture service's (role
// `capture`), so a delay and a recording outlive this panel, which is freed
// when it closes.
//
// Placement "overlay" (the default) gives the panel the whole screen
// (PanelPopup.qml): the bar sits near the bottom, a click anywhere else
// closes it and Escape is handled here. Any other placement shows the bar in
// a panel card at its own size. `shape` "pill" (the default) rounds the bar,
// its buttons and the card fully, as the original; "theme" takes the theme's
// corners.
//
// One cursor serves the keyboard and a game controller (Model.rows, .move):
// arrow keys or the D-pad move it, Tab and Shift+Tab walk every control,
// Enter or A presses the control under it. Space or Start captures,
// Ctrl+Space captures and opens the editor (screenshots), Escape or B closes
// the options card and then the toolbar, Y opens the options. Left and Right
// follow the screen in a right-to-left language, as the menu's do
// (architecture 5.8).
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
    // The options card above the bar: the panel's own, closed on open.
    property bool optionsOpen: false
    readonly property bool cardShown: optionsOpen && !recording && service !== null
    readonly property var rows: Model.rows(state, recording, cardShown)
    property string cursor: Model.home(rows)
    // A control that left the toolbar (another mode's, or the closed card's)
    // hands the cursor back to the capture button.
    onRowsChanged: if (!rows.some(r => r.indexOf(cursor) >= 0))
        cursor = Model.home(rows)
    readonly property string keyHint: recording ? I18n.tr("Space stops · Esc closes") : state.mode === "screenshot" ? I18n.tr("Space captures · Ctrl+Space edits · Esc closes") : I18n.tr("Space records · Esc closes")
    readonly property string cursorLabel: {
        const l = Model.label(state, cursor);
        return l === "" ? "" : I18n.tr(l);
    }

    readonly property bool overlay: settings.placement === "overlay"
    readonly property bool round: settings.shape !== "theme"
    // The bar's buttons: Omarchy's control height, a little larger, as the
    // original's touch-sized circles.
    readonly property int controlSize: Math.round(Theme.spacing.controlHeight * 1.3)
    readonly property int inset: Theme.space(6)
    readonly property int edge: Math.max(1, Theme.borderWidth)
    readonly property color ink: Theme.popups.text
    readonly property color dim: Qt.alpha(Theme.popups.text, 0.7)
    // Clear of a bar at the bottom: the overlay ignores exclusive zones.
    readonly property int bottomMargin: (Config.barPosition === "bottom" ? Config.barThickness : 0) + Theme.space(48)

    function cornerFor(size: real, rounded: real): real {
        return root.round ? rounded : Math.min(Theme.radius, size / 2);
    }

    implicitWidth: stack.width
    implicitHeight: stack.height
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

    // Escape and B: the card first, then the toolbar.
    function back(): void {
        if (cardShown)
            optionsOpen = false;
        else
            close();
    }

    function press(id: string): void {
        const result = Model.activate(state, id);
        if (!result)
            return;
        if (result.action === "close") {
            close();
            return;
        }
        if (result.action === "options") {
            optionsOpen = !optionsOpen;
        } else if (!service) {
            return;
        } else if (result.key !== undefined) {
            service.change(result.key, result.value);
        } else if (result.action === "stop") {
            service.stop();
        } else {
            capture(false);
        }
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
            back();
        else if (action.change)
            service.change(action.change.key, action.change.value);
        else if (action.action === "options")
            optionsOpen = !optionsOpen;
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
    Keys.onEscapePressed: back()
    Keys.onSpacePressed: event => capture((event.modifiers & Qt.ControlModifier) !== 0 && state.mode === "screenshot")

    // A round icon button of the bar.
    component IconButton: PanelButton {
        required property string controlId
        property string glyph: ""

        implicitWidth: root.controlSize
        implicitHeight: root.controlSize
        horizontalPadding: 0
        verticalPadding: 0
        radius: root.cornerFor(height, height / 2)
        iconText: glyph
        iconSize: Theme.font.iconLarge
        foreground: root.ink
        opacity: enabled ? 1 : 0.5
        hasCursor: root.cursor === controlId
        Accessible.name: Model.label(root.state, controlId) === "" ? "" : I18n.tr(Model.label(root.state, controlId))
        onClicked: root.press(controlId)
        onHovered: isHovered => {
            if (isHovered)
                root.cursor = controlId;
        }
    }

    // A text chip of the options card: a delay or a format.
    component Chip: PanelButton {
        required property string controlId

        bordered: true
        radius: root.cornerFor(height, height / 2)
        foreground: root.ink
        fontSize: Theme.font.bodySmall
        hasCursor: root.cursor === controlId
        onClicked: root.press(controlId)
        onHovered: isHovered => {
            if (isHovered)
                root.cursor = controlId;
        }
    }

    // A divider between the bar's groups.
    component Divider: Rectangle {
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        width: Math.max(1, Theme.space(1))
        height: Math.round(root.controlSize * 0.55)
        color: Theme.separator
    }

    // A section of the options card: a heading and what it holds.
    component Section: Rectangle {
        id: section

        default property alias content: body.data
        property string glyph: ""
        property string title: ""

        width: parent ? parent.width : 0
        implicitHeight: body.implicitHeight + root.inset * 2
        radius: root.cornerFor(height, Theme.space(12))
        color: Qt.alpha(root.ink, Theme.normalFillAlpha)

        Column {
            id: body

            x: root.inset
            y: root.inset
            width: parent.width - root.inset * 2
            spacing: Theme.space(8)

            Row {
                visible: section.title !== ""
                spacing: Theme.space(8)

                Glyph {
                    anchors.verticalCenter: parent.verticalCenter
                    glyph: section.glyph
                    color: root.dim
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: section.title
                    color: root.ink
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.font.body
                }
            }
        }
    }

    // An on/off row of the options card.
    component SwitchRow: Item {
        id: switchRow

        required property string controlId
        required property string glyph
        required property string label
        required property bool on

        width: parent ? parent.width : 0
        implicitHeight: Math.max(toggle.implicitHeight, name.implicitHeight)

        Glyph {
            id: mark

            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            glyph: switchRow.glyph
            color: root.dim
        }

        Text {
            id: name

            anchors.left: mark.right
            anchors.leftMargin: Theme.space(8)
            anchors.right: toggle.left
            anchors.rightMargin: Theme.space(8)
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            text: switchRow.label
            color: root.ink
            font.family: Theme.fontFamily
            font.pixelSize: Theme.font.body
        }

        PanelSwitch {
            id: toggle

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            checked: switchRow.on
            rounded: root.round || Theme.radius > 0
            foreground: root.ink
            hasCursor: root.cursor === switchRow.controlId
            onToggled: root.press(switchRow.controlId)
            onHovered: isHovered => {
                if (isHovered)
                    root.cursor = switchRow.controlId;
            }
        }
    }

    // A click anywhere but the bar, the card or the hint closes the toolbar.
    MouseArea {
        anchors.fill: parent
        enabled: root.overlay
        onClicked: root.close()
    }

    // The card, the bar and the hint, top to bottom.
    Item {
        id: stack

        readonly property bool mirrored: LayoutMirroring.enabled

        width: Math.max(bar.width, root.cardShown ? card.width : 0, hint.visible ? hint.width : 0)
        height: column.implicitHeight
        anchors.horizontalCenter: root.overlay ? parent.horizontalCenter : undefined
        anchors.bottom: root.overlay ? parent.bottom : undefined
        anchors.bottomMargin: root.overlay ? root.bottomMargin : 0

        Column {
            id: column

            width: stack.width
            spacing: Theme.space(10)

            // --- the options card ---------------------------------------
            Item {
                id: cardBox

                // The card stands over the gear, as far as the stack allows;
                // its nub points at the gear.
                readonly property real gearFromEdge: root.inset + root.controlSize + bar.spacing + root.controlSize / 2
                readonly property real gearCentre: stack.mirrored ? bar.x + gearFromEdge : bar.x + bar.width - gearFromEdge

                visible: root.cardShown
                x: Math.max(0, Math.min(gearCentre - card.width / 2, stack.width - card.width))
                width: card.width
                height: card.height + nub.height / 2

                Rectangle {
                    id: card

                    width: Math.max(cardColumn.implicitWidth, Theme.space(280)) + root.inset * 4
                    height: cardColumn.implicitHeight + root.inset * 4
                    radius: root.cornerFor(height, Theme.space(20))
                    color: Theme.popups.background
                    border.color: Theme.popups.border
                    border.width: root.edge

                    MouseArea {
                        anchors.fill: parent
                    }

                    Column {
                        id: cardColumn

                        x: root.inset * 2
                        y: root.inset * 2
                        width: card.width - root.inset * 4
                        spacing: Theme.space(10)

                        Row {
                            spacing: Theme.space(8)

                            Glyph {
                                anchors.verticalCenter: parent.verticalCenter
                                glyph: Model.GLYPHS.options
                                color: root.ink
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: I18n.tr("Options")
                                color: root.ink
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.font.subtitle
                            }
                        }

                        Section {
                            visible: root.state.mode === "video"

                            Repeater {
                                model: Model.SOURCES

                                SwitchRow {
                                    required property var modelData
                                    objectName: "captureOption-" + modelData.id
                                    controlId: modelData.id
                                    glyph: modelData.glyph
                                    label: I18n.tr(modelData.label)
                                    on: root.state[modelData.id] === true
                                }
                            }
                        }

                        Section {
                            visible: root.state.mode !== "audio"
                            glyph: Model.GLYPHS.delay
                            title: I18n.tr("Delay")

                            Row {
                                spacing: Theme.space(6)

                                Repeater {
                                    model: Model.DELAYS

                                    Chip {
                                        required property int modelData
                                        objectName: "captureDelay-" + modelData
                                        controlId: "delay:" + modelData
                                        text: modelData === 0 ? I18n.tr("None") : I18n.tr("%1 s", modelData)
                                        selected: root.state.delay === modelData
                                    }
                                }
                            }
                        }

                        Section {
                            visible: root.state.mode === "screenshot"

                            SwitchRow {
                                objectName: "captureEdit"
                                controlId: "edit"
                                glyph: Model.GLYPHS.edit
                                label: I18n.tr("Open in the editor")
                                on: root.state.edit === true
                            }
                        }

                        Section {
                            visible: root.state.mode === "audio"
                            glyph: Model.GLYPHS.format
                            title: I18n.tr("Format")

                            Flow {
                                width: parent.width
                                spacing: Theme.space(6)

                                Repeater {
                                    model: Model.FORMATS

                                    Chip {
                                        required property string modelData
                                        objectName: "captureFormat-" + modelData
                                        controlId: "format:" + modelData
                                        text: modelData.toUpperCase()
                                        selected: root.state.format === modelData
                                    }
                                }
                            }
                        }
                    }
                }

                // The nub under the card, pointing at the gear: a turned
                // square, its upper half and the card's edge above it hidden
                // by a patch of the card's colour.
                Rectangle {
                    id: nub

                    readonly property real side: Theme.space(14)

                    x: Math.max(card.radius, Math.min(cardBox.gearCentre - cardBox.x, card.width - card.radius)) - width / 2
                    y: card.height - height / 2
                    width: side
                    height: side
                    rotation: 45
                    color: Theme.popups.background
                    border.color: Theme.popups.border
                    border.width: root.edge
                }

                Rectangle {
                    x: nub.x - nub.width * 0.2
                    y: card.height - nub.height * 0.75 - root.edge
                    width: nub.width * 1.4
                    height: nub.height * 0.75
                    color: Theme.popups.background
                }
            }

            // --- the bar --------------------------------------------------
            Rectangle {
                id: bar

                readonly property int spacing: Theme.space(4)

                x: (stack.width - width) / 2
                width: barRow.implicitWidth + root.inset * 2
                height: root.controlSize + root.inset * 2
                radius: root.cornerFor(height, height / 2)
                color: Theme.popups.background
                border.color: Theme.popups.border
                border.width: root.edge

                MouseArea {
                    anchors.fill: parent
                }

                Row {
                    id: barRow

                    anchors.centerIn: parent
                    spacing: bar.spacing

                    // Without its service the toolbar can run nothing.
                    Text {
                        id: problem

                        visible: !root.service
                        anchors.verticalCenter: parent.verticalCenter
                        leftPadding: Theme.space(8)
                        rightPadding: Theme.space(8)
                        text: I18n.tr("The capture service is not running. Enable it with: haseen plugin enable haseen.capture")
                        color: root.ink
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.font.body
                    }

                    // A running recording.
                    Row {
                        visible: root.service !== null && root.recording
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.space(10)
                        leftPadding: Theme.space(10)

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: Theme.space(10)
                            height: width
                            radius: width / 2
                            color: Theme.urgent
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.service ? root.service.elapsed : ""
                            color: root.ink
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.font.title
                        }

                        Glyph {
                            anchors.verticalCenter: parent.verticalCenter
                            glyph: root.service && root.service.recordingKind === "audio" ? Model.GLYPHS.sound : Model.MODES[1].glyph
                            color: root.dim
                        }

                        IconButton {
                            objectName: "captureStop"
                            controlId: "stop"
                            glyph: Model.GLYPHS.stop
                            active: true
                        }
                    }

                    // The modes.
                    Repeater {
                        model: root.service !== null && !root.recording ? Model.MODES : []

                        IconButton {
                            required property var modelData
                            objectName: "captureMode-" + modelData.id
                            controlId: "mode:" + modelData.id
                            glyph: modelData.glyph
                            selected: root.state.mode === modelData.id
                        }
                    }

                    Divider {
                        visible: root.service !== null && !root.recording
                    }

                    // What the mode captures; sound's sources in its place.
                    Repeater {
                        model: root.service !== null && !root.recording ? Model.targets(root.state.mode) : []

                        IconButton {
                            required property var modelData
                            objectName: "captureTarget-" + modelData.id
                            controlId: "target:" + modelData.id
                            glyph: modelData.glyph
                            selected: Model.currentTarget(root.state) === modelData.id
                        }
                    }

                    Repeater {
                        model: root.service !== null && !root.recording && root.state.mode === "audio" ? Model.SOURCES : []

                        IconButton {
                            required property var modelData
                            objectName: modelData.id === "mic" ? "captureMic" : "captureDesktop"
                            controlId: modelData.id
                            glyph: modelData.glyph
                            selected: root.state[modelData.id] === true
                        }
                    }

                    Divider {
                        visible: root.service !== null && !root.recording
                    }

                    // Capture: the accent's own circle.
                    Rectangle {
                        visible: root.service !== null && !root.recording
                        anchors.verticalCenter: parent.verticalCenter
                        width: root.controlSize
                        height: root.controlSize
                        radius: root.cornerFor(height, height / 2)
                        color: Theme.accent
                        opacity: go.enabled ? 1 : 0.5

                        IconButton {
                            id: go

                            objectName: "captureGo"
                            anchors.fill: parent
                            controlId: "capture"
                            glyph: root.state.mode === "screenshot" ? Model.GLYPHS.capture : Model.GLYPHS.record
                            foreground: Theme.accentFg
                            opacity: 1
                            enabled: Model.canCapture(root.state)
                        }
                    }

                    IconButton {
                        objectName: "captureOptions"
                        visible: root.service !== null && !root.recording
                        controlId: "options"
                        glyph: Model.GLYPHS.options
                        selected: root.cardShown
                    }

                    IconButton {
                        objectName: "captureClose"
                        controlId: "close"
                        glyph: Model.GLYPHS.close
                    }
                }
            }

            // --- the hint -------------------------------------------------
            Rectangle {
                id: hint

                readonly property string line: {
                    let text = root.keyHint;
                    if (root.cursorLabel !== "")
                        text = I18n.tr("%1  ·  %2", root.cursorLabel, text);
                    if (root.service && root.service.controllers > 0)
                        text = I18n.tr("%1  ·  %2", text, I18n.tn("%1 controller", "%1 controllers", root.service.controllers));
                    return text;
                }

                visible: root.service !== null
                x: (stack.width - width) / 2
                width: hintColumn.implicitWidth + Theme.space(14) * 2
                height: hintColumn.implicitHeight + Theme.space(6) * 2
                radius: root.cornerFor(height, height / 2)
                color: Theme.popups.background
                border.color: Qt.alpha(Theme.popups.border, 0.5)
                border.width: root.edge

                MouseArea {
                    anchors.fill: parent
                }

                Column {
                    id: hintColumn

                    anchors.centerIn: parent

                    Text {
                        objectName: "captureHint"
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: hint.line
                        color: root.dim
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.font.caption
                    }

                    Text {
                        visible: !Model.canCapture(root.state) && !root.recording
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: I18n.tr("Choose desktop audio, the microphone or both")
                        color: Theme.warning
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.font.caption
                    }

                    Text {
                        visible: root.service !== null && root.service.controllerError !== "" && root.settings.controller === true
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: I18n.tr("Controller: %1", root.service ? root.service.controllerError : "")
                        color: Theme.warning
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.font.caption
                    }
                }
            }
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
                options: root.cardShown,
                hasService: root.service !== null
            });
        }
    }
}
