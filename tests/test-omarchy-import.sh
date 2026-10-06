# shellcheck shell=bash
# haseen import omarchy: an Omarchy 4 user's shell.json (the real shape, with
# public city-level coordinates), branding, hooks, themes and Hyprland files
# become haseen's files; what has no equivalent is reported; Omarchy's own
# files are never touched; a re-run changes nothing.
IMPORT_FIXTURE="$FIXTURES/omarchy-import"

# import_sandbox NAME — a home holding an Omarchy setup where the command
# looks by default: ~/.config/omarchy, a ~/.config/hypr.omarchy-* backup and
# ~/.local/state/omarchy.
import_sandbox() {
    sandbox "$1"
    mkdir -p "$XDG_CONFIG_HOME" "$XDG_STATE_HOME"
    cp -R "$IMPORT_FIXTURE/omarchy" "$XDG_CONFIG_HOME/omarchy"
    cp -R "$IMPORT_FIXTURE/hypr.omarchy-20261006" "$XDG_CONFIG_HOME/"
    cp -R "$IMPORT_FIXTURE/state/omarchy" "$XDG_STATE_HOME/omarchy"
    export HASEEN_SYSROOT="$IMPORT_FIXTURE/sysroot"
    HC="$XDG_CONFIG_HOME/haseen"
    HY="$XDG_CONFIG_HOME/hypr"
}

# tree_sum DIR... — contents and modes of every file, for "nothing changed".
# The shell.json lock every writer shares is not content.
tree_sum() {
    local d
    for d in "$@"; do
        [[ -e $d ]] || continue
        find "$d" -type f ! -name .shell.json.lock -printf '%p %m\n' -exec sha256sum {} \;
    done | LC_ALL=C sort | sha256sum
}
omarchy_sum() { tree_sum "$XDG_CONFIG_HOME/omarchy" "$XDG_CONFIG_HOME/hypr.omarchy-20261006" "$XDG_STATE_HOME/omarchy"; }
haseen_sum() { tree_sum "$HC" "$HY"; }
cfg() { jq -c "$1" "$HC/shell.json"; }

# --- dry run: prints the plan, writes nothing --------------------------------
import_sandbox omarchy-import-dry
before="$(omarchy_sum)"
capture "$REPO/bin/haseen-import-omarchy" --dry-run
assert_status "dry run succeeds" 0 "$STATUS"
assert_dry_pure "import" "$OUTPUT"
assert_contains "dry run shows the shell.json it would write" "$OUTPUT" '"haseen.workspaces"'
assert_contains "dry run shows the bindings it would write" "$OUTPUT" 'haseen.bind("SUPER + H"'
assert_eq "dry run creates no haseen config" "absent" "$([[ -e $HC || -e $HY ]] && echo present || echo absent)"
assert_eq "dry run leaves Omarchy's files alone" "$before" "$(omarchy_sum)"
assert_contains "dry run shows it would apply the gestures it carried over" "$OUTPUT" "DRYRUN: $REPO/bin/haseen-gestures-apply"
assert_eq "and renders no gestures" "absent" \
    "$([[ -e $XDG_STATE_HOME/haseen/toggles/hypr/gestures.lua ]] && echo present || echo absent)"

# --- first import into an empty haseen config ---------------------------------
import_sandbox omarchy-import
before="$(omarchy_sum)"
capture "$REPO/bin/haseen-import-omarchy"
assert_status "import succeeds" 0 "$STATUS"
assert_eq "Omarchy's files are untouched" "$before" "$(omarchy_sum)"

assert_eq "bar position and transparency carry over" '["top",false]' "$(cfg '[.bar.position, .bar.transparent]')"
assert_eq "left section: built-ins mapped, add-ons kept, order kept" \
    '["haseen.workspaces","agx.screen-time","t1nk33r.active-window"]' "$(cfg .bar.left)"
assert_eq "centre section: dropped built-ins leave no gap" \
    '["haseen.clock","t1nk33r.omaprayers","haseen.weather","t1nk33r.privacy"]' "$(cfg .bar.center)"
assert_eq "right section starts with the tray and ends with the power add-on" \
    '["haseen.tray","t1nk33r.power",14]' "$(cfg '[.bar.right[0], .bar.right[-1], (.bar.right | length)]')"
