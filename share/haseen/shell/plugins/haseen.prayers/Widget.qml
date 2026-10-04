import QtQuick
import Quickshell
import qs.Haseen
import qs.Haseen.Widgets
import "Model.js" as Model

// Next prayer in the bar from the haseen.prayers service (role `prayers`):
// a to-scale day strip with the countdown, or a text label (barDisplay).
// Accent tint inside highlightBeforeMinutes of the next adhan or iqama.
// Left click toggles the panel, middle click cycles the bar label, right
// click re-reads the timezone window. Hover shows the full next-prayer line.
//
// Adapted from BarWidget.qml in OmaPrayers (MIT, Copyright (c) 2026 Salem
// Sayed); see LICENSE and UPSTREAM.md beside this file.
Item {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null
    // Set by BarSection in a left/right bar.
    property bool vertical: false

    readonly property var host: {
        const entry = Plugins.roles.prayers;
        return entry && entry.id === root.pluginId ? entry.instance : null;
    }
    readonly property bool ready: host !== null
    readonly property string displayText: ready ? Model.barText(host.nextEvent, host.nowTick, host.language, host.barDisplay, host.timeFormat) : ""
    readonly property bool iconOnly: displayText === "\ueed3"
    readonly property bool stripMode: ready && host.barDisplay === "Strip + countdown" && !vertical
    readonly property color tone: ready && host.prayerSoon ? Theme.accent : Theme.barForeground
    readonly property real dim: ready && host.unavailable ? 0.5 : 1

    implicitWidth: !ready ? 0 : stripMode ? stripRow.implicitWidth + Theme.gap * 2 : button.implicitWidth
    implicitHeight: stripMode ? Config.barThickness : button.implicitHeight

    function onClick(buttonCode: int): void {
        if (buttonCode === Qt.RightButton)
            host.refresh();
        else if (buttonCode === Qt.MiddleButton)
            host.cycleBarDisplay();
        else
            Quickshell.execDetached(["qs", "ipc", "--pid", String(Quickshell.processId), "call", "panel", "toggle", root.pluginId]);
    }

    BarButton {
        id: button

        anchors.fill: parent
        visible: root.ready
        vertical: root.vertical
        text: root.stripMode ? "" : root.displayText
        color: root.tone
        opacity: root.dim
        onClicked: b => root.onClick(b)
    }

    Row {
        id: stripRow

        visible: root.stripMode
        anchors.centerIn: parent
        spacing: Math.round(Theme.gap / 2)
        opacity: root.dim
        LayoutMirroring.enabled: root.ready && root.host.isArabic
        LayoutMirroring.childrenInherit: true

        Item {
            id: miniStrip

            readonly property var segments: root.ready ? root.host.daySegments : []

            anchors.verticalCenter: parent.verticalCenter
            width: Math.round(Theme.fontSize * 2.8)
            height: Math.round(Theme.fontSize * 0.66)

            // Fraction-based x positions do not inherit LayoutMirroring.
            function place(fraction: real, itemWidth: real): real {
                return root.host && root.host.isArabic ? width - fraction * width - itemWidth : fraction * width;
            }

            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: Qt.rgba(root.tone.r, root.tone.g, root.tone.b, 0.13)
            }

            Repeater {
                model: miniStrip.segments

                Rectangle {
                    required property var modelData

                    x: miniStrip.place((modelData.start - miniStrip.segments[0].start) / 1440, width)
                    width: 1
                    height: miniStrip.height
                    color: Qt.rgba(root.tone.r, root.tone.g, root.tone.b, 0.42)
                }
            }

            Rectangle {
                visible: miniStrip.segments.length > 0
                x: miniStrip.place(root.ready ? root.host.dayFraction : 0, width)
                width: 2
                height: parent.height
                color: Theme.accent
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: root.ready ? Model.remaining(root.host.nextEvent, root.host.nowTick, root.host.language) : ""
            color: root.tone
            font.family: root.ready && root.host.isArabic ? root.host.arabicFont : Theme.fontFamily
            font.pixelSize: Theme.fontSize
        }
    }

    // The strip has no BarButton under it: its own hover tint and clicks.
    Rectangle {
        anchors.fill: parent
        anchors.topMargin: 3
        anchors.bottomMargin: 3
        z: -1
        radius: Theme.radius
        color: Theme.surfaceAlt
        visible: root.stripMode && hover.hovered
    }

    // Passive: BarButton keeps its own hover tint in the text modes.
    HoverHandler {
        id: hover
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.stripMode
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: event => root.onClick(event.button)
    }

    // Hover line (next prayer, time, method); the window exists only while hovered.
    LazyLoader {
        active: hover.hovered && root.ready && root.host.tooltipText !== ""

        PopupWindow {
            readonly property string pos: Config.barPosition
            readonly property int away: pos === "bottom" ? Edges.Top : pos === "left" ? Edges.Right : pos === "right" ? Edges.Left : Edges.Bottom

            visible: true
            color: "transparent"
            anchor.item: root
            anchor.edges: away
            anchor.gravity: away
            anchor.margins.top: pos === "top" ? Theme.gap : 0
            anchor.margins.bottom: pos === "bottom" ? Theme.gap : 0
            anchor.margins.left: pos === "left" ? Theme.gap : 0
            anchor.margins.right: pos === "right" ? Theme.gap : 0
            implicitWidth: Math.ceil(label.implicitWidth) + Theme.gap * 2
            implicitHeight: Math.ceil(label.implicitHeight) + Theme.gap * 2

            Rectangle {
                anchors.fill: parent
                color: Theme.surface
                radius: Theme.radius
                border.width: Theme.borderWidth
                border.color: Theme.border

                Text {
                    id: label

                    anchors.centerIn: parent
                    text: root.host ? root.host.tooltipText : ""
                    textFormat: Text.PlainText
                    color: Theme.foreground
                    font.family: root.host && root.host.isArabic ? root.host.arabicFont : Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                }
            }
        }
    }
}
