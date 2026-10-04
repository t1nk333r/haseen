import QtQuick
import qs.Haseen

// Today's prayers from the haseen.prayers service in one of two layouts
// (settings.panelStyle): Horizon draws the day to scale with window lengths,
// Compact is a ruled timetable. Both end with the settings fold.
// Open with `haseen shell ipc panel toggle haseen.prayers` or a bar click.
//
// Keys (while no field or list owns them): r refresh, m method, d settings,
// s layout, b bar label, t clock, a language, c or / city search.
//
// Adapted from Panel.qml in OmaPrayers (MIT, Copyright (c) 2026 Salem Sayed);
// see LICENSE and UPSTREAM.md beside this file. The Omarchy panel chrome
// (anchoring, Tab switching between panels) is haseen's PanelPopup here.
Item {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    readonly property var host: {
        const entry = Plugins.roles.prayers;
        return entry && entry.id === root.pluginId ? entry.instance : null;
    }
    // The fold can outgrow the screen; past this the panel scrolls.
    readonly property real maxHeight: (root.screen ? root.screen.height : 1080) * 0.8 - Config.barThickness

    width: host ? host.sp(360) : Theme.fontSize * 30
    implicitWidth: width
    height: Math.min(layoutLoader.height, maxHeight)
    implicitHeight: height
    focus: true

    function syncLayout(): void {
        if (!host) {
            layoutLoader.source = "";
            return;
        }
        host.keysBlocked = false;
        layoutLoader.setSource(Qt.resolvedUrl(host.panelStyle === "Compact" ? "PanelCompact.qml" : "PanelHorizon.qml"), {
            host: host
        });
    }

    onHostChanged: syncLayout()
    Component.onCompleted: {
        Qt.callLater(() => root.forceActiveFocus());
        syncLayout();
        if (host && !host.schedule)
            host.recompute();
    }
    Component.onDestruction: {
        if (host)
            host.keysBlocked = false;
    }

    Connections {
        target: root.host

        function onPanelStyleChanged(): void {
            root.syncLayout();
        }

        // A field or list that let go of the keys hands them back here.
        function onKeysBlockedChanged(): void {
            if (!root.host.keysBlocked)
                root.forceActiveFocus();
        }
    }

    Keys.onPressed: event => {
        if (!root.host || root.host.keysBlocked || event.modifiers & (Qt.ControlModifier | Qt.AltModifier))
            return;
        const key = event.text.toLowerCase();
        const h = root.host;
        const actions = {
            r: () => h.refresh(),
            m: () => h.requestMethodPicker(),
            d: () => h.toggleDisplaySettings(),
            s: () => h.cyclePanelStyle(),
            b: () => h.cycleBarDisplay(),
            t: () => h.cycleTimeFormat(),
            a: () => h.cycleLanguage(),
            c: () => h.requestLocationSearch(),
            "/": () => h.requestLocationSearch()
        };
        if (actions[key]) {
            actions[key]();
            event.accepted = true;
        }
    }

    Text {
        visible: !root.host
        width: parent.width
        wrapMode: Text.WordWrap
        text: "The prayers service is not running (add haseen.prayers to shell.json services)."
        color: Theme.muted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }

    Flickable {
        id: scroller

        anchors.fill: parent
        contentWidth: width
        contentHeight: layoutLoader.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        // The fold sits below the schedule; when the panel is at its height
        // cap, scroll it into view as it opens or as results arrive.
        function revealBottom(): void {
            if (contentHeight > height)
                contentY = contentHeight - height;
        }

        Connections {
            target: root.host

            function onLocationChoicesChanged(): void {
                if (root.host.locationChoices.length > 0)
                    Qt.callLater(scroller.revealBottom);
            }
            function onLocationSearchRequested(): void {
                Qt.callLater(scroller.revealBottom);
            }
            function onMethodPickerRequested(): void {
                revealTimer.restart();
            }
            function onDisplaySettingsOpenChanged(): void {
                if (root.host.displaySettingsOpen)
                    revealTimer.restart();
            }
        }

        // The fold reports its height a frame after it becomes visible.
        // haseen:ui-timeout
        Timer {
            id: revealTimer

            interval: 80
            onTriggered: scroller.revealBottom()
        }

        Loader {
            id: layoutLoader

            width: scroller.width
            height: item ? item.implicitHeight : 0
            LayoutMirroring.enabled: root.host !== null && root.host.isArabic
            LayoutMirroring.childrenInherit: true
        }
    }
}
