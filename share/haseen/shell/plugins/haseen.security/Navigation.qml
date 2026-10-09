import QtQuick
import qs.Haseen
Row {
    id: root
    property int selected: 0
    signal chosen(int index)
    function focusSelected(): void { tabs.itemAt(selected).forceActiveFocus(); }
    spacing: 0
    Accessible.role: Accessible.PageTabList
    Accessible.name: "Security pages"
    Repeater {
        id: tabs
        model: ["Overview", "Tools", "Services", "Local"]
        delegate: ActionButton {
            required property string modelData
            required property int index
            width: root.width / 4
            text: modelData
            current: root.selected === index
            activeFocusOnTab: activeFocus || current
            Accessible.role: Accessible.PageTab
            Accessible.name: index === 3 ? "Local actions" : modelData
            Accessible.selected: current
            onClicked: root.chosen(index)
            Keys.onPressed: event => {
                if ([Qt.Key_Left, Qt.Key_H, Qt.Key_Right, Qt.Key_L, Qt.Key_Home, Qt.Key_End].indexOf(event.key) >= 0) {
                    root.chosen(event.key === Qt.Key_Home ? 0 : event.key === Qt.Key_End ? 3 : Math.max(0, Math.min(3, index + (event.key === Qt.Key_Left || event.key === Qt.Key_H ? -1 : 1))));
                    root.focusSelected();
                    event.accepted = true;
                }
            }
        }
    }
}
