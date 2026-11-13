import QtQuick
import Quickshell
import Quickshell.Io
import qs.Haseen
import qs.Haseen.Widgets
import "Model.js" as Model

// The weather panel, laid out as Omarchy's (shell/plugins/panels/weather/
// Panel.qml; MIT, Copyright (c) David Heinemeier Hansson), compacted (plan
// 164): icon, temperature and location on one row, feels/wind/humidity on
// the next, then the next three days.
// Click the location (or press Enter) to search a city (Open-Meteo
// geocoding); an empty search returns to automatic (GeoClue, else IP).
// The data comes from the haseen.weather service (role `weather`).
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
    readonly property bool hasCurrent: !!(service && service.current)
    readonly property var forecastDays: service ? service.forecastDays : []

    property bool editingLocation: false
    property var locationSuggestions: []
    property int suggestionIndex: 0
    property string geocodePendingQuery: ""
    property string geocodeActiveQuery: ""
    readonly property bool savingLocation: !!(service && service.savingLocation)

    function startEditingLocation(): void {
        if (!service)
            return;
        service.cancelSaving();
        editingLocation = true;
        locationSuggestions = [];
        suggestionIndex = 0;
        locationField.text = service.configuredLocation;
        locationField.selectAll();
        locationField.forceActiveFocus();
    }

    function cancelEditingLocation(): void {
        editingLocation = false;
        locationSuggestions = [];
        geocodeDebounce.stop();
        keyCatcher.forceActiveFocus();
    }

    function commitLocation(): void {
        const location = Model.locationCommit(locationField.text, locationSuggestions, suggestionIndex);
        if (location.name === "") {
            clearLocation();
            return;
        }
        service.setLocation(location.name, location.latitude, location.longitude);
    }

    function pickSuggestion(suggestion: var): void {
        if (suggestion)
            service.setLocation(suggestion.name, suggestion.latitude, suggestion.longitude);
    }

    function clearLocation(): void {
        service.clearLocation();
        cancelEditingLocation();
    }

    // Debounced geocoding. One curl at a time; a query that moved on while a
    // fetch ran is fetched right after it.
    function requestGeocode(): void {
        const query = locationField.text.trim();
        if (query.length < 2) {
            locationSuggestions = [];
            return;
        }
        geocodePendingQuery = query;
        if (!geocodeProc.running)
            startGeocode();
    }

    function startGeocode(): void {
        geocodeActiveQuery = geocodePendingQuery;
        geocodeProc.command = ["curl", "-fsS", "--max-time", "5", Model.geocodeUrl(geocodeActiveQuery)];
        geocodeProc.running = true;
    }

    // Day names in the interface language (plan 109), not the session's.
    function dayName(dateString: string): string {
        return Model.dayName(dateString, d => I18n.formatDate(d, "dddd"));
    }

    function sourceText(): string {
        if (!service)
            return "";
        const parts = [];
        if (service.locationSource === "geoclue")
            parts.push(I18n.tr("GeoClue location"));
        else if (service.locationSource === "ip")
            parts.push(service.geoclueNote !== "" ? I18n.tr("IP location · %1", service.geoclueNote) : I18n.tr("IP location"));
        if (service.updated > 0)
            parts.push(I18n.tr("updated %1", new Date(service.updated).toLocaleTimeString(I18n.locale, "HH:mm")));
        return parts.join(" · ");
    }

    // A finished save closes the editor (the spinner ran until the new
    // location's first answer).
    onSavingLocationChanged: {
        if (!savingLocation && editingLocation)
            cancelEditingLocation();
    }

    width: Theme.fontSize * 26
    spacing: Theme.gap
    Component.onCompleted: keyCatcher.forceActiveFocus()

    Item {
        id: keyCatcher

        width: 0
        height: 0
        focus: true
        Keys.onReturnPressed: root.startEditingLocation()
        Keys.onEnterPressed: root.startEditingLocation()
    }

    Text {
        width: parent.width
        visible: root.service === null
        wrapMode: Text.WordWrap
        text: I18n.tr("The weather service is not running (enable haseen.weather in shell.json).")
        color: Theme.muted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.font.body
    }

    // ---- Hero: icon and temperature, the location at the row's end.
    Item {
        width: parent.width
        height: Math.max(heroLeft.height, locationLabel.height)
        visible: root.service !== null

        Row {
            id: heroLeft

            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.gap

            Glyph {
                anchors.verticalCenter: parent.verticalCenter
                glyph: root.service && root.service.label ? root.service.label : "—"
                font.pixelSize: Theme.font.iconLarge
            }

            // The number and its unit read "21°C" in every language.
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1
                LayoutMirroring.enabled: false

                Text {
                    id: tempBig

                    textFormat: Text.PlainText
                    text: root.service && root.service.reportTempNum ? root.service.reportTempNum : "—"
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.font.heading
                    font.bold: true
                }

                Text {
                    anchors.baseline: tempBig.baseline
                    textFormat: Text.PlainText
                    text: root.hasCurrent ? root.service.tempUnit : ""
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.font.bodySmall
                }
            }
        }

        // Anchored to the row's end, so a mirrored panel (plan 109) puts it
        // on the left.
        Row {
            id: locationLabel

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: !root.editingLocation
            spacing: Math.round(Theme.gap / 2)

            TapHandler {
                onTapped: root.startEditingLocation()
            }
            HoverHandler {
                cursorShape: Qt.PointingHandCursor
            }

            Glyph {
                id: marker

                anchors.verticalCenter: parent.verticalCenter
                glyph: "" // nf-fa-map_marker
                color: Theme.muted
                font.pixelSize: Theme.font.bodySmall
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, root.width - heroLeft.width - marker.width - Theme.gap * 2)
                textFormat: Text.PlainText
                text: root.service && root.service.reportLocation !== "" ? root.service.reportLocation.toUpperCase() : I18n.tr("SET LOCATION")
                color: Theme.muted
                elide: Text.ElideRight
                font.family: Theme.fontFamily
                font.pixelSize: Theme.font.bodySmall
                font.letterSpacing: 1
            }
        }
    }

    // ---- The city search, in place of the stats while it is open.
    Row {
        width: parent.width
        visible: root.service !== null && root.editingLocation
        spacing: Math.round(Theme.gap / 2)

        TextInput {
            id: locationField

            width: parent.width - clearButton.width - parent.spacing
            enabled: !root.savingLocation
            leftPadding: Math.round(Theme.gap * 0.75)
            rightPadding: leftPadding
            topPadding: Math.round(Theme.gap / 2)
            bottomPadding: topPadding
            clip: true
            selectByMouse: true
            color: Theme.foreground
            selectionColor: Theme.selection
            selectedTextColor: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.font.body

            onTextChanged: {
                if (root.editingLocation && !root.savingLocation)
                    geocodeDebounce.restart();
            }
            // Escape cancels the search instead of closing the panel
            // (PanelPopup's window shortcut).
            Keys.onShortcutOverride: event => event.accepted = event.key === Qt.Key_Escape
            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) {
                    root.cancelEditingLocation();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Down) {
                    if (root.suggestionIndex < root.locationSuggestions.length - 1)
                        root.suggestionIndex++;
                    event.accepted = true;
                } else if (event.key === Qt.Key_Up) {
                    if (root.suggestionIndex > 0)
                        root.suggestionIndex--;
                    event.accepted = true;
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    root.commitLocation();
                    event.accepted = true;
                }
            }

            Rectangle {
                z: -1
                anchors.fill: parent
                radius: Theme.radius
                color: Theme.surfaceAlt
                border.width: Theme.borderWidth
                border.color: locationField.activeFocus ? Theme.accent : Theme.border
            }

            Text {
                anchors.fill: parent
                anchors.leftMargin: locationField.leftPadding
                verticalAlignment: Text.AlignVCenter
                visible: locationField.text === ""
                text: I18n.tr("Search city (empty = automatic)")
                color: Theme.muted
                elide: Text.ElideRight
                font: locationField.font
            }
        }

        // Clear back to automatic; a spinner while a location loads.
        Rectangle {
            id: clearButton

            width: Theme.fontSize + Theme.gap
            height: width
            anchors.verticalCenter: parent.verticalCenter
            radius: Theme.radius
            color: !root.savingLocation && clearArea.containsMouse ? Theme.selection : "transparent"

            Glyph {
                anchors.centerIn: parent
                glyph: root.savingLocation ? "\u{f0996}" : "✕"
                color: Theme.muted
                font.pixelSize: Theme.font.body

                RotationAnimator on rotation {
                    running: root.savingLocation
                    from: 0
                    to: 360
                    duration: 800
                    loops: Animation.Infinite
                }
            }

            MouseArea {
                id: clearArea

                anchors.fill: parent
                enabled: !root.savingLocation
                hoverEnabled: true
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: root.clearLocation()
            }
        }
    }

    // ---- Feels, wind and humidity on one line; wraps if a language needs it.
    Flow {
        width: parent.width
        visible: root.hasCurrent && !root.editingLocation
        spacing: Theme.gap * 2

        Repeater {
            model: [
                { label: I18n.mark("FEELS"), value: root.service ? root.service.reportFeels : "" },
                { label: I18n.mark("WIND"), value: root.service ? root.service.reportWind : "" },
                { label: I18n.mark("HUMID"), value: root.service ? root.service.reportHumidity : "" }
            ]

            delegate: Row {
                required property var modelData

                spacing: Math.round(Theme.gap / 2)

                Text {
                    anchors.baseline: statValue.baseline
                    text: I18n.tr(modelData.label)
                    color: Theme.muted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.font.caption
                    font.letterSpacing: 1
                }

                Text {
                    id: statValue

                    textFormat: Text.PlainText
                    text: modelData.value
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.font.body
                }
            }
        }
    }

    // ---- Geocoding suggestions while the location is edited.
    Column {
        visible: root.editingLocation && !root.savingLocation && root.locationSuggestions.length > 0
        width: parent.width

        Repeater {
            model: root.locationSuggestions

            delegate: Rectangle {
                id: suggestion

                required property var modelData
                required property int index

                width: root.width
                height: suggestionRow.implicitHeight + Theme.gap
                radius: Theme.radius
                color: index === root.suggestionIndex ? Theme.selection : "transparent"

                Row {
                    id: suggestionRow

                    anchors.left: parent.left
                    anchors.leftMargin: Theme.gap
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.gap

                    Text {
                        textFormat: Text.PlainText
                        text: suggestion.modelData.name
                        color: Theme.foreground
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.font.body
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: text !== ""
                        textFormat: Text.PlainText
                        text: suggestion.modelData.description
                        color: Theme.muted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.font.caption
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onPositionChanged: root.suggestionIndex = suggestion.index
                    onClicked: root.pickSuggestion(suggestion.modelData)
                }
            }
        }
    }

    Text {
        width: parent.width
        visible: root.service !== null && !root.hasCurrent
        text: I18n.tr("Fetching forecast…")
        color: Theme.muted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.font.bodySmall
        font.italic: true
    }

    Rectangle {
        visible: root.forecastDays.length > 0
        width: parent.width
        height: Theme.borderWidth
        color: Theme.border
    }

    // ---- The next three days in equal columns: icon, short day name, high
    // and low.
    Row {
        visible: root.forecastDays.length > 0
        width: parent.width

        Repeater {
            model: root.forecastDays

            delegate: Item {
                id: day

                required property var modelData

                width: root.width / Math.max(1, root.forecastDays.length)
                height: dayRow.height

                Row {
                    id: dayRow

                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: Math.round(Theme.gap * 0.75)

                    Glyph {
                        anchors.verticalCenter: parent.verticalCenter
                        glyph: Model.dayIcon(day.modelData)
                        font.pixelSize: Theme.font.icon
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter

                        Text {
                            textFormat: Text.PlainText
                            text: root.dayName(day.modelData.date).toUpperCase()
                            color: Theme.muted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.font.caption
                            font.letterSpacing: 1
                        }

                        Row {
                            spacing: Math.round(Theme.gap / 2)

                            Text {
                                textFormat: Text.PlainText
                                text: Model.bareTempForDay(day.modelData, "max", root.service && root.service.useImperial)
                                color: Theme.foreground
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.font.bodySmall
                            }

                            Text {
                                textFormat: Text.PlainText
                                text: Model.bareTempForDay(day.modelData, "min", root.service && root.service.useImperial)
                                color: Theme.muted
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.font.bodySmall
                            }
                        }
                    }
                }
            }
        }
    }

    Text {
        width: parent.width
        visible: text !== ""
        horizontalAlignment: Text.AlignRight
        elide: Text.ElideLeft
        textFormat: Text.PlainText
        text: root.sourceText()
        color: Theme.muted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.font.caption
    }

    Process {
        id: geocodeProc

        stdout: StdioCollector {
            id: geocodeOut
            waitForEnd: true
        }
        onExited: {
            root.locationSuggestions = root.editingLocation ? Model.parseGeocodingResults(geocodeOut.text) : [];
            root.suggestionIndex = 0;
            if (root.geocodePendingQuery !== root.geocodeActiveQuery)
                Qt.callLater(root.startGeocode);
        }
    }

    // Typing pause before a city search.
    // haseen:ui-timeout
    Timer {
        id: geocodeDebounce

        interval: 300
        repeat: false
        onTriggered: root.requestGeocode()
    }

    // Test hook (settings.debugIpc): drive the location search without
    // injected input.
    IpcHandler {
        target: "haseen.weather.panel"
        enabled: root.settings.debugIpc === true

        function edit(text: string): void {
            root.startEditingLocation();
            locationField.text = text;
        }

        function pick(index: int): void {
            root.pickSuggestion(root.locationSuggestions[index]);
        }

        function cancel(): void {
            root.cancelEditingLocation();
        }

        function state(): string {
            return JSON.stringify({
                editing: root.editingLocation,
                saving: root.savingLocation,
                suggestions: root.locationSuggestions.map(s => s.name + "|" + s.description)
            });
        }
    }
}
