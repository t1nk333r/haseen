# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# haseen's answers to Omarchy's menu, package, plugin, network, notification,
# OSD, plymouth, power, refresh and reminder commands (plan 093). The plugin
# commands must never touch ~/.config/omarchy/plugins or
# ~/.config/DankMaterialShell/plugins (CLAUDE.md).

OMA="$HASEEN_PATH/omarchy"

# This group's commands with a script of their own.
SCRIPTS="omarchy-menu omarchy-menu-clipboard omarchy-menu-emoji
omarchy-menu-emoji-insert omarchy-menu-file omarchy-menu-herdr-keybindings
omarchy-menu-images omarchy-menu-input omarchy-menu-plugin omarchy-menu-share
omarchy-menu-tmux-keybindings omarchy-mise-install omarchy-monitor-state
omarchy-network-password omarchy-network-qr omarchy-network-speedtest
omarchy-network-status omarchy-notification-battery omarchy-notification-dismiss
omarchy-notification-send omarchy-notification-time omarchy-notification-wait
omarchy-notification-weather omarchy-openclaw-onboard omarchy-osd omarchy-pkg-add
omarchy-pkg-aur-accessible omarchy-pkg-aur-add omarchy-pkg-drop omarchy-pkg-missing
omarchy-pkg-present omarchy-plugin-add omarchy-plugin-catalog omarchy-plugin-clone
omarchy-plugin-enable omarchy-plugin-list omarchy-plugin-remove omarchy-plugin-update
omarchy-plugin-validate omarchy-plymouth-current omarchy-plymouth-reset
omarchy-plymouth-set omarchy-plymouth-set-by-theme omarchy-plymouth-switcher
omarchy-power-present omarchy-refresh-config omarchy-refresh-herdr
omarchy-refresh-tmux omarchy-reminder"

# fake_tree CMD... — a haseen tree whose bin/ holds a recording CMD for each
# name: it logs its name and arguments in brackets to $CALLS. The rest of
# share/haseen is the real one.
fake_tree() {
    FAKE="$SANDBOX/fake"
    mkdir -p "$FAKE/bin" "$FAKE/share/haseen"
    local d t
    for d in "$HASEEN_PATH"/*; do ln -s "$d" "$FAKE/share/haseen/${d##*/}"; done
    export CALLS="$SANDBOX/calls"
    : >"$CALLS"
    for t in "$@"; do
        printf '#!/bin/sh\n{ printf %%s "${0##*/}"; for a in "$@"; do printf " [%%s]" "$a"; done; echo; } >>"$CALLS"\n' >"$FAKE/bin/$t"
        chmod +x "$FAKE/bin/$t"
    done
}
# fake NAME ARGS... — run an Omarchy command against the fake tree.
fake() { env HASEEN_PATH="$FAKE/share/haseen" "$OMA/bin/$1" "${@:2}"; }
calls() { cat "$CALLS"; }

# --- every script answers --help without doing anything ----------------------
sandbox omarchy-menu-help
bad=""
for name in $SCRIPTS; do
    capture "$OMA/bin/$name" --help </dev/null
    [[ $STATUS == 0 && -n $OUTPUT && $OUTPUT != *STUB-CALLED* ]] || bad+="$name($STATUS) "
done
assert_eq "every script of the group prints its usage for --help, running nothing" "" "$bad"
bad=""
for name in $SCRIPTS; do
    [[ -f $OMA/bin/$name && ! -L $OMA/bin/$name && -x $OMA/bin/$name ]] || bad+="$name "
done
assert_eq "every script of the group is an executable file of its own" "" "$bad"

