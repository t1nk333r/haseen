// Adapted from Omarchy shell/plugins/image-picker/ImagePicker.qml.
// MIT, Copyright (c) David Heinemeier Hansson.
// haseen: no scrim and no shade over unselected slices. The background and
// theme pickers share this widget (plan 152).
import QtQuick
import Quickshell
import qs.Haseen
import "Carousel.js" as Carousel

// Omarchy's image picker as a widget. The selected item sits large in the
// middle of the screen with its label under it, and the other items are
// slanted slices on either side. Left and Right, or Tab and Shift+Tab, move
// the selection. Enter, or a click on the selected item, emits
// activated(index). A click on another slice selects it.
//
// A filterable carousel takes typed text as a filter on the names.
// Backspace, Ctrl+Backspace and Ctrl+U edit the filter. Escape clears the
// filter first, then emits dismissed(). Keys the carousel does not use go to
// its parent.
//
// Omarchy dims the screen behind the picker and shades every slice but the
// selected one. This carousel does neither, at the owner's request
// (2026-11-01), so it opens over the desktop as it is, as the menu does.
//
// Each slice holds one `slice` component, which it loads only while the
// slice is on screen or within Carousel.PRELOAD slices of it. The Loader
// that holds the component has `modelIndex` and `selected`, and sizes it to
// the slice.
Item {
    id: root

    // One name per item, a theme name or an image path. The filter and the
    // label read it.
    property var names: []
    property int currentIndex: -1
    property bool showLabels: false
    property bool filterable: false
    property string filterText: ""
    // Text shown in place of the label, such as an error or an empty list.
    property string notice: ""
    property Component slice: null
    // The ShellScreen the carousel fits. Without one it takes its full
    // design size, because fitting its own size would make the size depend
    // on itself.
    property var screen: null
    // A narrower carousel for a panel card, in the `center` and `bar`
    // placements. It shows the selected item and up to
    // Carousel.COMPACT_STEPS slices on each side.
    property bool compact: false

    signal activated(int index)
    signal dismissed

    readonly property bool mirrored: LayoutMirroring.enabled
    readonly property real screenWidth: screen && screen.width > 0 ? screen.width : Carousel.designWidth()
    readonly property real areaWidth: compact ? Math.min(screenWidth, Carousel.compactWidth()) : screenWidth
    readonly property real areaHeight: screen && screen.height > 0 ? screen.height : topMargin + Carousel.GEOMETRY.expandedHeight + bottomChrome
    // Device pixels per logical pixel in the carousel's window, the size
    // every picture decodes at. A ShellScreen reports the output's scale
    // rounded up to a whole number, 2 on IO's 1.25 screen, which decodes
    // 2.56 times the pixels the window shows (plan 158). So the window's own
    // ratio comes first.
    readonly property real pixelRatio: QsWindow.window && QsWindow.window.devicePixelRatio > 0 ? QsWindow.window.devicePixelRatio : (screen && screen.devicePixelRatio ? screen.devicePixelRatio : 1)
    // Omarchy's margin above the carousel and its room for the label and
    // filter below it (ImagePicker.qml:48,398).
    readonly property int topMargin: Theme.space(30)
    readonly property int bottomChrome: Theme.space(showLabels || notice !== "" ? (filterable ? 104 : 74) : (filterable ? 60 : 30))
    readonly property var geometry: Carousel.fit(areaWidth, areaHeight, topMargin + bottomChrome)
    readonly property var shown: Carousel.shown(names, filterable ? filterText : "")
    readonly property int selectedPosition: Math.max(0, shown.indexOf(currentIndex))
    // A compact card shows up to COMPACT_STEPS slices on each side, and only
    // those that fit inside it. On a narrow screen another slice would reach
    // past the card into its padding.
    readonly property int reach: compact ? Carousel.fitReach(strip.width, geometry, Carousel.COMPACT_STEPS) : Carousel.reach(strip.width, geometry)
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

    // A direction of +1 moves to the next item and -1 to the previous one.
    // The selection wraps at both ends.
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

    // Left and Right follow the screen. In a right-to-left carousel the next
    // item sits on the left, so Left moves forward.
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
    // the picker closes it (ImagePicker.qml:380-393).
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

    // The label sits over whatever is behind the picker. An outline in the
    // theme's background colour keeps it readable on any wallpaper
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
