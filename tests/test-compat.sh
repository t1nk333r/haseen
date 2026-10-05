# shellcheck shell=bash
# Plugin compat (plan 011): Omarchy manifest.json and DMS plugin.json
# adaptation in the CLI (shell/lib/plugin.sh, jq) and in the shell
# (shell/Compat/Manifest.js, run headless through Qt's qml tool when it is
# installed), refusal of malformed manifests, the read-only compat search
# dirs, and the qs.* module names the adapters provide.

SHELL_DIR="$HASEEN_PATH/shell"
QML_BIN=${QML_BIN:-/usr/lib/qt6/bin/qml}

# put DIR FILE JSON [ENTRY...] — a plugin directory with one manifest file.
put() {
    local dir="$1" file="$2" json="$3" f
    shift 3
    mkdir -p "$dir"
    printf '%s\n' "$json" >"$dir/$file"
    for f in "$@"; do : >"$dir/$f"; done
}


# --- fixtures ----------------------------------------------------------------
sandbox compat-cli
P="$XDG_CONFIG_HOME/haseen/plugins"
O="$XDG_CONFIG_HOME/omarchy/plugins"
D="$XDG_CONFIG_HOME/DankMaterialShell/plugins"
mkdir -p "$P"

OMARCHY_OK='{"schemaVersion":1,"id":"me.traffic","name":"Traffic","version":"1.0.0","description":"rates",
 "kinds":["bar-widget","service"],"entryPoints":{"barWidget":"BarWidget.qml","service":"Service.qml"},
 "barWidget":{"defaults":{"interval":3,"compact":false,"extra":"x"},
  "schema":[{"key":"interval","type":"integer","label":"Interval","defaultValue":5},
            {"key":"compact","type":"boolean","description":"Compact","defaultValue":true},
            {"key":"mode","type":"select","defaultValue":"auto"}]}}'
put "$O/me.traffic" manifest.json "$OMARCHY_OK" BarWidget.qml Service.qml
put "$O/me.nokinds" manifest.json '{"schemaVersion":1,"id":"me.nokinds","name":"x","version":"1.0.0","entryPoints":{"barWidget":"B.qml"}}' B.qml
put "$O/me.svconly" manifest.json '{"schemaVersion":1,"id":"me.svconly","name":"x","version":"1.0.0","kinds":["service"],"entryPoints":{"service":"S.qml"}}' S.qml
put "$O/omaconnect" manifest.json '{"schemaVersion":1,"id":"omaconnect","name":"Connect","version":"1.0.0","kinds":["bar-widget","service"],"entryPoints":{"barWidget":"Widget.qml","service":"Service.qml"}}' Widget.qml Service.qml
put "$O/me.panelonly" manifest.json '{"schemaVersion":1,"id":"me.panelonly","name":"Panel","version":"1.0.0","kinds":["panel"],"entryPoints":{"panel":"Panel.qml"}}' Panel.qml
put "$O/me.baronly" manifest.json '{"schemaVersion":1,"id":"me.baronly","name":"Bar","version":"1.0.0","kinds":["bar"],"entryPoints":{"bar":"Bar.qml"}}' Bar.qml
put "$O/me.flat" manifest.json '{"schemaVersion":1,"id":"me.flat","name":"Flat","version":"1.0.0","kinds":["service"],"entryPoints":{"service":"Service.qml"},"settings":{"showBattery":{"type":"boolean","default":false},"mode":{"type":"string","default":"flat"}},"barWidget":{"defaults":{"mode":"bar"}}}' Service.qml
put "$O/me.nested" manifest.json '{"schemaVersion":1,"id":"me.nested","name":"Nested","version":"1.0.0","kinds":["service"],"entryPoints":{"service":"Service.qml"},"settings":{"defaults":{"scale":75,"enabled":false},"schema":[{"key":"scale","type":"integer","defaultValue":100}]}}' Service.qml
put "$O/me.escape" manifest.json '{"schemaVersion":1,"id":"me.escape","name":"x","version":"1.0.0","kinds":["bar-widget"],"entryPoints":{"barWidget":"../me.traffic/BarWidget.qml"}}'
put "$O/me.dirname" manifest.json '{"schemaVersion":1,"id":"me.other","name":"x","version":"1.0.0","kinds":["bar-widget"],"entryPoints":{"barWidget":"B.qml"}}' B.qml
put "$O/me.noentry" manifest.json '{"schemaVersion":1,"id":"me.noentry","name":"x","version":"1.0.0","kinds":["bar-widget"],"entryPoints":{"barWidget":"Missing.qml"}}'
put "$O/me.noname" manifest.json '{"schemaVersion":1,"id":"me.noname","version":"1.0.0","kinds":["bar-widget"],"entryPoints":{"barWidget":"B.qml"}}' B.qml