# --- the plugin commands: haseen's directory only ----------------------------
sandbox omarchy-menu-plugins
OMP="$XDG_CONFIG_HOME/omarchy/plugins"
DMS="$XDG_CONFIG_HOME/DankMaterialShell/plugins"
HP="$XDG_CONFIG_HOME/haseen/plugins"
mkdir -p "$OMP/weather/.git" "$DMS/DmsThing" "$HP/me.notes"
printf '%s\n' '{"schemaVersion":1,"id":"weather","name":"Weather","version":"1.0.0","kinds":["bar-widget","bar"],"entryPoints":{"barWidget":"W.qml","bar":"B.qml"}}' >"$OMP/weather/manifest.json"
touch "$OMP/weather/W.qml" "$OMP/weather/B.qml"
printf '%s\n' '{"id":"dmsThing","name":"Dms thing","component":"./Widget.qml"}' >"$DMS/DmsThing/plugin.json"
touch "$DMS/DmsThing/Widget.qml"
printf '%s\n' '{"schemaVersion":1,"id":"me.notes","name":"Notes","version":"1.0.0","kinds":["bar-widget"],"entry":{"bar-widget":"Widget.qml"}}' >"$HP/me.notes/manifest.json"
printf 'import QtQuick\nItem {}\n' >"$HP/me.notes/Widget.qml"
ln -s "$OMP/weather" "$HP/omarchy-link"
printf '%s\n' '{"bar":{"left":["haseen.workspaces","me.notes"],"center":["haseen.clock"],"right":["haseen.tray","haseen.audio","haseen.network"]}}' >"$XDG_CONFIG_HOME/haseen/shell.json"
stub notify-send 'exit 0'

# foreign_state — every entry, link target and file digest under Omarchy's and
# DMS's plugin directories.
foreign_state() {
    local root
    for root in "$OMP" "$DMS"; do
        (cd "$root" && find . -printf '%p %y %m %s %l\n' | sort && find . -type f -exec sha256sum {} + | sort)
    done
}
before="$(foreign_state)"

capture "$OMA/bin/omarchy-plugin-catalog"
assert_status "the catalog lists plugins" 0 "$STATUS"
assert_eq "a haseen built-in is first-party, with its bar widget's path" \
    "true $HASEEN_PATH/shell/plugins/haseen.clock/Widget.qml" \
    "$(jq -r '.[] | select(.id == "haseen.clock") | "\(.firstParty) \(.barWidgetPath)"' <<<"$OUTPUT")"
assert_eq "an Omarchy plugin is read from Omarchy's directory, its bar kind marked unsupported" \
    'omarchy false ["bar"]' \
    "$(jq -rc '.[] | select(.id == "omarchy.weather") | "\(.origin) \(.firstParty) \(.unsupportedKinds)"' <<<"$OUTPUT")"
assert_eq "DMS and user plugins are listed with their origin" "dms user" \
    "$(jq -r '[.[] | select(.id == "dms.dms-thing" or .id == "me.notes") | .origin] | join(" ")' <<<"$OUTPUT")"

capture "$OMA/bin/omarchy-plugin-list" --json
assert_status "plugin list --json" 0 "$STATUS"
assert_eq "enabled follows the bar for widgets and the enabled flag for others" \
    "haseen.calculator=true haseen.clock=true haseen.media=false me.notes=true" \
    "$(jq -r '[.[] | select(.id | IN("haseen.clock", "haseen.media", "haseen.calculator", "me.notes"))
        | "\(.id)=\(.enabled)"] | sort | join(" ")' <<<"$OUTPUT")"
assert_eq "in Omarchy's shape" "true true" \
    "$(jq -r '.[] | select(.id == "haseen.clock") | "\(.canDisable) \(.firstParty)"' <<<"$OUTPUT")"
capture "$OMA/bin/omarchy-plugin-list"
assert_contains "plugin list prints haseen's table" "$OUTPUT" "ORIGIN"
capture "$OMA/bin/omarchy-plugin-list" --bogus
assert_status "an unknown option fails as Omarchy's" 1 "$STATUS"

for id in omarchy.weather weather dms.dms-thing DmsThing haseen.clock; do
    capture "$OMA/bin/omarchy-plugin-remove" "$id" --yes
    assert_status "removing $id is refused" 1 "$STATUS"
    assert_contains "removing $id says why" "$OUTPUT" "not available under haseen"
    assert_contains "and the haseen way" "$OUTPUT" "haseen plugin disable"
