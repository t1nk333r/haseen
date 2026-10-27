import QtQuick
import qs.Haseen

// One size and one font for every plugin's bar widget (plan 141). haseen's
// bar draws a label at Theme.font.body and an icon at the bar's icon size
// (Theme.barMetrics.iconFont, Omarchy's Style.bar.iconFont), in the bar
// font. A third-party bar widget asks for its own: caption, bodySmall, a
// family of its choosing. This walks the widget's visual children, which are
// what the bar shows (its popouts are windows of their own, outside the
// walk), and binds their text to the bar's, so the owner's plugins match
// without their files changing:
//  - a qs.Ui WidgetButton with a bar adopts it through adoptBarFont(), which
//    rebinds the button's fontSize, so a plugin that measures its label at
//    button.fontSize measures what is drawn;
//  - a Text inside a component that owns a fontSize (the label of a
//    WidgetButton without a bar, qs.Ui's OpticalGlyph) follows that
//    fontSize, which the plugin usually binds to its button's: a plugin
//    that squeezes a long line to 0.9 of it keeps doing so;
//  - any other Text takes the icon size when it shows icons only and the
//    text size otherwise. Its family becomes the bar's, except for icons
//    and for scripts the bar font may lack (Arabic, CJK), which keep the
//    family the plugin gave them.
// Children that appear later (a Loader's item, a Repeater's delegates) are
// walked when childrenChanged reports them, never on a timer.
QtObject {
    id: root

    // The plugin's bar widget; null for any other kind of entry.
    property Item target: null
    property string family: Theme.fontMono
    readonly property int textSize: Theme.font.body
    readonly property int iconSize: Theme.barMetrics.iconFont
    // The items adopted, as of the last walk. Each walk builds a new set, so
    // an item that is gone (a Repeater's old delegate) is not kept.
    property var _seen: new Set()

    // Nerd Font icons: the BMP private-use area and, as surrogate pairs, the
    // supplementary one (the nf-md set).
    function iconOnly(text: string): bool {
        return /^(?:[\ue000-\uf8ff\s]|[\udb80-\udbff][\udc00-\udfff])+$/.test(text);
    }

    // Hebrew to Mongolian and the rest of the BMP's non-Latin scripts the bar
    // font may lack (CJK, Hangul, Arabic presentation forms), and CJK's
    // supplementary planes (U+20000 to U+2FFFF) as surrogate pairs.
    function otherScript(text: string): bool {
        return /[\u0590-\u1cff\u2e80-\ua4cf\uac00-\ud7af\uf900-\ufaff\ufb1d-\ufdff\ufe70-\ufeff]|[\ud840-\ud87f][\udc00-\udfff]/.test(text);
    }

    function sizeFor(text: string): int {
        return iconOnly(text) ? iconSize : textSize;
    }

    function familyFor(text: string, own: string): string {
        return iconOnly(text) || otherScript(text) ? own : family;
    }

    function bind(text: Text) {
        const own = text.font.family;
        text.font.pixelSize = Qt.binding(() => root.sizeFor(text.text));
        text.font.family = Qt.binding(() => root.familyFor(text.text, own));
    }

    // The whole tree each time: a new child can sit under an item already
    // seen. What was adopted is not adopted again while it stays in the tree.
    function adopt(item: Item, seen: var) {
        if (!item || seen.has(item))
            return;
        seen.add(item);
        if (!_seen.has(item)) {
            if (typeof item.adoptBarFont === "function") {
                if (item.bar)
                    item.adoptBarFont(root);
            } else if (item instanceof Text && !(item.parent && item.parent.fontSize !== undefined)) {
                bind(item);
            }
            item.childrenChanged.connect(root.schedule);
        }
        for (const child of item.children)
            adopt(child, seen);
    }

    function scan() {
        const seen = new Set();
        if (target)
            adopt(target, seen);
        _seen = seen;
    }

    function schedule() {
        Qt.callLater(root.scan);
    }

    onTargetChanged: {
        _seen = new Set();
        scan();
    }
    // A target given at creation does not report a change.
    Component.onCompleted: scan()
}
