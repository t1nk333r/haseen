import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.Notifications
import Quickshell.Wayland
import qs.Haseen

// haseen.notifications: the org.freedesktop.Notifications server.
// New notifications pop up top-right (at most maxPopups, newest on top) and
// stay in memory for the panel until dismissed; nothing is written to disk.
// Do-not-disturb keeps everything but critical out of the popups.
//
// Only one process can own the D-Bus name. While another daemon (DMS,
// omarchy-shell, mako) holds it, Quickshell logs the failure and this service
// just never receives anything; the rest of the shell is unaffected.
Scope {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    readonly property int defaultTimeout: _int(settings.timeout, 5000, 1000)
    readonly property int maxPopups: Math.min(_int(settings.maxPopups, 3, 1), 3)
    readonly property int historySize: _int(settings.historySize, 50, 1)
    readonly property int popupWidth: _int(settings.width, 360, 200)

    property bool dnd: false
    // Notification objects shown as popups, newest first.
    property var popups: []
    // Every tracked notification, oldest first (the panel reverses it).
    readonly property var history: server.trackedNotifications.values

    function _int(v: var, fallback: int, min: int): int {
        return (typeof v === "number" && isFinite(v) && v >= min) ? Math.round(v) : fallback;
    }

    function toggleDnd(): void {
        dnd = !dnd;
        if (dnd)
            popups = popups.filter(n => n.urgency === NotificationUrgency.Critical);
    }

    function clear(): void {
        popups = [];
        for (const n of server.trackedNotifications.values.slice())
            n.dismiss();
    }

    function dismiss(n: var): void {
        n.dismiss();
    }

    // The popup timed out or was clicked away; the notification stays in the
    // panel unless the sender marked it transient.
    function hidePopup(n: var): void {
        popups = popups.filter(p => p !== n);
        if (n.transient)
            n.expire();
    }

    // 0 means "stay until dismissed". expireTimeout is in seconds; a
    // negative value is the D-Bus "server default".
    function timeoutFor(n: var): int {
        if (n.urgency === NotificationUrgency.Critical || n.resident)
            return 0;
        if (n.expireTimeout > 0)
            return Math.round(n.expireTimeout * 1000);
        if (n.expireTimeout === 0)
            return 0;
        return defaultTimeout;
    }

    function invokeDefault(n: var): void {
        for (let i = 0; i < n.actions.length; i++) {
            if (n.actions[i].identifier === "default") {
                n.actions[i].invoke();
                return;
            }
        }
        hidePopup(n);
    }

    function _trimHistory(): void {
        const all = server.trackedNotifications.values;
        for (let i = 0; i < all.length - historySize; i++)
            all[i].dismiss();
    }

    function _forget(n: var): void {
        if (popups.indexOf(n) >= 0)
            popups = popups.filter(p => p !== n);
    }

    function focusedScreen(): var {
        const mon = Hyprland.focusedMonitor;
        const screens = Quickshell.screens;
        for (let i = 0; i < screens.length; i++)
            if (mon && screens[i].name === mon.name)
                return screens[i];
        return screens.length > 0 ? screens[0] : null;
    }

    NotificationServer {
        id: server

        actionsSupported: true
        bodySupported: true
        // Plain text only: StyledText would fetch <img> sources from senders.
        bodyMarkupSupported: false
        bodyHyperlinksSupported: false
        imageSupported: true
        persistenceSupported: false

        onNotification: n => {
            n.tracked = true;
            n.closed.connect(() => root._forget(n));
            Qt.callLater(root._trimHistory);
            if (root.dnd && n.urgency !== NotificationUrgency.Critical) {
                if (n.transient)
                    n.expire();
                return;
            }
            const next = [n].concat(root.popups.filter(p => p !== n));
            for (const old of next.slice(root.maxPopups))
                if (old.transient)
                    old.expire();
            root.popups = next.slice(0, root.maxPopups);
        }
    }

    // The window exists only while a popup is visible.
    LazyLoader {
        active: root.popups.length > 0

        PanelWindow {
            screen: root.focusedScreen()
            anchors {
                top: true
                right: true
            }
            margins {
                top: Theme.gap
                right: Theme.gap
            }
            exclusiveZone: 0
            implicitWidth: root.popupWidth
            implicitHeight: Math.max(column.implicitHeight, 1)
            color: "transparent"
            WlrLayershell.namespace: "haseen-notifications"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            Column {
                id: column

                width: parent.width
                spacing: Theme.gap

                Repeater {
                    // ScriptModel diffs by identity: a new popup does not
                    // recreate (and restart the timers of) the others.
                    model: ScriptModel {
                        values: root.popups
                    }

                    delegate: NotificationCard {
                        required property var modelData

                        notification: modelData
                        width: column.width
                        popup: true
                        timeout: root.timeoutFor(modelData)
                        onExpired: root.hidePopup(modelData)
                        onActivated: root.invokeDefault(modelData)
                        onCloseClicked: root.dismiss(modelData)
                    }
                }
            }
        }
    }
}