done
capture "$OMA/bin/omarchy-plugin-remove" me.notes --dry-run
assert_status "a dry-run removal" 0 "$STATUS"
assert_contains "plans the backup move" "$OUTPUT" "DRYRUN: mv -T -- $HP/me.notes $HP/.me.notes.bak."
assert_dry_pure "plugin-remove" "$OUTPUT"
assert_eq "and moves nothing" "yes" "$([[ -f $HP/me.notes/manifest.json ]] && echo yes)"
capture "$OMA/bin/omarchy-plugin-remove" omarchy-link --yes
assert_status "a link of yours into Omarchy's directory is removed" 0 "$STATUS"
assert_contains "it is unlinked" "$OUTPUT" "Unlinked omarchy-link."
assert_eq "the link is gone, Omarchy's copy stays" "gone kept" \
    "$([[ -e $HP/omarchy-link || -L $HP/omarchy-link ]] || echo gone) $([[ -f $OMP/weather/manifest.json ]] && echo kept)"
capture "$OMA/bin/omarchy-plugin-remove" me.notes --yes
assert_status "a plain folder of yours is removed" 0 "$STATUS"
assert_contains "and backed up" "$OUTPUT" "Backup at: $HP/.me.notes.bak."
assert_eq "into a hidden backup the shell does not load" "1 gone" \
    "$(compgen -G "$HP/.me.notes.bak.*" | wc -l) $([[ -e $HP/me.notes ]] || echo gone)"
assert_eq "it was turned off first" "false" \
    "$(jq '(.bar.left // []) | index("me.notes") != null' "$XDG_CONFIG_HOME/haseen/shell.json")"
capture "$OMA/bin/omarchy-plugin-remove" --yes </dev/null
assert_status "no id without a terminal fails" 1 "$STATUS"
assert_contains "asking for one" "$OUTPUT" "a plugin-id is required"
capture "$OMA/bin/omarchy-plugin-remove" nothere --yes
assert_contains "an unknown id is not installed" "$OUTPUT" "is not installed"

capture "$OMA/bin/omarchy-plugin-clone" omarchy.nope
assert_status "cloning an unknown built-in fails" 1 "$STATUS"
capture "$OMA/bin/omarchy-plugin-clone" haseen.clock --dry-run
assert_status "a dry-run clone" 0 "$STATUS"
assert_contains "plans the copy into haseen's directory" "$OUTPUT" "DRYRUN: cp -aL -- $HASEEN_PATH/shell/plugins/haseen.clock/."
assert_contains "named as Omarchy names a clone" "$OUTPUT" '"name": "My Clock"'
assert_dry_pure "plugin-clone" "$OUTPUT"
assert_eq "and copies nothing" "none" "$([[ -e $HP/haseen.clock ]] || echo none)"
capture "$OMA/bin/omarchy-plugin-clone" omarchy.clock </dev/null
assert_status "cloning Omarchy's clock clones haseen's" 0 "$STATUS"
assert_contains "and switches to the copy" "$OUTPUT" "switched to haseen.clock"
assert_eq "the copy keeps the built-in's id and is yours" "haseen.clock My Clock" \
    "$(jq -r '"\(.id) \(.name)"' "$HP/haseen.clock/manifest.json")"
capture "$OMA/bin/omarchy-plugin-list" --json
assert_eq "the copy replaces the built-in" "user haseen.clock false" \
    "$(jq -r '.[] | select(.id == "haseen.clock") | "\(.origin) \(.clonedFrom) \(.firstParty)"' <<<"$OUTPUT")"
capture "$OMA/bin/omarchy-plugin-clone" haseen.clock
assert_contains "a second clone is refused" "$OUTPUT" "already exists"
capture "$OMA/bin/omarchy-plugin-remove" haseen.clock --yes
assert_status "removing the copy" 0 "$STATUS"
assert_contains "gives the built-in back" "$OUTPUT" "Restored haseen.clock."
assert_eq "still on, as a built-in again" "builtin true" \
    "$("$OMA/bin/omarchy-plugin-list" --json | jq -r '.[] | select(.id == "haseen.clock") | "\(.origin) \(.enabled)"')"

capture "$OMA/bin/omarchy-plugin-update" omarchy.weather
assert_status "a plugin in Omarchy's directory is never pulled" 1 "$STATUS"
assert_contains "the user is pointed at git" "$OUTPUT" "git -C $OMP/weather pull"
capture "$OMA/bin/omarchy-plugin-update" haseen.clock
assert_contains "a built-in updates with haseen" "$OUTPUT" "haseen update"
capture "$OMA/bin/omarchy-plugin-update" --dry-run
assert_status "updating everything" 0 "$STATUS"
assert_contains "leaves Omarchy's checkouts alone, saying so" "$OUTPUT" "left alone"
assert_contains "and updates haseen's pins" "$OUTPUT" "no pinned plugins"
assert_dry_pure "plugin-update" "$OUTPUT"