DMS_OK='{"id":"exampleStartupCheck","name":"Startup","description":"d","version":"1.0.0","author":"a","type":"widget",
 "capabilities":["dankbar-widget"],"component":"./Widget.qml","permissions":["process","settings_read","process"]}'
DMS_COMPOSITE='{"id":"composite2Demo","name":"Composite","version":"2.0.0","type":"composite",
 "components":{"daemon":"./D.qml","widget":"./W.qml","desktop":"./Desk.qml","dash":""},"permissions":"network, settings_write"}'
put "$D/StartupCheck" plugin.json "$DMS_OK" Widget.qml
put "$D/Composite" plugin.json "$DMS_COMPOSITE" W.qml D.qml Desk.qml
put "$D/Launcher" plugin.json '{"id":"launcherOnly","name":"L","version":"1.0.0","type":"launcher","component":"./L.qml"}' L.qml
put "$D/BadId" plugin.json '{"id":"bad-id","name":"B","version":"1.0.0","component":"./W.qml"}' W.qml
put "$D/NoName" plugin.json '{"id":"noName","version":"1.0.0","component":"./W.qml"}' W.qml
put "$D/Broken" plugin.json '{"id":' W.qml
put "$D/Daemon" plugin.json '{"id":"justDaemon","name":"D","version":"1.0.0","type":"daemon","component":"./D.qml"}' D.qml
# A DMS plugin copied into the haseen user dir is found there too.
put "$P/Counter" plugin.json '{"id":"dashCounterExample","name":"Counter","version":"1.0.0","type":"composite","components":{"dash":"./T.qml","widget":"./CounterWidget.qml"}}' CounterWidget.qml T.qml
# A native plugin in the user dir stays native.
put "$P/me.native" manifest.json '{"schemaVersion":1,"id":"me.native","name":"N","version":"1.0.0","kinds":["bar-widget"],"entry":{"bar-widget":"W.qml"}}' W.qml

adapt() { bash -c 'source "$HASEEN_PATH/shell/lib/plugin.sh"; plugin_adapt "$1"' _ "$1"; }

# --- CLI adapter: Omarchy ----------------------------------------------------
out="$(adapt "$O/me.traffic")"
assert_eq "omarchy: compat tag" omarchy "$(jq -r .compat <<<"$out")"
assert_eq "omarchy: id is the directory" me.traffic "$(jq -r .id <<<"$out")"
assert_eq "omarchy: widget and its companion service are adapted" '["bar-widget","service"]' "$(jq -c .manifest.kinds <<<"$out")"
assert_eq "omarchy: supported kinds leave no unsupported entry" '[]' "$(jq -c .unsupported <<<"$out")"
assert_eq "omarchy: both entry points are retained" '{"bar-widget":"BarWidget.qml","service":"Service.qml"}' "$(jq -c .manifest.entry <<<"$out")"
assert_eq "omarchy: barWidget.defaults win over schema defaultValue" '{"type":"integer","default":3,"description":"Interval"}' "$(jq -c .manifest.settings.interval <<<"$out")"
assert_eq "omarchy: false default kept, description preferred over label" '{"type":"boolean","default":false,"description":"Compact"}' "$(jq -c .manifest.settings.compact <<<"$out")"
assert_eq "omarchy: unknown setting type falls back to the value type" '{"type":"string","default":"auto"}' "$(jq -c .manifest.settings.mode <<<"$out")"
assert_eq "omarchy: defaults without schema entry become settings" '{"type":"string","default":"x"}' "$(jq -c .manifest.settings.extra <<<"$out")"
out="$(adapt "$O/me.flat")"
assert_eq "flat top-level false defaults survive adaptation" false "$(jq -r .manifest.settings.showBattery.default <<<"$out")"
assert_eq "bar settings override top-level defaults" bar "$(jq -r .manifest.settings.mode.default <<<"$out")"
out="$(adapt "$O/me.nested")"
assert_eq "nested settings defaults override their schema fallback" 75 "$(jq -r .manifest.settings.scale.default <<<"$out")"
assert_eq "nested settings retain declared numeric type" integer "$(jq -r .manifest.settings.scale.type <<<"$out")"
assert_eq "nested false defaults remain available to service" false "$(jq -r .manifest.settings.enabled.default <<<"$out")"

