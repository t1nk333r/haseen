// Adapted from RulesView.qml of K53N0/omarchy-browser-picker (MIT, Copyright
// (c) 2026 K53N0), via the owner's fork t1nk33r.browser-picker; see LICENSE
// and UPSTREAM.md beside this file.
// haseen: one row per rule on Theme tokens; the profile is chosen from the
// panel's list instead of a searchable dropdown.
import QtQuick
import qs.Haseen
import qs.Haseen.Widgets

// A host → profile rule: the site, editable in place (Enter or leaving the
// field saves it), the profile it opens in (click to choose another) and ✕.
// A rule whose profile no longer exists says so instead of showing a raw id.
Item {
    id: root

    property var rule: ({})
    property string targetLabel: ""
    property bool choosing: false

    signal renamed(string oldPattern, string newPattern)
    signal chooseTarget
    signal removed

    width: parent ? parent.width : 0
    height: Math.round(Theme.fontSize * 2.4)

    function commit(): void {
        const next = field.text.trim().toLowerCase();
        if (next !== "" && next !== root.rule.pattern)
            root.renamed(root.rule.pattern, next);
        else
            field.text = root.rule.pattern;
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radius
        color: root.choosing ? Theme.selection : Theme.surfaceAlt
    }

    TextInput {
        id: field

        anchors.left: parent.left
        anchors.leftMargin: Theme.gap
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width * 0.42
        text: root.rule.pattern || ""
        color: Theme.foreground
        selectionColor: Theme.selection
        font.family: Theme.fontFamily
        font.pixelSize: Theme.font.body
        clip: true
        onAccepted: root.commit()
        onActiveFocusChanged: if (!activeFocus)
            root.commit()
    }

    Text {
        anchors.left: field.right
        anchors.leftMargin: Theme.gap
        anchors.right: remove.left
        anchors.rightMargin: Theme.gap
        anchors.verticalCenter: parent.verticalCenter
        text: root.targetLabel !== "" ? root.targetLabel : I18n.tr("missing profile: %1", root.rule.entryId || "")
        textFormat: Text.PlainText
        elide: Text.ElideRight
        color: root.targetLabel !== "" ? Theme.foreground : Theme.warning
        font.family: Theme.fontFamily
        font.pixelSize: Theme.font.body

        MouseArea {
            anchors.fill: parent
            onClicked: root.chooseTarget()
        }
    }

    BarButton {
        id: remove

        anchors.right: parent.right
        height: parent.height
        glyph: ""
        color: Theme.muted
        onClicked: root.removed()
    }
}