capture "$OMA/bin/omarchy-plugin-add" </dev/null
assert_status "add without a URL or a terminal" 1 "$STATUS"
assert_contains "asks for a URL" "$OUTPUT" "a git URL is required"
capture "$OMA/bin/omarchy-plugin-add" --bogus
assert_status "add rejects an unknown option" 1 "$STATUS"
capture "$OMA/bin/omarchy-plugin-add" https://example.invalid/acme/weather.git </dev/null
assert_contains "add never clones unconfirmed" "$OUTPUT" "refusing to continue without confirmation"
capture "$OMA/bin/omarchy-plugin-add" https://example.invalid/acme/weather.git --yes --dry-run
assert_contains "a dry-run add plans the link in haseen's directory" "$OUTPUT" "DRYRUN: ln -sfn $HP/.repos/"
assert_dry_pure "plugin-add" "$OUTPUT"
config="$(cat "$XDG_CONFIG_HOME/haseen/shell.json")"
capture "$OMA/bin/omarchy-plugin-enable" haseen.media left --dry-run
assert_contains "a dry-run enable plans haseen's placement" "$OUTPUT" "Enabled and moved haseen.media"
assert_dry_pure "plugin-enable" "$OUTPUT"
assert_eq "and leaves shell.json as it was" "$config" "$(cat "$XDG_CONFIG_HOME/haseen/shell.json")"

assert_eq "Omarchy's and DMS's plugin directories are untouched" "$before" "$(foreign_state)"

# validate: Omarchy's schema, Omarchy's messages and exit codes.
v="$SANDBOX/validate"
mkdir -p "$v/ok" "$v/reserved" "$v/linked" "$v/nokind"
printf '%s\n' '{"schemaVersion":1,"id":"acme.weather","name":"W","version":"1","kinds":["bar-widget"],"entryPoints":{"barWidget":"W.qml"}}' >"$v/ok/manifest.json"
touch "$v/ok/W.qml"
sed 's/acme.weather/omarchy.weather/' "$v/ok/manifest.json" >"$v/reserved/manifest.json"
cp "$v/ok/manifest.json" "$v/ok/W.qml" "$v/linked/"
ln -s /etc/hostname "$v/linked/leak"
printf '%s\n' '{"schemaVersion":1,"id":"acme.n","name":"N","version":"1","kinds":["panel"],"entryPoints":{}}' >"$v/nokind/manifest.json"
capture "$OMA/bin/omarchy-plugin-validate" "$v/ok"
assert_status "a valid plugin validates" 0 "$STATUS"
capture "$OMA/bin/omarchy-plugin-validate" "$v/reserved"
assert_contains "the omarchy.* namespace is reserved" "$OUTPUT" "omarchy-plugin-validate: plugin id 'omarchy.weather' uses the reserved omarchy.* namespace"
capture "$OMA/bin/omarchy-plugin-validate" "$v/linked"
assert_contains "symlinks are refused" "$OUTPUT" "symlinks are not allowed"
capture "$OMA/bin/omarchy-plugin-validate" "$v/nokind"
assert_status "a kind without its entry point" 1 "$STATUS"
assert_contains "names the entry point" "$OUTPUT" "requires an 'entryPoints.panel'"
capture "$OMA/bin/omarchy-plugin-validate" "$v/none"
assert_contains "a missing folder" "$OUTPUT" "plugin folder not found"

