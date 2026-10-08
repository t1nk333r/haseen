import QtQuick
import qs.Haseen
Row {
    id: root
    property bool nested: false
    property bool refreshing: false
    signal back()
    property string backPage: "Overview"
    signal refresh()
    signal close()
    spacing: Theme.gap
    ActionButton { id: backButton; visible: root.nested; text: "\uf060"; glyphOnly: true; width: height; Accessible.name: "Back to " + root.backPage; onClicked: root.back() }
    Label { width: Math.max(1, root.width - controls.width - (backButton.visible ? backButton.width + root.spacing : 0) - root.spacing); height: Math.max(Math.round(48 * Theme.fontSize / 11), implicitHeight); text: "Security workstation"; heading: true; font.pixelSize: Math.round(16 * Theme.fontSize / 11); verticalAlignment: Text.AlignVCenter }
    Row {
        id: controls
        spacing: Theme.gap
        ActionButton { text: "\uf021"; glyphOnly: true; width: height; Accessible.name: "Refresh local status"; enabled: !root.refreshing; onClicked: root.refresh() }
        ActionButton { text: "\uf00d"; glyphOnly: true; width: height; Accessible.name: "Close Security workstation"; onClicked: root.close() }
    }
}
