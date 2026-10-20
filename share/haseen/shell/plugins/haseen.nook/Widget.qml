import QtQuick
import Quickshell
import qs.Haseen
import qs.Haseen.Widgets

// A bar drawer you place yourself (plan 095), after the owner's t1nk33r.nook,
// a port of Katsari's Nook (https://github.com/Katsari/nook, MIT, Copyright
// (c) 2026 Katsari): rarely used widgets collapse into a card that opens
// below the bar, so nothing on the bar is covered or moved. haseen's bar
// already has that drawer, the overflow panel (architecture 5.3: Bar.qml,
// BarOverflowPanel.qml), which holds the widgets live and moves them in and
// out with arrange mode and `haseen bar overflow`. So this widget is not a
// second drawer: it is the overflow panel's opener, put where the user puts
// it in a bar section instead of at the bar's end. The panel opens under it,
// the end chevron then shows only in arrange mode, and it never moves into
// the panel itself. Like the chevron it takes no room while the panel would
// be empty. A left click opens or closes the panel, a right click arranges.
// Off by default.
BarButton {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    // The bar window this widget sits in; anything else (a test window, the
    // overflow panel) leaves it inert.
    readonly property var host: QsWindow.window
    readonly property bool hosted: host !== null && host !== undefined && typeof host.toggleOverflowFrom === "function"
    readonly property bool active: hosted && (host.fit.button === true || host.overflowOpen === true)

    visible: active
    implicitWidth: active ? contentWidth : 0
    glyph: hosted ? host.overflowGlyph : ""
    highlighted: hosted && host.overflowOpen === true

    onHostedChanged: {
        if (hosted)
            host.nookItem = root;
    }
    Component.onCompleted: {
        if (hosted)
            host.nookItem = root;
    }
    Component.onDestruction: {
        if (hosted && host.nookItem === root)
            host.nookItem = null;
    }

    onClicked: button => {
        if (!root.hosted)
            return;
        if (button === Qt.LeftButton)
            root.host.toggleOverflowFrom(root);
        else if (button === Qt.RightButton)
            root.host.setArranging(!root.host.arranging);
    }
}