# --- enable: haseen plugin enable, then haseen bar add/move ------------------
sandbox omarchy-menu-enable
fake_tree haseen-plugin-enable haseen-bar-add haseen-bar-move
mkdir -p "$XDG_CONFIG_HOME/haseen" "$XDG_CONFIG_HOME/omarchy/plugins/weather"
printf '%s\n' '{"bar":{"left":["haseen.workspaces"],"center":["haseen.clock"],"right":["haseen.tray","haseen.audio","haseen.network"]}}' >"$XDG_CONFIG_HOME/haseen/shell.json"
printf '%s\n' '{"schemaVersion":1,"id":"weather","name":"Weather","version":"1","kinds":["bar"],"entryPoints":{"bar":"B.qml"}}' >"$XDG_CONFIG_HOME/omarchy/plugins/weather/manifest.json"
capture fake omarchy-plugin-enable omarchy.battery
assert_eq "an Omarchy built-in id means haseen's" "haseen-plugin-enable [haseen.battery]" "$(calls)"
assert_contains "and says so as Omarchy does" "$OUTPUT" "Enabled haseen.battery"
: >"$CALLS"
capture fake omarchy-plugin-enable haseen.battery right --after haseen.audio --dry-run
assert_eq "--after places it before the next widget" \
    "haseen-bar-add [haseen.battery] [right] [--before] [haseen.network] [--dry-run]" "$(calls)"
: >"$CALLS"
capture fake omarchy-plugin-enable haseen.battery --section right --index 1
assert_eq "--index places it before the Nth widget" \
    "haseen-bar-add [haseen.battery] [right] [--before] [haseen.audio]" "$(calls)"
: >"$CALLS"
capture fake omarchy-plugin-enable haseen.clock right --after haseen.network
assert_eq "a widget in the bar is moved, to the end after the last one" \
    "haseen-plugin-enable [haseen.clock]
haseen-bar-move [haseen.clock] [right]" "$(calls)"
capture fake omarchy-plugin-enable omarchy.weather
assert_status "a whole-bar plugin is refused" 1 "$STATUS"
assert_contains "as haseen has none" "$OUTPUT" "is a bar"
capture fake omarchy-plugin-enable haseen.clock middle
assert_contains "a bad section is refused" "$OUTPUT" "section must be left, center, or right"
capture fake omarchy-plugin-enable acme.nothere
assert_status "an unknown plugin" 1 "$STATUS"
capture fake omarchy-plugin-enable
assert_contains "an id is required" "$OUTPUT" "plugin id is required"

# --- add, update and the plugin menu against recording commands ---------------
sandbox omarchy-menu-plugin-calls
fake_tree haseen-plugin-install haseen-plugin-update haseen-menu haseen-config-terminal haseen-notification-send
printf '#!/bin/sh\nprintf "Clock\\thaseen.clock\\n"\n' >"$FAKE/bin/haseen-menu-select"
chmod +x "$FAKE/bin/haseen-menu-select"
mkdir -p "$XDG_CONFIG_HOME/haseen"
printf '%s\n' '{"version":1,"plugins":{"pinned.one":{"repo":"https://example.invalid/p.git","path":"","commit":"0000000000000000000000000000000000000000"}},"repositories":{}}' >"$XDG_CONFIG_HOME/haseen/plugins.lock.json"
capture fake omarchy-plugin-add https://example.invalid/acme/weather.git --enable --yes
assert_eq "add installs into haseen's directory" \
    "haseen-plugin-install [https://example.invalid/acme/weather.git] [--enable] [--yes]" "$(calls)"
: >"$CALLS"
capture fake omarchy-plugin-add https://example.invalid/acme/weather.git --dry-run
assert_eq "add passes --dry-run and enables nothing unasked" \
    "haseen-plugin-install [https://example.invalid/acme/weather.git] [--dry-run]" "$(calls)"
: >"$CALLS"
capture fake omarchy-plugin-update pinned.one -y
assert_eq "update one pinned plugin" "haseen-plugin-update [pinned.one] [--yes]" "$(calls)"
: >"$CALLS"
capture fake omarchy-plugin-update
assert_eq "update without an id updates every pin" "haseen-plugin-update [--all]" "$(calls)"
: >"$CALLS"
for verb in enable disable remove; do
    capture fake omarchy-menu-plugin "$verb"
    assert_eq "the $verb menu is haseen's list" "haseen-menu [setup.plugin.$verb]" "$(calls)"
    : >"$CALLS"
done
capture fake omarchy-menu-plugin clone
assert_eq "clone copies the picked built-in in a terminal" \
    "haseen-config-terminal [--] [$OMA/bin/omarchy-plugin-clone] [haseen.clock] [--edit]" "$(calls)"
