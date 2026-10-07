import QtQuick
import Quickshell
import Quickshell.Io
import qs.Haseen
import qs.Haseen.Widgets

// The About view of haseen.menu: facts from `haseen about --facts` (OS,
// kernel, CPU, GPU, memory, uptime, haseen version) under the user's
// branding: ~/.config/haseen/branding/about.png if present, else about.txt,
// else the wordmark of the selected mark (Branding, plan 059). Facts are read
// once per refresh(), never polled.
Column {
    id: root

    required property string binDir
    readonly property string brandingDir: Paths.userConfig + "/branding"
    property var facts: []
    property bool hasImage: false
    property string brandText: ""

    function refresh(): void {
        factsProc.running = false;
        factsProc.running = true;
        imageCheck.reload();
        textFile.reload();
    }

    spacing: Theme.gap

    Process {
        id: factsProc

        command: ["bash", "-c", "PATH=\"$1:$PATH\"; haseen about --facts", "bash", root.binDir]
        stdout: StdioCollector {
            onStreamFinished: root.facts = text.split("\n").filter(l => l.indexOf("\t") > 0).map(l => {
                    const i = l.indexOf("\t");
                    return {
                        key: l.slice(0, i),
                        value: l.slice(i + 1)
                    };
                })
        }
    }

    // Existence check only; the Image below loads the file itself.
    FileView {
        id: imageCheck

        path: root.brandingDir + "/about.png"
        printErrors: false
        blockLoading: false
        onLoaded: root.hasImage = true
        onLoadFailed: root.hasImage = false
    }

    FileView {
        id: textFile

        path: root.brandingDir + "/about.txt"
        printErrors: false
        onLoaded: root.brandText = text().replace(/\s+$/, "")
        onLoadFailed: root.brandText = ""
    }

    Image {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: root.hasImage
        source: root.hasImage ? Paths.fileUrl(root.brandingDir + "/about.png") : ""
        cache: false
        fillMode: Image.PreserveAspectFit
        sourceSize.width: root.width
        sourceSize.height: Theme.fontSize * 12
    }

    BrandImage {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: !root.hasImage && root.brandText === ""
        height: Theme.fontSize * 4
        width: Math.min(implicitWidth, root.width)
        path: Branding.wordmarkPath
        color: Theme.accent
    }

    Text {
        width: parent.width
        visible: !root.hasImage && root.brandText !== ""
        text: root.brandText
        color: Theme.accent
        horizontalAlignment: Text.AlignHCenter
        textFormat: Text.PlainText
        wrapMode: Text.NoWrap
        font.family: Theme.fontMono
        font.pixelSize: root.brandText.indexOf("\n") >= 0 ? Theme.fontSize - 2 : Theme.fontSize * 2
        font.bold: true
    }

    Grid {
        anchors.horizontalCenter: parent.horizontalCenter
        columns: 2
        columnSpacing: Theme.gap * 2
        rowSpacing: Theme.gap / 2

        Repeater {
            model: root.facts.length * 2

            Text {
                required property int index

                readonly property var fact: root.facts[Math.floor(index / 2)]

                text: index % 2 === 0 ? fact.key : fact.value
                color: index % 2 === 0 ? Theme.accent : Theme.foreground
                width: index % 2 === 0 ? implicitWidth : Math.min(implicitWidth, root.width * 0.7)
                elide: Text.ElideRight
                textFormat: Text.PlainText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
            }
        }
    }
}
