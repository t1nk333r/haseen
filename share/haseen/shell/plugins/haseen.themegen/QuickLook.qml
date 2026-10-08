import QtQuick
import qs.Haseen

// Large in-panel preview of the current local file or cached Wallhaven thumb.
Item {
    id: root

    property string imagePath: ""
    readonly property string imageSource: picture.source
    property real pixelRatio: 1

    Rectangle {
        anchors.fill: parent
        color: Theme.surface
        radius: Theme.radius
        border.color: Theme.border
        border.width: Theme.borderWidth

        Column {
            anchors.fill: parent
            anchors.margins: Theme.gap * 2
            spacing: Theme.gap

            Item {
                width: parent.width
                height: Math.max(1, parent.height - footer.implicitHeight - parent.spacing)

                Image {
                    id: picture

                    anchors.fill: parent
                    source: root.imagePath !== "" ? Paths.fileUrl(root.imagePath) : ""
                    sourceSize.width: Math.max(1, Math.round(width * root.pixelRatio))
                    sourceSize.height: Math.max(1, Math.round(height * root.pixelRatio))
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    cache: false
                    visible: status === Image.Ready
                }

                Text {
                    anchors.centerIn: parent
                    text: root.imagePath === "" ? "Preview unavailable" : picture.status === Image.Error ? "Preview unavailable" : "Loading preview…"
                    color: Theme.subtle(Theme.surface)
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    visible: picture.status !== Image.Ready
                }
            }

            Text {
                id: footer

                width: parent.width
                text: "Space or Esc closes · h/j/k/l or arrows browse · Enter picks"
                color: Theme.subtle(Theme.surface)
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 1
            }
        }
    }
}
