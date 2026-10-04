import QtQuick
import Quickshell
import "Cliphist.js" as Cliphist

// Launcher provider: `>text` in the launcher searches clipboard history;
// Enter copies the entry back. Created when the launcher opens and destroyed
// with it, so `cliphist list` runs once per open.
Scope {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    readonly property string prefix: ">"

    function query(text: string): var {
        return Cliphist.filter(history.entries, text).slice(0, 50).map(e => ({
                    title: e.preview.replace(/\s+/g, " ").trim(),
                    subtitle: e.image ? "Image" : "Clipboard",
                    icon: e.image ? "image-x-generic" : "edit-paste",
                    exec: () => history.copy(e)
                }));
    }

    History {
        id: history
    }
}
