.pragma library

// The haseen shell renders with Qt's software scene graph (shell.qml sets
// QT_QUICK_BACKEND=software; architecture 6: no shaders). A layer effect such
// as `layer.effect: MultiEffect { shadowEnabled: true }` is a shader there and
// draws nothing, so the layered item and everything inside it vanish. DMS
// plugins put backgrounds and whole popovers in such layers for a drop
// shadow; the DMS hosts turn those layers off once the plugin is built, which
// shows the content without the shadow. Items a plugin creates later are not
// visited.

// dropEffects(root) — walk root's object tree (children and resources, window
// contents, Variants instances, Loader items) and disable every layer that
// carries an effect. Returns how many layers were turned off.
function dropEffects(root) {
    var seen = new Set(), stack = [root], dropped = 0;
    while (stack.length > 0) {
        var o = stack.pop();
        if (!o || typeof o !== "object" || seen.has(o))
            continue;
        seen.add(o);
        if (o.layer && o.layer.enabled && o.layer.effect) {
            o.layer.enabled = false;
            dropped++;
        }
        var lists = [o.data, o.instances];
        for (var l = 0; l < lists.length; l++) {
            var list = lists[l];
            if (list && typeof list.length === "number")
                for (var i = 0; i < list.length; i++)
                    stack.push(list[i]);
        }
        if (o.contentItem)
            stack.push(o.contentItem);
        if (o.item)
            stack.push(o.item);
    }
    return dropped;
}