: >"$CALLS"
capture fake omarchy-menu-plugin clone --dry-run
assert_contains "a dry-run clone menu plans the pick" "$OUTPUT" "DRYRUN: $FAKE/share/haseen/../../bin/haseen-menu-select Clone plugin"
assert_eq "and opens nothing" "" "$(calls)"
capture fake omarchy-menu-plugin nope
assert_status "an unknown verb" 1 "$STATUS"

# --- reminders ----------------------------------------------------------------
sandbox omarchy-menu-reminder
fake_tree haseen-reminder-set haseen-reminder-clear
now=$(date +%s)
cat >"$FAKE/bin/haseen-reminder-show" <<SHOW
#!/bin/sh
[ "\$1" = --json ] || { echo "haseen-reminder-show \$*" >>"$SANDBOX/calls"; exit 0; }
printf '%s\n' '[{"unit":"haseen-reminder-5m-1","at":$((now + 300)),"atTime":"x","remainingSeconds":300,"message":"Your 5 minutes are up"},{"unit":"haseen-reminder-10m-1","at":$((now + 600)),"atTime":"y","remainingSeconds":600,"message":"Tea"}]'
SHOW
chmod +x "$FAKE/bin/haseen-reminder-show"
capture fake omarchy-reminder 5 Check the oven
assert_eq "minutes and a message set a haseen reminder" "haseen-reminder-set [5] [Check] [the] [oven]" "$(calls)"
: >"$CALLS"
capture fake omarchy-reminder clear --dry-run
assert_eq "clear passes --dry-run" "haseen-reminder-clear [--dry-run]" "$(calls)"
for bad in 0 abc 2000; do
    capture fake omarchy-reminder "$bad"
    assert_status "omarchy-reminder $bad is refused" 1 "$STATUS"
done
capture fake omarchy-reminder show --json
assert_status "show --json" 0 "$STATUS"
assert_eq "in Omarchy's shape" "2 true 2 reminders" "$(jq -r '"\(.count) \(.active) \(.tooltip)"' <<<"$OUTPUT")"
assert_eq "a default message reads as none, labelled by its minutes" \
    "5 5-min reminder  haseen-reminder-5m-1.timer" \
    "$(jq -r '.reminders[0] | "\(.minutes) \(.label) \(.message) \(.timer)"' <<<"$OUTPUT")"
assert_eq "a message is the label" "Tea Tea" "$(jq -r '.reminders[1] | "\(.label) \(.message)"' <<<"$OUTPUT")"
# The fixture's clock was read before the command's: a loaded machine may
# tick a few seconds in between.
rem="$(jq -r '.reminders[1].remaining' <<<"$OUTPUT")"
[[ $rem =~ ^(10m|9m\ [0-9]+s)$ ]] && _pass || _fail "the time left is in Omarchy's format (10m, less a tick): $rem"
capture fake omarchy-reminder show --bogus
assert_status "show takes only --json" 1 "$STATUS"
sandbox omarchy-menu-reminder-dry
capture "$OMA/bin/omarchy-reminder" 5 Tea --dry-run
assert_contains "a dry-run reminder plans haseen's timer" "$OUTPUT" "DRYRUN: systemd-run --user"
assert_dry_pure "reminder set" "$OUTPUT"
capture "$OMA/bin/omarchy-reminder" clear --dry-run
assert_dry_pure "reminder clear" "$OUTPUT"

# --- herdr keybindings, OpenClaw onboarding -----------------------------------
sandbox omarchy-menu-herdr
fake_tree haseen-menu-select
stub herdr 'printf "%s\n" "# [keys]" "# prefix = \"ctrl+b\"" "# split_vertical = \"prefix+v\""'
printf '[keys]\nprefix = "ctrl+a"\n' >"$SANDBOX/herdr.toml"
capture "$OMA/bin/omarchy-menu-herdr-keybindings" --print --config "$SANDBOX/herdr.toml"
assert_contains "the user config overrides herdr's default" "$OUTPUT" "PREFIX                           → CTRL + A"
assert_contains "actions are described" "$OUTPUT" "→ Split vertical"
capture fake omarchy-menu-herdr-keybindings "$SANDBOX/herdr.toml"
assert_eq "the list opens in haseen's menu, 40% of a 900 px fallback" \
    "haseen-menu-select [Herdr keybindings] [--width] [800] [--height] [360]" "$(calls)"

