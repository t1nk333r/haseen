# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# `haseen plugin install` with a forge browse URL that names the plugin's
# directory (https://github.com/O/R/tree/REF/DIR): the repository, the
# subdirectory and the ref are taken from the link. git's url.insteadOf maps
# the https URL onto a local repository, so nothing reaches the network.
sandbox plugin-tree-url
export HASEEN_REGISTRY_DEFAULT=""
export GIT_AUTHOR_NAME=haseen GIT_AUTHOR_EMAIL=haseen@example.invalid
export GIT_COMMITTER_NAME=haseen GIT_COMMITTER_EMAIL=haseen@example.invalid
GIT=/usr/bin/git
rm -f "$SANDBOX/stubs/git"

repo="$SANDBOX/repos/dms-plugins"
mkdir -p "$repo/plugins/virtualkeyboard" "$repo/plugins/other"
dms_plugin() { # DIR ID
    printf '{"id":"%s","name":"%s","version":"1.0.0","type":"daemon","component":"./D.qml"}\n' "$2" "$2" >"$1/plugin.json"
    printf 'import QtQuick\nItem {}\n' >"$1/D.qml"
}
dms_plugin "$repo/plugins/virtualkeyboard" virtualKeyboard
dms_plugin "$repo/plugins/other" otherPlugin
(
    cd "$repo" || exit 1
    $GIT init -q -b main .
    $GIT add -A
    $GIT commit -qm first
    $GIT checkout -q -b feature/new
    printf '{"id":"virtualKeyboard","name":"virtualKeyboard","version":"2.0.0","type":"daemon","component":"./D.qml"}\n' >plugins/virtualkeyboard/plugin.json
    $GIT commit -qam second
    $GIT tag -a v2 -m v2
    $GIT checkout -q main
)
main_commit="$($GIT -C "$repo" rev-parse main)"
feature_commit="$($GIT -C "$repo" rev-parse feature/new)"
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0="url.$repo.insteadOf" GIT_CONFIG_VALUE_0="https://example.invalid/alice/dms-plugins"
lock="$XDG_CONFIG_HOME/haseen/plugins.lock.json"

capture haseen plugin install https://example.invalid/alice/dms-plugins/tree/main/plugins/virtualkeyboard --dry-run
assert_status "a tree URL dry run succeeds" 0 "$STATUS"
assert_contains "it clones the repository, not the browse URL" "$OUTPUT" "git clone --quiet https://example.invalid/alice/dms-plugins "
assert_contains "and links the named directory" "$OUTPUT" "/plugins/virtualkeyboard $XDG_CONFIG_HOME/haseen/plugins/virtualkeyboard"
assert_dry_pure "tree URL dry run" "$OUTPUT"
assert_eq "a dry run installs nothing" "" "$(ls "$XDG_CONFIG_HOME/haseen/plugins" 2>/dev/null || true)"

capture haseen plugin install https://example.invalid/alice/dms-plugins/tree/main/plugins/virtualkeyboard --yes
assert_status "a plugin in a subdirectory installs from its tree URL" 0 "$STATUS"
assert_eq "the subdirectory is what landed" virtualKeyboard \
    "$(jq -r .id "$XDG_CONFIG_HOME/haseen/plugins/virtualkeyboard/plugin.json")"
assert_eq "the pin records the repository" https://example.invalid/alice/dms-plugins "$(jq -r .plugins.virtualkeyboard.repo "$lock")"
assert_eq "the pin records the subdirectory" plugins/virtualkeyboard "$(jq -r .plugins.virtualkeyboard.path "$lock")"
assert_eq "the default branch installs at its head" "$main_commit" "$(jq -r .plugins.virtualkeyboard.commit "$lock")"
capture haseen plugin validate dms.virtual-keyboard
assert_status "it validates under its adapted id" 0 "$STATUS"

capture haseen plugin install https://example.invalid/alice/dms-plugins/tree/feature/new/plugins/virtualkeyboard --yes
assert_status "a branch name with a slash resolves" 0 "$STATUS"
assert_eq "another branch is pinned where it points" "$feature_commit" "$(jq -r .plugins.virtualkeyboard.commit "$lock")"
assert_eq "and its files are the ones installed" 2.0.0 \
    "$(jq -r .version "$XDG_CONFIG_HOME/haseen/plugins/virtualkeyboard/plugin.json")"

capture haseen plugin install https://example.invalid/alice/dms-plugins/-/tree/v2/plugins/other --yes
assert_status "a GitLab-style tree URL on a tag installs" 0 "$STATUS"
assert_eq "the tag's commit is pinned" "$feature_commit" "$(jq -r .plugins.other.commit "$lock")"
assert_eq "both plugins share one checkout" 1 \
    "$(find "$XDG_CONFIG_HOME/haseen/plugins/.repos" -mindepth 1 -maxdepth 1 | wc -l)"

capture haseen plugin install https://example.invalid/alice/dms-plugins/tree/nope/plugins/other --yes
assert_status "an unknown ref is refused" 1 "$STATUS"
assert_contains "and says so" "$OUTPUT" "has no branch or tag at the start of 'nope/plugins/other'"
capture haseen plugin install https://example.invalid/alice/dms-plugins/tree/main/plugins/other --path plugins/virtualkeyboard --yes
assert_status "a --path that contradicts the URL is refused" 1 "$STATUS"
capture haseen plugin install https://example.invalid/alice/dms-plugins/tree/main/../../etc --yes
assert_status "a directory that climbs out is refused" 1 "$STATUS"