assert_eq "right section maps bluetooth, network and audio in place" \
    '["haseen.bluetooth","haseen.network","haseen.audio"]' "$(cfg '.bar.right[9:12]')"
# haseen.gestures is the native port of omagesture; the original's panel would
# rewrite ~/.config/hypr/hyprland.lua and fight the port over the gestures.
assert_eq "omagesture is replaced in place by haseen.gestures, settings kept" \
    '["haseen.gestures",{"g3Up":"none","g3Down":"none"},null,null]' \
    "$(cfg '[.bar.right[5], .plugins["haseen.gestures"].settings, (.bar | [.left, .center, .right] | add | index("io.github.heroesofcode.omagesture")), .plugins["io.github.heroesofcode.omagesture"]]')"
assert_eq "the carried-over gestures are rendered into Hyprland (haseen gestures apply)" "present" \
    "$([[ -s $XDG_STATE_HOME/haseen/toggles/hypr/gestures.lua ]] && echo present || echo absent)"
assert_eq "clock formats carry over (Qt formats in both)" \
    '{"format":"dddd HH:mm","verticalFormat":"HH\n—\nmm"}' "$(cfg '.plugins["haseen.clock"].settings')"
assert_eq "add-on settings pass through under the same id, enabled" \
    '[true,"Riyadh",4,"Asia/Riyadh"]' \
    "$(cfg '.plugins["t1nk33r.omaprayers"] | [.enabled, .settings.locationLabel, .settings.calculationMethod, .settings.timezone]')"
assert_eq "omastats keeps every setting" "10" "$(cfg '.plugins["crmne.omastats"].settings | length')"
assert_eq "per-widget settings never leak the id key" "null" "$(cfg '.plugins["t1nk33r.power"].settings.id')"
assert_eq "weather is turned on with Omarchy's stored location" \
    '[true,"24.7136,46.6753"]' "$(cfg '.plugins["haseen.weather"] | [.enabled, .settings.location]')"
assert_eq "idle screensaver and lock seconds go to haseen.idle" \
    '{"screensaverAfter":150,"lockAfter":300}' "$(cfg '.plugins["haseen.idle"].settings')"
assert_eq "Omarchy's service plugins are enabled after haseen's own services" \
    '[true,true,true,"io.github.sumanthmukkala.hot-corners","expose.window-overview"]' \
    "$(cfg '[(.services | index("haseen.lock") != null), .plugins["io.github.sumanthmukkala.hot-corners"].enabled, .plugins["expose.window-overview"].enabled, .services[-2], .services[-1]]')"
merged="$(jq -c --slurpfile u "$HC/shell.json" '. * $u[0] | .bar.left' "$HASEEN_PATH/default/shell.json")"
assert_eq "the running shell's merged config shows the imported bar" \
    '["haseen.workspaces","agx.screen-time","t1nk33r.active-window"]' "$merged"

for item in "omarchy.menu: Omarchy built-in with no haseen equivalent" "omarchy.indicators: Omarchy built-in" \
    "omarchy.keyboard-layout: Omarchy built-in" "omarchy.system-update: Omarchy built-in" \
    "omarchy.clock: setting formatAlt has no haseen equivalent" "bar.centerAnchor (omarchy.clock)" \
    "crmne.omastats: plugin not installed"; do
    assert_contains "reported: ${item%%:*}" "$OUTPUT" "$item"
done
assert_not_contains "a plugin Omarchy provides is not called missing" "$OUTPUT" "t1nk33r.active-window: plugin not installed"

assert_eq "custom screensaver text is copied" "$(cat "$XDG_CONFIG_HOME/omarchy/branding/screensaver.txt")" \
    "$(cat "$HC/branding/screensaver.txt" 2>/dev/null)"
assert_eq "Omarchy's stock about art is not" "absent" "$([[ -e $HC/branding/about.txt ]] && echo present || echo absent)"
assert_contains "and that is reported" "$OUTPUT" "branding/about.txt: Omarchy's stock art"

