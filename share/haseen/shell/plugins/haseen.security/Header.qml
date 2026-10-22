import QtQuick
import qs.Haseen
Row {
    id: root
    property bool nested: false
    property bool refreshing: false
    signal back()
    // An English page name (I18n.mark), translated here.
    property string backPage: I18n.mark("Overview")
    signal refresh()
    signal close()
    spacing: Theme.gap
    // The back arrow points to where the row starts: right in a mirrored
    // (right-to-left) panel.
    ActionButton { id: backButton; visible: root.nested; text: I18n.rightToLeft ? "\uf061" : "\uf060"; glyphOnly: true; width: height; Accessible.name: I18n.tr("Back to %1", I18n.tr(root.backPage)); onClicked: root.back() }
    Label { width: Math.max(1, root.width - controls.width - (backButton.visible ? backButton.width + root.spacing : 0) - root.spacing); height: Math.max(Math.round(48 * Theme.fontSize / 11), implicitHeight); text: I18n.tr("Security workstation"); heading: true; font.pixelSize: Math.round(16 * Theme.fontSize / 11); verticalAlignment: Text.AlignVCenter }
    Row {
        id: controls
        spacing: Theme.gap
        ActionButton { text: "\uf021"; glyphOnly: true; width: height; Accessible.name: I18n.tr("Refresh local status"); enabled: !root.refreshing; onClicked: root.refresh() }
        ActionButton { text: "\uf00d"; glyphOnly: true; width: height; Accessible.name: I18n.tr("Close Security workstation"); onClicked: root.close() }
    }
}