sandbox omarchy-menu-openclaw
capture "$OMA/bin/omarchy-openclaw-onboard" --dry-run
assert_contains "a dry run prints the wizard" "$OUTPUT" "DRYRUN: openclaw onboard --flow quickstart --install-daemon --skip-ui"
assert_dry_pure "openclaw-onboard" "$OUTPUT"
capture "$OMA/bin/omarchy-openclaw-onboard"
assert_contains "without OpenClaw, the haseen way to install it" "$OUTPUT" "haseen install app openclaw"
stub openclaw '[ "$1" = dashboard ] && echo "{\"ok\":true}"'
mkdir -p "$HOME/.openclaw" && echo '{}' >"$HOME/.openclaw/openclaw.json"
capture "$OMA/bin/omarchy-openclaw-onboard"
assert_status "set up already: nothing to do" 0 "$STATUS"
assert_contains "and says so" "$OUTPUT" "already set up"

# --- packages and power ---------------------------------------------------------
sandbox omarchy-menu-pkg
export HASEEN_SYSROOT="$SANDBOX/root"
mkdir -p "$HASEEN_SYSROOT/var/lib/pacman/local/foo-1.0-1"
for c in "present foo:0" "present foo bar:1" "present:0" "missing foo:1" "missing foo bar:0" "missing:1"; do
    read -r -a words <<<"${c%:*}"
    capture "$OMA/bin/omarchy-pkg-${words[0]}" "${words[@]:1}"
    assert_status "omarchy-pkg-${c%:*}" "${c##*:}" "$STATUS"
done
fake_tree haseen-install haseen-remove
capture fake omarchy-pkg-add foo --dry-run
assert_eq "pkg-add installs through haseen" "haseen-install [package] [--yes] [--dry-run] [foo]" "$(calls)"
: >"$CALLS"
capture fake omarchy-pkg-add bar
assert_status "a package still missing afterwards fails" 1 "$STATUS"
: >"$CALLS"
capture fake omarchy-pkg-aur-add bar --dry-run
assert_eq "pkg-aur-add goes through haseen's source order" "haseen-install [aur] [--yes] [--dry-run] [bar]" "$(calls)"
: >"$CALLS"
capture fake omarchy-pkg-drop foo bar
assert_eq "pkg-drop removes only what is installed" "haseen-remove [package] [--yes] [foo]" "$(calls)"
unset HASEEN_SYSROOT
ps="$SANDBOX/power"
mkdir -p "$ps/AC" "$ps/BAT0"
echo Mains >"$ps/AC/type" && echo 1 >"$ps/AC/online"
echo Battery >"$ps/BAT0/type" && echo 1 >"$ps/BAT0/online"
OMARCHY_POWER_SUPPLY_PATH="$ps" capture "$OMA/bin/omarchy-power-present"
assert_status "on mains power" 0 "$STATUS"
echo 0 >"$ps/AC/online"
OMARCHY_POWER_SUPPLY_PATH="$ps" capture "$OMA/bin/omarchy-power-present"
assert_status "on battery" 1 "$STATUS"

sandbox omarchy-menu-mise
stub mise 'exit 0'
capture "$OMA/bin/omarchy-mise-install" node --dry-run
assert_dry_pure "mise-install" "$OUTPUT"
assert_eq "a dry run writes no wrapper" "none" "$([[ -e $HOME/.local/bin/node ]] || echo none)"
capture "$OMA/bin/omarchy-mise-install" node
assert_status "mise-install writes the wrapper" 0 "$STATUS"
assert_contains "which installs and runs through mise" "$(cat "$HOME/.local/bin/node")" 'exec mise x "node" -- "node"'
assert_eq "executable" "yes" "$([[ -x $HOME/.local/bin/node ]] && echo yes)"
capture "$OMA/bin/omarchy-mise-install" node ../evil
assert_status "a path is not a command name" 1 "$STATUS"

# --- notifications, OSD, the small menus ----------------------------------------
sandbox omarchy-menu-notify
fake_tree haseen-notification-send haseen-notification-wait haseen-notification-dismiss haseen-shell-ipc \
    haseen-tmux-keybinds haseen-share-clipboard haseen-refresh haseen-plymouth-set
