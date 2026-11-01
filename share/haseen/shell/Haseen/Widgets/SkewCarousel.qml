// Adapted from Omarchy shell/plugins/image-picker/ImagePicker.qml.
// MIT, Copyright (c) David Heinemeier Hansson.
// haseen: no scrim and no shade over unselected slices; a widget the
// background and theme pickers share (plan 152).
import QtQuick
import qs.Haseen
import "Carousel.js" as Carousel

// Omarchy's image picker as a widget: the selected item large in the middle
// of the screen, the others as slanted slices on either side, its label
// under it. Left/Right (Tab/Shift+Tab) move, Enter or a click on the
// selected item emits activated(index), a click on another slice selects
// it. A filterable carousel takes typed text as a filter on the names
// (Backspace, Ctrl+Backspace and Ctrl+U edit it); Escape clears the filter,
// then emits dismissed(). Keys it does not use reach the parent.
//
// Omarchy dims the screen behind the picker and shades every slice but the
// selected one. haseen does neither (owner, 2026-11-01, "make the wallpaper
// selector and theme selector like omarchy but without the dimming"): the
// picker opens over the desktop as it is, as the menu does (plan 152).
//
// Each slice holds one `slice` component, loaded only while the slice is on
// screen or about to be (Carousel.PRELOAD). The Loader that holds it carries
// `modelIndex` and `selected`, and sizes the picture to the slice.
Item {
    id: root

    // One name per item: a theme name or an image path. Filtering and the
    // label read it.
    property var names: []
    property int currentIndex: -1
    property bool showLabels: false
    property bool filterable: false
    property string filterText: ""
    // Said in place of the label (an error, an empty list).
    property string notice: ""
    property Component slice: null
    // The screen the picker fits (ShellScreen), else its own size.
    property var screen: null

    signal activated(int index)
    signal dismissed

    readonly property bool mirrored: LayoutMirroring.enabled
    readonly property real areaWidth: screen && screen.width > 0 ? screen.width : width
    readonly property real areaHeight: screen && screen.height > 0 ? screen.height : height
    readonly property real pixelRatio: screen && screen.devicePixelRatio ? screen.devicePixelRatio : 1
    // Omarchy's margin over the carousel and its room under it
    // (ImagePicker.qml:48,398).
    readonly property int topMargin: Theme.space(30)
    readonly property int bottomChrome: Theme.space(showLabels || notice !== "" ? (filterable ? 104 : 74) : (filterable ? 60 : 30))
    readonly property var geometry: Carousel.fit(areaWidth, areaHeight, topMargin + bottomChrome)
    readonly property var shown: Carousel.shown(names, filterable ? filterText : "")
    readonly property int selectedPosition: Math.max(0, shown.indexOf(currentIndex))
    readonly property int reach: Carousel.reach(strip.width, geometry)
    readonly property bool hasSelection: shown.indexOf(currentIndex) >= 0
    readonly property string label: {
        if (notice !== "")
            return notice;
        if (!hasSelection)
            return filterText !== "" ? I18n.tr("No matches") : "";
        return showLabels ? Carousel.labelFor(names[currentIndex]) : "";
    }

    function select(index: int): void {
        if (shown.indexOf(index) >= 0)
            currentIndex = index;
    }

    // +1 is the next item, -1 the previous one, wrapping.
    function move(direction: int): void {
        const next = Carousel.step(shown, currentIndex, direction);
        if (next >= 0)
            currentIndex = next;
    }

    function setFilter(text: string): void {
        filterText = text;
        currentIndex = Carousel.keep(Carousel.shown(names, text), currentIndex);
    }

    implicitWidth: Carousel.cardWidth(geometry, areaWidth)
    implicitHeight: topMargin + geometry.expandedHeight + bottomChrome
    focus: true

    // Left and Right move on screen: in a mirrored (right-to-left) carousel
    // the next item sits on the left.
    Keys.onPressed: event => {
        const k = event.key;
        event.accepted = true;
        if (k === Qt.Key_Escape) {
            if (root.filterText !== "")
                root.setFilter("");
            else
                root.dismissed();
        } else if (k === Qt.Key_Return || k === Qt.Key_Enter) {
            if (root.hasSelection)
                root.activated(root.currentIndex);
        } else if (root.filterable && Carousel.editsFilter(k, event.modifiers, root.filterText)) {
            root.setFilter(Carousel.editedFilter(k, event.modifiers, root.filterText));
        } else if (k === Qt.Key_Backtab || (k === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier))) {
            root.move(-1);
        } else if (k === Qt.Key_Tab) {
            root.move(1);
        } else if (k === Qt.Key_Left) {
            root.move(root.mirrored ? 1 : -1);
        } else if (k === Qt.Key_Right) {
            root.move(root.mirrored ? -1 : 1);
        } else if (root.filterable && Carousel.typed(event.text, event.modifiers)) {
            root.setFilter(root.filterText + event.text);
        } else {
            event.accepted = false;
        }
    }

    // The card around the strip takes clicks, so only a click well away from
    // the picker closes it (ImagePicker.qml:380-392).
    MouseArea {
        anchors.horizontalCenter: parent.horizontalCenter
        width: Carousel.cardWidth(root.geometry, root.width)
        height: parent.height
    }

    Item {
        id: strip

        y: root.topMargin
        width: root.width
        height: root.geometry.expandedHeight

        Repeater {
            model: root.names.length

            delegate: SkewSlice {
                id: item

                required property int index

                readonly property int position: root.shown.indexOf(index)
                readonly property int rel: position - root.selectedPosition
                readonly property bool selected: position >= 0 && index === root.currentIndex
                readonly property var place: Carousel.slot(rel, strip.width, root.mirrored, root.geometry)

                visible: position >= 0 && Math.abs(rel) <= root.reach
                x: place.x
                y: place.y
                z: place.z
                width: place.width
                height: place.height
                skew: root.geometry.skew
                // Omarchy's [image-picker] borders (ImagePicker.qml:528-529).
                borderColor: selected ? Theme.imagePicker.selectedBorder : Theme.imagePicker.unselectedBorder
                borderWidth: selected ? 3 : 1
                onClicked: selected ? root.activated(index) : root.select(index)

                Loader {
                    readonly property int modelIndex: item.index
                    readonly property bool selected: item.selected

                    width: item.width
                    height: item.height
                    active: item.position >= 0 && Math.abs(item.rel) <= root.reach + Carousel.PRELOAD
                    sourceComponent: root.slice
                }
            }
        }
    }

    // The label over whatever is behind the picker: an outline in the
    // theme's background keeps it legible on any wallpaper
    // (ImagePicker.qml:557-558).
    Text {
        id: label

        anchors.top: strip.bottom
        anchors.topMargin: Theme.space(16)
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.geometry.expandedWidth
        visible: text !== ""
        text: root.label
        textFormat: Text.PlainText
        color: Theme.imagePicker.text
        style: Text.Outline
        styleColor: Theme.alpha(Theme.background, 0.7)
        font.family: Theme.fontFamily
        font.pixelSize: Theme.font.display
        font.weight: Font.DemiBold
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
    }

    Text {
        anchors.top: label.bottom
        anchors.topMargin: Theme.space(8)
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.geometry.expandedWidth
        visible: root.filterable && root.filterText !== ""
        text: root.filterText
        textFormat: Text.PlainText
        color: Theme.imagePicker.text
        opacity: 0.85
        style: Text.Outline
        styleColor: Theme.alpha(Theme.background, 0.7)
        font.family: Theme.fontFamily
        font.pixelSize: Theme.font.title
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
    }
}