capture haseen plugin validate me.traffic
assert_status "omarchy plugin validates" 0 "$STATUS"
assert_contains "omarchy validate names the compat origin" "$OUTPUT" "ok: me.traffic (omarchy: $O/me.traffic)"

capture haseen plugin validate me.svconly me.panelonly omarchy.omaconnect
assert_status "service-only, panel-only and single-segment Omarchy plugins validate" 0 "$STATUS"
capture haseen plugin info omarchy.omaconnect
assert_contains "single-segment registry id resolves to untouched source directory" "$OUTPUT" "$O/omaconnect"
capture haseen plugin enable me.traffic
assert_status "enable starts the widget and its service" 0 "$STATUS"
assert_eq "enabled mixed plugin supplies companion service exactly once" 1 \
    "$(jq '[.services[] | select(. == "me.traffic")] | length' "$XDG_CONFIG_HOME/haseen/shell.json")"
capture haseen plugin disable me.traffic
assert_status "disable mixed plugin" 0 "$STATUS"
assert_eq "disabled mixed plugin leaves no live service entry" 0 \
    "$(jq '[.services[] | select(. == "me.traffic")] | length' "$XDG_CONFIG_HOME/haseen/shell.json")"
check_invalid() { # LABEL ARG EXPECTED_ERROR
    capture haseen plugin validate "$2"
    assert_status "$1: exit 1" 1 "$STATUS"
    assert_contains "$1: reported" "$OUTPUT" "$3"
}
check_invalid "omarchy without kinds" "$O/me.nokinds" "error: omarchy: kinds must be a non-empty array"
check_invalid "omarchy whole-bar replacement requires a native host" "$O/me.baronly" "error: omarchy: no supported kind (has bar; supported: bar-widget, service, panel, overlay)"
check_invalid "omarchy entry escaping" "$O/me.escape" "must be a relative .qml path inside the plugin"
check_invalid "omarchy id/dir mismatch" "$O/me.dirname" "error: id 'me.other' does not match its directory 'me.dirname'"
check_invalid "omarchy missing entry file" "$O/me.noentry" "error: entry file 'Missing.qml' does not exist"
check_invalid "omarchy without name" "$O/me.noname" "error: name is required"

# --- CLI adapter: DMS --------------------------------------------------------
out="$(adapt "$D/StartupCheck")"
assert_eq "dms: compat tag" dms "$(jq -r .compat <<<"$out")"
assert_eq "dms: camelCase id -> dms.<kebab>" dms.example-startup-check "$(jq -r .id <<<"$out")"
assert_eq "dms: upstream id kept" exampleStartupCheck "$(jq -r .upstreamId <<<"$out")"
assert_eq "dms: single component of a widget type is the bar widget" '{"bar-widget":"Widget.qml"}' "$(jq -c .manifest.entry <<<"$out")"
assert_eq "dms: process -> exec, duplicates and DMS-only permissions dropped" '["exec"]' "$(jq -c .manifest.permissions <<<"$out")"
out="$(adapt "$D/Composite")"
assert_eq "dms composite: digits in the id" dms.composite2-demo "$(jq -r .id <<<"$out")"
assert_eq "dms composite: components.widget is the bar widget" '{"bar-widget":"W.qml"}' "$(jq -c .manifest.entry <<<"$out")"
assert_eq "dms composite: other surfaces unsupported, empty ones ignored" '["dms:daemon","dms:desktop"]' "$(jq -c .unsupported <<<"$out")"
assert_eq "dms composite: comma-separated permissions" '["network"]' "$(jq -c .manifest.permissions <<<"$out")"

capture haseen plugin validate dms.example-startup-check dms.composite2-demo
assert_status "dms plugins validate by registry id" 0 "$STATUS"
assert_contains "dms validate names the compat origin" "$OUTPUT" "(dms: $D/StartupCheck)"
assert_contains "dms network permission warns" "$OUTPUT" "warning: requests unrestricted 'network' access"
check_invalid "dms launcher only" "$D/Launcher" "error: dms: no bar widget surface (has launcher; the compat adapter loads the bar widget only)"
check_invalid "dms daemon only" "$D/Daemon" "error: dms: no bar widget surface (has daemon;"
check_invalid "dms bad id" "$D/BadId" "error: dms: id must match ^[a-zA-Z][a-zA-Z0-9]*\$"
check_invalid "dms without name" "$D/NoName" "error: name is required"
check_invalid "dms invalid JSON" "$D/Broken" "error: plugin.json is not a valid JSON object"

