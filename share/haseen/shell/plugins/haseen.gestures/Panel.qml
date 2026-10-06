import QtQuick
import qs.Haseen
import "Model.js" as Model

// Gestures panel: what each swipe and pinch does, the workspace swipe's reach
// and the touchpad's click and scroll behaviour.
//
// Adapted from omagesture's Panel.qml (github.com/heroesofcode/omagesture,
// MIT, Copyright (c) 2026 Pedro Henrique), rebuilt on haseen's panel host and
// Theme tokens. The panel never writes Lua: every change goes through
// GestureSettings to `haseen gestures apply --set`. Open with
// `haseen shell ipc panel toggle haseen.gestures` or a bar click.
Column {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    readonly property bool on: settings.enabled !== false

    function save(patch: var): void {
        store.save(patch);
    }

    width: Theme.fontSize * 34
    spacing: Theme.gap

    GestureSettings {
        id: store
        pluginId: root.pluginId
    }

    component SectionLabel: Text {
        width: root.width
        color: Theme.muted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 1
        font.bold: true
    }

    component Note: Text {
        width: root.width
        wrapMode: Text.WordWrap
        color: Theme.muted
        font.family: Theme.fontFamily
        font.pixelSize: Math.max(1, Theme.fontSize - 2)
    }

    // One finger count: both swipe axes and the pinch.
    component FingerColumn: Column {
        id: column

        required property int fingers
        required property string title

        spacing: 2

        SectionLabel {
            width: column.width
            text: column.title
        }
        GestureChoice {
            width: column.width
            label: "Swipe ← →"
            options: Model.ACTIONS
            value: Model.axisValue(root.settings, column.fingers, "horizontal")
            onPicked: v => root.save(Model.axisPatch(column.fingers, "horizontal", v))
        }
        GestureChoice {
            width: column.width
            label: "Swipe ↑ ↓"
            options: Model.ACTIONS
            value: Model.axisValue(root.settings, column.fingers, "vertical")
            onPicked: v => root.save(Model.axisPatch(column.fingers, "vertical", v))
        }
        GestureChoice {
            width: column.width
            label: "Pinch"
            options: Model.ACTIONS
            value: Model.axisValue(root.settings, column.fingers, "pinch")
            onPicked: v => root.save(Model.axisPatch(column.fingers, "pinch", v))
        }
    }

    GestureSwitch {
        width: root.width
        label: "Gestures"
        description: Model.summary(root.settings)
        checked: root.on
        onToggled: root.save({
            enabled: !root.on
        })
    }

    Row {
        width: root.width
        spacing: Theme.gap * 2
        opacity: root.on ? 1 : 0.45

        FingerColumn {
            width: (root.width - Theme.gap * 2) / 2
            fingers: 3
            title: "THREE FINGERS"
        }
        FingerColumn {
            width: (root.width - Theme.gap * 2) / 2
            fingers: 4
            title: "FOUR FINGERS"
        }
    }

    // Two fingers get pinch only: their swipes are scroll, and a gesture
    // there would take scrolling away from every application.
    Column {
        width: root.width
        spacing: 2
        opacity: root.on ? 1 : 0.45

        SectionLabel {
            text: "TWO FINGERS"
        }
        GestureChoice {
            width: (root.width - Theme.gap * 2) / 2
            label: "Pinch"
            options: Model.ACTIONS
            value: Model.axisValue(root.settings, 2, "pinch")
            onPicked: v => root.save(Model.axisPatch(2, "pinch", v))
        }
        Note {
            visible: Model.axisValue(root.settings, 2, "pinch") !== "none"
            text: "While this is mapped the compositor takes the two-finger pinch first: browsers and image viewers lose their own pinch-to-zoom."
        }
    }

    // The swipe's reach only matters while some gesture switches workspaces.
    Column {
        width: root.width
        spacing: 2
        visible: Model.workspaceSwipeMapped(root.settings)

        SectionLabel {
            text: "WORKSPACE SWIPE"
        }
        GestureChoice {
            width: root.width
            label: "Reaches"
            options: Model.SWIPE_RANGES
            value: String(root.settings.swipeRange)
            onPicked: v => root.save({
                    swipeRange: v
                })
        }
        GestureSwitch {
            width: root.width
            label: "Keep swiping without lifting"
            description: "Cross several workspaces in one motion instead of one per swipe."
            checked: root.settings.swipeForever === true
            onToggled: root.save({
                swipeForever: root.settings.swipeForever !== true
            })
        }
    }

    Column {
        width: root.width
        spacing: 2

        SectionLabel {
            text: "TOUCHPAD"
        }
        GestureSwitch {
            width: root.width
            label: "Natural scrolling"
            description: "Content follows the fingers, on the touchpad and the mouse."
            checked: root.settings.naturalScroll !== false
            onToggled: root.save({
                naturalScroll: root.settings.naturalScroll === false
            })
        }
        GestureChoice {
            width: root.width
            label: "Click method"
            options: Model.CLICK_METHODS
            value: String(root.settings.clickMethod)
            onPicked: v => root.save({
                    clickMethod: v
                })
        }
        GestureChoice {
            width: root.width
            label: "Middle click"
            options: Model.MIDDLE_BUTTONS
            value: String(root.settings.middleButton)
            onPicked: v => root.save({
                    middleButton: v
                })
        }
        GestureChoice {
            width: root.width
            label: "Multi-finger drag"
            options: Model.DRAG_MODES
            value: String(root.settings.drag)
            onPicked: v => root.save({
                    drag: v
                })
        }
        Note {
            visible: root.settings.middleButton !== "none"
            text: "A three-finger click is the middle button, so applications no longer receive middle click: no paste on middle click, no open-link-in-new-tab."
        }
        Note {
            visible: Model.dragShadowed(root.settings)
            text: "Drag stays off while swipes of the same finger count are mapped: libinput can give those fingers to only one of the two."
        }
    }
}
