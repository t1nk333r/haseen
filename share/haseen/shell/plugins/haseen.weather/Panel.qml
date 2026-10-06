import QtQuick
import Quickshell
import Quickshell.Io
import qs.Haseen
import qs.Haseen.Widgets
import "Model.js" as Model

// The weather panel, laid out as Omarchy's (shell/plugins/panels/weather/
// Panel.qml; MIT, Copyright (c) David Heinemeier Hansson): big icon and
// temperature, the location with feels/wind/humidity, the next three days.
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

    function dayName(dateString: string): string {
        return Model.dayName(dateString, d => Qt.formatDate(d, "dddd"));
    }

    function sourceText(): string {
        if (!service)
            return "";
        const parts = [];
        if (service.locationSource === "geoclue")
            parts.push("GeoClue location");
        else if (service.locationSource === "ip")
            parts.push(service.geoclueNote !== "" ? "IP location · " + service.geoclueNote : "IP location");
        if (service.updated > 0)
            parts.push("updated " + new Date(service.updated).toLocaleTimeString(Qt.locale(), "HH:mm"));
        return parts.join(" · ");
    }

    // A finished save closes the editor (the spinner ran until the new
    // location's first answer).
    onSavingLocationChanged: {
        if (!savingLocation && editingLocation)
            cancelEditingLocation();
    }

    width: Theme.fontSize * 34
    spacing: Theme.gap * 1.5
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
        text: "The weather service is not running (enable haseen.weather in shell.json)."
        color: Theme.muted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }

    // ---- Hero: big icon and temperature; location and stats on the right.
    Item {
        width: parent.width
        height: Math.max(heroLeft.height, heroRight.height)
        visible: root.service !== null

        Row {
            id: heroLeft

            anchors.left: parent.left
            anchors.leftMargin: Theme.gap
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.gap * 1.5

            Glyph {
                anchors.verticalCenter: parent.verticalCenter
                glyph: root.service && root.service.label ? root.service.label : "—"
                font.pixelSize: Theme.fontSize * 4.5
            }

            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                Text {
                    id: tempBig

                    textFormat: Text.PlainText
                    text: root.service && root.service.reportTempNum ? root.service.reportTempNum : "—"
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize * 4
                    font.bold: true
                }

                Text {
                    anchors.top: tempBig.top
                    anchors.topMargin: Theme.gap
                    textFormat: Text.PlainText
                    text: root.hasCurrent ? root.service.tempUnit : ""
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize * 2
                }
            }
        }

        Column {
            id: heroRight

            anchors.right: parent.right
            anchors.rightMargin: Theme.gap
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(stats.implicitWidth, Theme.fontSize * 14)
            spacing: Theme.gap

            Row {
                visible: !root.editingLocation
                spacing: Math.round(Theme.gap / 2)

                TapHandler {
                    onTapped: root.startEditingLocation()
                }
                HoverHandler {
                    cursorShape: Qt.PointingHandCursor
                }

                Glyph {
                    anchors.verticalCenter: parent.verticalCenter
                    glyph: "\uf041" // nf-fa-map_marker
                    color: Theme.muted
                    font.pixelSize: Theme.fontSize
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, heroRight.width - Theme.fontSize * 2)
                    textFormat: Text.PlainText
                    text: root.service && root.service.reportLocation !== "" ? root.service.reportLocation.toUpperCase() : "SET LOCATION"
                    color: Theme.muted
                    elide: Text.ElideRight
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    font.letterSpacing: 1
                }
            }

            Row {
                visible: root.editingLocation
                spacing: Math.round(Theme.gap / 2)

                TextInput {
                    id: locationField

                    width: heroRight.width - clearButton.width - parent.spacing
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
                    font.pixelSize: Theme.fontSize

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
                        text: "Search city (empty = automatic)"
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
                        font.pixelSize: Theme.fontSize

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

            Row {
                id: stats

                visible: root.hasCurrent
                spacing: Theme.gap * 2.5

                Repeater {
                    model: [
                        { label: "FEELS", value: root.service ? root.service.reportFeels : "" },
                        { label: "WIND", value: root.service ? root.service.reportWind : "" },
                        { label: "HUMID", value: root.service ? root.service.reportHumidity : "" }
                    ]

                    delegate: Column {
                        required property var modelData

                        spacing: Math.round(Theme.gap / 3)

                        Text {
                            text: modelData.label
                            color: Theme.muted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 2
                            font.letterSpacing: 1
                        }

                        Text {
                            textFormat: Text.PlainText
                            text: modelData.value
                            color: Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize + 3
                        }
                    }
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
                        font.pixelSize: Theme.fontSize
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: text !== ""
                        textFormat: Text.PlainText
                        text: suggestion.modelData.description
                        color: Theme.muted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 2
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
        visible: root.service !== null && !root.hasCurrent
        text: "Fetching forecast…"
        color: Theme.muted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 1
        font.italic: true
    }

    Rectangle {
        visible: root.forecastDays.length > 0
        width: parent.width
        height: Theme.borderWidth
        color: Theme.border
    }

    // ---- The next three days: icon, day name, high and low.
    Item {
        visible: root.forecastDays.length > 0
        width: parent.width
        height: forecastRow.height

        Row {
            id: forecastRow

            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Theme.gap * 3

            Repeater {
                model: root.forecastDays

                delegate: Row {
                    id: day

                    required property var modelData

                    spacing: Theme.gap

                    Glyph {
                        anchors.verticalCenter: parent.verticalCenter
                        glyph: Model.dayIcon(day.modelData)
                        font.pixelSize: Theme.fontSize * 2
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        Text {
                            textFormat: Text.PlainText
                            text: root.dayName(day.modelData.date).toUpperCase()
                            color: Theme.muted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 3
                            font.letterSpacing: 1
                        }

                        Row {
                            spacing: Math.round(Theme.gap / 2)

                            Text {
                                textFormat: Text.PlainText
                                text: Model.bareTempForDay(day.modelData, "max", root.service && root.service.useImperial)
                                color: Theme.foreground
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize
                            }

                            Text {
                                textFormat: Text.PlainText
                                text: Model.bareTempForDay(day.modelData, "min", root.service && root.service.useImperial)
                                color: Theme.muted
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize
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
        font.pixelSize: Theme.fontSize - 3
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