assert_eq "a plain post-update hook lands in haseen's hook dir, executable" "yes" \
    "$([[ -x $HC/hooks/post-update.d/notify-done ]] && echo yes || echo no)"
assert_eq "a plain theme-set hook file too" "yes" "$([[ -x $HC/hooks/theme-set ]] && echo yes || echo no)"
assert_eq "a hook that runs Omarchy commands does not" "absent" \
    "$([[ -e $HC/hooks/post-update.d/setup-agent.hook ]] && echo present || echo absent)"
assert_contains "it is reported" "$OUTPUT" "hooks/post-update.d/setup-agent.hook: runs Omarchy commands"
assert_contains "an event haseen does not fire is reported" "$OUTPUT" "hooks/battery-low.d/beep: haseen has no battery-low event"
assert_eq "samples stay behind silently" "absent" "$([[ -e $HC/hooks/post-boot.d ]] && echo present || echo absent)"
assert_not_contains "samples are not reported" "$OUTPUT" "weather.sample"

assert_eq "a user theme with colors.toml is copied whole" "yes" \
    "$([[ -f $HC/themes/dune/colors.toml && -f $HC/themes/dune/backgrounds/1-dune.txt ]] && echo yes || echo no)"
assert_contains "a theme without colors.toml is reported" "$OUTPUT" "themes/no-colors: no colors.toml"
assert_eq "and not copied" "absent" "$([[ -e $HC/themes/no-colors ]] && echo present || echo absent)"

binds="$(cat "$HY/bindings.lua" 2>/dev/null)"
assert_contains "o.bind becomes haseen.bind" "$binds" 'haseen.bind("SUPER + H", "Move focus left", hl.dsp.focus({ direction = "left" }))'
assert_contains "binds inside loops are translated" "$binds" '	haseen.bind("SUPER + SHIFT + " .. key'
assert_contains "o.launch becomes haseen.launch" "$binds" 'haseen.bind("SUPER + SHIFT + Z", "Browser", haseen.launch("zen-browser"))'
assert_contains "{ launch = … } becomes haseen.launch" "$binds" "haseen.bind(\"SUPER + SHIFT + F\", \"File manager\", haseen.launch('flea --gui'))"
assert_contains "plain hl.* statements are kept whole" "$binds" 'end, { description = "Cycle windows (raise)" })'
assert_contains "unbinds are kept" "$binds" 'hl.unbind("SUPER + J") -- toggle split -> focus down'
assert_not_contains "no Omarchy helper is left to call" "$(grep -v '^[[:space:]]*--' "$HY/bindings.lua")" "o."
assert_not_contains "no Omarchy command is left to run" "$(grep -v '^[[:space:]]*--' "$HY/bindings.lua")" "omarchy"
assert_not_contains "Omarchy's commented-out examples are not carried" "$binds" "your-server"
for bind in 'SUPER + D", "Apps menu", "omarchy-menu' 'SUPER + ALT + SHIFT + F' 'SUPER + SHIFT + B", "Docs"' 'o.window("com.example.picker"'; do
    assert_contains "skipped and reported: $bind" "$OUTPUT" "$bind"
done
assert_contains "the skipped bind is marked where it was" "$binds" '-- haseen import omarchy skipped (runs an Omarchy command): o.bind("SUPER + D"'

localf="$(cat "$HY/local.lua" 2>/dev/null)"
assert_contains "input settings go to local.lua" "$localf" 'accel_profile = "flat",'
assert_contains "with the comment above them" "$localf" "-- Flat acceleration, natural scrolling."
assert_contains "with g3Up none, the hl.* 3-finger-up gesture carries over" "$localf" 'hl.dispatch(hl.dsp.event("expose.window-overview:toggle"))'
assert_contains "o.launch_on_start becomes a start handler" "$localf" \
    'hl.on("hyprland.start", function() hl.exec_cmd(haseen.launch("syncthing --no-browser")) end)'
