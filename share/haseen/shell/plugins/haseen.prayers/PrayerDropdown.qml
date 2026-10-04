import QtQuick
import qs.Haseen

// Panel control for haseen.prayers, standing in for the Omarchy Ui control
// of the same role that upstream OmaPrayers used. Theme tokens only.
// A dropdown whose list opens inline under it (a second popup window would
// break the panel's focus grab), so the row holding it grows while open.
// `searchable` adds a filter field; options carry {value, label,
// description?}. Up/Down/Enter/Escape drive the list while it is open.
Column {
    id: root

    property var options: []
    property string value: ""
    property bool searchable: false
    property bool showLabel: false
    property string placeholderText: ""
    property string emptyText: ""
    property color foreground: Theme.foreground
    property string fontFamily: Theme.fontFamily
    property bool popupOpen: false
    property int highlighted: 0
    readonly property var current: {
        for (let i = 0; i < options.length; i++)
            if (String(options[i].value) === value)
                return options[i];
        return null;
    }
    readonly property var filtered: {
        const q = searchable ? filter.text.trim().toLowerCase() : "";
        if (q === "")
            return options;
        return options.filter(o => String(o.label).toLowerCase().indexOf(q) >= 0 || String(o.description || "").toLowerCase().indexOf(q) >= 0 || String(o.value) === q);
    }

    signal changed(string next)

    spacing: 2

    function open(): void {
        popupOpen = true;
        highlighted = Math.max(0, filtered.indexOf(current));
        if (searchable) {
            filter.text = "";
            Qt.callLater(() => filter.forceActiveFocus());
        } else {
            Qt.callLater(() => list.forceActiveFocus());
        }
    }

    function close(): void {
        popupOpen = false;
        filter.focus = false;
        list.focus = false;
    }

    function pick(index: int): void {
        const o = filtered[index];
        close();
        if (o && String(o.value) !== value)
            changed(String(o.value));
    }

    function keys(event: var): void {
        if (event.key === Qt.Key_Down) {
            highlighted = Math.min(filtered.length - 1, highlighted + 1);
            event.accepted = true;
        } else if (event.key === Qt.Key_Up) {
            highlighted = Math.max(0, highlighted - 1);
            event.accepted = true;
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            pick(highlighted);
            event.accepted = true;
        } else if (event.key === Qt.Key_Escape) {
            close();
            event.accepted = true;
        }
    }

    Rectangle {
        width: root.width
        height: headLabel.implicitHeight + Math.round(Theme.fontSize * 0.6)
        radius: Theme.radius
        color: headMouse.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08) : "transparent"
        border.width: Theme.borderWidth
        border.color: root.popupOpen ? Theme.accent : Theme.border

        Text {
            id: headLabel

            anchors.left: parent.left
            anchors.right: chevron.left
            anchors.leftMargin: Math.round(Theme.gap * 0.75)
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: root.current ? root.current.label : root.value
            color: root.foreground
            elide: Text.ElideRight
            font.family: root.fontFamily
            font.pixelSize: Math.max(1, Theme.fontSize - 1)
        }

        Text {
            id: chevron

            anchors.right: parent.right
            anchors.rightMargin: Math.round(Theme.gap * 0.75)
            anchors.verticalCenter: parent.verticalCenter
            text: root.popupOpen ? "\u25b4" : "\u25be"
            color: Theme.muted
            font.pixelSize: Math.max(1, Theme.fontSize - 1)
        }

        MouseArea {
            id: headMouse

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.popupOpen ? root.close() : root.open()
        }
    }

    PrayerTextField {
        id: filter

        visible: root.popupOpen && root.searchable
        width: root.width
        placeholderText: root.placeholderText
        foreground: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Math.max(1, Theme.fontSize - 1)
        onTextChanged: root.highlighted = 0
        Keys.onPressed: event => root.keys(event)
    }

    Text {
        visible: root.popupOpen && root.filtered.length === 0 && root.emptyText !== ""
        width: root.width
        textFormat: Text.PlainText
        text: root.emptyText
        color: Theme.muted
        font.family: root.fontFamily
        font.pixelSize: Math.max(1, Theme.fontSize - 1)
    }

    ListView {
        id: list

        visible: root.popupOpen && root.filtered.length > 0
        width: root.width
        height: visible ? Math.min(contentHeight, Theme.fontSize * 16) : 0
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: root.popupOpen ? root.filtered : []
        currentIndex: root.highlighted
        Keys.onPressed: event => root.keys(event)

        delegate: Rectangle {
            id: row

            required property var modelData
            required property int index

            width: list.width
            height: rowColumn.implicitHeight + Math.round(Theme.fontSize * 0.5)
            radius: Theme.radius
            color: index === root.highlighted || rowMouse.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10) : "transparent"

            Column {
                id: rowColumn

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: Math.round(Theme.gap * 0.75)
                anchors.rightMargin: anchors.leftMargin
                anchors.verticalCenter: parent.verticalCenter

                Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    text: row.modelData.label
                    color: String(row.modelData.value) === root.value ? Theme.accent : root.foreground
                    elide: Text.ElideRight
                    font.family: root.fontFamily
                    font.pixelSize: Math.max(1, Theme.fontSize - 1)
                }

                Text {
                    width: parent.width
                    visible: text !== ""
                    textFormat: Text.PlainText
                    text: row.modelData.description || ""
                    color: Theme.muted
                    elide: Text.ElideRight
                    font.family: root.fontFamily
                    font.pixelSize: Math.max(1, Theme.fontSize - 2)
                }
            }

            MouseArea {
                id: rowMouse

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.pick(row.index)
            }
        }
    }
}
