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
            activeFocusOnTab: current
            Accessible.role: Accessible.PageTab
            Accessible.name: index === 3 ? "Local actions" : modelData
            Accessible.selected: current
            onClicked: root.chosen(index)
            Keys.onPressed: event => {
                if (event.key === Qt.Key_Left || event.key === Qt.Key_H || event.key === Qt.Key_Right || event.key === Qt.Key_L) {
                    root.chosen((index + (event.key === Qt.Key_Left || event.key === Qt.Key_H ? 3 : 1)) % 4);
                    root.focusSelected();
                    event.accepted = true;
                }
            }
        }
    }
}
