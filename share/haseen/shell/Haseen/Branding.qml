pragma Singleton

import QtQuick
import Quickshell

// haseen's mark (plan 059): `branding.mark` in shell.json, one of kufic,
// shield or gate; anything else is kufic, the same rule as
// share/haseen/lib/branding.sh. The files are SVGs filled with currentColor
// (Widgets/BrandImage colours them) and a terminal logo per mark.
Singleton {
    id: root

    readonly property var marks: ["kufic", "shield", "gate"]
    readonly property string fallback: "kufic"
    readonly property var configured: Config._object(Config.merged.branding).mark
    readonly property string mark: marks.indexOf(configured) >= 0 ? configured : fallback
    readonly property string dir: Paths.haseenPath + "/branding"

    readonly property var paths: pathsFor(mark)
    readonly property string markPath: paths.mark
    readonly property string symbolicPath: paths.symbolic
    readonly property string symbolic24Path: paths.symbolic24
    readonly property string wordmarkPath: paths.wordmark
    readonly property string logoPath: paths.logo

    // The files of NAME, or of the fallback when NAME is not a mark.
    function pathsFor(name: string): var {
        const m = marks.indexOf(name) >= 0 ? name : fallback;
        const base = dir + "/" + m + "/";
        return {
            mark: base + "mark.svg",
            symbolic: base + "symbolic.svg",
            symbolic24: base + "symbolic-24.svg",
            wordmark: base + "wordmark.svg",
            logo: dir + "/logo-" + m + ".txt"
        };
    }
}
