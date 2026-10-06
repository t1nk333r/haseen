# shellcheck shell=bash
# An Omarchy plugin's updateEntryInline is mirrored into Omarchy's own
# shell.json (t1nk33r.nearby-share reads its settings back from there).
sandbox compat-mirror
p="$XDG_CONFIG_HOME/omarchy/plugins/me.mirror"
mkdir -p "$p" "$XDG_CONFIG_HOME/haseen/plugins/me.native"
printf '%s\n' '{"schemaVersion":1,"id":"me.mirror","name":"Mirror fixture","version":"1.0.0","kinds":["bar-widget"],"entryPoints":{"barWidget":"Panel.qml"}}' >"$p/manifest.json"
printf 'import QtQuick\nItem {}\n' >"$p/Panel.qml"
printf '%s\n' '{"schemaVersion":1,"id":"me.native","name":"Native fixture","version":"1.0.0","kinds":["service"],"entry":{"service":"Service.qml"},"settings":{},"permissions":[]}' >"$XDG_CONFIG_HOME/haseen/plugins/me.native/manifest.json"
printf 'import QtQuick\nQtObject {}\n' >"$XDG_CONFIG_HOME/haseen/plugins/me.native/Service.qml"
omarchy="$HOME/.config/omarchy/shell.json"
haseen="$XDG_CONFIG_HOME/haseen/shell.json"

# No Omarchy shell.json: haseen's file is written, Omarchy's is never created.
request='{"changes":[{"path":["plugins","me.mirror","settings","mode"],"value":"quickshare"}],"omarchyEntry":{"mode":"quickshare","receiverEnabled":true}}'
capture haseen-plugin-settings me.mirror <<<"$request"
assert_status "an Omarchy plugin's mirrored write is accepted" 0 "$STATUS"
assert_eq "haseen's shell.json holds the change" quickshare "$(jq -r '.plugins["me.mirror"].settings.mode' "$haseen")"
assert_eq "a missing Omarchy shell.json is not created" false "$([[ -e $omarchy ]] && echo true || echo false)"

# A layout object entry is replaced by {id, ...entry}; nothing else changes.
original='{"version":1,"bar":{"layout":{"left":["clock"],"right":[{"id":"other","x":1},{"id":"me.mirror","mode":"localsend","receiverEnabled":true,"stale":1}]}},"plugins":[{"id":"me.mirror","marker":true}]}'
printf '%s\n' "$original" >"$omarchy"
chmod 600 "$omarchy"
request='{"changes":[{"path":["plugins","me.mirror","settings","receiverEnabled"],"value":false}],"omarchyEntry":{"id":"spoofed","mode":"localsend","receiverEnabled":false}}'
capture haseen-plugin-settings me.mirror --dry-run <<<"$request"
assert_status "a mirrored dry run is accepted" 0 "$STATUS"
assert_eq "a dry run leaves Omarchy's shell.json alone" "$(jq -c . <<<"$original")" "$(jq -c . "$omarchy")"
capture haseen-plugin-settings me.mirror <<<"$request"
assert_status "the mirrored write succeeds" 0 "$STATUS"
assert_eq "the plugin's layout entry is exactly what it wrote, under its own id" \
    '{"id":"me.mirror","mode":"localsend","receiverEnabled":false}' "$(jq -c '.bar.layout.right[1]' "$omarchy")"
assert_eq "other entries and the plugins[] marker are untouched" \
    '[["clock"],{"id":"other","x":1},{"id":"me.mirror","marker":true},1]' \
    "$(jq -c '[.bar.layout.left, .bar.layout.right[0], .plugins[0], .version]' "$omarchy")"
assert_eq "the first mirror keeps a backup of the original" "$(jq -c . <<<"$original")" "$(jq -c . "$omarchy.haseen-bak")"
assert_eq "the mirrored file keeps its mode" 600 "$(stat -c %a "$omarchy")"
assert_eq "no staging file is left behind" "" "$(find "$(dirname "$omarchy")" -maxdepth 1 -name 'shell.json.new*')"

# Without a layout object entry the plugins[] marker is the target; the
# backup still holds the very first original.
printf '%s\n' '{"version":1,"bar":{"layout":{"right":["me.mirror"]}},"plugins":[{"id":"me.mirror","marker":true}]}' >"$omarchy"
request='{"changes":[],"omarchyEntry":{"mode":"quickshare"}}'
capture haseen-plugin-settings me.mirror <<<"$request"
assert_status "a mirror-only request succeeds" 0 "$STATUS"
assert_eq "the plugins[] marker is replaced when the layout holds no object entry" \
    '{"bar":{"layout":{"right":["me.mirror"]}},"plugins":[{"id":"me.mirror","mode":"quickshare"}]}' "$(jq -c 'del(.version)' "$omarchy")"
assert_eq "later mirrors keep the first backup" "$(jq -c . <<<"$original")" "$(jq -c . "$omarchy.haseen-bak")"

# A plugin absent from Omarchy's file gets no entry there.
printf '%s\n' '{"version":1,"plugins":[{"id":"someone.else"}]}' >"$omarchy"
capture haseen-plugin-settings me.mirror <<<"$request"
assert_eq "an absent entry is never added" '{"version":1,"plugins":[{"id":"someone.else"}]}' "$(jq -c . "$omarchy")"

# Native plugins cannot ask for the mirror.
request='{"changes":[],"omarchyEntry":{"x":1}}'
capture haseen-plugin-settings me.native <<<"$request"
assert_status "a native plugin's omarchyEntry is refused" 1 "$STATUS"
assert_eq "the refused request leaves Omarchy's shell.json alone" '{"version":1,"plugins":[{"id":"someone.else"}]}' "$(jq -c . "$omarchy")"
