.pragma library

// Where a native panel popup sits (PanelPopup.qml). Pure: no Qt types, so
// tests/test-panel-placement.sh runs it headless.
//
// An opener is the bar widget a click landed on, as Bar.qml reports it:
// { screen, position, centre, extent, time }, with `centre` the widget's
// middle along the bar and `extent` the bar's length, both measured on the
// bar's edge without the pixel it reaches under the frame at each end, and
// `time` from Date.now().
//
// Widgets open panels through a detached `qs ipc call panel toggle`, which
// carries no item, so the shell pairs the toggle with the last bar press.
// A press older than OPENER_MS did not cause the toggle: that one came from
// a key, the CLI or the menu, and the panel opens centred on the bar edge.
const OPENER_MS = 1500;

const EDGES = ["top", "bottom", "left", "right"];

// The press a toggle at `now` came from, or null.
function opener(press, now) {
    if (!press || !(press.extent > 0) || !(now - press.time >= 0) || now - press.time >= OPENER_MS)
        return null;
    return press;
}

// Start of a popup of `size` centred on `centre`, kept `margin` inside a bar
// of length `extent`. A popup wider than the room left starts at `margin`.
function offset(centre, size, extent, margin) {
    return Math.round(Math.max(margin, Math.min(centre - size / 2, extent - size - margin)));
}

// Layer-shell anchors and margins for a popup of width x height on a bar at
// `position`. The bar's edge is always anchored, `margin` off it. With an
// opener on that bar, the start of the bar (left for a top/bottom bar, top
// for a left/right one) is anchored too, with the popup centred on the
// widget. The popup and the bar measure from the same origin: Hyprland lays
// both out in the area the surfaces arranged before them leave (the frame's
// strips, which sit on the bottom layer). Without an opener the compositor
// centres the popup along the bar edge. A panel whose `placement` setting is
// "center" anchors nothing, so the compositor centres it on the screen.
function place(position, press, width, height, margin, placement) {
    const edge = EDGES.indexOf(position) >= 0 ? position : "top";
    const r = {
        top: false,
        bottom: false,
        left: false,
        right: false,
        marginTop: 0,
        marginBottom: 0,
        marginLeft: 0,
        marginRight: 0
    };
    if (placement === "center")
        return r;
    r[edge] = true;
    r["margin" + edge[0].toUpperCase() + edge.slice(1)] = margin;
    if (!press || press.position !== edge || !(press.extent > 0))
        return r;
    const vertical = edge === "left" || edge === "right";
    if (vertical) {
        r.top = true;
        r.marginTop = offset(press.centre, height, press.extent, margin);
    } else {
        r.left = true;
        r.marginLeft = offset(press.centre, width, press.extent, margin);
    }
    return r;
}
