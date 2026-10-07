import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.Haseen
import "MenuStyle.js" as Style

// One row of haseen.menu (Panel.qml's ListView delegate), Omarchy's row: a
// glyph or app icon in a fixed column, the label, the description under it
// while a search runs (always in a pick list), a chevron on submenus. The
// selected row is tinted with the foreground and draws in the accent; it
// changes at once, with no moving highlight to lag behind or overshoot. Roles
// come from MenuModel.displayRow and MenuModel.pickRows.
//
// Adapted from Omarchy shell/plugins/menu/Menu.qml (MIT, Copyright (c)
// David Heinemeier Hansson).
Rectangle {
    id: row

    required property string itemId
    required property string kind
    required property string icon
    required property string appIcon
    required property string label
    required property string detail
    required property bool disabled
    // The Panel.qml root: sizes, colours and the query.
    required property var menu
    property bool hasCursor: false

    readonly property bool isApp: kind === "app"
    readonly property bool hasIcon: icon.length > 0 || isApp
    readonly property bool submenu: kind === "menu" || kind === "link"

    signal hovered(Item item, var mouse)
    signal clicked

    height: menu.rowHeightForDetail(detail)
    radius: menu.cornerRadius
    color: hasCursor ? menu.selectedBackground : "transparent"
    // haseen's `disabled` rows (software already installed) stay readable but
    // recede; the cursor skips them.
    opacity: disabled ? 0.5 : 1

    Text {
        id: glyph

        visible: row.hasIcon && !row.isApp
        anchors.left: parent.left
        anchors.leftMargin: row.menu.space(8)
        y: content.y + labelText.y + (labelText.height - height) / 2
        width: row.menu.iconColumn
        text: row.icon
        color: row.hasCursor ? row.menu.selectedText : row.menu.foreground
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        textFormat: Text.PlainText
        font.family: row.menu.fontFamily
        font.pixelSize: row.menu.iconSize
    }

    IconImage {
        visible: row.isApp
        anchors.left: parent.left
        anchors.leftMargin: row.menu.space(8) + (row.menu.iconColumn - implicitSize) / 2
        y: content.y + labelText.y + (labelText.height - height) / 2
        implicitSize: row.menu.iconSize
        asynchronous: true
        source: row.isApp && row.appIcon !== "" ? Quickshell.iconPath(row.appIcon, true) : ""
    }

    Column {
        id: content

        anchors.left: row.hasIcon ? glyph.right : parent.left
        anchors.leftMargin: row.hasIcon ? row.menu.space(6) : row.menu.space(18)
        anchors.right: trail.left
        anchors.rightMargin: row.menu.space(6)
        anchors.verticalCenter: parent.verticalCenter
        spacing: row.menu.space(3)

        Text {
            id: labelText

            width: parent.width
            text: row.label
            color: row.hasCursor ? row.menu.selectedText : row.menu.foreground
            elide: Text.ElideRight
            textFormat: Text.PlainText
            font.family: row.menu.fontFamily
            font.pixelSize: row.menu.headingSize
            font.weight: Font.Medium
        }

        Text {
            width: parent.width
            visible: row.menu.detailShown(row.detail)
            text: row.detail
            color: row.hasCursor ? row.menu.detailOnSelected : row.menu.detailOnCard
            elide: Text.ElideRight
            textFormat: Text.PlainText
            font.family: row.menu.fontFamily
            font.pixelSize: row.menu.fontPx(0.917)
        }
    }

    Text {
        id: trail

        anchors.right: parent.right
        anchors.rightMargin: row.menu.space(8)
        y: content.y + labelText.y + (labelText.height - height) / 2
        width: row.menu.space(14)
        text: row.submenu ? "›" : ""
        color: row.hasCursor ? row.menu.selectedText : row.menu.foreground
        opacity: Style.CHEVRON
        textFormat: Text.PlainText
        font.family: row.menu.fontFamily
        font.pixelSize: row.menu.headingSize
        font.weight: Font.Normal
    }

    MouseArea {
        id: mouseArea

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: row.hovered(row, {
            x: mouseArea.mouseX,
            y: mouseArea.mouseY
        })
        onPositionChanged: mouse => row.hovered(row, mouse)
        onClicked: row.clicked()
    }
}
