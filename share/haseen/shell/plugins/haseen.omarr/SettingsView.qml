import QtQuick
import qs.Haseen
import qs.Haseen.Widgets
import "Model.js" as Model

// haseen.omarr's settings, loaded into the panel on demand. Two tabs:
// SETTINGS (poll interval, queue page size, density, the progress
// notification) and FLEET (the services, grouped, with reorder and remove,
// a scan of this machine's common ports, and the add/edit form with the
// kind's credentials and notification switches). Everything is written
// through the service; credentials go to its private state file.
//
// Adapted from SettingsView.qml in omARR (MIT, Copyright (c) 2026 luccast),
// as the owner's fork t1nk33r.omarr 1.0.0; see LICENSE and UPSTREAM.md beside
// this file. haseen changes: theme tokens and the Omarr* controls instead of
// the Ui controls, the kind dropdown is a row of pills, remove asks for a second click,
// Enter in a field saves.
Column {
    id: root

    property var service: null
    property bool compact: false

    readonly property color dim: Theme.subtle(Theme.surface)
    readonly property var services: service && service.services ? service.services : []
    readonly property string fleetKey: Model.fleetOrderKey(services)
    readonly property var scanResults: service && service.scanResults ? service.scanResults : []
    readonly property bool scanning: service ? service.scanning === true : false
    // While a field has the keyboard the panel's single-key shortcuts stay off.
    readonly property bool editorOpen: nameField.activeFocus || urlField.activeFocus || groupField.activeFocus || apiField.activeFocus || userField.activeFocus || passField.activeFocus

    readonly property var kindOptions: [
        {
            value: "generic",
            label: "Generic"
        },
        {
            value: "sonarr",
            label: "Sonarr"
        },
        {
            value: "radarr",
            label: "Radarr"
        },
        {
            value: "jellyfin",
            label: "Jellyfin"
        },
        {
            value: "sabnzbd",
            label: "SABnzbd"
        },
        {
            value: "qbittorrent",
            label: "qBittorrent"
        }
    ]
    readonly property var listTabs: [
        {
            id: "settings",
            label: "SETTINGS"
        },
        {
            id: "fleet",
            label: "FLEET"
        }
    ]

    property string mode: "list"
    property string listTab: "settings"
    property string editingId: ""
    property string confirmRemoveId: ""
    property string formKind: "generic"
    property bool formNotifyGrab: true
    property bool formNotifyImport: true
    property bool formNotifyDownload: true
    property bool formNotifyHealth: true
    property bool formShowQueue: false
    property bool formShowCalendar: false

    readonly property bool needsKey: Model.kindNeedsApiKey(formKind)
    readonly property bool needsUser: Model.kindNeedsUserPass(formKind)
    readonly property bool needsUsername: Model.kindNeedsUsername(formKind)
    readonly property bool arrKind: formKind === "sonarr" || formKind === "radarr"
    readonly property bool downloaderKind: formKind === "sabnzbd" || formKind === "qbittorrent"

    signal closeSettings
    // The form closed; the panel takes the keyboard back from its fields.
    signal editingDone

    function setFormKind(kind: string): void {
        formKind = Model.kindOf(kind);
    }

    function resetForm(): void {
        setFormKind("generic");
        nameField.text = "";
        urlField.text = Model.defaultUrlForKind("generic");
        groupField.text = "";
        apiField.text = "";
        userField.text = "";
        passField.text = "";
        formNotifyGrab = true;
        formNotifyImport = true;
        formNotifyDownload = true;
        formNotifyHealth = true;
        formShowQueue = false;
        formShowCalendar = false;
        editingId = "";
    }

    function leaveForm(): void {
        resetForm();
        mode = "list";
        editingDone();
    }

    function fillKind(kind: string): void {
        const previous = formKind;
        setFormKind(kind);
        const prevLabel = Model.kindLabel(previous);
        if (!nameField.text || nameField.text === prevLabel)
            nameField.text = Model.uniqueServiceName(services, formKind, editingId);
        if (!urlField.text || urlField.text.indexOf("127.0.0.1") !== -1)
            urlField.text = Model.defaultUrlForKind(formKind);
        if (!editingId && (!groupField.text || groupField.text === Model.kindGroup(previous)))
            groupField.text = Model.kindGroup(formKind);
        if (!editingId) {
            formShowQueue = downloaderKind;
            formShowCalendar = arrKind;
        }
    }

    function startAdd(): void {
        listTab = "fleet";
        resetForm();
        mode = "edit";
    }

    function showFleet(): void {
        resetForm();
        mode = "list";
        listTab = "fleet";
    }

    function startEdit(row: var): void {
        if (!row)
            return;
        listTab = "fleet";
        mode = "edit";
        confirmRemoveId = "";
        editingId = row.id;
        setFormKind(row.kind);
        nameField.text = row.name;
        urlField.text = row.url;
        groupField.text = row.group;
        formNotifyGrab = row.notifyGrab !== false;
        formNotifyImport = row.notifyImport !== false;
        formNotifyDownload = row.notifyDownload !== false;
        formNotifyHealth = row.notifyHealth !== false;
        formShowQueue = row.showQueue === true;
        formShowCalendar = row.showCalendar === true;
        const cred = service ? service.cred(row.id) : null;
        apiField.text = cred && cred.apiKey ? cred.apiKey : "";
        userField.text = cred && cred.username ? cred.username : "";
        passField.text = cred && cred.password ? cred.password : "";
    }

    function saveForm(): void {
        if (!service)
            return;
        const draft = {
            kind: formKind,
            name: nameField.text,
            url: urlField.text,
            group: Model.normalizeGroup(groupField.text, ""),
            notifyGrab: formNotifyGrab,
            notifyImport: formNotifyImport,
            notifyDownload: formNotifyDownload,
            notifyHealth: formNotifyHealth,
            showQueue: formShowQueue,
            showCalendar: formShowCalendar
        };
        const creds = {
            apiKey: apiField.text,
            username: userField.text,
            password: passField.text
        };
        if (editingId)
            service.updateService(editingId, draft, creds);
        else
            service.addService(draft, creds);
        leaveForm();
    }

    function applyScan(hit: var): void {
        startAdd();
        setFormKind(hit.kind);
        nameField.text = Model.uniqueServiceName(services, formKind);
        urlField.text = hit.url;
        groupField.text = Model.kindGroup(hit.kind);
        formShowQueue = downloaderKind;
        formShowCalendar = arrKind;
    }

    function removeRow(id: string): void {
        if (confirmRemoveId !== id) {
            confirmRemoveId = id;
            return;
        }
        confirmRemoveId = "";
        if (service)
            service.removeService(id);
    }

    spacing: compact ? Math.round(Theme.gap * 0.75) : Theme.gap

    // Header: the list tabs or the form's title, and its actions.
    Item {
        width: parent.width
        height: Math.max(formTitle.implicitHeight, tabs.implicitHeight, headerActions.implicitHeight)

        OmarrSectionHeader {
            id: formTitle

            anchors.left: parent.left
            anchors.right: headerActions.left
            anchors.verticalCenter: parent.verticalCenter
            visible: root.mode === "edit"
            text: root.editingId ? "EDIT SERVICE" : "ADD SERVICE"
        }

        OmarrTabs {
            id: tabs

            anchors.left: parent.left
            anchors.right: headerActions.left
            anchors.rightMargin: Theme.gap
            anchors.verticalCenter: parent.verticalCenter
            visible: root.mode === "list"
            model: root.listTabs
            current: root.listTab
            onPicked: id => root.listTab = id
        }

        Row {
            id: headerActions

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            OmarrButton {
                visible: root.mode === "list" && root.listTab === "fleet"
                glyph: "\u{f0415}"
                tooltipText: "Add service"
                onClicked: root.startAdd()
            }

            OmarrButton {
                visible: root.mode === "list" && root.listTab === "fleet"
                glyph: "\u{f0349}"
                tooltipText: root.scanning ? "Scanning…" : "Scan local ports"
                foreground: root.scanning ? Theme.accent : Theme.foreground
                onClicked: {
                    if (root.service)
                        root.service.startScan();
                }
            }

            OmarrButton {
                glyph: "\u{f0156}"
                tooltipText: root.mode === "edit" ? "Back" : "Close settings"
                onClicked: {
                    if (root.mode === "edit")
                        root.leaveForm();
                    else
                        root.closeSettings();
                }
            }
        }
    }

    // SETTINGS tab.
    Column {
        width: parent.width
        spacing: Theme.gap * 2
        visible: root.mode === "list" && root.listTab === "settings"

        Row {
            spacing: Theme.gap * 2

            OmarrNumberField {
                label: "Poll interval (seconds)"
                value: root.service ? root.service.pollSeconds : Model.DEFAULT_POLL_SECONDS
                from: 5
                to: 3600
                stepSize: 5
                onModified: v => {
                    if (root.service)
                        root.service.persistSettings({
                            pollSeconds: v
                        });
                }
            }

            OmarrNumberField {
                label: "Queue page size"
                value: root.service ? root.service.pageSize : Model.LIST_PAGE_SIZE
                from: Model.PAGE_SIZE_MIN
                to: Model.PAGE_SIZE_MAX
                stepSize: 5
                onModified: v => {
                    if (!root.service)
                        return;
                    root.service.persistSettings({
                        pageSize: v
                    });
                    root.service.clearDetailQueue();
                    root.service.forcePoll();
                }
            }
        }

        OmarrToggle {
            label: "Compact density"
            description: "Tighter fleet rows"
            checked: root.compact
            onClicked: {
                if (root.service)
                    root.service.persistSettings({
                        density: root.compact ? "comfortable" : "compact"
                    });
            }
        }

        OmarrToggle {
            label: "Download progress"
            description: "Keep a notification with the progress up while something is downloading"
            checked: root.service ? root.service.showProgressToast !== false : true
            onClicked: {
                if (root.service)
                    root.service.persistSettings({
                        showProgressToast: !root.service.showProgressToast
                    });
            }
        }
    }

    // FLEET tab.
    Column {
        width: parent.width
        spacing: Theme.gap
        visible: root.mode === "list" && root.listTab === "fleet"

        Text {
            visible: root.scanning
            width: parent.width
            textFormat: Text.PlainText
            text: "Pinging common ports on this machine…"
            color: root.dim
            font.family: Theme.fontFamily
            font.pixelSize: Math.max(1, Theme.fontSize - 1)
            font.italic: true
        }

        Column {
            width: parent.width
            spacing: Math.round(Theme.gap / 2)
            visible: root.scanResults.length > 0

            Text {
                width: parent.width
                textFormat: Text.PlainText
                text: "Found on localhost"
                color: root.dim
                font.family: Theme.fontFamily
                font.pixelSize: Math.max(1, Theme.fontSize - 1)
                font.bold: true
            }

            Repeater {
                model: root.scanResults

                OmarrRow {
                    id: scanRow

                    required property var modelData

                    width: parent.width
                    implicitHeight: scanLabel.implicitHeight + Theme.gap * 1.5
                    hasCursor: scanMouse.containsMouse

                    Row {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.margins: Math.round(Theme.gap * 0.75)
                        spacing: Theme.gap

                        ServiceIcon {
                            id: scanIcon

                            anchors.verticalCenter: parent.verticalCenter
                            service: scanRow.modelData
                        }

                        Text {
                            id: scanLabel

                            width: parent.width - scanIcon.width - parent.spacing
                            textFormat: Text.PlainText
                            text: scanRow.modelData.name + " · " + scanRow.modelData.url
                            color: Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            elide: Text.ElideRight
                        }
                    }

                    MouseArea {
                        id: scanMouse

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.applyScan(scanRow.modelData)
                    }
                }
            }
        }

        Text {
            visible: root.services.length === 0 && root.scanResults.length === 0 && !root.scanning
            width: parent.width
            textFormat: Text.PlainText
            text: "No services yet. Add one, or scan this machine for Sonarr, Radarr, and friends."
            wrapMode: Text.WordWrap
            color: root.dim
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            font.italic: true
        }

        Repeater {
            model: {
                root.fleetKey;
                return Model.groupedServices(root.services);
            }

            Column {
                id: groupCol

                required property var modelData

                width: parent.width
                spacing: 2

                Text {
                    visible: groupCol.modelData.group !== ""
                    width: parent.width
                    textFormat: Text.PlainText
                    text: groupCol.modelData.group
                    color: root.dim
                    font.family: Theme.fontFamily
                    font.pixelSize: Math.max(1, Theme.fontSize - 1)
                    font.bold: true
                }

                Repeater {
                    model: groupCol.modelData.services

                    OmarrRow {
                        id: svcRow

                        required property var modelData
                        required property int index

                        width: parent.width
                        implicitHeight: Math.max(svcCol.implicitHeight, upButton.height) + Theme.gap * 1.5
                        hasCursor: svcMouse.containsMouse

                        MouseArea {
                            id: svcMouse

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.startEdit(svcRow.modelData)
                        }

                        Row {
                            anchors.fill: parent
                            anchors.margins: Math.round(Theme.gap * 0.75)
                            spacing: Theme.gap

                            ServiceIcon {
                                id: svcIcon

                                anchors.verticalCenter: parent.verticalCenter
                                service: svcRow.modelData
                            }

                            Column {
                                id: svcCol

                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - svcIcon.width - actions.width - parent.spacing * 2
                                spacing: 1

                                Text {
                                    width: parent.width
                                    textFormat: Text.PlainText
                                    text: svcRow.modelData.name
                                    color: Theme.foreground
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize
                                    font.bold: true
                                    elide: Text.ElideRight
                                }

                                Text {
                                    width: parent.width
                                    textFormat: Text.PlainText
                                    text: root.confirmRemoveId === svcRow.modelData.id ? "Click remove again to delete it and its credentials" : Model.kindLabel(svcRow.modelData.kind) + " · " + (svcRow.modelData.url || "no url")
                                    color: root.confirmRemoveId === svcRow.modelData.id ? Theme.urgent : root.dim
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Math.max(1, Theme.fontSize - 1)
                                    elide: Text.ElideRight
                                }
                            }

                            Row {
                                id: actions

                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2

                                OmarrButton {
                                    id: upButton

                                    glyph: "\u{f005d}"
                                    tooltipText: "Move up"
                                    enabled: svcRow.index > 0
                                    onClicked: {
                                        if (root.service)
                                            root.service.moveService(svcRow.modelData.id, -1);
                                    }
                                }

                                OmarrButton {
                                    glyph: "\u{f0045}"
                                    tooltipText: "Move down"
                                    enabled: svcRow.index < groupCol.modelData.services.length - 1
                                    onClicked: {
                                        if (root.service)
                                            root.service.moveService(svcRow.modelData.id, 1);
                                    }
                                }

                                OmarrButton {
                                    glyph: "\u{f01b4}"
                                    tooltipText: root.confirmRemoveId === svcRow.modelData.id ? "Remove for good" : "Remove"
                                    foreground: root.confirmRemoveId === svcRow.modelData.id ? Theme.urgent : Theme.foreground
                                    hoverColor: Theme.urgent
                                    onClicked: root.removeRow(svcRow.modelData.id)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // The add/edit form.
    Column {
        width: parent.width
        spacing: Theme.gap
        visible: root.mode === "edit"

        Text {
            width: parent.width
            textFormat: Text.PlainText
            text: "Kind"
            color: root.dim
            font.family: Theme.fontFamily
            font.pixelSize: Math.max(1, Theme.fontSize - 1)
        }

        Flow {
            width: parent.width
            spacing: Math.round(Theme.gap / 2)

            Repeater {
                model: root.kindOptions

                Pill {
                    required property var modelData

                    text: modelData.label
                    active: root.formKind === modelData.value
                    onClicked: {
                        if (!active)
                            root.fillKind(modelData.value);
                    }
                }
            }
        }

        OmarrField {
            id: nameField

            width: parent.width
            activeFocusOnTab: true
            placeholderText: "Name"
            onAccepted: root.saveForm()
        }

        OmarrField {
            id: urlField

            width: parent.width
            activeFocusOnTab: true
            placeholderText: "http://127.0.0.1:8989"
            onAccepted: root.saveForm()
        }

        OmarrField {
            id: groupField

            width: parent.width
            activeFocusOnTab: true
            placeholderText: "Group (optional)"
            onAccepted: root.saveForm()
        }

        OmarrField {
            id: apiField

            width: parent.width
            visible: root.needsKey
            activeFocusOnTab: visible
            password: true
            placeholderText: root.formKind === "jellyfin" ? "Jellyfin API key" : "API key"
            onAccepted: root.saveForm()
        }

        OmarrField {
            id: userField

            width: parent.width
            visible: root.needsUsername
            activeFocusOnTab: visible
            placeholderText: root.formKind === "jellyfin" ? "Profile name (optional)" : "Username"
            onAccepted: root.saveForm()
        }

        OmarrField {
            id: passField

            width: parent.width
            visible: root.needsUser
            activeFocusOnTab: visible
            password: true
            placeholderText: "Password"
            onAccepted: root.saveForm()
        }

        OmarrToggle {
            visible: root.arrKind || root.downloaderKind
            label: "Show queue on Overview"
            checked: root.formShowQueue
            onClicked: root.formShowQueue = !root.formShowQueue
        }

        OmarrToggle {
            visible: root.arrKind
            label: "Show calendar on Overview"
            checked: root.formShowCalendar
            onClicked: root.formShowCalendar = !root.formShowCalendar
        }

        OmarrToggle {
            visible: root.arrKind || Model.isMediaKind(root.formKind)
            label: Model.isMediaKind(root.formKind) ? "Notify on newly added" : "Notify on grab"
            checked: root.formNotifyGrab
            onClicked: root.formNotifyGrab = !root.formNotifyGrab
        }

        OmarrToggle {
            visible: root.arrKind
            label: "Notify on import"
            checked: root.formNotifyImport
            onClicked: root.formNotifyImport = !root.formNotifyImport
        }

        OmarrToggle {
            visible: root.downloaderKind
            label: "Notify when downloads finish"
            checked: root.formNotifyDownload
            onClicked: root.formNotifyDownload = !root.formNotifyDownload
        }

        OmarrToggle {
            visible: root.arrKind
            label: "Notify on download fail"
            checked: root.formNotifyDownload
            onClicked: root.formNotifyDownload = !root.formNotifyDownload
        }

        OmarrToggle {
            label: "Notify on health changes"
            checked: root.formNotifyHealth
            onClicked: root.formNotifyHealth = !root.formNotifyHealth
        }

        Row {
            spacing: Theme.gap

            Pill {
                text: "Save"
                active: true
                onClicked: root.saveForm()
            }

            Pill {
                text: "Cancel"
                onClicked: root.leaveForm()
            }
        }
    }
}
