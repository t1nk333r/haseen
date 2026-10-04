import QtQuick
import qs.Common

// qs.Widgets.StyledText for DankMaterialShell plugins (architecture 5.4):
// a Text with the theme's font and surfaceText colour, as DMS's StyledText
// (DankMaterialShell, MIT, Copyright (c) 2025 Avenge Media LLC) defaults to.
Text {
    color: Theme.surfaceText
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fontSizeMedium
    verticalAlignment: Text.AlignVCenter
    elide: Text.ElideRight
    wrapMode: Text.NoWrap
}
