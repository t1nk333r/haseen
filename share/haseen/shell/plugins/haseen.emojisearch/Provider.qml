import QtQuick
import Quickshell
import Quickshell.Io
import qs.Haseen
import "Emoji.js" as Emoji
import "../haseen.emoji/EmojiSearch.js" as EmojiSearch

// Launcher provider (plan 081): `:text` searches emoji with haseen.emoji's
// list (whether or not that panel is enabled); Enter copies the emoji with
// wl-copy. Never typed into a window: no key injection (plan 018). The
// 100 KiB list is read when the launcher opens and freed with it.
Scope {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    readonly property string prefix: ":"
    property var emojis: []
    // haseen.emoji's directory: a user copy when one overrides it.
    readonly property string dataDir: {
        const rec = Plugins.registry["haseen.emoji"];
        return rec && rec.dir ? rec.dir : Paths.builtinPlugins + "/haseen.emoji";
    }

    function copy(emoji: string): void {
        Quickshell.execDetached(Emoji.copyArgv(emoji));
    }

    function query(text: string): var {
        if (emojis.length === 0)
            return [
                {
                    title: "Loading emoji…",
                    subtitle: "",
                    icon: "face-smile",
                    exec: () => {}
                }
            ];
        const rows = Emoji.rank(emojis, text, 50).map(item => ({
                    title: item.e + "   " + item.k,
                    subtitle: "Emoji  ·  Enter copies",
                    icon: "",
                    exec: () => root.copy(item.e)
                }));
        if (rows.length === 0)
            return [
                {
                    title: "No matching emoji",
                    subtitle: "Emoji: type a word like heart, smile, cat",
                    icon: "face-smile",
                    exec: () => {}
                }
            ];
        return rows;
    }

    FileView {
        path: root.dataDir + "/emojis.json"
        onLoaded: root.emojis = EmojiSearch.parseEmojis(text())
    }
}
