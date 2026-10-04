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

# --- contracts: module names, symlinks, native code stays native -------------
sandbox compat-contract
declare -A MODULES=([Commons]=Compat/Omarchy/Commons [Ui]=Compat/Omarchy/Ui
    [Common]=Compat/Dms/Common [Services]=Compat/Dms/Services
    [Widgets]=Compat/Dms/Widgets [Modules]=Compat/Dms/Modules)
for name in "${!MODULES[@]}"; do
    assert_eq "shell/$name is a relative symlink to ${MODULES[$name]}" "${MODULES[$name]}" "$(readlink "$SHELL_DIR/$name")"
done
for mod in Commons Ui Common Services Widgets Modules/Plugins; do
    assert_eq "qs.${mod//\//.} qmldir names its module" "module qs.${mod//\//.}" "$(head -n1 "$SHELL_DIR/$mod/qmldir")"
done
# quickshell resolves `import qs.X` to <shell dir>/X only, so these six names
# are reserved for adapted plugins (architecture 5.1): no native file may
# import them.
assert_eq "native shell code never imports the compat module names" "" \
    "$(grep -rnE '^[[:space:]]*import[[:space:]]+qs\.(Commons|Ui|Common|Services|Widgets|Modules)([.[:space:]]|$)' \
        --include='*.qml' --include='*.js' "$SHELL_DIR" --exclude-dir=Compat || true)"
assert_eq "no hex colour literals in Compat" "" "$(grep -rnE '"#[0-9a-fA-F]{3,8}"' "$SHELL_DIR/Compat" || true)"
assert_eq "every Omarchy/DMS-derived Compat file carries the upstream notice" "" "$(
    grep -rL -e 'Copyright (c) David Heinemeier Hansson' -e 'Copyright (c) 2025 Avenge Media LLC' \
        "$SHELL_DIR/Compat/Omarchy" "$SHELL_DIR/Compat/Dms" --include='*.qml' || true
)"
assert_contains "Plugins.qml loads the shared adapter" "$(cat "$SHELL_DIR/Haseen/Plugins.qml")" 'import "../Compat/Manifest.js" as CompatManifest'

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
assert_eq "omarchy: only bar-widget is adapted" '["bar-widget"]' "$(jq -c .manifest.kinds <<<"$out")"
assert_eq "omarchy: other kinds are listed as unsupported" '["service"]' "$(jq -c .unsupported <<<"$out")"
assert_eq "omarchy: entryPoints.barWidget -> entry.bar-widget" '{"bar-widget":"BarWidget.qml"}' "$(jq -c .manifest.entry <<<"$out")"
assert_eq "omarchy: barWidget.defaults win over schema defaultValue" '{"type":"integer","default":3,"description":"Interval"}' "$(jq -c .manifest.settings.interval <<<"$out")"
assert_eq "omarchy: false default kept, description preferred over label" '{"type":"boolean","default":false,"description":"Compact"}' "$(jq -c .manifest.settings.compact <<<"$out")"
assert_eq "omarchy: unknown setting type falls back to the value type" '{"type":"string","default":"auto"}' "$(jq -c .manifest.settings.mode <<<"$out")"
assert_eq "omarchy: defaults without schema entry become settings" '{"type":"string","default":"x"}' "$(jq -c .manifest.settings.extra <<<"$out")"

capture haseen plugin validate me.traffic
assert_status "omarchy plugin validates" 0 "$STATUS"
assert_contains "omarchy validate names the compat origin" "$OUTPUT" "ok: me.traffic (omarchy: $O/me.traffic)"

check_invalid() { # LABEL ARG EXPECTED_ERROR
    capture haseen plugin validate "$2"
    assert_status "$1: exit 1" 1 "$STATUS"
    assert_contains "$1: reported" "$OUTPUT" "$3"
}
check_invalid "omarchy without kinds" "$O/me.nokinds" "error: omarchy: kinds must be a non-empty array"
check_invalid "omarchy service only" "$O/me.svconly" "error: omarchy: no supported kind (has service; the compat adapter loads bar-widget only)"
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
assert_contains "list: invalid omarchy plugin" "$OUTPUT" "$(printf '%-28s %-8s %-10s' me.svconly omarchy invalid)"
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