# --- list / info: the compat source is visible -------------------------------
capture haseen plugin list
assert_status "list exits 0" 0 "$STATUS"
assert_contains "list: omarchy origin" "$OUTPUT" "$(printf '%-28s %-8s' me.traffic omarchy)"
assert_contains "list: dms origin" "$OUTPUT" "$(printf '%-28s %-8s' dms.example-startup-check dms)"
assert_contains "list: dms plugin in the user dir" "$OUTPUT" "$(printf '%-28s %-8s' dms.dash-counter-example user:dms)"
assert_contains "list: native user plugin unchanged" "$OUTPUT" "$(printf '%-28s %-8s' me.native user)"
assert_contains "list: invalid compat plugin" "$OUTPUT" "$(printf '%-28s %-8s %-10s' dms.launcher-only dms invalid)"
assert_contains "list: service-only Omarchy plugin is available" "$OUTPUT" "$(printf '%-28s %-8s %-10s' me.svconly omarchy available)"
capture haseen plugin info me.traffic
assert_contains "info: adapted entry" "$OUTPUT" "entry:       bar-widget -> BarWidget.qml"
assert_contains "info: adapted setting" "$OUTPUT" "interval (integer) default=3 - Interval"
assert_contains "info: compat origin" "$OUTPUT" "origin:      omarchy ($O/me.traffic)"
capture haseen plugin enable dms.example-startup-check
assert_status "enable a dms plugin by registry id" 0 "$STATUS"
assert_eq "enable places the dms bar widget" true \
    "$(jq '.bar.right | index("dms.example-startup-check") != null' "$XDG_CONFIG_HOME/haseen/shell.json")"
capture haseen plugin enable t1nk33r.missing
assert_status "enable an unknown compat id fails" 1 "$STATUS"

# A user copy wins over the read-only Omarchy directory.
put "$P/me.traffic" manifest.json "$OMARCHY_OK" BarWidget.qml Service.qml
capture haseen plugin validate me.traffic
assert_contains "user copy of an omarchy plugin wins" "$OUTPUT" "ok: me.traffic (user:omarchy: $P/me.traffic)"
rm -rf "${P:?}/me.traffic"

# --- resolution follows the shell's search order -----------------------------
# Haseen/Plugins.qml scans user, built-in, Omarchy and DMS and keeps the first
# directory whose *adapted* id matches; the rest only override. So a directory
# merely named like an adapted id in a lower-priority root must lose to the
# user's copy under its upstream name, or validate/enable/settings would work
# on a manifest the running shell never loads.
put "$P/ExampleEmojiPlugin" plugin.json '{"id":"exampleEmojiPlugin","name":"Emoji user copy","version":"2.0.0","type":"widget","component":"./Widget.qml"}' Widget.qml
put "$D/dms.example-emoji-plugin" plugin.json '{"id":"exampleEmojiPlugin","name":"Emoji read-only","version":"1.0.0","type":"widget","component":"./Widget.qml"}' Widget.qml
index="$(bash -c 'source "$HASEEN_PATH/shell/lib/plugin.sh"; plugin_index')"
shell_order="$(awk -F'\t' '$1 == "dms.example-emoji-plugin" { print $2; exit }' <<<"$index")"
resolved="$(bash -c 'source "$HASEEN_PATH/shell/lib/plugin.sh"; plugin_resolve "$1"' _ dms.example-emoji-plugin)"
assert_eq "resolve agrees with the shell's search order" "$shell_order" "$resolved"
assert_eq "upstream-named user copy beats a lower-priority adapted-id directory" "$P/ExampleEmojiPlugin" "$resolved"
capture haseen plugin info dms.example-emoji-plugin
assert_status "info on the contested id exits 0" 0 "$STATUS"
assert_contains "info reads the manifest the shell loads" "$OUTPUT" "name:        Emoji user copy"
assert_contains "info names the user directory" "$OUTPUT" "origin:      user:dms ($P/ExampleEmojiPlugin)"
rm -rf "${P:?}/ExampleEmojiPlugin" "${D:?}/dms.example-emoji-plugin"

