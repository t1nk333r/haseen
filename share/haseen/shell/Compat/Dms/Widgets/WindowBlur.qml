import QtQuick

// qs.Widgets.WindowBlur for DankMaterialShell plugins (architecture 5.4).
// DMS asks the compositor to blur a region behind a window; haseen draws no
// blur (architecture 6), so this keeps the properties and functions of
// DankMaterialShell's quickshell/Widgets/WindowBlur.qml (MIT, Copyright (c)
// 2025 Avenge Media LLC) and does nothing. The window's own colours show.
Item {
    id: root

    required property var targetWindow
    property bool blurEnabled: false
    property color surfaceColor: "transparent"
    property real blurX: 0
    property real blurY: 0
    property real blurWidth: 0
    property real blurHeight: 0
    property real blurRadius: 0
    property real blurBottomRadius: blurRadius
    property bool clipEnabled: false
    property real clipX: blurX
    property real clipY: blurY
    property real clipWidth: blurWidth
    property real clipHeight: blurHeight

    function kick() {
    }

    visible: false
}
