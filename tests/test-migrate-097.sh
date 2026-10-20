# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# tests/test-migrate-097.sh — plan 097's migration: a shell.json that uses
# t1nk33r.todoist or t1nk33r.omarr gets haseen.todoist / haseen.omarr in bar
# sections, `services` and `plugins`; idempotent, --dry-run pure, atomic,
# and the old plugin and state directories untouched. Fixture values only.

MIGRATION=1791560200-adopt-todoist-omarr.sh
run_migration() { # [ENV=VALUE...]
    capture env HASEEN_PATH="$HASEEN_PATH" HASEEN_MIGRATION="$MIGRATION" "$@" \
        bash -Eeuo pipefail "$HASEEN_PATH/migrations/$MIGRATION"
}
CFG() { printf '%s\n' "$XDG_CONFIG_HOME/haseen/shell.json"; }
put() { mkdir -p "$XDG_CONFIG_HOME/haseen" && printf '%s\n' "$1" >"$(CFG)"; }
q() { jq -c "$1" "$(CFG)"; }

assert_eq "the migration is shipped" yes "$([[ -r $HASEEN_PATH/migrations/$MIGRATION ]] && echo yes || echo no)"
assert_eq "the migration sorts after every earlier one" "$MIGRATION" \
    "$(find "$HASEEN_PATH/migrations" -name '17915602[0-9][0-9]-*.sh' -o -name '1791[0-5][0-9][0-9][0-9][0-9][0-9]-*.sh' | sed 's|.*/||' | sort | tail -n1)"

sandbox migrate-097
# The owner's layout, with fixture values: both widgets in bar.right, todoist
# also in the overflow panel, an own services list, omarr's settings with the
# `id` Omarchy's writer adds.
put '{"bar":{"right":["haseen.tray","t1nk33r.omarr","t1nk33r.todoist","haseen.clock"],"overflow":["t1nk33r.todoist"],"pinned":[]},
 "services":["haseen.pager","me.svc"],
 "plugins":{"t1nk33r.omarr":{"enabled":true,"settings":{"id":"t1nk33r.omarr","density":"compact","pollSeconds":15,"services":[{"id":"svc-1","kind":"sonarr","name":"Sonarr","url":"http://127.0.0.1:8989"}]}},
            "t1nk33r.todoist":{"enabled":true,"settings":{}},"me.x":{"enabled":false}}}'
# The old directories, which nothing may touch.
for d in "$XDG_CONFIG_HOME/haseen/plugins/t1nk33r.omarr" "$XDG_CONFIG_HOME/omarchy/plugins/t1nk33r.todoist" \
    "$HOME/.local/state/omarchy/omarr" "$HOME/.local/state/omarchy/t1nk33r.todoist"; do
    mkdir -p "$d" && printf 'fixture\n' >"$d/marker"
done
olds="$(find "$XDG_CONFIG_HOME/haseen/plugins" "$XDG_CONFIG_HOME/omarchy" "$HOME/.local/state/omarchy" -type f -exec sha256sum {} + | sort)"
before="$(cat "$(CFG)")"

run_migration DRY_RUN=true
assert_status "dry run exits 0" 0 "$STATUS"
assert_dry_pure "migration" "$OUTPUT"
assert_contains "dry run shows the write" "$OUTPUT" "DRYRUN: write"
assert_eq "dry run changes nothing" "$before" "$(cat "$(CFG)")"

run_migration
assert_status "migration exits 0" 0 "$STATUS"
assert_contains "migration says what it did" "$OUTPUT" "haseen.todoist and haseen.omarr"
assert_eq "bar.right: new ids in the old places" '["haseen.tray","haseen.omarr","haseen.todoist","haseen.clock"]' "$(q .bar.right)"
assert_eq "bar.overflow: re-pointed" '["haseen.todoist"]' "$(q .bar.overflow)"
assert_eq "services: own list kept, both services added" '["haseen.pager","me.svc","haseen.omarr","haseen.todoist"]' "$(q .services)"
assert_eq "plugins: old entries gone" '[]' "$(q '[.plugins | keys[] | select(startswith("t1nk33r."))]')"
assert_eq "plugins: omarr's settings moved, Omarchy's id dropped" \
    '{"enabled":true,"settings":{"density":"compact","pollSeconds":15,"services":[{"id":"svc-1","kind":"sonarr","name":"Sonarr","url":"http://127.0.0.1:8989"}]}}' \
    "$(q '.plugins["haseen.omarr"]')"
assert_eq "plugins: todoist moved" '{"enabled":true,"settings":{}}' "$(q '.plugins["haseen.todoist"]')"
assert_eq "the rest of shell.json survives" 'false' "$(q '.plugins["me.x"].enabled')"
assert_eq "the old plugin and state directories are untouched" "$olds" \
    "$(find "$XDG_CONFIG_HOME/haseen/plugins" "$XDG_CONFIG_HOME/omarchy" "$HOME/.local/state/omarchy" -type f -exec sha256sum {} + | sort)"
assert_eq "no staging file left behind" "" "$(find "$XDG_CONFIG_HOME/haseen" -maxdepth 1 -name 'shell.json.new*')"

after="$(cat "$(CFG)")"
run_migration
assert_status "re-run exits 0" 0 "$STATUS"
assert_eq "re-run is a no-op" "$after" "$(cat "$(CFG)")"
assert_eq "re-run says nothing" "" "$OUTPUT"

# No own services list: the default list is written out with the new ids,
# because a native service runs only from `services`.
put '{"bar":{"right":["t1nk33r.omarr"]}}'
run_migration
assert_eq "no own services: defaults plus the new service" \
    "$(jq -c '.services + ["haseen.omarr"]' "$HASEEN_PATH/default/shell.json")" "$(q .services)"

# The new id already there: one place, the new entry wins key by key.
put '{"bar":{"left":["haseen.todoist","t1nk33r.todoist"]},"services":["haseen.todoist"],
 "plugins":{"t1nk33r.todoist":{"enabled":false,"settings":{"a":1,"b":1}},"haseen.todoist":{"settings":{"b":2}}}}'
run_migration
assert_eq "an id once, at its first place" '["haseen.todoist"]' "$(q .bar.left)"
assert_eq "services not doubled" '["haseen.todoist"]' "$(q .services)"
assert_eq "the existing new entry wins" '{"enabled":false,"settings":{"a":1,"b":2}}' "$(q '.plugins["haseen.todoist"]')"

# Only in services, or only a plugins entry: renamed, nothing added.
put '{"services":["t1nk33r.omarr","haseen.pager"]}'
run_migration
assert_eq "services only: renamed in place" '["haseen.omarr","haseen.pager"]' "$(q .services)"
put '{"plugins":{"t1nk33r.todoist":{"enabled":true}}}'
run_migration
assert_eq "plugins only: moved, no services list invented" 'null|{"enabled":true}' "$(q .services)|$(q '.plugins["haseen.todoist"]')"

# Upstream ids are not the owner's and stay as they are.
put '{"bar":{"right":["io.github.luccast.omarr"]}}'
before="$(cat "$(CFG)")"
run_migration
assert_eq "no old id: the file is untouched" "$before" "$(cat "$(CFG)")"

printf '{"bar":' >"$(CFG)"
run_migration
assert_status "invalid shell.json: the migration fails" 1 "$STATUS"
assert_eq "invalid shell.json is left as it was" '{"bar":' "$(cat "$(CFG)")"

rm -f "$(CFG)"
run_migration
assert_status "no shell.json: exits 0" 0 "$STATUS"
assert_eq "no shell.json: none written" no "$([[ -e $(CFG) ]] && echo yes || echo no)"
