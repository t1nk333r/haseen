# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# dms:// links (the DankMaterialShell plugin gallery's Install button):
# haseen-plugin-url parses them, refuses what is not a plugin install from an
# https repository, shows the plugin, asks, and installs it through
# `haseen plugin install`. The shell layer makes it the dms:// handler without
# overriding a handler the user chose. git is a wrapper that serves
# https://example.invalid/<x> from local repositories: nothing reaches the
# network.
sandbox dms-url
export HASEEN_REGISTRY_DEFAULT=""
export GIT_AUTHOR_NAME=haseen GIT_AUTHOR_EMAIL=haseen@example.invalid
export GIT_COMMITTER_NAME=haseen GIT_COMMITTER_EMAIL=haseen@example.invalid
GIT=/usr/bin/git
REPOS="$SANDBOX/repos"
GIT_LOG="$SANDBOX/git.log"
stub git "for a; do case \$a in https://example.invalid/*) set -- \"\$@\" \"$REPOS/\${a#https://example.invalid/}\" ;; *) set -- \"\$@\" \"\$a\" ;; esac; shift; done
echo \"\$*\" >>\"$GIT_LOG\"
exec $GIT \"\$@\""
# Prompts read from the pipes below; the floating terminal is tested on its own.
export HASEEN_INLINE=1
LINK=dms://plugin/install/quickCapture

# A DMS plugin in a monorepo, the gallery's commonest shape.
mkdir -p "$REPOS/alice/dms-plugins/quickCapture"
printf '%s\n' '{"id":"quickCapture","name":"Quick Capture","version":"1.0.0","type":"widget","component":"./Widget.qml"}' \
    >"$REPOS/alice/dms-plugins/quickCapture/plugin.json"
printf 'import QtQuick\nItem {}\n' >"$REPOS/alice/dms-plugins/quickCapture/Widget.qml"
(cd "$REPOS/alice/dms-plugins" && $GIT init -q -b main . && $GIT add -A && $GIT commit -qm first)

# A registry in DMS's format: one JSON per plugin, the gallery's ids.
registry="$REPOS/registry"
mkdir -p "$registry/plugins"
entry() { # ID REPO [PATH]
    jq -n --arg id "$1" --arg repo "$2" --arg path "${3:-}" \
        '{id: $id, name: "Quick Capture", repo: $repo, author: "Alice",
          description: "Screenshot annotation and screen recording plugin."}
         + (if $path == "" then {} else {path: $path} end)' >"$registry/plugins/$1.json"
}
entry quickCapture https://example.invalid/alice/dms-plugins quickCapture
entry sshOnly git@example.invalid:alice/dms-plugins.git
entry localOnly "$REPOS/alice/dms-plugins"
entry plainHttp http://example.invalid/alice/dms-plugins
entry withToken https://alice:token@example.invalid/alice/dms-plugins
entry climbs https://example.invalid/alice/dms-plugins ../../etc
(cd "$registry" && $GIT init -q -b main . && $GIT add -A && $GIT commit -qm index)
mkdir -p "$XDG_CONFIG_HOME/haseen"
printf '{"sources":[{"name":"local","url":"%s"}]}\n' "$registry" >"$XDG_CONFIG_HOME/haseen/registries.json"
PLUGINS="$XDG_CONFIG_HOME/haseen/plugins"
LOCK="$XDG_CONFIG_HOME/haseen/plugins.lock.json"

# --- links that are refused before anything is fetched ----------------------
refused() { # LABEL LINK EXPECTED
    capture haseen-plugin-url "$2" --dry-run
    assert_status "$1: refused" 1 "$STATUS"
    assert_contains "$1: says why" "$OUTPUT" "$3"
}
refused "not dms" "https://danklinux.com/plugins" "not a dms:// link"
refused "a theme link" "dms://theme/install/catppuccin?flavor=mocha&accent=blue" "DankMaterialShell theme"
refused "another action" "dms://plugin/uninstall/quickCapture" "not a plugin install link"
refused "no id" "dms://plugin/install/" "not a plugin install link"
refused "a path in the id" "dms://plugin/install/../../etc" "not a plugin install link"
refused "an encoded slash" "dms://plugin/install/a%2Fb" "not a plugin install link"
refused "a shell metacharacter" 'dms://plugin/install/x;rm' "not a plugin install link"
assert_eq "no refused link fetched anything" "no" "$([[ -e $GIT_LOG ]] && echo yes || echo no)"

