import QtQuick
import qs.Haseen
import qs.Haseen.Widgets

// Current conditions and a 3-day forecast from the haseen.weather service.
// Open with `haseen shell ipc panel toggle haseen.weather` or a bar click.
Column {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    readonly property var service: {
        const entry = Plugins.roles.weather;
        return entry && entry.id === root.pluginId ? entry.instance : null;
    }
    readonly property var forecast: service ? service.forecast : null

    function dayName(date: string, index: int): string {
        if (index === 0)
            return "Today";
        const d = new Date(date + "T12:00:00");
        return isNaN(d.getTime()) ? date : d.toLocaleDateString(Qt.locale(), "ddd d");
    }

    width: Theme.fontSize * 26
    spacing: Theme.gap

    Text {
        width: parent.width
        text: root.forecast && root.forecast.location !== "" ? root.forecast.location : "Weather"
        color: Theme.accent
        elide: Text.ElideRight
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize + 2
    }

    Text {
        width: parent.width
        visible: root.forecast === null
        wrapMode: Text.WordWrap
        text: !root.service ? "The weather service is not running (add haseen.weather to shell.json services)." : root.service.failed ? "Weather is unavailable right now." : "Loading…"
        color: Theme.muted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }

    Row {
        visible: root.forecast !== null
        spacing: Theme.gap * 2

        Glyph {
            glyph: root.forecast ? root.forecast.current.glyph : ""
            color: Theme.foreground
            font.pixelSize: Theme.fontSize * 3
            anchors.verticalCenter: parent.verticalCenter
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter

            Text {
                text: root.forecast ? root.forecast.current.temp + root.forecast.unit : ""
                color: Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize * 2
            }

            Text {
                text: {
                    if (!root.forecast)
                        return "";
                    const c = root.forecast.current;
                    const parts = [c.desc];
                    if (c.feels !== null)
                        parts.push("feels " + c.feels + "°");
                    return parts.join(", ");
                }
                color: Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
            }

            Text {
                text: {
                    if (!root.forecast)
                        return "";
                    const c = root.forecast.current;
                    const parts = [];
                    if (c.humidity !== null)
                        parts.push("humidity " + c.humidity + "%");
                    if (c.wind !== null)
                        parts.push("wind " + c.wind + " " + c.windUnit);
                    return parts.join(" · ");
                }
                color: Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
            }
        }
    }

    Rectangle {
        width: parent.width
        height: Theme.borderWidth
        color: Theme.border
        visible: root.forecast !== null
    }

    Repeater {
        model: root.forecast ? root.forecast.days : []

        delegate: Row {
            id: day

            required property var modelData
            required property int index

            width: root.width
            height: Theme.fontSize * 2.2
            spacing: Theme.gap

            Text {
                width: Theme.fontSize * 5
                anchors.verticalCenter: parent.verticalCenter
                text: root.dayName(day.modelData.date, day.index)
                color: Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
            }

            Glyph {
                width: Theme.fontSize * 2
                anchors.verticalCenter: parent.verticalCenter
                glyph: day.modelData.glyph
                color: Theme.foreground
            }

            Text {
                width: day.width - Theme.fontSize * 13 - Theme.gap * 3
                anchors.verticalCenter: parent.verticalCenter
                text: day.modelData.desc + (day.modelData.rain ? " · " + day.modelData.rain + "% rain" : "")
                color: Theme.muted
                elide: Text.ElideRight
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
            }

            Text {
                width: Theme.fontSize * 6
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignRight
                text: day.modelData.max + "° / " + day.modelData.min + "°"
                color: Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
            }
        }
    }

    Text {
        width: parent.width
        visible: root.service !== null && root.service.updated > 0
        horizontalAlignment: Text.AlignRight
        text: root.service && root.service.updated > 0 ? "wttr.in · " + new Date(root.service.updated).toLocaleTimeString(Qt.locale(), "HH:mm") : ""
        color: Theme.muted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 2
    }
}
