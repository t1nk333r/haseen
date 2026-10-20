import QtQuick
import qs.Haseen
import qs.Haseen.Widgets

// A titled row of choices on the shared Pill: `options` are {value, label},
// `current` the value in force. Picking one emits picked(value); the panel
// runs it, and `busy` dims every pill while a change is in flight.
Column {
    id: row

    property string title
    property var options: []
    property var current
    property bool busy: false

    signal picked(var value)

    spacing: Math.round(Theme.gap / 2)

    Text {
        text: row.title
        color: Theme.subtle(Theme.surface)
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 1
    }

    Flow {
        width: row.width
        spacing: Math.round(Theme.gap / 2)

        Repeater {
            model: row.options

            delegate: Pill {
                required property var modelData

                text: modelData.label
                active: modelData.value === row.current
                busy: row.busy
                onClicked: {
                    if (modelData.value !== row.current)
                        row.picked(modelData.value);
                }
            }
        }
    }
}
