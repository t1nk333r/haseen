# shellcheck shell=bash
# haseen:covers bin/haseen-bar-edit
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# Plan 126: holding a bar widget starts the default coding agent on the
# widget's files. This covers where the command points it: a user plugin, a
# checkout named by ~/.config/haseen/source, or a built-in copied into the
# user's plugins; and the words the agent starts with. Nothing is started:
# every run here is --dry-run.
sandbox bar-edit
EDIT="$REPO/bin/haseen-bar-edit"
CONFIG="$HOME/.config/haseen"

# --- a user plugin is edited where it is ------------------------------------
mkdir -p "$CONFIG/plugins/haseen.demo"
printf '{"id":"haseen.demo","kinds":["bar-widget"]}\n' >"$CONFIG/plugins/haseen.demo/manifest.json"
capture "$EDIT" haseen.demo --dry-run
assert_status "a user plugin resolves" 0 "$STATUS"
assert_contains "in its own directory" "$OUTPUT" "cd '$CONFIG/plugins/haseen.demo'"
assert_contains "with the widget named in the request" "$OUTPUT" 'haseen bar widget "haseen.demo"'
assert_contains "and the validator named" "$OUTPUT" "haseen plugin validate haseen.demo"
assert_dry_pure "the user plugin dry run" "$OUTPUT"

# --- a checkout wins over the installed tree --------------------------------
mkdir -p "$SANDBOX/src/share/haseen/shell/plugins/haseen.clock"
printf '{"id":"haseen.clock","kinds":["bar-widget"]}\n' >"$SANDBOX/src/share/haseen/shell/plugins/haseen.clock/manifest.json"
printf '%s\n' "$SANDBOX/src" >"$CONFIG/source"
capture "$EDIT" haseen.clock --dry-run
assert_status "a checkout resolved" 0 "$STATUS"
assert_contains "from ~/.config/haseen/source" "$OUTPUT" "cd '$SANDBOX/src/share/haseen/shell/plugins/haseen.clock'"

# --- a built-in is copied into the user's plugins first ---------------------
rm -f "$CONFIG/source"
capture "$EDIT" haseen.battery --dry-run
assert_status "a built-in resolves" 0 "$STATUS"
assert_contains "by copying it into the user's plugins" "$OUTPUT" "cp -R $HASEEN_PATH/shell/plugins/haseen.battery $CONFIG/plugins/haseen.battery"
assert_contains "so the agent edits the copy" "$OUTPUT" "cd '$CONFIG/plugins/haseen.battery'"
assert_eq "and nothing was written by a dry run" "no" \
    "$([[ -e $CONFIG/plugins/haseen.battery ]] && echo yes || echo no)"

# --- the words can be replaced ----------------------------------------------
capture "$EDIT" haseen.demo --prompt "make it purple" --dry-run
assert_contains "a given prompt is passed through" "$OUTPUT" "--prompt 'make it purple'"

# --- an unknown id asks for nothing -----------------------------------------
capture "$EDIT" no.such.thing --dry-run
assert_status "an unknown plugin fails" 1 "$STATUS"
assert_contains "and says so" "$OUTPUT" "unknown plugin: no.such.thing"
