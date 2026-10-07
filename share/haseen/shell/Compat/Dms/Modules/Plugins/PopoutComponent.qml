import QtQuick
import qs.Common
import qs.Widgets

// qs.Modules.Plugins.PopoutComponent for DankMaterialShell plugins
// (architecture 5.4): the column a plugin's popoutContent builds, with an
// optional header and details line above the plugin's own items. The
// properties follow DankMaterialShell's
// quickshell/Modules/Plugins/PopoutComponent.qml (MIT, Copyright (c) 2025
// Avenge Media LLC); PluginPopout sets closePopout and parentPopout. As in
// DMS, showCloseButton is accepted and draws nothing.
Column {
    id: root

    property string headerText: ""
    property string detailsText: ""
    property bool showCloseButton: false
    property var closePopout: null
    property var parentPopout: null
    property alias headerActions: headerActionsLoader.sourceComponent

    readonly property int headerHeight: popoutHeader.visible ? popoutHeader.height : 0
    readonly property int detailsHeight: popoutDetails.visible ? popoutDetails.implicitHeight : 0

    spacing: 0

    Item {
        id: popoutHeader

        width: parent.width
        height: 40
        visible: root.headerText.length > 0

        StyledText {
            anchors.left: parent.left
            anchors.leftMargin: Theme.spacingS
            anchors.verticalCenter: parent.verticalCenter
            text: root.headerText
            font.pixelSize: Theme.fontSizeLarge + 4
        }

        Loader {
            id: headerActionsLoader

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    StyledText {
        id: popoutDetails

        width: parent.width
        leftPadding: Theme.spacingS
        bottomPadding: Theme.spacingS
        text: root.detailsText
        color: Theme.surfaceVariantText
        visible: root.detailsText.length > 0
        wrapMode: Text.WordWrap
    }
}
