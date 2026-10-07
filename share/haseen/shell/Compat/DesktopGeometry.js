.pragma library

// Size and position of a DMS desktop widget on its screen (DmsDesktopWindow),
// kept apart from the layer window so it can be computed without one. The
// rules follow DankMaterialShell's Modules/Plugins/DesktopWidgetGeometry.qml
// and DesktopWidgetContent.qml (MIT, Copyright (c) 2025 Avenge Media LLC),
// read from shell.json `plugins.<id>.settings.desktop` instead of DMS's saved
// drag positions.

function number(value, fallback) {
    return typeof value === "number" && isFinite(value) ? value : fallback;
}

// The size the plugin asks for: defaultWidth, else widgetWidth, else 280 x 180.
function defaultSize(item) {
    return {
        width: number(item ? item.defaultWidth : undefined, number(item ? item.widgetWidth : undefined, 280)),
        height: number(item ? item.defaultHeight : undefined, number(item ? item.widgetHeight : undefined, 180))
    };
}

// DesktopWidgetGeometry.anchoredPosition: an offset from the start, the
// centre or the end of the screen; no offset at all is centred.
function coordinate(offset, anchor, extent, size) {
    if (typeof offset !== "number" || !isFinite(offset))
        return (extent - size) / 2;
    if (anchor === "center")
        return (extent - size) / 2 + offset;
    if (anchor === "end")
        return extent - size - offset;
    return offset;
}

// place(placement, screenWidth, screenHeight, widget) -> { x, y, width, height }.
// widget: { defaultWidth, defaultHeight, minWidth, minHeight, forceSquare,
// resizeWidth, resizeHeight } (a resize below 0 is none).
function place(placement, screenWidth, screenHeight, widget) {
    const p = placement || {};
    const wantWidth = widget.resizeWidth >= 0 ? widget.resizeWidth : number(p.width, widget.defaultWidth);
    const wantHeight = widget.resizeHeight >= 0 ? widget.resizeHeight : (widget.forceSquare ? wantWidth : number(p.height, widget.defaultHeight));
    const width = Math.max(widget.minWidth, Math.min(wantWidth, screenWidth));
    const height = Math.max(widget.minHeight, Math.min(wantHeight, screenHeight));
    return {
        x: Math.max(0, Math.min(coordinate(p.x, p.anchorX, screenWidth, width), screenWidth - width)),
        y: Math.max(0, Math.min(coordinate(p.y, p.anchorY, screenHeight, height), screenHeight - height)),
        width: width,
        height: height
    };
}
