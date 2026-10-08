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
//   - text is decoded once and read through `head -c`, so the pane holds at
//     most `textCap`; the rest is only counted;
//   - binary data (cliphist's "binary data" that is not an image Qt reads
//     here, such as a TIFF, or a decoded body holding a NUL byte) is
//     described by its type and size, never shown as text;
//   - an image is decoded only into the private cache (Cliphist.imageCommand);
//     with no XDG_RUNTIME_DIR there is none, and the pane says so;
//   - the Image is loaded with sourceSize set to the pane, so the retained
//     pixmap is the pane, not the file.
Item {
    id: root

    // A Cliphist.parse row, or null.
    property var entry: null
    // Where decoded images land, "" for none; Panel.qml owns and removes it.
    property string thumbDir: ""
    property int maxBytes: 8388608
    property int maxPixels: 12000000

    // Text is laid out by a Text item, which costs far more than the bytes,
    // so the decoded body is capped well below the image limit.
    readonly property int textCap: Math.max(1024, Math.min(maxBytes, 65536))
    readonly property string entryId: entry ? entry.id : ""
    readonly property bool isImage: entry !== null && entry.image === true
    readonly property bool isBinary: entry !== null && entry.binary === true && !isImage
    readonly property string refused: Cliphist.tooLarge(entry, maxBytes, maxPixels)
    readonly property string imagePath: isImage && refused === "" && thumbDir !== "" ? thumbDir + "/" + entry.id + "." + entry.ext : ""

    // Decoded state for the current entry.
    property string body: ""
    property int bytes: -1
    property bool truncated: false
    property bool imageReady: false
    property string failure: ""
    // Set when the decoded body turns out to be binary (a NUL byte).
    property bool binaryBody: false

    readonly property int lines: body === "" ? 0 : body.split("\n").length
    readonly property string meta: {
        if (!entry)
            return "";
        const base = Cliphist.summary(entry, isImage ? entry.bytes : bytes, lines);
        return truncated ? base + " \u00b7 first " + Cliphist.humanSize(textCap) : base;
    }
    readonly property string notice: {
        if (refused !== "")
            return entry.type + ", " + refused;
        if (isBinary || binaryBody)
            return "Binary data, not shown as text.";
        if (isImage && thumbDir === "")
            return "Images are not decoded: XDG_RUNTIME_DIR is not set, and there is no other private place to put them.";
        return failure;
    }

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
        binaryBody = false;
        flick.contentY = 0;
        if (!entry || refused !== "" || isBinary)
            return;
        if (isImage) {
            if (imagePath === "")
                return;
            imageDecoder.run = _run;
            imageDecoder.command = Cliphist.imageCommand(entry.id, imagePath);
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

    // One decode: the body goes to stdout through `head -c`, and the byte
    // count of the body and of the rest go to stderr, so no pass holds the
    // entry. The id goes in argv, never in the script.
    Process {
        id: textDecoder

        property int run: 0
        readonly property string script: "command -v cliphist >/dev/null || exit 127\n" + "cliphist decode \"$1\" 2>/dev/null | { head -c \"$2\" | tee /dev/fd/3 | wc -c >&2; wc -c >&2; } 3>&1\n"

        stdout: StdioCollector {
            id: decoded
        }
        stderr: StdioCollector {
            id: counted
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
            const counts = counted.text.trim().split(/\s+/).map(n => parseInt(n, 10));
            const valid = counts.length === 2 && !isNaN(counts[0]) && !isNaN(counts[1]);
            root.bytes = valid ? counts[0] + counts[1] : -1;
            root.truncated = valid && counts[1] > 0;
            const text = decoded.text;
            root.binaryBody = text.indexOf("\u0000") >= 0;
            root.body = root.binaryBody ? "" : text;
        }
    }

    // The same decode as the row thumbnail, into the same private cache.
    Process {
        id: imageDecoder

        property int run: 0

        onExited: code => {
            if (imageDecoder.run !== root._run)
                return;
            root.imageReady = code === 0;
            if (code === 127)
                root.failure = "cliphist is not installed.";
            else if (code === 3)
                root.failure = "Images are not decoded: the image cache (or XDG_RUNTIME_DIR) is not a private directory of yours.";
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
