import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import qs.Haseen
import "Privacy.js" as Privacy

// iPhone-style privacy dots, event-driven and hidden (zero size) while
// nothing is in use:
//   green  (Theme.success) camera: a camera source linked to a stream
//   orange (Theme.warning) microphone: an audio source linked to a capture stream
//   red    (Theme.urgent)  screen: the `recording` flag (Flags) or a portal
//                          screencast linked to a consumer
//   blue   (Theme.accent)  location: GeoClue Manager.InUse (geoclue-watch.sh)
// The iOS colours map onto theme tokens (architecture 7: no literals).
// Hover lists the apps; a click on the red dot while recording stops it.
//
// PipeWire link groups come from Quickshell's own event stream. Node types
// are known unbound (registry globals); only the groups that matter and
// their two ends are bound (PwObjectTracker) to learn the link state and the
// consumer's application.name, so nothing is bound while nothing captures.
// The approach follows the owner's t1nk33r.privacy plugin.
//
// Limits: apps that open /dev/video* directly (V4L2, not PipeWire) are not
// seen; detecting them needs polling /proc, which architecture 6 forbids.
Item {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null
    property bool vertical: false

    readonly property var ignore: Array.isArray(settings.ignore) ? settings.ignore : []
    property bool locationInUse: false

    function plainNode(n: var): var {
        if (!n)
            return null;
        const t = Number(n.type);
        return {
            id: n.id,
            name: n.name,
            description: n.description,
            nickname: n.nickname,
            audio: (t & PwNodeType.Audio) !== 0,
            video: (t & PwNodeType.Video) !== 0,
            source: (t & PwNodeType.Source) !== 0,
            stream: (t & PwNodeType.Stream) !== 0,
            props: n.properties || {}
        };
    }

    // [{ group, plain }] for the groups Privacy.interesting() keeps.
    readonly property var captures: (Pipewire.linkGroups ? Pipewire.linkGroups.values : []).map(g => ({
                group: g,
                plain: {
                    source: root.plainNode(g.source),
                    target: root.plainNode(g.target),
                    active: g.state === PwLinkState.Active
                }
            })).filter(c => Privacy.interesting(c.plain))
    readonly property var usage: Privacy.classify(captures.map(c => c.plain), ignore)

    readonly property var screenApps: (Flags.recording ? ["Screen recording"] : []).concat(usage.screen)
    readonly property var dots: {
        const out = [];
        if (settings.showCamera !== false && usage.camera.length > 0)
            out.push({
                color: Theme.success,
                label: "Camera",
                apps: usage.camera
            });
        if (settings.showMicrophone !== false && usage.mic.length > 0)
            out.push({
                color: Theme.warning,
                label: "Microphone",
                apps: usage.mic
            });
        if (settings.showScreen !== false && screenApps.length > 0)
            out.push({
                color: Theme.urgent,
                label: "Screen",
                apps: screenApps
            });
        if (settings.showLocation !== false && locationInUse)
            out.push({
                color: Theme.accent,
                label: "Location",
                apps: []
            });
        return out;
    }
    readonly property string summary: dots.map(d => d.label + (d.apps.length > 0 ? ": " + d.apps.join(", ") : " in use")).join("\n") + (Flags.recording && settings.showScreen !== false ? "\nClick the red dot to stop recording" : "")
    readonly property int dotSize: Math.max(6, Math.round(Theme.fontSize * 0.55))

    // Vertical: the slot is the bar's width anyway; report content width
    // only (depending on the parent's width would loop through BarSection).
    implicitWidth: dots.length === 0 ? 0 : vertical ? grid.implicitWidth : grid.implicitWidth + Theme.gap * 2
    implicitHeight: dots.length === 0 ? 0 : vertical ? grid.implicitHeight + Theme.gap * 2 : Config.barHeight

    PwObjectTracker {
        objects: {
            const out = [];
            for (const c of root.captures) {
                out.push(c.group);
                if (c.group.source)
                    out.push(c.group.source);
                if (c.group.target)
                    out.push(c.group.target);
            }
            return out;
        }
    }

    // Test hook (settings.debugIpc): what the hover would list, without a
    // pointer. One bar per screen means one handler per screen; the first wins.
    IpcHandler {
        target: "haseen.privacy"
        enabled: root.settings.debugIpc === true

        function summary(): string {
            return JSON.stringify({
                dots: root.dots.map(d => d.label),
                usage: root.usage,
                location: root.locationInUse,
                recording: Flags.recording,
                tooltip: root.summary
            });
        }
    }

    Process {
        running: root.settings.showLocation !== false
        command: ["bash", Qt.resolvedUrl("geoclue-watch.sh").toString().replace(/^file:\/\//, "")]
        stdout: SplitParser {
            onRead: line => {
                const v = Privacy.parseGeoclue(line);
                if (v !== null)
                    root.locationInUse = v;
            }
        }
    }

    // Hover only: clicks fall through to the dots.
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
    }

    Grid {
        id: grid
        anchors.centerIn: parent
        visible: root.dots.length > 0
        columns: root.vertical ? 1 : Math.max(1, root.dots.length)
        spacing: Math.round(Theme.gap * 0.66)

        Repeater {
            model: root.dots

            delegate: Rectangle {
                required property var modelData

                width: root.dotSize
                height: root.dotSize
                radius: width / 2
                color: modelData.color

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -Math.round(Theme.gap / 2)
                    enabled: modelData.label === "Screen" && Flags.recording
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: Quickshell.execDetached(["haseen", "capture", "screenrecord", "--stop"])
                }
            }
        }
    }

    // Hover list of who uses what; the window exists only while hovered.
    LazyLoader {
        active: mouse.containsMouse && root.summary !== ""

        PopupWindow {
            // Opens away from the bar edge, whichever edge that is.
            readonly property string pos: Config.barPosition
            readonly property int away: pos === "bottom" ? Edges.Top : pos === "left" ? Edges.Right : pos === "right" ? Edges.Left : Edges.Bottom

            visible: true
            color: "transparent"
            anchor.item: root
            anchor.edges: away
            anchor.gravity: away
            anchor.margins.top: pos === "top" ? Theme.gap : 0
            anchor.margins.bottom: pos === "bottom" ? Theme.gap : 0
            anchor.margins.left: pos === "left" ? Theme.gap : 0
            anchor.margins.right: pos === "right" ? Theme.gap : 0
            implicitWidth: Math.ceil(label.implicitWidth) + Theme.gap * 2
            implicitHeight: Math.ceil(label.implicitHeight) + Theme.gap * 2

            Rectangle {
                anchors.fill: parent
                color: Theme.surface
                radius: Theme.radius
                border.width: Theme.borderWidth
                border.color: Theme.border

                Text {
                    id: label
                    anchors.centerIn: parent
                    text: root.summary
                    textFormat: Text.PlainText
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                }
            }
        }
    }
}
