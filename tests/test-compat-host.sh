# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# Scoped persistence boundaries; no original plugin runs.
sandbox compat-host-settings
p="$XDG_CONFIG_HOME/haseen/plugins/me.host"
mkdir -p "$p" "$XDG_CONFIG_HOME/omarchy"
printf '%s\n' '{"schemaVersion":1,"id":"me.host","name":"Host fixture","version":"1.0.0","kinds":["service"],"entry":{"service":"Service.qml"},"settings":{},"permissions":[]}' >"$p/manifest.json"
printf 'import QtQuick\nQtObject {}\n' >"$p/Service.qml"
printf '%s\n' '{"owner":"untouched"}' >"$XDG_CONFIG_HOME/omarchy/shell.json"
config="$XDG_CONFIG_HOME/haseen/shell.json"
request='{"settings":{"value":7,"nested":{"new":true}}}'
capture haseen-plugin-settings me.host --dry-run <<<"$request"
assert_status "settings dry run accepted" 0 "$STATUS"
assert_dry_pure "settings dry run" "$OUTPUT"
assert_eq "dry run creates neither config nor lock" 0 "$(find "$XDG_CONFIG_HOME/haseen" -maxdepth 1 -type f | wc -l)"
printf '%s\n' '{"owner":{"custom":true},"bar":{"height":31},"plugins":{"me.host":{"enabled":false,"settings":{"keep":9,"nested":{"old":true}}},"me.other":{"settings":{"secret":"fixture-only"}}}}' >"$config"
capture haseen-plugin-settings me.host <<<"$request"
assert_status "own settings write accepted" 0 "$STATUS"
assert_eq "nested own settings merge preserves existing keys" '{"old":true,"new":true}' "$(jq -c '.plugins["me.host"].settings.nested' "$config")"
assert_eq "unrelated user setting remains" true "$(jq '.owner.custom and (.plugins["me.other"].settings.secret == "fixture-only") and (.plugins["me.host"].enabled == false) and (.bar.height == 31)' "$config")"
assert_eq "Omarchy config never changes" '{"owner":"untouched"}' "$(cat "$XDG_CONFIG_HOME/omarchy/shell.json")"
assert_eq "atomic temporary file gone" no "$([[ -e $config.new ]] && echo yes || echo no)"
before="$(cat "$config")"
for request in \
    '{"changes":[{"path":["plugins","me.other","settings","value"],"value":1}]}' \
    '{"changes":[{"path":["services"],"value":[]}]}' \
    '{"settings":{"__proto__":{"bad":true}}}' \
    '{"changes":[{"path":["bar","position"],"value":"diagonal"}]}' \
    '{"changes":[{"path":["bar","height","nested"],"value":1}]}' \
    '{} {}'; do
    capture haseen-plugin-settings me.host <<<"$request"
    assert_status "invalid/out-of-scope request refused" 1 "$STATUS"
    assert_eq "refused mutation leaves user config unchanged" "$before" "$(cat "$config")"
done
request='{"changes":[{"path":["idle","screensaver"],"value":180}],"idleProvider":"haseen.idle"}'
capture haseen-plugin-settings me.host <<<"$request"
assert_status "legacy screensaver timeout accepted" 0 "$STATUS"
assert_eq "idle timeout uses actual haseen key" 180 "$(jq '.plugins["haseen.idle"].settings.screensaverAfter' "$config")"
assert_eq "legacy idle branch is not written" false "$(jq 'has("idle")' "$config")"
# Concurrent screens/widgets read under the same lock, so neither update
# overwrites the other's independent key.
haseen-plugin-settings me.host <<< '{"settings":{"first":1}}' >"$SANDBOX/first.out" 2>"$SANDBOX/first.err" &
first=$!
haseen-plugin-settings me.host <<< '{"settings":{"second":2}}' >"$SANDBOX/second.out" 2>"$SANDBOX/second.err" &
second=$!
wait "$first" && wait "$second"
assert_eq "concurrent settings writes both survive" true "$(jq '.plugins["me.host"].settings | .first == 1 and .second == 2 and .keep == 9' "$config")"
printf 'owner is currently editing\n' >"$config"
capture haseen-plugin-settings me.host <<< '{"settings":{"value":0}}'
assert_status "malformed user config is never overwritten" 1 "$STATUS"
assert_eq "malformed user's bytes remain" 'owner is currently editing' "$(cat "$config")"

