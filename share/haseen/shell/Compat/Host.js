.pragma library

// Shared by Compat/OmarchyHost.qml and Compat/DmsHost.qml (architecture 5.4).
// .pragma library: one copy per engine, so `live` sees every screen's bar.

// pluginId -> [plugin items], for Omarchy's broadcast()/moduleWidgets().
var live = {};

function register(id, item) {
    live[id] = (live[id] || []).concat([item]);
}

function unregister(id, item) {
    live[id] = (live[id] || []).filter(function (i) {
        return i !== item;
    });
}

function instances(id) {
    return (live[id] || []).slice();
}

// First line of a component error, with the plugin directory stripped:
// "Panel.qml:40:5: PanelHero is not a type".
function firstError(text, url) {
    var dir = String(url).replace(/[^/]*$/, "");
    var lines = String(text || "").split("\n").filter(function (l) {
        return l.trim() !== "";
    });
    var line = lines.length > 0 ? lines[0].trim() : "unknown error";
    return line.split(dir).join("");
}

// Creates the plugin entry under parent. done({ item, error }) runs once;
// a component that fails to compile (an unsupported import or type) yields
// an error and no item, so only this plugin is lost.
function load(url, parent, done) {
    var component = Qt.createComponent(url);
    function finish() {
        if (component.status === 3) {
            done({
                item: null,
                error: firstError(component.errorString(), url)
            });
            return;
        }
        var item = component.createObject(parent);
        if (item === null) {
            done({
                item: null,
                error: "could not create " + url.replace(/^.*\//, "") + ": " + firstError(component.errorString(), url)
            });
            return;
        }
        done({
            item: item,
            error: ""
        });
    }
    if (component.status === 2) {
        component.statusChanged.connect(function () {
            if (component.status !== 2)
                finish();
        });
        return;
    }
    finish();
}
