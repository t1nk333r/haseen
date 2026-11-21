import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import qs.Haseen
import qs.Haseen.Widgets
import qs.Ui
import "Model.js" as Model

// The weather panel, from Omarchy's (shell/plugins/panels/weather/Panel.qml;
// MIT, Copyright (c) David Heinemeier Hansson), redesigned (plan 180): the
// icon, temperature, condition and today's high and low with the location
// at the row's end, feels/wind/humidity on the next line, then two tabs:
// the coming hours and five days with their ranges on a shared scale, or a
// 24-hour temperature curve and three days. The body keeps the taller tab's
// height, so switching never resizes the panel.
// Click the location (or press Enter) to search a city (Open-Meteo
// geocoding); an empty search returns to automatic (GeoClue, else IP).
// The data comes from the haseen.weather service (role `weather`).
// Open with `haseen shell ipc panel toggle haseen.weather` or a bar click;
// Tab or the arrow keys switch the tabs.
Column {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    // A test may hand the panel a service of its own.
    property var service: {
        const entry = Plugins.roles.weather;
        return entry && entry.id === root.pluginId ? entry.instance : null;
    }
    readonly property bool hasCurrent: !!(service && service.current)
    readonly property var forecastDays: service ? service.forecastDays : []
    readonly property bool imperial: !!(service && service.useImperial)
    readonly property int tab: service ? service.panelTab : 0
    readonly property var daysScale: Model.daysScale(forecastDays, imperial)
    // "Now" (the current conditions), then the next three-hourly forecasts.
    readonly property var slots: {
        if (!hasCurrent)
            return [];
        const now = [{ hour: I18n.tr("Now"), temp: service.reportTempNum, icon: service.label, now: true }];
        return now.concat((service.hours || []).map(h => ({ hour: h.hour, temp: imperial ? h.tempF : h.tempC, icon: h.icon, now: false })));
    }
    readonly property int curveTop: Theme.font.caption + Theme.gap
    readonly property int curveHeight: Theme.fontSize * 4.5
    readonly property var curve: Model.curve(slots.map(s => s.temp), width, curveTop, curveHeight, curveTop + curveHeight + Theme.gap)

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

    function setTab(index: int): void {
        if (service)
            service.panelTab = (index + 2) % 2;
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

    width: Theme.fontSize * 28
    spacing: Math.round(Theme.gap * 1.5)
    Component.onCompleted: keyCatcher.forceActiveFocus()

    Item {
        id: keyCatcher

        width: 0
        height: 0
        focus: true
        Keys.onReturnPressed: root.startEditingLocation()
        Keys.onEnterPressed: root.startEditingLocation()
        Keys.onTabPressed: root.setTab(root.tab + 1)
        Keys.onBacktabPressed: root.setTab(root.tab - 1)
        // The arrow points at the tab it selects, also in a mirrored panel.
        Keys.onLeftPressed: root.setTab(root.tab + (root.LayoutMirroring.enabled ? 1 : -1))
        Keys.onRightPressed: root.setTab(root.tab + (root.LayoutMirroring.enabled ? -1 : 1))
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

    // ---- Hero: icon and temperature, the condition and today's high and
    // low beside them, the location at the row's end.
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
                color: Theme.accent
                font.pixelSize: Theme.font.display
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
                    font.pixelSize: Theme.font.display
                    font.bold: true
                }

                Text {
                    anchors.top: tempBig.top
                    anchors.topMargin: Math.round(Theme.gap / 2)
                    textFormat: Text.PlainText
                    text: root.hasCurrent ? root.service.tempUnit : ""
                    color: Theme.muted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.font.bodySmall
                }
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.hasCurrent
                spacing: 2

                Text {
                    textFormat: Text.PlainText
                    text: root.service ? root.service.condition : ""
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.font.body
                }

                Text {
                    readonly property var range: root.service ? root.service.todayRange : null
                    readonly property string high: range ? (root.imperial ? range.maxF : range.maxC) : ""
                    readonly property string low: range ? (root.imperial ? range.minF : range.minC) : ""

                    visible: high !== "" && low !== ""
                    textFormat: Text.PlainText
                    text: I18n.tr("H %1°  L %2°", high, low)
                    color: Theme.muted
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
            anchors.top: parent.top
            visible: !root.editingLocation
            spacing: Math.round(Theme.gap / 2)

            TapHandler {
                onTapped: root.startEditingLocation()
            }
            HoverHandler {
                id: locationHover

                cursorShape: Qt.PointingHandCursor
            }
            // Where the forecast comes from and when it was fetched.
            PanelToolTip {
                visible: locationHover.hovered && text !== ""
                text: root.sourceText()
            }

            Glyph {
                id: marker

                anchors.verticalCenter: parent.verticalCenter
                glyph: "" // nf-fa-map_marker
                color: Theme.muted
                font.pixelSize: Theme.font.caption
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(0, Math.min(implicitWidth, root.width - heroLeft.width - marker.width - Theme.gap * 2))
                textFormat: Text.PlainText
                text: root.service && root.service.reportLocation !== "" ? root.service.reportLocation.toUpperCase() : I18n.tr("SET LOCATION")
                color: Theme.muted
                elide: Text.ElideRight
                font.family: Theme.fontFamily
                font.pixelSize: Theme.font.caption
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

    // ---- The tabs: a segmented control, the selected tab in the accent.
    Rectangle {
        id: tabBar

        readonly property int fiveDays: Math.min(5, root.forecastDays.length)
        readonly property int threeDays: Math.min(3, root.forecastDays.length)

        visible: root.hasCurrent
        width: parent.width
        height: Theme.font.body + Theme.gap * 2
        radius: Theme.radius
        color: "transparent"
        border.width: Theme.borderWidth
        border.color: Theme.border

        Row {
            anchors.fill: parent
            anchors.margins: Theme.borderWidth + 1

            Repeater {
                model: [
                    tabBar.fiveDays > 0 ? I18n.tn("Hourly · %1 day", "Hourly · %1 days", tabBar.fiveDays) : I18n.tr("Hourly"),
                    tabBar.threeDays > 0 ? I18n.tn("Curve · %1 day", "Curve · %1 days", tabBar.threeDays) : I18n.tr("Curve")
                ]

                delegate: Rectangle {
                    id: tabCell

                    required property string modelData
                    required property int index
                    readonly property bool selected: index === root.tab

                    width: (tabBar.width - (Theme.borderWidth + 1) * 2) / 2
                    height: parent.height
                    radius: Math.max(0, Theme.radius - Theme.borderWidth - 1)
                    color: selected ? Theme.accent : (tabArea.containsMouse ? Theme.selection : "transparent")

                    Text {
                        anchors.centerIn: parent
                        width: Math.min(implicitWidth, parent.width - Theme.gap)
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                        text: tabCell.modelData
                        color: tabCell.selected ? Theme.accentFg : Theme.muted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.font.bodySmall
                    }

                    MouseArea {
                        id: tabArea

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.setTab(tabCell.index)
                    }
                }
            }
        }
    }

    // ---- The tab's body, as tall as the taller tab.
    Item {
        visible: root.hasCurrent
        width: parent.width
        height: Math.max(hoursTab.implicitHeight, curveTab.implicitHeight)

        // Tab 1: the coming hours, then five days.
        Column {
            id: hoursTab

            width: parent.width
            visible: root.tab === 0
            spacing: Math.round(Theme.gap * 1.5)

            Row {
                width: parent.width

                Repeater {
                    model: root.slots

                    delegate: Column {
                        id: slot

                        required property var modelData

                        width: root.width / Math.max(1, root.slots.length)
                        spacing: Math.round(Theme.gap / 2)

                        // One line height for every label, so a taller script's
                        // "Now" does not push its column down.
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            height: Math.ceil(Theme.font.caption * 1.6)
                            verticalAlignment: Text.AlignVCenter
                            textFormat: Text.PlainText
                            text: slot.modelData.hour
                            color: slot.modelData.now ? Theme.accent : Theme.muted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.font.caption
                        }

                        Glyph {
                            anchors.horizontalCenter: parent.horizontalCenter
                            glyph: slot.modelData.icon
                            font.pixelSize: Theme.font.icon
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            textFormat: Text.PlainText
                            text: slot.modelData.temp !== "" ? slot.modelData.temp + "°" : "—"
                            color: Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.font.bodySmall
                        }
                    }
                }
            }

            Rectangle {
                visible: root.forecastDays.length > 0
                width: parent.width
                height: Theme.borderWidth
                color: Theme.border
            }

            // Day, icon, low, the range on the days' shared scale, high.
            Column {
                width: parent.width
                spacing: Theme.gap

                Repeater {
                    model: root.forecastDays

                    delegate: Row {
                        id: dayRow

                        required property var modelData
                        readonly property var bar: Model.rangeBar(modelData, root.daysScale, root.imperial)

                        width: parent.width
                        height: Theme.font.icon + 4
                        spacing: Theme.gap

                        Text {
                            id: dayName

                            anchors.verticalCenter: parent.verticalCenter
                            width: Theme.fontSize * 3.5
                            elide: Text.ElideRight
                            textFormat: Text.PlainText
                            text: Model.dayName(dayRow.modelData.date, d => I18n.formatDate(d, "ddd"))
                            color: Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.font.body
                        }

                        Glyph {
                            id: dayIcon

                            anchors.verticalCenter: parent.verticalCenter
                            width: Theme.fontSize * 2
                            glyph: Model.dayIcon(dayRow.modelData)
                            font.pixelSize: Theme.font.icon
                        }

                        Text {
                            id: dayLow

                            anchors.verticalCenter: parent.verticalCenter
                            width: Theme.fontSize * 2.5
                            horizontalAlignment: Text.AlignRight
                            textFormat: Text.PlainText
                            text: Model.bareTempForDay(dayRow.modelData, "min", root.imperial)
                            color: Theme.muted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.font.bodySmall
                        }

                        // Anchored from the track's start, so a mirrored
                        // panel runs the bar from the right.
                        Item {
                            id: track

                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - dayName.width - dayIcon.width - dayLow.width - dayHigh.width - dayRow.spacing * 4
                            height: 4

                            Rectangle {
                                anchors.fill: parent
                                radius: height / 2
                                color: Theme.border
                            }

                            Rectangle {
                                anchors.left: parent.left
                                anchors.leftMargin: track.width * dayRow.bar.start
                                visible: dayRow.bar.width > 0
                                width: Math.max(height, track.width * dayRow.bar.width)
                                height: parent.height
                                radius: height / 2
                                color: Theme.accent
                            }
                        }

                        Text {
                            id: dayHigh

                            anchors.verticalCenter: parent.verticalCenter
                            width: Theme.fontSize * 2.5
                            textFormat: Text.PlainText
                            text: Model.bareTempForDay(dayRow.modelData, "max", root.imperial)
                            color: Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.font.bodySmall
                        }
                    }
                }
            }
        }

        // Tab 2: the temperature curve over the same hours, then three days.
        // The curve is a timeline and reads left to right in every language.
        Column {
            id: curveTab

            width: parent.width
            visible: root.tab === 1
            spacing: Math.round(Theme.gap * 1.5)

            Item {
                width: parent.width
                height: root.curveTop + root.curveHeight + Theme.gap * 2 + Theme.font.icon + Theme.font.caption + 4
                LayoutMirroring.enabled: false
                LayoutMirroring.childrenInherit: true

                Shape {
                    anchors.fill: parent
                    visible: root.curve.line !== ""

                    ShapePath {
                        strokeColor: "transparent"
                        fillGradient: LinearGradient {
                            x1: 0
                            y1: root.curveTop
                            x2: 0
                            y2: root.curveTop + root.curveHeight + Theme.gap
                            GradientStop {
                                position: 0
                                color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.28)
                            }
                            GradientStop {
                                position: 1
                                color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0)
                            }
                        }
                        PathSvg {
                            path: root.curve.area
                        }
                    }

                    ShapePath {
                        strokeColor: Theme.accent
                        strokeWidth: 2
                        fillColor: "transparent"
                        capStyle: ShapePath.RoundCap
                        joinStyle: ShapePath.RoundJoin
                        PathSvg {
                            path: root.curve.line
                        }
                    }
                }

                Repeater {
                    model: root.curve.points.length === root.slots.length ? root.slots : []

                    delegate: Item {
                        id: point

                        required property var modelData
                        required property int index
                        readonly property var at: root.curve.points[index]

                        Rectangle {
                            x: point.at[0] - width / 2
                            y: point.at[1] - height / 2
                            width: 6
                            height: 6
                            radius: 3
                            color: point.modelData.now ? Theme.accent : Theme.popups.background
                            border.color: Theme.accent
                            border.width: 1.5
                        }

                        Text {
                            x: point.at[0] - width / 2
                            y: point.at[1] - height - 4
                            textFormat: Text.PlainText
                            text: point.modelData.temp + "°"
                            color: Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.font.caption
                        }

                        Glyph {
                            x: point.at[0] - width / 2
                            y: root.curveTop + root.curveHeight + Theme.gap * 1.5
                            glyph: point.modelData.icon
                            color: Theme.muted
                            font.pixelSize: Theme.font.icon
                        }

                        Text {
                            x: point.at[0] - width / 2
                            y: root.curveTop + root.curveHeight + Theme.gap * 1.5 + Theme.font.icon + 4
                            textFormat: Text.PlainText
                            text: point.modelData.hour
                            color: point.modelData.now ? Theme.accent : Theme.muted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.font.caption
                        }
                    }
                }
            }

            Rectangle {
                visible: root.forecastDays.length > 0
                width: parent.width
                height: Theme.borderWidth
                color: Theme.border
            }

            // Three days in equal columns: the name over icon, high and low.
            Row {
                width: parent.width

                Repeater {
                    model: root.forecastDays.slice(0, 3)

                    delegate: Column {
                        id: day

                        required property var modelData

                        width: root.width / 3
                        spacing: Math.round(Theme.gap / 2)

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            textFormat: Text.PlainText
                            text: root.dayName(day.modelData.date).toUpperCase()
                            color: Theme.muted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.font.caption
                            font.letterSpacing: 1
                        }

                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: Theme.gap

                            Glyph {
                                anchors.verticalCenter: parent.verticalCenter
                                glyph: Model.dayIcon(day.modelData)
                                font.pixelSize: Theme.font.icon
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                textFormat: Text.PlainText
                                text: Model.bareTempForDay(day.modelData, "max", root.imperial)
                                color: Theme.foreground
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.font.bodySmall
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                textFormat: Text.PlainText
                                text: Model.bareTempForDay(day.modelData, "min", root.imperial)
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
