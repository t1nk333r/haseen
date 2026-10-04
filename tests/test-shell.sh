# shellcheck shell=bash
# Shell core (plan 005): plugin validate/new/enable/disable/list/info, the
# shell run/restart/ipc commands (DMS routing), the shell layer, and the
# contracts the QML and the CLI must agree on.

SHELL_DIR="$HASEEN_PATH/shell"
BUILTINS=(haseen.workspaces haseen.clock haseen.tray haseen.audio haseen.network haseen.battery)

# mkplugin DIR JSON [ENTRY_FILE...] — a plugin directory with a manifest.
mkplugin() {
    local dir="$1" json="$2" f
    shift 2
    mkdir -p "$dir"
    printf '%s\n' "$json" >"$dir/manifest.json"
    for f in "$@"; do : >"$dir/$f"; done
}

# record CMD — a stub that echoes its argv instead of failing.
record() { stub "$1" "echo \"$1: \$*\""; }

# --- contracts: schema, QML registry and CLI agree --------------------------
sandbox shell-contract
schema_kinds="$(jq -r '."$defs".kind.enum | join(" ")' "$SHELL_DIR/plugin.schema.json")"
cli_kinds="$(bash -c 'source "$HASEEN_PATH/shell/lib/plugin.sh"; echo "${PLUGIN_KINDS[*]}"')"
qml_kinds="$(sed -n 's/.*readonly property var kinds: \[\(.*\)\]/\1/p' "$SHELL_DIR/Haseen/Plugins.qml" | tr -d '", ' | tr -s '[:space:]' ' ')"
assert_eq "schema kinds == CLI kinds" "$schema_kinds" "$cli_kinds"
assert_eq "schema kinds == QML kinds" "$(tr -d ' ' <<<"$schema_kinds")" "$(tr -d ' ' <<<"$qml_kinds")"
assert_eq "schema id pattern == CLI pattern" \
    "$(jq -r .properties.id.pattern "$SHELL_DIR/plugin.schema.json")" \
    "$(bash -c 'source "$HASEEN_PATH/shell/lib/plugin.sh"; echo "$PLUGIN_ID_RE"')"
assert_contains "schema has provides" "$(jq -r '.properties | keys | join(" ")' "$SHELL_DIR/plugin.schema.json")" "provides"
# Every id the default config places must exist as a built-in.
while read -r id; do
    assert_eq "default shell.json id $id is a built-in" "yes" "$([[ -r $SHELL_DIR/plugins/$id/manifest.json ]] && echo yes || echo no)"
done < <(jq -r '[.bar.left, .bar.center, .bar.right, .services] | add | .[]' "$HASEEN_PATH/default/shell.json")
# Widgets take colours from Theme only.
assert_eq "no hex colour literals in built-in plugins/widgets" "" \
    "$(grep -rnE '"#[0-9a-fA-F]{3,8}"' "$SHELL_DIR/plugins" "$SHELL_DIR/Haseen/Widgets" "$SHELL_DIR/templates" || true)"