# --- shell adapter (Compat/Manifest.js) agrees with the CLI ------------------
if [[ -x $QML_BIN ]]; then
    harness="$SANDBOX/harness"
    mkdir -p "$harness"
    {
        echo 'var cases = ['
        for dir in "$O"/*/ "$D"/*/ "$P"/*/; do
            dir="${dir%/}"
            m=null p=null
            [[ -r $dir/manifest.json ]] && m="$(jq -Rs . "$dir/manifest.json")"
            [[ -r $dir/plugin.json ]] && p="$(jq -Rs . "$dir/plugin.json")"
            printf '{ path: %s, name: %s, manifest: %s, plugin: %s },\n' \
                "$(jq -Rn --arg v "$dir" '$v')" "$(jq -Rn --arg v "${dir##*/}" '$v')" "$m" "$p"
        done
        echo '];'
    } >"$harness/cases.js"
    cat >"$harness/Harness.qml" <<EOF
import QtQuick
import "file://$SHELL_DIR/Compat/Manifest.js" as M
import "cases.js" as C
Item {
    Component.onCompleted: {
        for (const c of C.cases)
            console.warn("RESULT " + JSON.stringify({ path: c.path, result: M.adapt(c.name, c.manifest, c.plugin) }));
        Qt.quit();
    }
}
EOF
    qml_out="$(cd "$harness" && QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 timeout 30 "$QML_BIN" Harness.qml 2>&1 | sed -n 's/^.*RESULT //p')"
    assert_eq "qml adapter ran every case" "$(grep -c . "$harness/cases.js" | awk '{print $1 - 2}')" "$(grep -c . <<<"$qml_out")"
    # Same shape, ignoring JSON-null vs absent (JS drops undefined fields).
    norm='walk(if type == "object" then with_entries(select(.value != null)) else . end) | del(.problems) | tojson'
    while IFS= read -r line; do
        path="$(jq -r .path <<<"$line")"
        case "$path" in */Broken) continue ;; esac # parse-error texts differ by design
        js="$(jq -r ".result | $norm" <<<"$line")"
        cli="$(adapt "$path" | jq -r "if .compat == \"\" then {compat, upstreamId, id, unsupported} else . end | $norm")"
        if [[ $(jq -r .result.compat <<<"$line") == "" ]]; then
            js="$(jq -r ".result | {compat, upstreamId, id, unsupported} | $norm" <<<"$line")"
        fi
        assert_eq "qml == cli adapter for ${path##*/}" "$cli" "$js"
        assert_eq "qml == cli problems for ${path##*/}" \
            "$(adapt "$path" | jq -c .problems)" "$(jq -c .result.problems <<<"$line")"
    done <<<"$qml_out"
    broken="$(grep '/Broken"' <<<"$qml_out")"
    assert_contains "qml adapter: broken plugin.json refused" "$broken" '"problems":["plugin.json is not valid JSON'
    assert_contains "qml adapter: broken plugin.json keeps a dms id" "$broken" '"id":"dms.broken"'
else
    echo "  skip: $QML_BIN not installed, Compat/Manifest.js not exercised" >&2
fi

# --- compat panel pointer input (plan 027) -----------------------------------
# A compat panel may replace the host's `mask`: flea-shelf empties its own for
# the length of a drag so the drop reaches the application underneath
# (Panel.qml, mask bound to `carrying`). Two rules hold on top of whatever
# mask is in force. While the panel is closed the surface takes no pointer
# input at all — it stays mapped for the fade-out and would otherwise swallow
# clicks meant for applications or the bar — and the dismissal twins on the
# other outputs take input only while the panel itself does. The policy runs
# in the real engine against real Region objects; layer-shell surfaces
# themselves need a compositor and are out of reach here.
QS_BIN=${QS_BIN:-/usr/bin/qs}
if [[ ! -x $QS_BIN ]]; then
    echo "  skip: Quickshell not installed; panel pointer-input policy not exercised" >&2
else
    sandbox compat-panel-input
    XDG_RUNTIME_DIR="$(mktemp -d "${TMPDIR:-/tmp}/haseen-compat-panel.XXXXXX")"
    export XDG_RUNTIME_DIR
    trap 'rm -rf "$XDG_RUNTIME_DIR"' EXIT
    chmod 700 "$XDG_RUNTIME_DIR"
    unset DISPLAY WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE DBUS_SESSION_BUS_ADDRESS
    harness="$SANDBOX/panel-input"
    mkdir -p "$harness"
    # The fixture panel is the flea-shelf shape: one Region of its own, bound
    # to a `carrying` flag, emptied for the length of a drag.
    cat >"$harness/shell.qml" <<EOF
import QtQuick
import Quickshell
import "file://$SHELL_DIR/Compat/Omarchy/Ui/PanelInput.js" as PanelInput

