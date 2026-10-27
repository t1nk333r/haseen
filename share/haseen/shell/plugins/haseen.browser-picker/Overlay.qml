// Adapted from Picker.qml (the card) of K53N0/omarchy-browser-picker (MIT,
// Copyright (c) 2026 K53N0), via the owner's fork t1nk33r.browser-picker;
// see LICENSE and UPSTREAM.md beside this file.
// haseen: PanelSurface on Theme tokens; created by the service's LazyLoader
// only while a link waits for an answer.
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Haseen
import qs.Haseen.Widgets
import "Model.js" as Model

// The card: the link's host, a filter, the ranked browsers and profiles. Type
// to filter (fzf-style: `chdes` finds "Chrome — Design Studio"), arrows move,
// Enter opens, Ctrl+Enter opens and makes it the rule for this host, Escape
// or a click outside opens nothing.
PanelWindow {
    id: root

    property var service: null

    property string filter: ""
    property int cursor: 0
    readonly property var rows: !service ? [] : Model.rankEntries(service.entries, service.pickerState, service.config, service.host, filter, Date.now() / 1000)
    readonly property var currentEntry: rows.length > 0 && cursor >= 0 && cursor < rows.length ? rows[cursor] : null
    readonly property bool offersRule: service !== null && currentEntry !== null && Model.shouldOfferRule(service.pickerState, service.config, service.host, currentEntry, service.pickerSettings.promptAfter)
    readonly property string heading: !service ? "" : service.host || (service.urls.length > 0 ? service.urls[0] : I18n.tr("Open with"))
    readonly property int rowHeight: Math.round(Theme.fontSize * 2.2)
    // The pointer position the card opened under: rows that slide under a
    // still pointer are not a hover, or Enter would open a profile the user
    // never looked at.
    property point lastPointer: Qt.point(-1, -1)

    function setFilter(text: string): void {
        field.text = text;
    }

    function move(delta: int): void {
        if (rows.length === 0) {
            cursor = 0;
            return;
        }
        cursor = Math.max(0, Math.min(rows.length - 1, cursor + delta));
    }

    function choose(makeRule: bool): void {
        if (currentEntry)
            service.finish(currentEntry, makeRule);
        else
            service.cancel();
    }

    onRowsChanged: if (cursor >= rows.length)
        cursor = Math.max(0, rows.length - 1)

    screen: service ? service.targetScreen : null
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.namespace: "haseen-browser-picker"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    MouseArea {
        anchors.fill: parent
        onClicked: root.service.cancel()
    }

    PanelSurface {
        id: card

        // The card is this window's own content, not a PanelPopup panel, so
        // it mirrors itself in a right-to-left language.
        LayoutMirroring.enabled: I18n.rightToLeft
        LayoutMirroring.childrenInherit: true
        anchors.centerIn: parent
        padding: Theme.gap * 2

        // Clicks inside the card do not reach the cancel area behind it.
        MouseArea {
            width: card.width
            height: card.height
            x: -card.padding
            y: -card.padding
        }

        Column {
            width: Math.min(root.width - Theme.gap * 10, Theme.fontSize * 36)
            spacing: Theme.gap

            Text {
                width: parent.width
                text: root.heading
                textFormat: Text.PlainText
                elide: Text.ElideMiddle
                color: Theme.accent
                font.family: Theme.fontFamily
                font.pixelSize: Theme.font.title
            }

            Rectangle {
                width: parent.width
                height: Theme.fontSize * 2.4
                radius: Theme.radius
                color: Theme.surfaceAlt
                border.color: field.activeFocus ? Theme.accent : Theme.border
                border.width: Theme.borderWidth

                TextInput {
                    id: field

                    anchors.fill: parent
                    anchors.leftMargin: Theme.gap * 1.5
                    anchors.rightMargin: Theme.gap * 1.5
                    verticalAlignment: TextInput.AlignVCenter
                    focus: true
                    color: Theme.foreground
                    selectionColor: Theme.selection
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.font.subtitle
                    clip: true
                    onTextChanged: {
                        root.filter = text;
                        root.cursor = 0;
                    }
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Escape)
                            root.service.cancel();
                        else if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab)
                            root.move(1);
                        else if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab)
                            root.move(-1);
                        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                            root.choose((event.modifiers & Qt.ControlModifier) !== 0);
                        else
                            return;
                        event.accepted = true;
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        visible: field.text === ""
                        text: I18n.tr("Type to filter")
                        color: Theme.muted
                        font: field.font
                    }
                }
            }

            Text {
                width: parent.width
                visible: root.rows.length === 0
                text: !root.service ? "" : !root.service.scanned ? I18n.tr("Looking for browsers…") : root.service.entries.length === 0 ? I18n.tr("No browser found.") : I18n.tr("No profile matches \"%1\"", root.filter)
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.font.body
            }

            ListView {
                id: list

                width: parent.width
                // Every row that fits on screen is one not scrolled to.
                height: Math.min(contentHeight, root.height - Theme.fontSize * 14)
                visible: root.rows.length > 0
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: root.rows
                currentIndex: root.cursor
                highlightMoveDuration: 0
                onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

                delegate: Item {
                    id: row

                    required property var modelData
                    required property int index
                    readonly property bool current: index === root.cursor

                    width: list.width
                    height: root.rowHeight

                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.radius
                        color: row.current ? Theme.selection : "transparent"
                    }

                    // A hard accent edge on the selected row survives a busy
                    // wallpaper behind a translucent theme.
                    Rectangle {
                        // The start edge: the right one in a right-to-left card.
                        anchors.left: parent.left
                        width: Math.max(2, Theme.borderWidth * 3)
                        height: parent.height
                        radius: Theme.radius
                        color: Theme.accent
                        visible: row.current
                    }

                    Text {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.gap * 1.5
                        anchors.rightMargin: Theme.gap
                        verticalAlignment: Text.AlignVCenter
                        text: row.modelData.label
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        color: Theme.foreground
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.font.body
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onPositionChanged: mouse => {
                            const p = mapToItem(null, mouse.x, mouse.y);
                            const moved = root.lastPointer.x >= 0 && (p.x !== root.lastPointer.x || p.y !== root.lastPointer.y);
                            root.lastPointer = p;
                            if (moved)
                                root.cursor = row.index;
                        }
                        onClicked: {
                            root.cursor = row.index;
                            root.choose(false);
                        }
                    }
                }
            }

            Text {
                width: parent.width
                text: root.offersRule ? I18n.tr("⏎ open · Ctrl+⏎ always open %1 here", root.service.host) : I18n.tr("⏎ open · ↑↓ move · esc cancel")
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: root.offersRule ? Theme.accent : Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.font.bodySmall
            }
        }
    }
}
