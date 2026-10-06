# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# Starter widgets C: haseen.imagepicker, haseen.background and haseen.agents,
# the three panels ported from Omarchy's image-picker, background and agents
# plugins. Manifests validate, the declared permissions match what the code
# actually does, nothing polls, colours come from Theme only, the background
# panel drives the existing `haseen theme bg` state instead of painting a
# second wallpaper, and the two pure JS modules plus the /proc scanner run for
# real (the scanner against a fixture tree, the JS under the Qt JS engine).

SHELL_DIR="$HASEEN_PATH/shell"
PLUGINS="$SHELL_DIR/plugins"
QML_BIN=${QML_BIN:-/usr/lib/qt6/bin/qml}
IDS=(haseen.imagepicker haseen.background haseen.agents)
DIRS=()
for id in "${IDS[@]}"; do DIRS+=("$PLUGINS/$id"); done

# --- manifests and entry contract ---------------------------------------------
sandbox widgets-c
capture haseen plugin validate "${IDS[@]}"
assert_status "widgets-c validate" 0 "$STATUS"
for id in "${IDS[@]}"; do
    assert_contains "$id validates" "$OUTPUT" "ok: $id (builtin:"
done
assert_not_contains "no plugin asks for network" "$OUTPUT" "warning:"
assert_dry_pure "plugin validate" "$OUTPUT"

