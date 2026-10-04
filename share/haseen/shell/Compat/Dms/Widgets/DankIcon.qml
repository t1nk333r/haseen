import QtQuick
import qs.Common
import "icons.js" as Icons

// qs.Widgets.DankIcon for DankMaterialShell plugins (architecture 5.4): a
// Material Symbols icon by name. Properties follow DMS's DankIcon
// (DankMaterialShell, MIT, Copyright (c) 2025 Avenge Media LLC). With the
// Material Symbols Rounded font installed the name renders as a ligature;
// otherwise icons.js maps it to a Nerd Font glyph.
Text {
    id: icon

    property string name: ""
    property real size: Theme.iconSize
    property bool filled: false
    property real fill: filled ? 1 : 0
    property int grade: 0
    property int weight: Font.Normal
    readonly property bool material: Icons.hasMaterial()

    text: material ? name : Icons.glyph(name)
    color: Theme.surfaceText
    font.family: material ? "Material Symbols Rounded" : Theme.monoFontFamily
    font.pixelSize: material ? Math.round(size) : Math.round(size * 0.8)
    font.weight: weight
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    textFormat: Text.PlainText
}
