import QtQuick

// Filters synthetic hover churn from rows moving under a stationary pointer:
// keyboard scrolling, a search narrowing the list or async rows landing pass
// rows under the pointer, and without this gate each one took the selection.
// Call reset() after keyboard and list changes, then moved() from a row's
// MouseArea before changing the selection. A change that came from the
// pointer (a click into a submenu) calls allowInitialSample() so the row
// under the still pointer may take the selection.
//
// Ported from Omarchy shell/Ui/PointerMoveGate.qml (MIT, Copyright (c)
// David Heinemeier Hansson), unchanged in behaviour.
QtObject {
    id: root

    property Item referenceItem: null
    property real threshold: 1
    property bool primed: false
    property bool initialSampleAllowed: false
    property real lastX: 0
    property real lastY: 0

    function reset(): void {
        primed = false;
        initialSampleAllowed = false;
        lastX = 0;
        lastY = 0;
    }

    function allowInitialSample(): void {
        reset();
        initialSampleAllowed = true;
    }

    function moved(item: Item, mouse: var): bool {
        if (!item || !mouse) {
            reset();
            return false;
        }
        const point = item.mapToItem(referenceItem || item, mouse.x, mouse.y);
        const firstSample = !primed;
        const didMove = firstSample ? initialSampleAllowed : Math.abs(point.x - lastX) > threshold || Math.abs(point.y - lastY) > threshold;
        // Keep the last accepted position while filtering jitter, so slow
        // sub-threshold steps add up to a deliberate move.
        if (firstSample || didMove) {
            lastX = point.x;
            lastY = point.y;
        }
        primed = true;
        initialSampleAllowed = false;
        return didMove;
    }
}