for id in "${IDS[@]}"; do
    assert_eq "$id is a panel and nothing else" "panel" "$(jq -r '.kinds | join(" ")' "$PLUGINS/$id/manifest.json")"
    assert_eq "$id entry is Panel.qml" "Panel.qml" "$(jq -r '.entry.panel' "$PLUGINS/$id/manifest.json")"
    assert_eq "$id debugIpc defaults off" "false" "$(jq -r '.settings.debugIpc.default' "$PLUGINS/$id/manifest.json")"
    # Every entry root takes the three contract properties (architecture 5.2).
    entry="$(cat "$PLUGINS/$id/Panel.qml")"
    assert_contains "$id declares pluginId" "$entry" "property string pluginId"
    assert_contains "$id declares settings" "$entry" "property var settings: ({})"
    assert_contains "$id declares screen" "$entry" "property var screen: null"
    # Every setting the manifest declares has a type and a description, and
    # every settings.<key> the QML reads is declared.
    assert_eq "$id settings are typed and described" "" \
        "$(jq -r '.settings | to_entries[] | select((.value.type | not) or (.value.description | not)) | .key' "$PLUGINS/$id/manifest.json")"
    for key in $(grep -ohE 'settings\.[a-zA-Z]+' "$PLUGINS/$id"/*.qml | cut -d. -f2 | sort -u); do
        assert_eq "$id declares the setting $key it reads" "$key" \
            "$(jq -r --arg k "$key" '.settings | has($k) | if . then $k else "undeclared" end' "$PLUGINS/$id/manifest.json")"
    done
done

# --- permissions say what the code does ----------------------------------------
for id in "${IDS[@]}"; do
    perms="$(jq -r '.permissions | sort | join(" ")' "$PLUGINS/$id/manifest.json")"
    assert_eq "$id declares exactly exec and files:read" "exec files:read" "$perms"
    code="$(cat "$PLUGINS/$id"/*.qml)"
    assert_contains "$id really runs something (exec)" "$code" "Process {"
done
# files:read is earned: the picker grids decode image files, the background
# panel reads the theme name, the agents panel's helper reads /proc.
assert_contains "imagepicker reads image files" "$(cat "$PLUGINS/haseen.imagepicker/ImageCard.qml")" "Paths.fileUrl(card.path)"
assert_contains "background reads the theme name" "$(cat "$PLUGINS/haseen.background/Panel.qml")" 'Paths.userState + "/current/theme.name"'
assert_contains "agents reads /proc" "$(cat "$PLUGINS/haseen.agents/agents-list.sh")" 'proc="${HASEEN_SYSROOT:-}/proc"'
# Nothing here writes a file, asks the network or posts a notification, so no
# plugin may claim (or quietly use) those permissions.
assert_eq "no write, network or notification permission" "" \
    "$(jq -r '.permissions[]' "$PLUGINS"/haseen.{imagepicker,background,agents}/manifest.json | grep -xE 'files:write|network|network:local|notifications' || true)"
assert_eq "no network or notification API in the QML" "" \
    "$(grep -rnE 'XMLHttpRequest|Qt\.openUrlExternally|notify-send|Notification' "${DIRS[@]}" --include='*.qml' --include='*.js' || true)"
assert_eq "no privilege escalation" "" \
    "$(grep -rnE '\b(sudo|pkexec|run_root)\b' "${DIRS[@]}" || true)"
assert_eq "no plugin writes files of its own" "" \
    "$(grep -rnE 'writeAdapter|setText\(|blockWrite|FileView \{[^}]*write' "${DIRS[@]}" --include='*.qml' || true)"

# --- theme tokens and the no-polling rule ---------------------------------------
assert_eq "no hex colour literals" "" \
    "$(grep -rnE '#[0-9a-fA-F]{3,8}\b' "${DIRS[@]}" --include='*.qml' --include='*.js' || true)"
# Every colour binding is a Theme token, a property of the component, or the
# literal "transparent" (no colour of its own).
assert_eq "colours come from Theme only" "" \
    "$(grep -rnE '(^|[^a-zA-Z])color(\.[a-z]+)?:' "${DIRS[@]}" --include='*.qml' | grep -vE 'Theme\.|card\.|root\.|modelData\.|"transparent"' || true)"
assert_eq "panels use Theme.foreground, never the bar token" "" \
    "$(grep -rn 'Theme.barForeground' "${DIRS[@]}" --include='*.qml' || true)"
# Event-driven or nothing: these three panels scan when they open and when
# asked, so not one of them may own a Timer or a clock tick.
assert_eq "no Timer anywhere in the three plugins" "" \
    "$(grep -rln 'Timer *{' "${DIRS[@]}" --include='*.qml' || true)"
assert_eq "no clock ticks either" "" \
    "$(grep -rnE 'SystemClock|Qt\.callLater\(.*running|interval:' "${DIRS[@]}" --include='*.qml' || true)"
assert_eq "paths come from Paths, never a hard-coded home" "" \
    "$(grep -rnE '"/home/|\.local/state/haseen|\.config/haseen' "${DIRS[@]}" --include='*.qml' --include='*.js' || true)"

# --- the background panel is a picker, not a second wallpaper daemon -------------
# (the header comment names swaybg and the link, so the code greps skip comments)
code_lines() { grep -vE '^[^:]+:[0-9]+:[[:space:]]*//'; }
bg="$(cat "$PLUGINS/haseen.background/Panel.qml")"
assert_eq "background paints no wallpaper of its own" "" \
    "$(grep -nE 'PanelWindow|WlrLayershell|Quickshell\.screens|Variants \{|swaybg|ShellRoot' "$PLUGINS/haseen.background"/*.qml | code_lines || true)"
assert_contains "background lists through the CLI" "$bg" '[root.cli, "theme", "bg", "list"]'
assert_contains "background asks the CLI what is current" "$bg" '[root.cli, "theme", "bg", "current"]'
assert_contains "picking runs haseen theme bg set" "$bg" '[cli, "theme", "bg", "set", path]'
assert_contains "n runs haseen theme bg next" "$bg" '[root.cli, "theme", "bg", "next"]'
assert_contains "it says the service keeps drawing" "$bg" "haseen-background.service"
assert_eq "it never moves the background link itself" "" \
    "$(grep -nE 'ln -s|current/background' "$PLUGINS/haseen.background"/*.qml | code_lines || true)"
assert_contains "background keeps the Omarchy MIT notice" "$bg" "MIT, Copyright (c) David"

# --- the image picker scans directories and hands the path to a command ----------
ip="$(cat "$PLUGINS/haseen.imagepicker/Panel.qml")"
assert_contains "imagepicker scans with find" "$ip" '["find", "-L"]'
assert_contains "the default action is haseen theme bg set" "$ip" '[cli, "theme", "bg", "set"]'
# The tildes are the manifest's own text; the QML expands them, not the shell.
# shellcheck disable=SC2088
assert_eq "its default directories are the user's pictures and backgrounds" \
    "~/Pictures ~/Pictures/Wallpapers ~/.config/haseen/backgrounds" \
    "$(jq -r '.settings.directories.default | join(" ")' "$PLUGINS/haseen.imagepicker/manifest.json")"
assert_eq "an empty command means the default" "0" \
    "$(jq -r '.settings.command.default | length' "$PLUGINS/haseen.imagepicker/manifest.json")"
assert_contains "arguments are a list, never a shell string" "$ip" "Quickshell.execDetached(applyCommand(image.path))"
assert_eq "no shell is spawned to apply a pick" "" \
    "$(grep -nE '"(ba)?sh", *"-c"' "$PLUGINS/haseen.imagepicker"/*.qml || true)"
assert_contains "imagepicker keeps the Omarchy MIT notice" "$ip" "MIT, Copyright (c) David"

# --- the agents panel is read-only -----------------------------------------------
ag="$(cat "$PLUGINS/haseen.agents/Panel.qml")"
assert_contains "agents runs only its own scanner" "$ag" "command: [root.script].concat(root.commands)"
assert_eq "agents starts, stops and signals nothing" "" \
    "$(grep -nE 'execDetached|Hyprland\.dispatch|kill|pkill|systemctl' "$PLUGINS/haseen.agents"/*.qml || true)"
assert_eq "exactly one Process in the agents panel" "1" "$(grep -c 'Process {' <<<"$ag")"
assert_contains "r takes a new snapshot" "$ag" "Qt.Key_R"
assert_contains "agents keeps the Omarchy MIT notice" "$ag" "MIT, Copyright (c) David"
assert_contains "the scanner keeps the Omarchy MIT notice" "$(cat "$PLUGINS/haseen.agents/agents-list.sh")" "MIT, Copyright (c) David"

# --- agents-list.sh against a fixture /proc ---------------------------------------
scan="$PLUGINS/haseen.agents/agents-list.sh"
ticks="$(getconf CLK_TCK)"
export HASEEN_SYSROOT="$FIXTURES/agents"
before="$(find "$HASEEN_SYSROOT" -printf '%p %s %T@\n' | sort)"
capture bash "$scan"
assert_status "agents-list.sh succeeds" 0 "$STATUS"
assert_eq "every agent, longest pid order, with cwd and runtime" \
    "$(printf '1000\tclaude\t%s\t/srv/people/Projects/haseen\n1001\tcodex\t%s\t/srv/people/Projects/site\n1003\topencode\t%s\t/srv/people/Projects/site\n1006\taider\t%s\t/srv/work' \
        "$((100000 - 9000000 / ticks))" "$((100000 - 9990000 / ticks))" "$((100000 - 9999400 / ticks))" "$((100000 - 9500000 / ticks))")" \
    "$OUTPUT"
assert_eq "reading /proc changed nothing" "$before" "$(find "$HASEEN_SYSROOT" -printf '%p %s %T@\n' | sort)"
capture bash "$scan" claude opencode
assert_eq "only the named agents" "claude opencode" "$(cut -f2 <<<"$OUTPUT" | tr '\n' ' ' | sed 's/ $//')"
capture bash "$scan" nothing-runs-by-this-name
assert_status "an unknown name is not an error" 0 "$STATUS"
assert_eq "and lists nobody" "" "$OUTPUT"
export HASEEN_SYSROOT="$SANDBOX/empty"
mkdir -p "$SANDBOX/empty/proc"
capture bash "$scan"
assert_status "an empty /proc is not an error" 0 "$STATUS"
assert_eq "an empty /proc lists nobody" "" "$OUTPUT"
unset HASEEN_SYSROOT

# --- pure JS under the Qt JS engine -----------------------------------------------
if [[ -x $QML_BIN ]]; then
    harness="$SANDBOX/harness"
    mkdir -p "$harness"
    printf 'var tsv = %s;\n' \
        "$(printf '1000\tclaude\t10000\t/srv/people/Projects/haseen\n1001\tcodex\t100\t/srv/people/Projects/site\n9\t\t5\t/x\nnot a line\n1006\taider\t5000\t/srv/work\n' | jq -Rs .)" \
        >"$harness/data.js"
    cat >"$harness/Harness.qml" <<EOF
import QtQuick
import "file://$PLUGINS/haseen.imagepicker/Images.js" as I
import "file://$PLUGINS/haseen.agents/Agents.js" as A
import "data.js" as D
Item {
    function out(k, v) { console.warn("RESULT " + k + " " + JSON.stringify(v)); }
    Component.onCompleted: {
        out("extensions", I.EXTENSIONS);
        out("expand", [I.expandHome("~/Pictures", "/srv/u"), I.expandHome("\$HOME/x", "/srv/u"), I.expandHome("~", "/srv/u"), I.expandHome("/srv/pics", "/srv/u"), I.expandHome("  ", "/srv/u")]);
        out("dirs", I.directories(["~/Pictures", "~/Pictures", "relative", "", "/srv/pics"], "/srv/u"));
        out("label", [I.labelFor("/a/b/deep-blue_sea.jpg"), I.nameFor("/a/b/deep-blue_sea.jpg")]);
        const images = I.parseList("/a/one.png\n/b/one.png\n\n/c/two toned.JPG\nnot-a-path\n");
        out("images", images.map(i => i.path + "|" + i.label));
        out("filter", I.filter(images, "two TONED").map(i => i.file));
        out("filterPath", I.filter(images, "/a/").map(i => i.file));
        out("filterAll", I.filter(images, "   ").length);
        const rows = A.parse(D.tsv, "/srv/people");
        out("rows", rows.map(r => r.pid + ":" + r.name + ":" + r.seconds + ":" + r.project + ":" + r.where));
        out("durations", [A.duration(0), A.duration(45), A.duration(90), A.duration(3600), A.duration(11430), A.duration(200000)]);
        out("summary", [A.summary(rows), A.summary([]), A.summary(rows.slice(0, 1))]);
        Qt.quit();
    }
}
EOF
    qml_out="$(cd "$harness" && QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 timeout 30 "$QML_BIN" Harness.qml 2>&1 | sed -n 's/^.*RESULT //p')"
    r() { sed -n "s/^$1 //p" <<<"$qml_out"; }
    # The list the find scan is built from, so the panel asks for file types
    # Qt can actually decode.
    assert_eq "Images: the scanned extensions" \
        '["jpg","jpeg","png","webp","gif","bmp","avif"]' "$(r extensions)"
    assert_eq "Images: ~ and \$HOME expand" '["/srv/u/Pictures","/srv/u/x","/srv/u","/srv/pics",""]' "$(r expand)"
    assert_eq "Images: absolute, deduplicated directories" '["/srv/u/Pictures","/srv/pics"]' "$(r dirs)"
    assert_eq "Images: label and name" '["Deep Blue Sea","deep-blue_sea"]' "$(r label)"
    assert_eq "Images: first file of a name wins, sorted by label" \
        '["/a/one.png|One","/c/two toned.JPG|Two Toned"]' "$(r images)"
    assert_eq "Images: every word matches, any case" '["two toned.JPG"]' "$(r filter)"
    assert_eq "Images: the path matches too" '["one.png"]' "$(r filterPath)"
    assert_eq "Images: a blank query keeps all" "2" "$(r filterAll)"
    assert_eq "Agents: longest running first, bad lines dropped" \
        '["1000:claude:10000:haseen:~/Projects/haseen","1006:aider:5000:work:/srv/work","1001:codex:100:site:~/Projects/site"]' "$(r rows)"
    assert_eq "Agents: durations" '["0s","45s","1m","1h 00m","3h 10m","2d 7h"]' "$(r durations)"
    assert_eq "Agents: summary counts agents and projects" \
        '["3 agents · 3 projects","nothing running","1 agent · 1 project"]' "$(r summary)"
else
    echo "  skip: $QML_BIN not installed, Images.js/Agents.js not exercised" >&2
fi
