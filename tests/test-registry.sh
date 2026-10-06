# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# The plugin registry and the lockfile: install from a registry, pin it, have a
# second machine resolve the same thing, and bump the pin on update. Everything
# runs against local git repositories; nothing reaches the network.
sandbox registry
# No network in tests: the built-in source is removed, and everything below
# runs against local git repositories.
export HASEEN_REGISTRY_DEFAULT=""

export GIT_AUTHOR_NAME=haseen GIT_AUTHOR_EMAIL=haseen@example.invalid
export GIT_COMMITTER_NAME=haseen GIT_COMMITTER_EMAIL=haseen@example.invalid
# The sandbox stubs git (it is a state-changing binary in a dry run); the real
# one is needed to build the fixtures and to clone them.
GIT=/usr/bin/git
rm -f "$SANDBOX/stubs/git"

plugin_files() { # DIR ID [VERSION]
    mkdir -p "$1"
    cat >"$1/manifest.json" <<EOF
{ "schemaVersion": 1, "id": "$2", "name": "Widget", "version": "${3:-1.0.0}",
  "description": "a fixture plugin", "kinds": ["bar-widget"],
  "entry": { "bar-widget": "Widget.qml" }, "permissions": [] }
EOF
    printf 'import QtQuick\nItem { property string pluginId; property var settings; property var screen }\n' \
        >"$1/Widget.qml"
}

# A plugin repository: the plugin at its root, and one in a subdirectory, so
# both the plain and the monorepo (`path`) shapes are covered.
repo="$SANDBOX/repos/widgets"
mkdir -p "$repo"
plugin_files "$repo" alice.load
plugin_files "$repo/packages/alice.clock" alice.clock
(
    cd "$repo" || exit 1
    $GIT init -q -b main .
    $GIT add -A
    $GIT commit -qm "first"
)
first_commit="$($GIT -C "$repo" rev-parse HEAD)"

# A registry: a git repository with one JSON file per plugin under plugins/.
registry="$SANDBOX/repos/registry"
mkdir -p "$registry/plugins"
cat >"$registry/plugins/alice.load.json" <<EOF
{ "id": "alice.load", "name": "Load", "repo": "$repo", "description": "load average" }
EOF
cat >"$registry/plugins/alice.clock.json" <<EOF
{ "id": "alice.clock", "name": "Clock", "repo": "$repo", "path": "packages/alice.clock",
  "description": "a clock in a monorepo" }
EOF
(
    cd "$registry" || exit 1
    $GIT init -q -b main .
    $GIT add -A
    $GIT commit -qm "index"
)

# The default source is the DMS registry on the network; point the test at the
# local one instead by adding it and ignoring what the default indexes.
mkdir -p "$XDG_CONFIG_HOME/haseen"
printf '{"sources":[{"name":"local","url":"%s"}]}\n' "$registry" >"$XDG_CONFIG_HOME/haseen/registries.json"

# --- sources and search -------------------------------------------------------
capture haseen plugin registry list
assert_not_contains "the built-in source is off in tests" "$OUTPUT" "dms-plugin-registry"
assert_contains "and the one that was added" "$OUTPUT" "local"

capture haseen plugin registry add local2 "ssh://nope"
assert_status "a URL that is not https or git@host is refused" 1 "$STATUS"
capture haseen plugin registry add local2 "https://user:token@example.invalid/x.git"
assert_status "credentials in a URL are refused" 1 "$STATUS"
capture haseen plugin registry add dms "https://example.invalid/x.git"
assert_status "the built-in source cannot be shadowed" 1 "$STATUS"

capture haseen plugin search clock
assert_status "search finds an indexed plugin" 0 "$STATUS"
assert_contains "by its description" "$OUTPUT" "monorepo"
assert_contains "and names the source" "$OUTPUT" "local"
capture haseen plugin search nothing-like-this
assert_status "a query that matches nothing exits 1" 1 "$STATUS"

