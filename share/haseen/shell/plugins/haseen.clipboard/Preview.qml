import QtQuick
import Quickshell.Io
import qs.Haseen
import "Cliphist.js" as Cliphist

// The selected clipboard entry in full: an image as an image, text wrapped
// and scrollable, with the entry's type and size above it. Panel.qml keeps
// this component inside a Loader bound to `settings.preview`, so a preview
// that is off costs an inactive Loader and decodes nothing.
//
// Resource rules (architecture 6):
//   - no timer; a decode starts when the selected entry changes;
//   - `cliphist list` already carries an image's size and pixel size, so an
//     entry over `maxBytes` or `maxPixels` is described from the list line
//     and never read (Qt decodes a PNG in full before scaling it, so an
//     unbounded screenshot would cost hundreds of MiB of pixmap);
//   - text is read through `head -c`, so the pane holds at most `textCap`;
//   - the Image is loaded with sourceSize set to the pane, so the retained
//     pixmap is the pane, not the file.
Item {
    id: root

    // A Cliphist.parse row, or null.
    property var entry: null
    // Where decoded images land; Panel.qml owns and removes this directory.
    property string thumbDir: ""
    property int maxBytes: 8388608
    property int maxPixels: 12000000

    // Text is laid out by a Text item, which costs far more than the bytes,
    // so the decoded body is capped well below the image limit.
    readonly property int textCap: Math.max(1024, Math.min(maxBytes, 65536))
    readonly property string entryId: entry ? entry.id : ""
    readonly property bool isImage: entry !== null && entry.image === true
    readonly property string refused: Cliphist.tooLarge(entry, maxBytes, maxPixels)
    readonly property string imagePath: isImage && refused === "" && thumbDir !== "" ? thumbDir + "/" + entry.id + "." + entry.ext : ""

    // Decoded state for the current entry.
    property string body: ""
    property int bytes: -1
    property bool truncated: false
    property bool imageReady: false
    property string failure: ""

    readonly property int lines: body === "" ? 0 : body.split("\n").length
    readonly property string meta: {
        if (!entry)
            return "";
        const base = Cliphist.summary(entry, isImage ? entry.bytes : bytes, lines);
        return truncated ? base + " \u00b7 first " + Cliphist.humanSize(textCap) : base;
    }
    readonly property string notice: refused !== "" ? entry.type + ", " + refused : failure

    // Panel.qml maps PageUp/PageDown here: +1 scrolls a pane down, -1 up.
    function scroll(direction: int): void {
        const limit = flick.contentHeight - flick.height;
        if (limit <= 0)
            return;
        flick.contentY = Math.max(0, Math.min(limit, flick.contentY + direction * flick.height * 0.8));
    }

    // The selection drives this: creation and every later change. Stopping a
    // Process reports an exit like any other, so each run carries the serial
    // it was started with and a superseded run is ignored.
    property string _current: ""
    property int _run: 0

    function reload(): void {
        if (_run > 0 && _current === entryId)
            return;
        _current = entryId;
        _run++;
        textDecoder.running = false;
        imageDecoder.running = false;
        body = "";
        bytes = -1;
        truncated = false;
        imageReady = false;
        failure = "";
        flick.contentY = 0;
        if (!entry || refused !== "")
            return;
        if (isImage) {
            imageDecoder.run = _run;
            imageDecoder.command = ["sh", "-c", imageDecoder.script, "sh", entry.id, imagePath];
            imageDecoder.running = true;
            return;
        }
        textDecoder.run = _run;
        textDecoder.command = ["sh", "-c", textDecoder.script, "sh", entry.id, String(textCap)];
        textDecoder.running = true;
    }

    onEntryIdChanged: reload()
    Component.onCompleted: reload()
    Component.onDestruction: {
        textDecoder.running = false;
        imageDecoder.running = false;
    }

    // The size first, then the capped body: the count streams through wc, so
    // neither pass holds the entry. The id goes in argv, never in the script.
    Process {
        id: textDecoder

        property int run: 0
        readonly property string script: "command -v cliphist >/dev/null || exit 127\n" + "cliphist decode \"$1\" | wc -c | tr -d ' \\n'\n" + "printf '\\n'\n" + "cliphist decode \"$1\" 2>/dev/null | head -c \"$2\"\n"

        stdout: StdioCollector {
            id: decoded
        }
        onExited: code => {
            if (textDecoder.run !== root._run)
                return;
            if (code === 127) {
                root.failure = "cliphist is not installed.";
                return;
            }
            if (code !== 0) {
                root.failure = "cliphist decode failed (exit " + code + ").";
                return;
            }
            const text = decoded.text;
            const nl = text.indexOf("\n");
            const size = nl < 0 ? NaN : parseInt(text.slice(0, nl), 10);
            root.bytes = isNaN(size) ? -1 : size;
            root.body = nl < 0 ? "" : text.slice(nl + 1);
            root.truncated = root.bytes > root.textCap;
        }
    }

    // Written through a temporary file so the row thumbnail and the pane can
    // ask for the same entry at once without reading a half-written image.
    Process {
        id: imageDecoder

        property int run: 0
        readonly property string script: "command -v cliphist >/dev/null || exit 127\n" + "mkdir -p \"${2%/*}\"\n" + "[ -s \"$2\" ] || { cliphist decode \"$1\" > \"$2.part.$$\" && mv -f \"$2.part.$$\" \"$2\"; }\n"

        onExited: code => {
            if (imageDecoder.run !== root._run)
                return;
            root.imageReady = code === 0;
            if (code === 127)
                root.failure = "cliphist is not installed.";
            else if (code !== 0)
                root.failure = "cliphist decode failed (exit " + code + ").";
        }
    }

    Column {
        id: stack

        anchors.fill: parent
        spacing: Math.round(Theme.gap / 2)

        Text {
            id: metaLine

            width: parent.width
            text: root.meta
            color: Theme.muted
            elide: Text.ElideRight
            maximumLineCount: 1
            textFormat: Text.PlainText
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 1
        }

        Item {
            id: pane

            width: parent.width
            height: Math.max(0, parent.height - metaLine.height - stack.spacing)

            Rectangle {
                anchors.fill: parent
                radius: Theme.radius
                color: Theme.surfaceAlt
                border.color: Theme.border
                border.width: Theme.borderWidth
            }

            Flickable {
                id: flick

                anchors.fill: parent
                anchors.margins: Theme.gap
                visible: !root.isImage && root.notice === ""
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                contentWidth: width
                contentHeight: content.implicitHeight

                Text {
                    id: content

                    width: flick.width
                    text: root.body
                    color: Theme.foreground
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.fontSize
                }
            }

            // Shown only while the body is longer than the pane.
            Rectangle {
                id: scrollbar

                readonly property real ratio: flick.contentHeight > 0 ? Math.min(1, flick.height / flick.contentHeight) : 1

                anchors.right: parent.right
                anchors.rightMargin: Math.round(Theme.gap / 2)
                width: Math.max(2, Math.round(Theme.borderWidth * 2))
                radius: width / 2
                color: Theme.muted
                visible: flick.visible && ratio < 1
                height: Math.max(width * 2, flick.height * ratio)
                y: flick.y + (flick.height - height) * (flick.contentHeight > flick.height ? flick.contentY / (flick.contentHeight - flick.height) : 0)
            }

            Image {
                anchors.fill: parent
                anchors.margins: Theme.gap
                visible: root.isImage && root.notice === ""
                source: root.imageReady ? Paths.fileUrl(root.imagePath) : ""
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                cache: false
                // The decoded pixmap is bounded by the pane, not by the file.
                sourceSize.width: Math.max(1, Math.round(pane.width))
                sourceSize.height: Math.max(1, Math.round(pane.height))
            }

            Text {
                anchors.fill: parent
                anchors.margins: Theme.gap
                visible: root.notice !== ""
                text: root.notice
                color: Theme.muted
                wrapMode: Text.WordWrap
                textFormat: Text.PlainText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
            }
        }
    }
}