# --- registry entries that are refused ---------------------------------------
refused "an unknown id" "dms://plugin/install/nothingLikeThis" "no registry indexes a plugin nothingLikeThis"
refused "an ssh repository" "dms://plugin/install/sshOnly" "not an https git repository"
refused "a local repository" "dms://plugin/install/localOnly" "not an https git repository"
refused "plain http" "dms://plugin/install/plainHttp" "not an https git repository"
refused "credentials in the URL" "dms://plugin/install/withToken" "not an https git repository"
refused "a path that climbs out" "dms://plugin/install/climbs" "unsafe directory"
assert_not_contains "no refused entry was cloned" "$(cat "$GIT_LOG")" "alice/dms-plugins"

# --- the plan ----------------------------------------------------------------
capture haseen-plugin-url "$LINK?utm=gallery#top" --dry-run
assert_status "a gallery link dry-runs" 0 "$STATUS"
assert_dry_pure "dms url" "$OUTPUT"
assert_contains "the plan names the plugin" "$OUTPUT" "Quick Capture (quickCapture)"
assert_contains "and its author" "$OUTPUT" "Alice"
assert_contains "and the repository from the registry" "$OUTPUT" "https://example.invalid/alice/dms-plugins"
assert_contains "and the directory in it" "$OUTPUT" "quickCapture"
assert_contains "the install is planned" "$OUTPUT" "DRYRUN: git clone --quiet https://example.invalid/alice/dms-plugins"
assert_contains "and pinned" "$OUTPUT" "DRYRUN: pin quickCapture to https://example.invalid/alice/dms-plugins"
assert_eq "nothing installed" "" "$(ls "$PLUGINS" 2>/dev/null || true)"
capture haseen-plugin-url "$LINK/" --dry-run
assert_status "a trailing slash is accepted" 0 "$STATUS"
capture haseen plugin url "$LINK" --dry-run
assert_status "the router reaches it" 0 "$STATUS"

# --- confirm -----------------------------------------------------------------
rm -f "$GIT_LOG"
capture bash -c 'printf "n\n" | haseen-plugin-url "$1"' _ "$LINK"
assert_status "declined: exits 1" 1 "$STATUS"
assert_contains "and says so" "$OUTPUT" "nothing installed"
assert_eq "declined: nothing installed" "" "$(ls "$PLUGINS" 2>/dev/null || true)"
assert_not_contains "declined: the plugin was not cloned" "$(cat "$GIT_LOG")" "alice/dms-plugins"

capture bash -c 'printf "y\n" | haseen-plugin-url "$1"' _ "$LINK"
assert_status "accepted: installs" 0 "$STATUS"
assert_eq "the plugin's directory landed" "yes" \
    "$([[ -e $PLUGINS/quickCapture/plugin.json ]] && echo yes || echo no)"
assert_eq "the pin records the https repository" "https://example.invalid/alice/dms-plugins" \
    "$(jq -r '.plugins.quickCapture.repo' "$LOCK")"
assert_eq "and the directory" "quickCapture" "$(jq -r '.plugins.quickCapture.path' "$LOCK")"
assert_eq "and the commit" "$($GIT -C "$REPOS/alice/dms-plugins" rev-parse HEAD)" \
    "$(jq -r '.plugins.quickCapture.commit' "$LOCK")"

# --- install --enable and uninstall reach shell.json --------------------------
# They used to pass --dry-run to enable/disable whenever DRY_RUN was set at
# all, and it always is ("false").
capture haseen plugin uninstall quickCapture --yes
assert_status "uninstall" 0 "$STATUS"
capture haseen plugin install quickCapture --enable --yes
assert_status "install --enable" 0 "$STATUS"
shell_id="$(sed -n "s/.*loaded as '\([^']*\)'.*/\1/p" <<<"$OUTPUT")"
assert_contains "the plugin loads under its adapted DMS id" "$shell_id" "dms."
assert_eq "install --enable turned it on" "true" \
    "$(jq -r --arg id "$shell_id" '.plugins[$id].enabled' "$XDG_CONFIG_HOME/haseen/shell.json")"
assert_eq "and put it on the bar" "true" \
    "$(jq -r --arg id "$shell_id" '.bar.right | index($id) != null' "$XDG_CONFIG_HOME/haseen/shell.json")"
capture haseen plugin uninstall quickCapture --yes
assert_status "uninstall again" 0 "$STATUS"
assert_eq "uninstall turned it off" "false" \
    "$(jq -r --arg id "$shell_id" '.plugins[$id].enabled' "$XDG_CONFIG_HOME/haseen/shell.json")"
assert_eq "and took it off the bar" "false" \
    "$(jq -r --arg id "$shell_id" '.bar.right | index($id) != null' "$XDG_CONFIG_HOME/haseen/shell.json")"
capture haseen plugin install quickCapture --enable --yes --dry-run
assert_contains "a dry run still plans the enable" "$OUTPUT" "DRYRUN"
assert_eq "and changes nothing" "false" \
    "$(jq -r --arg id "$shell_id" '.plugins[$id].enabled' "$XDG_CONFIG_HOME/haseen/shell.json")"

