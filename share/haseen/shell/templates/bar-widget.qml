import QtQuick
import qs.Haseen
import qs.Haseen.Widgets

// @ID@: bar widget. Colours, fonts and spacing come from Theme only (no hex
// literals). Prefer events over timers; a Timer under 2 s is not accepted.
BarButton {
    id: root

    // Every entry gets these from the host (docs/architecture.md 5.2).
    property string pluginId
    property var settings: ({})
    property var screen: null

    text: typeof settings.label === "string" ? settings.label : pluginId
    color: Theme.foreground

    onClicked: button => console.info(root.pluginId + ": clicked with button " + button)
}