assert_contains "an Omarchy start command is reported" "$OUTPUT" 'autostart.lua: runs an Omarchy command: o.exec_on_start("omarchy-cmd-first-run")'
assert_not_contains "a looknfeel.lua of only comments adds nothing" "$localf" "looknfeel.lua"
assert_contains "monitors carry over" "$(cat "$HY/monitors.lua" 2>/dev/null)" 'hl.monitor({ output = "", mode = "preferred"'
assert_contains "Omarchy's entry file is reported, not copied" "$OUTPUT" "hypr/hyprland.lua: not imported"
for f in bindings local monitors; do
    capture luac -p "$HY/$f.lua"
    assert_status "$f.lua is valid Lua" 0 "$STATUS"
done

# --- a re-run changes nothing -------------------------------------------------
before="$(haseen_sum)"
capture "$REPO/bin/haseen-import-omarchy"
assert_status "re-run succeeds without --merge" 0 "$STATUS"
assert_contains "re-run says shell.json already holds the import" "$OUTPUT" "already holds the import"
assert_eq "re-run changes no haseen file" "$before" "$(haseen_sum)"
assert_eq "re-run leaves no backups" "0" "$(find "$HC" "$HY" -name '*.bak-*' | wc -l)"
capture "$REPO/bin/haseen-import-omarchy" --merge
assert_eq "re-run with --merge changes nothing either" "$before" "$(haseen_sum)"

# --- an existing shell.json: refused without --merge, merged with it ----------
import_sandbox omarchy-import-merge
mkdir -p "$HC" "$HY"
user_json='{"bar":{"position":"bottom"},"plugins":{"haseen.clock":{"settings":{"format":"HH:mm:ss"}}},"services":["haseen.lock"]}'
printf '%s\n' "$user_json" >"$HC/shell.json"
# What an earlier hand carry-over left: the same input block and monitors.lua.
cp "$XDG_CONFIG_HOME/hypr.omarchy-20261006/monitors.lua" "$HY/monitors.lua"
printf -- '-- carried by hand\nhl.config({\n  input = {\n    accel_profile = "flat",\n    touchpad = {\n      natural_scroll = true,\n    },\n  },\n})\n' >"$HY/local.lua"
local_before="$(cat "$HY/local.lua")"
before="$(haseen_sum)"
capture "$REPO/bin/haseen-import-omarchy"
assert_status "a shell.json with settings is refused without --merge" 1 "$STATUS"
assert_contains "the refusal names --merge" "$OUTPUT" "--merge"
assert_eq "a refusal writes nothing at all" "$before" "$(haseen_sum)"

before_omarchy="$(omarchy_sum)"
capture "$REPO/bin/haseen-import-omarchy" --merge --dry-run
assert_dry_pure "merge" "$OUTPUT"
assert_eq "a merge dry run writes nothing" "$before" "$(haseen_sum)"

capture "$REPO/bin/haseen-import-omarchy" --merge
assert_status "--merge succeeds" 0 "$STATUS"
assert_eq "values the user set win" '["bottom","HH:mm:ss"]' "$(cfg '[.bar.position, .plugins["haseen.clock"].settings.format]')"
assert_eq "keys the user had not set are imported" '["HH\n—\nmm","haseen.workspaces",150]' \
    "$(cfg '[.plugins["haseen.clock"].settings.verticalFormat, .bar.left[0], .plugins["haseen.idle"].settings.screensaverAfter]')"
assert_eq "service plugins are added to the user's own services list" \
    '["haseen.lock","io.github.sumanthmukkala.hot-corners","expose.window-overview"]' "$(cfg .services)"
backups=("$HC"/shell.json.bak-*)
assert_eq "the old shell.json is kept as a timestamped backup" "$(jq -c . <<<"$user_json")" "$(jq -c . "${backups[0]}" 2>/dev/null)"
assert_eq "monitors.lua already carried over is left alone" \
    "$(cat "$XDG_CONFIG_HOME/hypr.omarchy-20261006/monitors.lua")" "$(cat "$HY/monitors.lua")"
assert_eq "and gets no backup" "0" "$(find "$HY" -name 'monitors.lua.bak-*' | wc -l)"
assert_eq "local.lua keeps the user's text first" "$local_before" "$(head -n "$(wc -l <<<"$local_before")" "$HY/local.lua")"
assert_eq "an input block already present is not added twice" "1" "$(grep -c 'accel_profile' "$HY/local.lua")"
assert_contains "only what is new is appended" "$(cat "$HY/local.lua")" "hl.gesture({"
lbackups=("$HY"/local.lua.bak-*)
assert_eq "local.lua is backed up before the append" "$local_before" "$(cat "${lbackups[0]}" 2>/dev/null)"
assert_eq "a merge leaves Omarchy's files alone" "$before_omarchy" "$(omarchy_sum)"

