import QtQuick

// @ID@: launcher provider. The launcher calls query(text) for input that
// starts with prefix and shows the results.
QtObject {
    id: root

    // Every entry gets these from the host (docs/architecture.md 5.2).
    property string pluginId
    property var settings: ({})
    property var screen: null

    property string prefix: "@ID@ "

    function query(text: string): var {
        return [
            {
                title: "Echo: " + text,
                subtitle: root.pluginId,
                icon: "",
                exec: () => console.info(root.pluginId + ": picked " + text)
            }
        ];
    }
}
