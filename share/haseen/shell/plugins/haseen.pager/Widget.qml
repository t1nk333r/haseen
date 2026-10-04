import QtQuick
import Quickshell
import qs.Haseen
import qs.Haseen.Widgets

// The bar indicator. Adapted from omapager (https://github.com/njpatel/omapager,
// MIT, Copyright (c) 2026 Neil Jagdish Patel).
//
// It takes a slot only while something is being kept from you - Do Not
// Disturb, everything snoozed, one source snoozed - or while a detected screen
// share is waiting for a snooze decision (`alwaysShow` keeps it). A bell that
// is always there, always showing nothing, is clutter.
//
// Left click opens the panel; right click silences, or lets everything back
// through when something is quiet (the owner's luna patch, kept).
BarButton {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    readonly property var service: {
        const entry = Plugins.roles.notifications;
        return entry && entry.id === root.pluginId ? entry.instance : null;
    }
    readonly property bool silenced: Flags.dnd
    readonly property int snoozeRevision: service ? service.snoozeRevision : 0
    readonly property bool globalSnoozed: {
        snoozeRevision;
        return service ? service.globalSnoozeUntil > 0 : false;
    }
    readonly property int snoozedSources: {
        snoozeRevision;
        return service ? service.snoozeCount : 0;
    }
    readonly property bool quiet: silenced || globalSnoozed
    readonly property bool hasState: quiet || snoozedSources > 0
    readonly property bool sharingOfferPending: service ? service.sharingOfferPending : false
    readonly property int recentCount: {
        if (!service)
            return 0;
        service.recentRevision;
        return service.recentForPanel(service.recentCount).length;
    }
    readonly property bool revealed: hasState || sharingOfferPending || settings.alwaysShow === true

    visible: revealed
    implicitWidth: visible ? contentWidth : 0
    // nf-md-monitor-share for a sharing offer, bell-off for silenced,
    // bell-sleep for snoozed, a plain bell otherwise.
    glyph: sharingOfferPending ? "\u{f1483}" : silenced ? "\u{f009b}" : (globalSnoozed || snoozedSources > 0) ? "\u{f00a0}" : "\u{f009a}"
    color: sharingOfferPending ? Theme.accent : silenced ? Theme.urgent : (globalSnoozed || snoozedSources > 0) ? Theme.accent : Theme.barForeground
    // The resting bell is dim only while Recent is empty.
    opacity: hasState || sharingOfferPending || recentCount > 0 ? 1 : 0.6

    onClicked: button => {
        if (button === Qt.RightButton && !sharingOfferPending) {
            if (quiet) {
                Flags.set("dnd", false);
                if (service)
                    service.unsnooze(service.globalKey);
            } else {
                Flags.set("dnd", true);
            }
            return;
        }
        Quickshell.execDetached(["qs", "ipc", "--pid", String(Quickshell.processId), "call", "panel", "toggle", root.pluginId]);
    }
}