# --- started by a browser (no terminal) --------------------------------------
NOTIFY_LOG="$SANDBOX/notify.log"
TERM_LOG="$SANDBOX/term.log"
stub notify-send "echo \"\$*\" >>\"$NOTIFY_LOG\""
stub foot "printf '%s\n' \"\$@\" >\"$TERM_LOG\""
capture env -u HASEEN_INLINE TERMINAL=foot haseen-plugin-url "dms://theme/install/x" </dev/null
assert_status "a refused link from a browser fails" 1 "$STATUS"
assert_contains "and the user is told on screen" "$(cat "$NOTIFY_LOG" 2>/dev/null)" "Plugin link refused"
capture env -u HASEEN_INLINE TERMINAL=foot haseen-plugin-url "$LINK" </dev/null
assert_status "a plugin link from a browser opens a terminal" 0 "$STATUS"
term_args="$(cat "$TERM_LOG" 2>/dev/null)"
assert_contains "a floating one" "$term_args" "--app-id=haseen.floating"
assert_contains "running the handler on the link" "$term_args" "haseen-plugin-url"$'\n'"$LINK"

# --- DMS as the active shell -------------------------------------------------
mkdir -p "$XDG_STATE_HOME/haseen"
echo dms >"$XDG_STATE_HOME/haseen/active-shell"
capture haseen-plugin-url "$LINK" --dry-run
assert_contains "under DMS the link goes to dms open" "$OUTPUT" "DRYRUN: dms open $LINK"
assert_dry_pure "dms forward" "$OUTPUT"
rm -f "$XDG_STATE_HOME/haseen/active-shell"

# --- the desktop entry and its install ---------------------------------------
desktop="$HASEEN_PATH/default/applications/haseen-dms-url.desktop"
assert_eq "the desktop entry handles dms://" "x-scheme-handler/dms;" "$(sed -n 's/^MimeType=//p' "$desktop")"
exec_cmd="$(sed -n 's/^Exec=\([^ ]*\).*/\1/p' "$desktop")"
assert_eq "and runs a haseen command" "yes" "$([[ -x $REPO/bin/$exec_cmd ]] && echo yes || echo no)"
capture env HASEEN_SYSROOT="$FIXTURES/cachyos-grub-plain" "$REPO/install.sh" --dry-run --tree-only --prefix /usr/local
assert_contains "install.sh installs the desktop entry" "$OUTPUT" \
    "DRYRUN: sudo install -Dm0644 $desktop /usr/local/share/applications/haseen-dms-url.desktop"

# --- registering the handler (shell layer) -----------------------------------
shell_layer() { # apply|status — the layer as `haseen layer` runs it, dry
    capture env HASEEN_SYSROOT="$FIXTURES/shell-quickshell-installed" DRY_RUN=true \
        bash -c 'source "$HASEEN_PATH/lib/layers.sh"; layer_run_'"$1"' shell'
}
MIMEAPPS="$XDG_CONFIG_HOME/mimeapps.list"
REGISTER="DRYRUN: xdg-mime default haseen-dms-url.desktop x-scheme-handler/dms"
rm -f "$MIMEAPPS"
shell_layer apply
assert_contains "no handler yet: registered" "$OUTPUT" "$REGISTER"
assert_dry_pure "register" "$OUTPUT"
shell_layer status
assert_contains "status: unhandled is missing" "$OUTPUT" "missing: dms:// links are not handled by haseen"

printf '[Default Applications]\nx-scheme-handler/dms=dms-open.desktop;\n' >"$MIMEAPPS"
shell_layer apply
assert_contains "DMS's own handler is replaced" "$OUTPUT" "$REGISTER"

printf '[Added Associations]\nx-scheme-handler/dms=other.desktop;\n[Default Applications]\ntext/html=firefox.desktop;\nx-scheme-handler/dms=my-handler.desktop;\n' >"$MIMEAPPS"
shell_layer apply
assert_not_contains "a handler the user chose is kept" "$OUTPUT" "$REGISTER"
assert_contains "and named" "$OUTPUT" "dms:// links stay with my-handler.desktop"
shell_layer status
assert_contains "status: the user's choice is fine" "$OUTPUT" "ok: dms:// links open my-handler.desktop (your choice)"

printf '[Default Applications]\nx-scheme-handler/dms=haseen-dms-url.desktop;\n' >"$MIMEAPPS"
shell_layer apply
assert_not_contains "already registered: nothing to do" "$OUTPUT" "$REGISTER"
shell_layer status
assert_contains "status: registered" "$OUTPUT" "ok: dms:// links open haseen plugin url"