printf '#!/bin/sh\necho "Battery 50%%"\n' >"$FAKE/bin/haseen-battery-status"
chmod +x "$FAKE/bin/haseen-battery-status"
capture fake omarchy-notification-time
assert_contains "the time as a low toast" "$(calls)" "haseen-notification-send [-u] [low] ["
assert_contains "with the week" "$(calls)" "Week "
: >"$CALLS"
capture fake omarchy-notification-battery
assert_eq "the battery line as a low toast" "haseen-notification-send [-u] [low] [Battery 50%]" "$(calls)"
: >"$CALLS"
capture fake omarchy-notification-wait 5
assert_eq "a bare timeout becomes --timeout" "haseen-notification-wait [--timeout] [5]" "$(calls)"
capture fake omarchy-notification-wait soon
assert_status "a timeout is a number" 1 "$STATUS"
: >"$CALLS"
capture fake omarchy-notification-dismiss
assert_status "dismiss needs a summary" 1 "$STATUS"
capture fake omarchy-notification-dismiss Update
assert_eq "dismiss by summary" "haseen-notification-dismiss [Update]" "$(calls)"
: >"$CALLS"
for pair in clipboard:menu-clipboard emoji:menu-emoji weather:notification-weather; do
    capture fake "omarchy-${pair#*:}"
    assert_eq "omarchy-${pair#*:} toggles haseen's panel" "haseen-shell-ipc [panel] [toggle] [haseen.${pair%%:*}]" "$(calls)"
    : >"$CALLS"
done
capture fake omarchy-osd -m Volume -p 40 --dry-run
assert_eq "an OSD message becomes a low toast" "haseen-notification-send [--dry-run] [-u] [low] [-p] [Volume 40%]" "$(calls)"
capture fake omarchy-osd
assert_status "an OSD needs a message or a level" 1 "$STATUS"
: >"$CALLS"
capture fake omarchy-menu-tmux-keybindings -p tmux.conf
assert_eq "a bare config path becomes --config" "haseen-tmux-keybinds [--print] [--config] [tmux.conf]" "$(calls)"
: >"$CALLS"
capture fake omarchy-menu-share clipboard --dry-run
assert_eq "share the clipboard" "haseen-share-clipboard [--dry-run]" "$(calls)"
: >"$CALLS"
capture fake omarchy-refresh-config hypr/hyprland.lua --yes
assert_eq "refresh-config maps a path to haseen refresh" "haseen-refresh [hyprland] [--yes]" "$(calls)"
capture fake omarchy-refresh-config waybar/config.jsonc
assert_status "a config haseen does not ship" 1 "$STATUS"
: >"$CALLS"
capture fake omarchy-plymouth-reset --dry-run
assert_eq "plymouth-reset is haseen's splash" "haseen-plymouth-set [--dry-run]" "$(calls)"
: >"$CALLS"
capture fake omarchy-plymouth-set-by-theme catppuccin --dry-run
assert_eq "plymouth-set-by-theme colours it from a haseen theme" "haseen-plymouth-set [--theme] [catppuccin] [--dry-run]" "$(calls)"
capture fake omarchy-plymouth-set-by-theme no-such-theme
assert_contains "an unknown theme" "$OUTPUT" "no haseen theme no-such-theme"

sandbox omarchy-menu-dry
stub wl-copy 'echo "STUB-CALLED: wl-copy" >&2; exit 97'
capture "$OMA/bin/omarchy-menu-emoji-insert" "x" --dry-run
assert_contains "emoji-insert copies through run" "$OUTPUT" "DRYRUN: wl-copy"
assert_dry_pure "menu-emoji-insert" "$OUTPUT"
for cmd in "omarchy-refresh-tmux --dry-run" "omarchy-refresh-herdr --dry-run" \
    "omarchy-refresh-config tmux/tmux.conf --dry-run" "omarchy-notification-time --dry-run"; do
    read -r -a words <<<"$cmd"
    capture "$OMA/bin/${words[0]}" "${words[@]:1}" </dev/null
    assert_dry_pure "$cmd" "$OUTPUT"
done
stub ip 'exit 1'
capture "$OMA/bin/omarchy-network-status"
assert_eq "no default route is disconnected" "disconnected" "$(cut -f1 <<<"$OUTPUT")"
