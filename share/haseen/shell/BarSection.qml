import QtQuick
import Quickshell
import qs.Haseen

// A row of bar-widget plugins. Disabled ids are filtered out; unknown ones
// are skipped by PluginSlot with one log line.
Row {
    id: section

    required property var ids
    required property var screen

    spacing: Math.round(Theme.gap / 2)

    Repeater {
        model: ScriptModel {
            values: section.ids.filter(id => Config.isEnabled(id))
        }

        delegate: PluginSlot {
            required property string modelData

            pluginId: modelData
            kind: "bar-widget"
            screen: section.screen
            height: section.height
        }
    }
}
