import QtQuick
import Quickshell
import qs.Haseen

// The lock screen itself: clock, date, password field and a preview banner.
// Shared by the session-lock surfaces and the preview window. When the
// fingerprint reader is armed, a fingerprint glyph sits inside the field's
// right edge, as in Omarchy's lock (shell/plugins/lock/LockView.qml, MIT,
// Copyright (c) David Heinemeier Hansson) and hyprlock.
//
// The field is Omarchy's (LockView.qml:23-30,120-218, plan 117): 381 x 67 px,
// a 3 px outline in `[lock]`'s border-active / border / border-error colour,
// the `[lock]` fill, a heading*1.125 label, and password dots at heading*1.33
// with heading*0.19 letter spacing, shrunk to fit rather than clipped.
Rectangle {
    id: root

    property bool busy: false
    // message: the failure in English (a change clears the field);
    // messageText: the same, translated, as the field shows it.
    property string message: ""
    property string messageText: message
    property bool preview: false
    // Fingerprint unlock is armed: show the hint. fingerprintError: the last
    // scan did not match, so the hint turns urgent until the next one.
    property bool fingerprint: false
    property bool fingerprintError: false

    readonly property int fieldWidth: 381
    readonly property int fieldHeight: 67
    readonly property int outlineThickness: 3
    readonly property int fieldFontSize: Math.round(Theme.font.heading * 1.125)
    readonly property int passwordDotFontSize: Math.round(Theme.font.heading * 1.33)
    readonly property int passwordDotLetterSpacing: Math.round(Theme.font.heading * 0.19)
    // Room inside the outline between it and the field's text.
    readonly property int fieldInset: 18
    readonly property bool errorState: !root.busy && root.message !== ""
    readonly property color fieldBorder: root.errorState ? Theme.lock.borderError : input.activeFocus ? Theme.lock.borderActive : Theme.lock.border
    readonly property string fieldText: root.busy ? I18n.tr("Checking…") : root.errorState ? root.messageText : I18n.tr("Password")
    // Shrink the dots to fit once the password outgrows the field, so every
    // keystroke stays visible — otherwise long passwords clip with no
    // feedback (LockView.qml:29-31,153-154).
    readonly property real passwordDotScale: dotMetrics.advanceWidth > 0 ? Math.min(1, (input.width - 4) / dotMetrics.advanceWidth) : 1

    // Room kept clear on both sides for the hint, so the centred dots stay
    // centred and never run under it.
    readonly property real fingerprintReserve: fingerprint ? Math.ceil(fingerprintHint.implicitWidth + Theme.space(12)) : 0

    signal submitted(string password)
    signal cancelled
    signal attemptCancelled

    color: Theme.background
    // The top item of a lock surface or the preview window, never a
    // PanelPopup: mirror here in a right-to-left language (plan 109).
    LayoutMirroring.enabled: I18n.rightToLeft
    LayoutMirroring.childrenInherit: true

    // A failed attempt clears the field for the next one.
    onMessageChanged: {
        if (message !== "")
            input.text = "";
    }

    // Waking a display from DPMS can stall the compositor for seconds while
    // the monitor modesets, so the wake key's release arrives late and key
    // repeat floods the field with that character. A held key has no business
    // typing a password; only holding Backspace or Delete to clear stays
    // useful. Takes a key event, or anything with its key, isAutoRepeat and
    // accepted; true when it swallowed the event. Adapted from Omarchy
    // shell/plugins/lock/LockView.qml (6e15d76a6, pull request 7806), plan 103.
    function dropsAutoRepeat(event: var): bool {
        if (!event.isAutoRepeat || event.key === Qt.Key_Backspace || event.key === Qt.Key_Delete)
            return false;
        event.accepted = true;
        return true;
    }

    SystemClock {
        id: clock

        precision: SystemClock.Minutes
        enabled: root.visible
    }

    // Measures the masked password at full size; passwordDotScale compares
    // this against the field width to decide how far the dots must shrink.
    TextMetrics {
        id: dotMetrics

        font.family: Theme.fontFamily
        font.pixelSize: root.passwordDotFontSize
        font.letterSpacing: root.passwordDotLetterSpacing
        text: "●".repeat(input.text.length)
    }

    Column {
        anchors.centerIn: parent
        spacing: Theme.gap * 2

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatTime(clock.date, "HH:mm")
            color: Theme.lock.text
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize * 6
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            // The format is a catalog string, so a language can use its own
            // comma; the names come from the interface language (plan 109).
            text: I18n.formatDate(clock.date, I18n.tr("dddd, d MMMM"))
            color: Theme.lock.placeholder
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize + 2
        }

        Rectangle {
            id: field

            anchors.horizontalCenter: parent.horizontalCenter
            width: root.fieldWidth
            height: root.fieldHeight
            radius: Theme.radius
            color: Theme.lock.background
            border.color: root.fieldBorder
            border.width: root.outlineThickness
            clip: true

            TextInput {
                id: input

                anchors.fill: parent
                anchors.leftMargin: field.border.width + root.fieldInset + root.fingerprintReserve
                anchors.rightMargin: field.border.width + root.fieldInset + root.fingerprintReserve
                verticalAlignment: TextInput.AlignVCenter
                horizontalAlignment: TextInput.AlignHCenter
                echoMode: TextInput.Password
                passwordCharacter: "\u25CF"
                passwordMaskDelay: 0
                readOnly: root.busy
                focus: true
                clip: true
                color: Theme.lock.text
                selectionColor: Theme.lock.selection
                selectedTextColor: Theme.lock.text
                font.family: Theme.fontFamily
                font.pixelSize: text.length > 0 ? Math.max(1, Math.floor(root.passwordDotFontSize * root.passwordDotScale)) : root.fieldFontSize
                font.letterSpacing: text.length > 0 ? root.passwordDotLetterSpacing * root.passwordDotScale : 0
                onAccepted: root.submitted(text)
                // Keys handles a key before the field does: a repeat dropped
                // here never types, submits or clears anything.
                Keys.priority: Keys.BeforeItem
                Keys.onPressed: event => root.dropsAutoRepeat(event)
                Keys.onEscapePressed: {
                    if (root.preview)
                        root.cancelled();
                    else if (root.busy)
                        root.attemptCancelled();
                    else
                        text = "";
                }
            }

            Text {
                anchors.fill: input
                visible: input.text === ""
                text: root.fieldText
                color: root.busy ? Theme.lock.text : root.errorState ? Theme.lock.textError : Theme.lock.placeholder
                font.family: Theme.fontFamily
                font.pixelSize: root.fieldFontSize
                font.italic: root.errorState
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
            }

            Text {
                id: fingerprintHint

                objectName: "fingerprintHint"
                anchors.right: parent.right
                anchors.rightMargin: field.border.width + root.fieldInset
                anchors.verticalCenter: parent.verticalCenter
                visible: root.fingerprint
                // nf-md-fingerprint
                text: "󰈷"
                color: root.fingerprintError ? Theme.urgent : Theme.lock.placeholder
                font.family: Theme.fontMono
                font.pixelSize: Math.round(root.fieldFontSize * 1.1)
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.preview
            text: I18n.tr("Preview: the session is not locked. Escape closes it.")
            color: Theme.warning
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
        }
    }

    Component.onCompleted: input.forceActiveFocus()
}
