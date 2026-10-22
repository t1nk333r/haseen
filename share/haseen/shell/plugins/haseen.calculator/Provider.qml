import QtQuick
import Quickshell
import qs.Haseen
import "Calc.js" as Calc

// Launcher provider: input that starts with `=` is a calculation. The result
// is the single row; Enter copies it to the clipboard. Nothing runs while the
// expression is incomplete: an error shows as the row's subtitle.
Scope {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    readonly property string prefix: "="

    function query(text: string): var {
        if (text.trim() === "")
            return [
                {
                    title: I18n.tr("Calculator"),
                    subtitle: I18n.tr("Type an expression: 12*(3+4), sqrt(2), 200 + 10%, 2^10"),
                    icon: "accessories-calculator",
                    glyph: "\u{F00EC}",
                    exec: () => {}
                }
            ];
        const r = Calc.evaluate(text);
        if (!r.ok)
            return [
                {
                    title: text.trim(),
                    subtitle: I18n.tr(r.message, ...r.args),
                    icon: "accessories-calculator",
                    glyph: "\u{F00EC}",
                    exec: () => {}
                }
            ];
        const shown = Calc.format(r.value);
        return [
            {
                title: shown,
                subtitle: I18n.tr("%1  ·  Enter copies", text.trim()),
                icon: "accessories-calculator",
                glyph: "\u{F00EC}",
                exec: () => Quickshell.execDetached(["wl-copy", "--", shown])
            }
        ];
    }
}
