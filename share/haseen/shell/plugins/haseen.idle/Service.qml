import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Haseen

// haseen.idle: two ext-idle-notify monitors, so the compositor does the
// counting and the shell holds no timer. After lockAfter seconds it calls
// the `lock` role (haseen.lock or any plugin providing it); after dpmsAfter
// seconds it turns the displays off and back on at the next input. With
// respectInhibitors, an idle inhibitor (mpv, a browser playing video) keeps
// both from firing.
Scope {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    readonly property int lockAfter: _seconds(settings.lockAfter, 300)
    readonly property int dpmsAfter: _seconds(settings.dpmsAfter, 330)
    readonly property bool respectInhibitors: settings.respectInhibitors !== false
    property bool _dpmsOff: false

    function _seconds(v: var, fallback: int): int {
        return (typeof v === "number" && isFinite(v) && v >= 0) ? Math.round(v) : fallback;
    }

    function _dpms(on: bool): void {
        // Hyprland 0.56 in Lua mode takes Lua dispatcher expressions.
        const action = on ? "enable" : "disable";
        Hyprland.dispatch(Hyprland.usingLua ? "hl.dsp.dpms({ action = \"" + action + "\" })" : "dpms " + (on ? "on" : "off"));
    }

    IdleMonitor {
        enabled: root.lockAfter > 0
        timeout: Math.max(root.lockAfter, 1)
        respectInhibitors: root.respectInhibitors
        onIsIdleChanged: {
            if (isIdle && !Plugins.callRole("lock", "lock", []))
                Plugins.warnOnce(root.pluginId + ":nolock", "haseen.idle: no plugin provides 'lock'; idle lock skipped");
        }
    }

    IdleMonitor {
        enabled: root.dpmsAfter > 0
        timeout: Math.max(root.dpmsAfter, 1)
        respectInhibitors: root.respectInhibitors
        onIsIdleChanged: {
            if (isIdle) {
                root._dpmsOff = true;
                root._dpms(false);
            } else if (root._dpmsOff) {
                root._dpmsOff = false;
                root._dpms(true);
            }
        }
    }
}