# --- install ------------------------------------------------------------------
capture haseen plugin install alice.load --dry-run --yes
assert_contains "a dry run plans the clone" "$OUTPUT" "git clone"
assert_eq "and installs nothing" "" "$(ls "$XDG_CONFIG_HOME/haseen/plugins" 2>/dev/null || true)"

capture haseen plugin install alice.load --yes
assert_status "a registry plugin installs" 0 "$STATUS"
assert_eq "it lands where the shell looks" 0 \
    "$([[ -e $XDG_CONFIG_HOME/haseen/plugins/alice.load/manifest.json ]] && echo 0 || echo 1)"
assert_eq "the lockfile pins the commit it took" "$first_commit" \
    "$(jq -r '.plugins["alice.load"].commit' "$XDG_CONFIG_HOME/haseen/plugins.lock.json")"
assert_eq "and the repository it came from" "$repo" \
    "$(jq -r '.plugins["alice.load"].repo' "$XDG_CONFIG_HOME/haseen/plugins.lock.json")"
assert_eq "the lockfile has a version" 1 "$(jq -r .version "$XDG_CONFIG_HOME/haseen/plugins.lock.json")"

capture haseen plugin install alice.clock --yes
assert_status "a plugin inside a monorepo installs" 0 "$STATUS"
assert_eq "its subdirectory is what landed" "alice.clock" \
    "$(jq -r .id "$XDG_CONFIG_HOME/haseen/plugins/alice.clock/manifest.json")"
assert_eq "the pin records the subdirectory" "packages/alice.clock" \
    "$(jq -r '.plugins["alice.clock"].path' "$XDG_CONFIG_HOME/haseen/plugins.lock.json")"
assert_eq "both plugins share one checkout" 1 \
    "$(find "$XDG_CONFIG_HOME/haseen/plugins/.repos" -mindepth 1 -maxdepth 1 | wc -l)"

capture haseen plugin search clock
assert_contains "search marks what is installed" "$OUTPUT" "(installed)"

