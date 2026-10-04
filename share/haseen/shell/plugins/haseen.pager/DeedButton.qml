import QtQuick
import qs.Haseen

// One thing a notification can do, as a button with its name on it.
// Adapted from omapager (https://github.com/njpatel/omapager, MIT,
// Copyright (c) 2026 Neil Jagdish Patel).
PagerButton {
    id: button

    property var deed: ({})
    // Not "card": the toast's id is `card`, so a property of that name would
    // bind to itself.
    property var toast: null
    property bool wide: false

    // Matched on the value as well as the kind: a card carrying two codes has
    // two Copy buttons, and pressing one must not tick both.
    readonly property bool taken: toast !== null && toast.takenKind === String(deed.kind) + ":" + String(deed.value)

    // Under the pointer? Worked out from where the deck says the pointer is.
    hot: {
        if (!toast || !toast.hovered)
            return false;
        const origin = mapToItem(toast, 0, 0);
        const px = toast.localHoverX;
        const py = toast.localHoverY;
        return px >= origin.x && px <= origin.x + width && py >= origin.y && py <= origin.y + height;
    }

    // A tick, not a word: the mark means "that happened" whatever the verb.
    text: taken ? "\u{f012c}" : String(deed.label || "")
    foreground: Theme.foreground
    fontSize: Theme.fontSize * (toast ? toast.fontScale : 1)
    leftAlign: wide
    wrap: wide
    width: wide && parent ? parent.width : implicitWidth

    onClicked: button.toast.doDeed(button.deed)
}