ShellRoot {
    id: probe
    property bool carrying: false
    property bool opened: false
    readonly property real screenW: 1920
    readonly property real screenH: 1080
    readonly property real twinScreenW: 1280

    property Region pluginMask: Region {
        width: probe.carrying ? 0 : probe.screenW
        height: probe.carrying ? 0 : probe.screenH
    }
    property Region closedMask: Region {}

    readonly property var hostMask: PanelInput.effectiveMask(probe.opened, probe.pluginMask, probe.closedMask)
    readonly property bool suspended: PanelInput.pointerInputSuspended(probe.opened, probe.hostMask)
    readonly property real twinW: PanelInput.twinSpan(probe.suspended, probe.twinScreenW)

    property var snaps: []
    function snap(label) {
        probe.snaps.push({
            at: label,
            hostIsPanelMask: probe.hostMask === probe.pluginMask,
            hostW: probe.hostMask ? probe.hostMask.width : -1,
            hostH: probe.hostMask ? probe.hostMask.height : -1,
            panelMaskW: probe.pluginMask.width,
            suspended: probe.suspended,
            twinW: probe.twinW
        });
    }

    Timer {
        interval: 20
        repeat: true
        running: true
        property int phase: 0
        onTriggered: {
            if (phase === 0) { probe.opened = true; phase = 1; }
            else if (phase === 1) { probe.snap("open"); probe.carrying = true; phase = 2; }
            else if (phase === 2) { probe.snap("carry"); probe.carrying = false; probe.opened = false; phase = 3; }
            else if (phase === 3) { probe.snap("fade"); probe.opened = true; phase = 4; }
            else if (phase === 4) { probe.snap("reopen"); probe.carrying = true; phase = 5; }
            else {
                probe.snap("reopen-carry");
                console.warn("RESULT " + JSON.stringify({ unmasked: PanelInput.regionIsEmpty(null), snaps: probe.snaps }));
                running = false;
                Qt.quit();
            }
        }
    }
}
EOF
    capture env QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME='' QT_QUICK_BACKEND=software QT_NO_XDG_DESKTOP_PORTAL=1 \
        QT_FORCE_STDERR_LOGGING=1 timeout 30 dbus-run-session --config-file="$REPO/tools/smoke-session.conf" -- "$QS_BIN" -p "$harness"
    assert_status "pointer-input scenario completes in the real engine" 0 "$STATUS"
    panel_result="$(sed -n 's/^.*RESULT //p' <<<"$OUTPUT")"
    if [[ -n $panel_result ]]; then
        at() { jq -r --arg a "$1" --arg k "$2" '.snaps[] | select(.at == $a) | .[$k]' <<<"$panel_result"; }
        assert_eq "an open panel keeps the mask it supplied itself" true "$(at open hostIsPanelMask)"
        assert_eq "an open panel takes pointer input over its own region" 1920 "$(at open hostW)"
        assert_eq "twins take input while the panel does" 1280 "$(at open twinW)"
        assert_eq "a panel that empties its mask takes no pointer input" 0 "$(at carry hostW)"
        assert_eq "twins release the pointer with the panel that emptied its mask" 0 "$(at carry twinW)"
        assert_eq "a closing panel takes no pointer input during the fade" 0 "$(at fade hostW)"
        assert_eq "the fade leaves nothing clickable vertically either" 0 "$(at fade hostH)"
        assert_eq "a closing panel does not use the mask it supplied" false "$(at fade hostIsPanelMask)"
        assert_eq "twins stay out of the way during the fade" 0 "$(at fade twinW)"
        assert_eq "the panel's own mask is left untouched while it is closed" 1920 "$(at fade panelMaskW)"
        assert_eq "reopening hands the panel its own mask back" true "$(at reopen hostIsPanelMask)"
        assert_eq "the reopened panel takes pointer input again" 1920 "$(at reopen hostW)"
        assert_eq "the panel's mask still follows the panel after a reopen" 0 "$(at reopen-carry hostW)"
        assert_eq "an emptied mask suspends the panel after a reopen too" true "$(at reopen-carry suspended)"
        assert_eq "a surface without a mask keeps taking pointer input" false "$(jq -r .unmasked <<<"$panel_result")"
    else
        _fail "pointer-input scenario produced no result" "$OUTPUT"
    fi
    assert_contains "the compat keyboard panel host shares that policy" \
        "$(cat "$SHELL_DIR/Compat/Omarchy/Ui/KeyboardPanel.qml")" "PanelInput.js"
fi