before="$(haseen_sum)"
capture "$REPO/bin/haseen-import-omarchy" --merge
assert_eq "a second --merge changes nothing" "$before" "$(haseen_sum)"

# --- legacy ids, other built-ins, explicit sources ----------------------------
sandbox omarchy-import-ids
src="$SANDBOX/elsewhere"
mkdir -p "$src"
printf '%s\n' '{"bar":{"layout":{"right":[{"id":"omaconnect"},{"id":"omarchy.power"},{"id":"omarchy.spacer","size":12},{"id":"omarchy.power"},{"id":"io.github.heroesofcode.omagesture","middleButton":"paste","g4Up":"none","pinchSpeed":2}]}}}' >"$src/shell.json"
capture "$REPO/bin/haseen-import-omarchy" --from "$src" --state "$SANDBOX/none"
assert_status "--from reads another directory" 0 "$STATUS"
assert_eq "single-segment ids get haseen's omarchy. namespace; power maps to battery" \
    '["omarchy.omaconnect","haseen.battery","haseen.gestures"]' "$(jq -c .bar.right "$XDG_CONFIG_HOME/haseen/shell.json")"
assert_eq "an omagesture setting the port lacks is dropped, the rest kept" '{"g4Up":"none"}' \
    "$(jq -c '.plugins["haseen.gestures"].settings' "$XDG_CONFIG_HOME/haseen/shell.json")"
assert_contains "and reported" "$OUTPUT" 'setting middleButton = "paste" is not supported by haseen.gestures'
assert_contains "a key haseen.gestures does not declare is reported" "$OUTPUT" "setting pinchSpeed is not a haseen.gestures setting"
assert_contains "a dropped built-in with settings is reported" "$OUTPUT" "omarchy.spacer: Omarchy built-in with no haseen equivalent"
assert_contains "a duplicate is reported" "$OUTPUT" "haseen.battery is already in the bar"
assert_contains "a missing Hyprland backup is reported" "$OUTPUT" "no $XDG_CONFIG_HOME/hypr.omarchy-* backup found"
assert_eq "no weather entry without the weather widget" "null" "$(jq -c '.plugins["haseen.weather"]' "$XDG_CONFIG_HOME/haseen/shell.json")"
capture "$REPO/bin/haseen-import-omarchy" --from "$SANDBOX/missing"
assert_status "a missing Omarchy dir fails" 1 "$STATUS"
capture "$REPO/bin/haseen-import-omarchy" --bogus
assert_status "an unknown argument is a usage error" 2 "$STATUS"

# --- an omagesture g3Up gesture: the hl.* 3-finger-up gesture would duplicate it
import_sandbox omarchy-import-g3up
jq '(.bar.layout.right[] | select(.id == "io.github.heroesofcode.omagesture")).g3Up = "menu"' \
    "$IMPORT_FIXTURE/omarchy/shell.json" >"$XDG_CONFIG_HOME/omarchy/shell.json"
capture "$REPO/bin/haseen-import-omarchy"
assert_status "import with an omagesture g3Up succeeds" 0 "$STATUS"
assert_eq "g3Up carries over to haseen.gestures" '"menu"' "$(cfg '.plugins["haseen.gestures"].settings.g3Up')"
localf="$(cat "$HY/local.lua" 2>/dev/null)"
assert_not_contains "the duplicate 3-finger-up hl.gesture is not carried" "$(grep -v '^[[:space:]]*--' "$HY/local.lua")" "hl.gesture"
assert_contains "its place is marked" "$localf" "haseen import omarchy skipped (haseen.gestures already binds 3-finger up (g3Up = menu))"
assert_contains "and it is reported" "$OUTPUT" "input.lua: haseen.gestures already binds 3-finger up (g3Up = menu): hl.gesture({"
assert_contains "the input settings still carry over" "$localf" 'accel_profile = "flat",'