# A plugin that does not validate is not kept: upstream enables foreign QML
# without checking anything, haseen refuses it.
bad="$SANDBOX/repos/bad"
mkdir -p "$bad"
printf '{ "schemaVersion": 1, "id": "bad.plugin", "kinds": ["bar-widget"] }\n' >"$bad/manifest.json"
(
    cd "$bad" || exit 1
    $GIT init -q -b main .
    $GIT add -A
    $GIT commit -qm x
)
capture haseen plugin install "$bad" --yes
assert_status "a plugin that fails the schema is refused" 1 "$STATUS"
assert_contains "and says why" "$OUTPUT" "does not validate"
assert_eq "nothing is left behind" "" "$(compgen -G "$XDG_CONFIG_HOME/haseen/plugins/*bad*" || true)"
assert_eq "and it is not in the lockfile" "null" \
    "$(jq -r '.plugins["bad"] // "null"' "$XDG_CONFIG_HOME/haseen/plugins.lock.json")"

# --- update -------------------------------------------------------------------
plugin_files "$repo" alice.load 1.1.0
(
    cd "$repo" || exit 1
    $GIT add -A
    $GIT commit -qm "second"
)
second_commit="$($GIT -C "$repo" rev-parse HEAD)"

capture haseen plugin update alice.load --yes
assert_status "update succeeds" 0 "$STATUS"
assert_contains "it reports the move" "$OUTPUT" "${first_commit:0:12} -> ${second_commit:0:12}"
assert_eq "the lockfile now pins the new commit" "$second_commit" \
    "$(jq -r '.plugins["alice.load"].commit' "$XDG_CONFIG_HOME/haseen/plugins.lock.json")"
assert_eq "and the installed copy moved with it" "1.1.0" \
    "$(jq -r .version "$XDG_CONFIG_HOME/haseen/plugins/alice.load/manifest.json")"
capture haseen plugin update alice.load --yes
assert_contains "a second update has nothing to do" "$OUTPUT" "already at"

capture haseen plugin update not.installed --yes
assert_status "updating something unpinned is an error" 1 "$STATUS"

# --- a second machine ---------------------------------------------------------
# Same lockfile, empty plugin directory: restore must produce the same commits.
lock="$(cat "$XDG_CONFIG_HOME/haseen/plugins.lock.json")"
export HOME="$SANDBOX/home2" XDG_CONFIG_HOME="$SANDBOX/home2/.config" \
    XDG_STATE_HOME="$SANDBOX/home2/.local/state" XDG_CACHE_HOME="$SANDBOX/home2/.cache"
mkdir -p "$XDG_CONFIG_HOME/haseen"
printf '%s\n' "$lock" >"$XDG_CONFIG_HOME/haseen/plugins.lock.json"

capture haseen plugin restore --yes
assert_status "the second machine restores from the lockfile" 0 "$STATUS"
assert_eq "both plugins are there" 2 \
    "$(find "$XDG_CONFIG_HOME/haseen/plugins" -mindepth 1 -maxdepth 1 -not -name '.*' | wc -l)"
assert_eq "at the pinned commit, not the newest" "1.1.0" \
    "$(jq -r .version "$XDG_CONFIG_HOME/haseen/plugins/alice.load/manifest.json")"
capture haseen plugin lock
assert_eq "its lockfile is the same one" "$(jq -S . <<<"$lock")" "$(jq -S . <<<"$OUTPUT")"

# A lockfile that claims an id the repository does not declare is refused.
jq '.plugins["alice.wrong"] = .plugins["alice.load"]' <<<"$lock" >"$XDG_CONFIG_HOME/haseen/plugins.lock.json"
capture haseen plugin restore --yes
assert_status "a mismatched id fails the restore" 1 "$STATUS"
assert_contains "and says which plugin the lockfile claims" "$OUTPUT" "is not the plugin 'alice.wrong'"

printf '%s\n' "$lock" >"$XDG_CONFIG_HOME/haseen/plugins.lock.json"
mkdir -p "$XDG_CONFIG_HOME/haseen/plugins/stray"
capture haseen plugin restore --prune --yes
assert_eq "--prune removes what the lockfile does not mention" 1 \
    "$([[ -e $XDG_CONFIG_HOME/haseen/plugins/stray ]] && echo 0 || echo 1)"

# --- lockfile invariants ------------------------------------------------------
for bad_lock in \
    '{"version":99,"plugins":{},"repositories":{}}' \
    '{"version":1,"plugins":{"../escape":{"repo":"https://example.invalid/x.git","path":"","commit":"'"$second_commit"'"}},"repositories":{}}' \
    '{"version":1,"plugins":{"ok":{"repo":"https://example.invalid/x.git","path":"../../etc","commit":"'"$second_commit"'"}},"repositories":{}}' \
    '{"version":1,"plugins":{"ok":{"repo":"https://example.invalid/x.git","path":"","commit":"abc"}},"repositories":{}}' \
    '{"version":1,"plugins":{},"repositories":{"https://user:token@example.invalid/x.git":"'"$second_commit"'"}}'; do
    printf '%s\n' "$bad_lock" >"$XDG_CONFIG_HOME/haseen/plugins.lock.json"
    capture haseen plugin restore --yes
    assert_status "a lockfile that breaks an invariant is refused" 1 "$STATUS"
done

# --- uninstall ----------------------------------------------------------------
printf '%s\n' "$lock" >"$XDG_CONFIG_HOME/haseen/plugins.lock.json"
capture haseen plugin uninstall alice.clock --yes
assert_status "uninstall succeeds" 0 "$STATUS"
assert_eq "the files are gone" 1 \
    "$([[ -e $XDG_CONFIG_HOME/haseen/plugins/alice.clock ]] && echo 0 || echo 1)"
assert_eq "and so is the pin" "null" \
    "$(jq -r '.plugins["alice.clock"] // "null"' "$XDG_CONFIG_HOME/haseen/plugins.lock.json")"
assert_eq "the other plugin is untouched" 0 \
    "$([[ -e $XDG_CONFIG_HOME/haseen/plugins/alice.load ]] && echo 0 || echo 1)"
capture haseen plugin uninstall ../escape --yes
assert_status "an id that could escape the plugin dir is refused" 1 "$STATUS"
