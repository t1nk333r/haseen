import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import qs.Haseen

// The file names in an icon directory that may not exist, so the cards only
// try files that are there (a missing file is a log line per card).
// FolderListModel falls back to the working directory for a missing folder,
// so it is created only once a FileView probe (NotAFile = a directory) says
// the directory exists - the same pattern as Plugins.qml.
Scope {
    id: root

    required property string path
    // 1 directory, -1 absent, 0 unknown.
    property int presence: 0
    property var names: ({})

    signal listingChanged

    function rescan(): void {
        probe.reload();
    }

    function _collect(): void {
        const out = {};
        const model = loader.item;
        if (model)
            for (let i = 0; i < model.count; i++)
                out[String(model.get(i, "fileName"))] = true;
        names = out;
        listingChanged();
    }

    FileView {
        id: probe

        path: root.path
        printErrors: false
        onLoaded: {
            root.presence = -1;
            root._collect();
        }
        onLoadFailed: error => {
            root.presence = error === FileViewError.NotAFile ? 1 : -1;
            root._collect();
        }
    }

    LazyLoader {
        id: loader

        active: root.presence === 1

        FolderListModel {
            folder: Paths.fileUrl(root.path)
            showDirs: false
            showDotAndDotDot: false
            nameFilters: ["*.png", "*.svg", "*.ico"]
            onStatusChanged: root._collect()
            onCountChanged: root._collect()
        }
    }
}