# No polling timers in the shell (architecture 6). Two kinds of Timer are
# allowed, each marked on the line directly above:
#   // haseen:ui-timeout  single-shot UI timeout (OSD hide, notification expiry)
#   // haseen:sample      a sampler that runs only while visible: a literal
#                         `interval:` >= 2000 and a `running:` binding that is
#                         not the literal `true` (plan 021: system usage)
assert_eq "no unmarked or too-fast Timer in shell QML" "" "$(find "$SHELL_DIR" -name '*.qml' -exec awk '
    function report(why) { print FILENAME ":" start ": " why }
    intimer && /\}/ {
        if (kind == "sample" && (interval < 2000)) report("sample interval < 2000")
        if (kind == "sample" && running != "gated") report("sample not gated by a running: binding")
        intimer = 0
    }
    intimer && /interval:[[:space:]]*[0-9]+/ { match($0, /[0-9]+/); interval = substr($0, RSTART, RLENGTH) + 0 }
    intimer && /running:/ { running = ($0 ~ /running:[[:space:]]*true[[:space:]]*$/) ? "always" : "gated" }
    /^[[:space:]]*Timer[[:space:]]*\{/ {
        start = FNR; interval = 0; running = ""; intimer = 1
        if (prev ~ /haseen:ui-timeout/) kind = "ui"
        else if (prev ~ /haseen:sample/) kind = "sample"
        else { report("unmarked Timer"); intimer = 0 }
    }
    { prev = $0 }' {} +)"

# --- validate: built-ins pass ----------------------------------------------
sandbox shell-validate
capture haseen plugin validate "${BUILTINS[@]}"
assert_status "built-ins validate" 0 "$STATUS"
for id in "${BUILTINS[@]}"; do
    assert_contains "built-in $id ok" "$OUTPUT" "ok: $id (builtin:"
done
assert_not_contains "built-ins request no network" "$OUTPUT" "warning:"

# --- validate: broken manifests are refused --------------------------------
P="$XDG_CONFIG_HOME/haseen/plugins"
mkplugin "$P/Bad_Id" '{"schemaVersion":1,"id":"Bad_Id","name":"x","version":"1.0.0","kinds":["panel"],"entry":{"panel":"P.qml"}}' P.qml
mkplugin "$P/me.noentry" '{"schemaVersion":1,"id":"me.noentry","name":"x","version":"1.0.0","kinds":["panel"],"entry":{"panel":"Missing.qml"}}'
mkplugin "$P/me.kind" '{"schemaVersion":1,"id":"me.kind","name":"x","version":"1.0.0","kinds":["dock"],"entry":{"dock":"D.qml"}}' D.qml
mkplugin "$P/me.nokindentry" '{"schemaVersion":1,"id":"me.nokindentry","name":"x","version":"1.0.0","kinds":["panel","service"],"entry":{"panel":"P.qml"}}' P.qml
mkplugin "$P/me.escape" '{"schemaVersion":1,"id":"me.escape","name":"x","version":"1.0.0","kinds":["panel"],"entry":{"panel":"../me.kind/D.qml"}}'
mkplugin "$P/me.dirname" '{"schemaVersion":1,"id":"me.other","name":"x","version":"1.0.0","kinds":["panel"],"entry":{"panel":"P.qml"}}' P.qml
mkplugin "$P/me.extra" '{"schemaVersion":1,"id":"me.extra","name":"x","version":"1.0.0","kinds":["panel"],"entry":{"panel":"P.qml"},"permission":["exec"]}' P.qml
mkplugin "$P/me.json" '{"schemaVersion":1,' P.qml
mkplugin "$P/me.settings" '{"schemaVersion":1,"id":"me.settings","name":"x","version":"1.0.0","kinds":["panel"],"entry":{"panel":"P.qml"},"settings":{"n":{"type":"integer","default":"ten"}}}' P.qml
mkplugin "$P/me.net" '{"schemaVersion":1,"id":"me.net","name":"x","version":"1.0.0","kinds":["service"],"entry":{"service":"S.qml"},"permissions":["exec","network"]}' S.qml

check_invalid() { # LABEL ARG EXPECTED_ERROR
    capture haseen plugin validate "$2"
    assert_status "$1: exit 1" 1 "$STATUS"
    assert_contains "$1: reported" "$OUTPUT" "$3"
}
check_invalid "bad id" "$P/Bad_Id" "error: id must be a string matching"
check_invalid "missing entry file" me.noentry "error: entry file 'Missing.qml' does not exist"
check_invalid "unknown kind" me.kind "error: unknown kind 'dock'"
check_invalid "kind without entry" me.nokindentry "error: kind 'service' has no entry"
check_invalid "entry escaping the plugin dir" me.escape "must be a relative .qml path inside the plugin"
check_invalid "id/dir mismatch" me.dirname "error: id 'me.other' does not match its directory 'me.dirname'"
check_invalid "unknown field (typo)" me.extra "error: unknown field 'permission'"
check_invalid "invalid JSON" me.json "error: manifest.json is not valid JSON"
check_invalid "setting default type" me.settings "error: setting 'n' default is not of type integer"
capture haseen plugin validate haseen.clock me.kind
assert_status "one bad plugin fails the batch" 1 "$STATUS"
assert_contains "the good one still reported" "$OUTPUT" "ok: haseen.clock"
capture haseen plugin validate me.nonexistent
assert_status "unknown id" 1 "$STATUS"
assert_contains "unknown id message" "$OUTPUT" "unknown plugin: me.nonexistent"

capture haseen plugin validate me.net
assert_status "network plugin is valid" 0 "$STATUS"
assert_contains "permissions printed" "$OUTPUT" "permissions: exec, network"
assert_contains "network warning" "$OUTPUT" "warning: requests unrestricted 'network' access"

capture haseen plugin list
assert_contains "list: invalid shown" "$OUTPUT" "me.kind"
assert_contains "list: invalid state" "$(grep '^me.kind ' <<<"$OUTPUT")" "invalid"
assert_contains "list: service not placed" "$(grep '^me.net ' <<<"$OUTPUT")" "available"
assert_contains "list: default bar widget enabled" "$(grep '^haseen.clock ' <<<"$OUTPUT")" "enabled"

# --- user copy overrides a built-in ----------------------------------------
sandbox shell-override
P="$XDG_CONFIG_HOME/haseen/plugins"
mkdir -p "$P"
cp -r "$SHELL_DIR/plugins/haseen.clock" "$P/"
jq '.name = "My Clock"' "$SHELL_DIR/plugins/haseen.clock/manifest.json" >"$P/haseen.clock/manifest.json"
capture haseen plugin list
assert_contains "override marked user*" "$(grep '^haseen.clock ' <<<"$OUTPUT")" "user*"
assert_contains "override name wins" "$(grep '^haseen.clock ' <<<"$OUTPUT")" "My Clock"
capture haseen plugin info haseen.clock
assert_contains "info: user origin" "$OUTPUT" "origin:      user ($P/haseen.clock)"
assert_contains "info: settings default" "$OUTPUT" 'format (string) default="HH:mm"'

# --- new -> validate -------------------------------------------------------
sandbox shell-new
P="$XDG_CONFIG_HOME/haseen/plugins"
capture haseen plugin new me.dry --kind bar-widget --dry-run
assert_status "new dry-run exit" 0 "$STATUS"
assert_dry_pure "plugin new" "$OUTPUT"
assert_contains "new dry-run shows manifest" "$OUTPUT" "DRYRUN: write $P/.me.dry.new/manifest.json:"
assert_contains "new dry-run swaps the staged dir in" "$OUTPUT" "DRYRUN: mv -- $P/.me.dry.new $P/me.dry"
assert_eq "new dry-run wrote nothing" "" "$(find "$HOME" -mindepth 1 -print -quit)"

for kind in bar-widget panel service launcher-provider overlay; do
    capture haseen plugin new "me.$kind" --kind "$kind"
    assert_status "new $kind exit" 0 "$STATUS"
    capture haseen plugin validate "me.$kind"
    assert_status "new $kind validates" 0 "$STATUS"
    assert_eq "new $kind QML has no placeholder" "" "$(grep -l '@ID@' "$P/me.$kind"/*.qml || true)"
    assert_contains "new $kind QML uses Theme or is non-visual" "$(cat "$P/me.$kind"/*.qml)" "pluginId"
done
assert_eq "no staging dirs left behind" "" "$(find "$P" -mindepth 1 -maxdepth 1 -name '.*' -print)"
assert_contains "bar-widget scaffold reads Theme" "$(cat "$P/me.bar-widget/Widget.qml")" "Theme.foreground"
capture haseen plugin new me.multi --kind bar-widget --kind panel --kind panel
assert_status "multi-kind new" 0 "$STATUS"
assert_eq "multi-kind manifest kinds (deduplicated)" '["bar-widget","panel"]' "$(jq -c .kinds "$P/me.multi/manifest.json")"
capture haseen plugin validate me.multi
assert_status "multi-kind validates" 0 "$STATUS"
capture haseen plugin info me.multi
assert_contains "info shows scaffold label default" "$OUTPUT" 'label (string) default="Multi"'

capture haseen plugin new me.bar-widget --kind panel
assert_status "new refuses an existing plugin" 1 "$STATUS"
capture haseen plugin new haseen.mine --kind panel
assert_status "new refuses haseen.*" 1 "$STATUS"
assert_contains "haseen.* reserved message" "$OUTPUT" "reserved for built-in"
capture haseen plugin new Bad --kind panel
assert_status "new refuses a bad id" 1 "$STATUS"
capture haseen plugin new me.x --kind dock
assert_status "new refuses an unknown kind" 1 "$STATUS"
capture haseen plugin new me.x
assert_status "new without --kind is a usage error" 2 "$STATUS"

# --- enable / disable edit shell.json idempotently -------------------------
sandbox shell-enable
P="$XDG_CONFIG_HOME/haseen/plugins"
CFG="$XDG_CONFIG_HOME/haseen/shell.json"
haseen plugin new me.widget --kind bar-widget >/dev/null
haseen plugin new me.svc --kind service >/dev/null
haseen plugin new me.pan --kind panel >/dev/null
default_right="$(jq -c .bar.right "$HASEEN_PATH/default/shell.json")"
default_services="$(jq -c .services "$HASEEN_PATH/default/shell.json")"

capture haseen plugin enable me.widget --dry-run
assert_dry_pure "enable" "$OUTPUT"
assert_contains "enable dry-run shows the write" "$OUTPUT" "DRYRUN: write $CFG.new:"
assert_contains "enable dry-run renames into place" "$OUTPUT" "DRYRUN: mv -f -- $CFG.new $CFG"
assert_eq "enable dry-run wrote nothing" "absent" "$([[ -e $CFG ]] && echo present || echo absent)"

capture haseen plugin enable me.widget
assert_status "enable bar-widget" 0 "$STATUS"
assert_contains "first shell.json asks for a reload" "$OUTPUT" "haseen shell ipc shell reload"
assert_eq "no temp file left" "absent" "$([[ -e $CFG.new ]] && echo present || echo absent)"
assert_eq "bar.right = default right + id" "$(jq -c '. + ["me.widget"]' <<<"$default_right")" "$(jq -c .bar.right "$CFG")"
assert_eq "enabled flag set" "true" "$(jq .plugins[\"me.widget\"].enabled "$CFG")"
assert_eq "only right section copied" "null" "$(jq -c .bar.left "$CFG")"
before="$(cat "$CFG")"
capture haseen plugin enable me.widget
assert_status "enable again" 0 "$STATUS"
assert_contains "enable again is a no-op" "$OUTPUT" "already enabled"
assert_eq "enable is idempotent" "$before" "$(cat "$CFG")"

capture haseen plugin enable me.svc
assert_not_contains "existing shell.json needs no reload hint" "$OUTPUT" "shell ipc shell reload"
assert_eq "service appended to services" "$(jq -c '. + ["me.svc"]' <<<"$default_services")" "$(jq -c .services "$CFG")"
assert_eq "service not placed in the bar" "$(jq -c '. + ["me.widget"]' <<<"$default_right")" "$(jq -c .bar.right "$CFG")"
capture haseen plugin enable me.pan
assert_eq "panel only gets the flag" "true" "$(jq .plugins[\"me.pan\"].enabled "$CFG")"
assert_eq "panel not placed anywhere" "$(jq -c '. + ["me.svc"]' <<<"$default_services")" "$(jq -c .services "$CFG")"

capture haseen plugin disable me.widget
assert_status "disable" 0 "$STATUS"
assert_eq "removed from bar.right" "$default_right" "$(jq -c .bar.right "$CFG")"
assert_eq "enabled flag false" "false" "$(jq .plugins[\"me.widget\"].enabled "$CFG")"
before="$(cat "$CFG")"
capture haseen plugin disable me.widget
assert_contains "disable again is a no-op" "$OUTPUT" "already disabled"
assert_eq "disable is idempotent" "$before" "$(cat "$CFG")"
capture haseen plugin disable haseen.clock
assert_eq "built-in removed from the default center section" "[]" "$(jq -c .bar.center "$CFG")"
capture haseen plugin disable me.svc
assert_eq "service removed" "$default_services" "$(jq -c .services "$CFG")"
capture haseen plugin enable me.widget
assert_eq "re-enable puts it back once" "1" "$(jq '[.bar.right[] | select(. == "me.widget")] | length' "$CFG")"

capture haseen plugin disable me.gone
assert_status "disable of an id not on disk still works" 0 "$STATUS"
assert_eq "stale id flagged off" "false" "$(jq .plugins[\"me.gone\"].enabled "$CFG")"

mkplugin "$P/me.broken" '{"schemaVersion":1,"id":"me.broken","name":"x","version":"1.0.0","kinds":["bar-widget"],"entry":{"bar-widget":"Nope.qml"}}'
before="$(cat "$CFG")"
capture haseen plugin enable me.broken
assert_status "enable refuses an invalid plugin" 1 "$STATUS"
assert_eq "refused enable left shell.json alone" "$before" "$(cat "$CFG")"

printf '{ "bar": { // comment\n' >"$CFG"
capture haseen plugin enable me.widget
assert_status "enable refuses a non-JSON shell.json" 1 "$STATUS"
assert_eq "non-JSON shell.json untouched" '{ "bar": { // comment' "$(cat "$CFG")"

# --- shell run / restart / ipc ---------------------------------------------
sandbox shell-cmds
record qs
capture haseen shell run
assert_eq "run execs qs -p HASEEN_PATH/shell" "qs: -p $HASEEN_PATH/shell" "$OUTPUT"

capture haseen shell ipc panel toggle me.x
assert_eq "ipc goes to qs by default" "qs: -p $HASEEN_PATH/shell ipc call panel toggle me.x" "$OUTPUT"
capture haseen shell ipc shell
assert_status "ipc needs target and function" 2 "$STATUS"

mkdir -p "$XDG_STATE_HOME/haseen"
echo haseen >"$XDG_STATE_HOME/haseen/active-shell"
capture haseen shell ipc launcher toggle
assert_eq "active-shell=haseen uses qs" "qs: -p $HASEEN_PATH/shell ipc call launcher toggle" "$OUTPUT"

# A HASEEN_PATH whose dms layer ships a stub translator (the real one belongs
# to the dms slice).
HP="$SANDBOX/haseen-path"
mkdir -p "$HP/layers/dms"
ln -s "$HASEEN_PATH/lib" "$HP/lib"
ln -s "$HASEEN_PATH/shell" "$HP/shell"
printf '#!/bin/sh\necho "TRANSLATE: $*"\n' >"$HP/layers/dms/ipc-translate"
chmod +x "$HP/layers/dms/ipc-translate"
echo dms >"$XDG_STATE_HOME/haseen/active-shell"
capture env HASEEN_PATH="$HP" haseen shell ipc panel toggle me.x
assert_eq "active-shell=dms routes to ipc-translate" "TRANSLATE: panel toggle me.x" "$OUTPUT"
assert_not_contains "dms route never calls qs" "$OUTPUT" "qs:"
rm "$HP/layers/dms/ipc-translate"
capture env HASEEN_PATH="$HP" haseen shell ipc lock lock
assert_status "dms active without translator fails" 1 "$STATUS"
assert_contains "missing translator explained" "$OUTPUT" "haseen layer apply dms"
rm "$XDG_STATE_HOME/haseen/active-shell"

sandbox shell-restart
stub systemctl '[ "$2" = is-active ] && exit 0; echo "STUB-CALLED: systemctl $*" >&2; exit 97'
capture haseen shell restart --dry-run
assert_status "restart (unit active) dry-run" 0 "$STATUS"
assert_dry_pure "restart unit" "$OUTPUT"
assert_contains "restart uses the unit" "$OUTPUT" "DRYRUN: systemctl --user restart haseen-shell.service"
assert_not_contains "restart unit does not kill qs" "$OUTPUT" "qs kill"
stub systemctl '[ "$2" = is-active ] && exit 3; echo "STUB-CALLED: systemctl $*" >&2; exit 97'
capture haseen shell restart --dry-run
assert_dry_pure "restart instance" "$OUTPUT"
assert_contains "restart kills the instance for the path" "$OUTPUT" "DRYRUN: qs kill -p $HASEEN_PATH/shell"
assert_contains "restart relaunches detached" "$OUTPUT" "DRYRUN: qs -p $HASEEN_PATH/shell -d"
capture haseen shell restart extra
assert_status "restart rejects arguments" 2 "$STATUS"

# --- shell layer -----------------------------------------------------------
shell_layer() { # FIXTURE ACTION — runs the layer directly (its requirements have their own tests)
    capture env HASEEN_SYSROOT="$1" DRY_RUN=true bash -c 'source "$HASEEN_PATH/lib/layers.sh"; '"$2"
}
fx_bare="$FIXTURES/cachyos-limine-luks-dualboot"
fx_qs="$FIXTURES/shell-quickshell-installed"

sandbox shell-layer
assert_eq "layer requires desktop and theme" $'desktop\ntheme' "$(bash -c 'source "$HASEEN_PATH/lib/layers.sh"; layer_field shell LAYER_REQUIRES')"
shell_layer "$fx_bare" 'layer_run_apply shell'
assert_status "layer dry-run exit" 0 "$STATUS"
assert_dry_pure "shell layer" "$OUTPUT"
assert_contains "packages planned" "$OUTPUT" "DRYRUN: sudo pacman -S --needed quickshell jq"
assert_contains "shell.json seeded" "$OUTPUT" "DRYRUN: seed $XDG_CONFIG_HOME/haseen/shell.json from $HASEEN_PATH/layers/shell/files/shell.json"
assert_contains "example seeded" "$OUTPUT" "DRYRUN: seed $XDG_CONFIG_HOME/haseen/shell.example.json"
assert_contains "unit enabled" "$OUTPUT" "DRYRUN: systemctl --user enable haseen-shell.service"
assert_eq "layer dry-run wrote nothing" "" "$(find "$HOME" -mindepth 1 -print -quit)"
assert_eq "seeded shell.json is {}" "{}" "$(jq -c . "$HASEEN_PATH/layers/shell/files/shell.json")"
capture jq -e '.bar.right | length > 0' "$HASEEN_PATH/layers/shell/files/shell.example.json"
assert_status "example is plain JSON with a bar" 0 "$STATUS"

shell_layer "$fx_bare" 'layer_run_status shell'
assert_status "status: nothing applied" 1 "$STATUS"

# Applied state: user files present, unit symlinked, packages in the fixture.
mkdir -p "$XDG_CONFIG_HOME/haseen" "$XDG_CONFIG_HOME/systemd/user/graphical-session.target.wants"
echo '{"bar":{"height":30}}' >"$XDG_CONFIG_HOME/haseen/shell.json"
ln -s /usr/lib/systemd/user/haseen-shell.service "$XDG_CONFIG_HOME/systemd/user/graphical-session.target.wants/haseen-shell.service"
shell_layer "$fx_bare" 'layer_run_status shell'
assert_status "status: degraded without packages" 2 "$STATUS"
assert_contains "status names the missing package" "$OUTPUT" "missing: package quickshell"
shell_layer "$fx_qs" 'layer_run_status shell'
assert_status "status: applied" 0 "$STATUS"
shell_layer "$fx_qs" 'layer_run_apply shell'
assert_dry_pure "re-apply" "$OUTPUT"
assert_not_contains "re-apply never reseeds shell.json" "$OUTPUT" "seed $XDG_CONFIG_HOME/haseen/shell.json "
assert_not_contains "re-apply does not re-enable" "$OUTPUT" "systemctl --user enable"
assert_contains "re-apply reports enabled" "$OUTPUT" "already enabled"
assert_eq "user shell.json kept" '{"bar":{"height":30}}' "$(cat "$XDG_CONFIG_HOME/haseen/shell.json")"
