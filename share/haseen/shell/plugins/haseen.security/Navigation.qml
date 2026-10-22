import QtQuick
import qs.Haseen
Row {
    id: root
    property int selected: 0
    signal chosen(int index)
    function focusSelected(): void { tabs.itemAt(selected).forceActiveFocus(); }
    spacing: 0
    Accessible.role: Accessible.PageTabList
    Accessible.name: I18n.tr("Security pages")
    Repeater {
        id: tabs
        // English names, translated where shown.
        model: [I18n.mark("Overview"), I18n.mark("Tools"), I18n.mark("Services"), I18n.mark("Local")]
        delegate: ActionButton {
            required property string modelData
            required property int index
            width: root.width / 4
            text: I18n.tr(modelData)
            current: root.selected === index
            activeFocusOnTab: activeFocus || current
            Accessible.role: Accessible.PageTab
            Accessible.name: index === 3 ? I18n.tr("Local actions") : I18n.tr(modelData)
            Accessible.selected: current
            onClicked: root.chosen(index)
            Keys.onPressed: event => {
                if ([Qt.Key_Left, Qt.Key_H, Qt.Key_Right, Qt.Key_L, Qt.Key_Home, Qt.Key_End].indexOf(event.key) >= 0) {
                    // Left and Right follow the tabs on screen: a mirrored
                    // (right-to-left) row puts the first tab on the right.
                    const leftward = event.key === Qt.Key_Left || event.key === Qt.Key_H;
                    const step = leftward !== root.LayoutMirroring.enabled ? -1 : 1;
                    root.chosen(event.key === Qt.Key_Home ? 0 : event.key === Qt.Key_End ? 3 : Math.max(0, Math.min(3, index + step)));
                    root.focusSelected();
                    event.accepted = true;
                }
            }
        }
    }
}
