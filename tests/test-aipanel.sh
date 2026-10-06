# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# AI panel and agent skill (plan 012): the haseen.ai manifest, the panel's
# contract with the CLI, the skill's references, and `haseen ai skill install`
# (one link per present agent, idempotent, dry-run pure).

AI_PLUGIN="$HASEEN_PATH/shell/plugins/haseen.ai"
SKILL="$HASEEN_PATH/agents/skills/haseen"

# home_state — every path under $HOME with its symlink target, for purity checks.
home_state() { (cd "$HOME" && find . -printf '%p %y %l\n' | sort); }

# --- the haseen.ai panel plugin -----------------------------------------------
sandbox aipanel-manifest
capture haseen plugin validate haseen.ai
assert_status "haseen.ai validates" 0 "$STATUS"
assert_contains "validate ok line" "$OUTPUT" "ok: haseen.ai (builtin:"
assert_not_contains "no remote network permission warning" "$OUTPUT" "arning"
assert_eq "panel kind only" '["panel"]' "$(jq -c .kinds "$AI_PLUGIN/manifest.json")"
assert_eq "declares exec + local network" "exec network:local files:write" "$(jq -r '.permissions | join(" ")' "$AI_PLUGIN/manifest.json")"
assert_contains "SUPER+A bind toggles it" "$(cat "$HASEEN_PATH/default/hypr/binds.lua")" 'ipc("panel", "toggle", "haseen.ai")'

panel="$(cat "$AI_PLUGIN/Panel.qml")"
# Policy, endpoints and keys stay in the CLI: the panel never speaks HTTP.
assert_contains "chat goes through haseen ai chat" "$panel" '"ai", "chat", "--endpoint"'
assert_contains "history via --messages-file" "$panel" '--messages-file /dev/fd/3'
assert_contains "models via haseen ai models" "$panel" '"ai", "models", "--endpoint"'
assert_contains "config via haseen ai config" "$panel" '"ai", "config"'
assert_not_contains "panel never runs curl itself" "$panel" '"curl"'
assert_not_contains "no XMLHttpRequest in the panel" "$panel" "XMLHttpRequest"
assert_contains "stop kills the process group" "$panel" '"kill", "-TERM", "--", "-" + chat.processId'
assert_contains "reply streamed chunk by chunk" "$panel" 'splitMarker: ""'
assert_not_contains "no Markdown/rich text (remote image fetches)" "$(cat "$AI_PLUGIN"/*.qml)" "RichText"
assert_not_contains "no Markdown text format" "$(cat "$AI_PLUGIN"/*.qml)" "MarkdownText"
assert_eq "every chat CLI flag the panel passes exists" "" \
    "$(for f in --endpoint --model --messages-file; do grep -q -- "$f)" "$REPO/bin/haseen-ai-chat" || echo "$f"; done)"

# The wrapper the panel runs: the history reaches the CLI on fd 3 and the
# temp file is gone before chat starts.
cat >"$SANDBOX/fake-chat" <<'SH'
#!/bin/bash
printf 'args:%s\n' "$*"
printf 'tmp-left:%s\n' "$(find "$XDG_RUNTIME_DIR" -name 'haseen-ai-chat.*' | wc -l)"
printf 'history:%s\n' "$(cat "${@: -1}")"
SH
chmod +x "$SANDBOX/fake-chat"
wrapper="$(sed -n "s/.*\"bash\", \"-c\", '\(.*\)', \"haseen-ai-chat\".*/\1/p" "$AI_PLUGIN/Panel.qml")"
assert_contains "wrapper extracted" "$wrapper" "mktemp"
mkdir -p "$SANDBOX/run"
capture env XDG_RUNTIME_DIR="$SANDBOX/run" bash -c "$wrapper" haseen-ai-chat "$SANDBOX/fake-chat" ai chat <<<'[{"role":"user","content":"hi"}]'
assert_contains "wrapper passes --messages-file /dev/fd/3" "$OUTPUT" "args:ai chat --messages-file /dev/fd/3"
assert_contains "history readable on fd 3" "$OUTPUT" 'history:[{"role":"user","content":"hi"}]'
assert_contains "temp file unlinked before chat runs" "$OUTPUT" "tmp-left:0"

# --- the skill ----------------------------------------------------------------
assert_eq "SKILL.md front matter name" "name: haseen" "$(sed -n '2p' "$SKILL/SKILL.md")"
assert_contains "SKILL.md has a description" "$(sed -n '1,12p' "$SKILL/SKILL.md")" "description:"
# Every topic file SKILL.md links exists, and every file is linked.
links="$(grep -o '](\([a-z-]*\.md\))' "$SKILL/SKILL.md" | tr -d '()]' | sort -u)"
for f in $links; do
    assert_eq "linked topic $f exists" "yes" "$([[ -r $SKILL/$f ]] && echo yes || echo no)"
done
for f in "$SKILL"/*.md; do
    [[ ${f##*/} == SKILL.md ]] && continue
    assert_contains "topic ${f##*/} linked from SKILL.md" "$links" "${f##*/}"
done
assert_contains "skill forbids editing HASEEN_PATH" "$(cat "$SKILL/SKILL.md")" "never edit \`\$HASEEN_PATH\`"
# Every `haseen <group> <verb>` the skill names (code blocks and `code`
# spans) resolves to a real command, so the guide cannot drift from the CLI.
# A bare group (`haseen plugin`) needs at least one command in that group.
skill_commands() {
    awk '/^ *```/ { fence = !fence; next }
        fence { if (match($0, /^ *haseen( [a-z][a-z0-9-]*)+/)) print substr($0, RSTART, RLENGTH); next }
        { s = $0; while (match(s, /`haseen( [a-z][a-z0-9-]*)+/)) { print substr(s, RSTART + 1, RLENGTH - 1); s = substr(s, RSTART + RLENGTH) } }' \
        "$SKILL"/*.md | sed 's/^ *//' | sort -u
}
missing=""
while read -r line; do
    read -ra w <<<"$line"
    ok=no
    [[ ${w[1]} == commands || ${w[1]} == doctor ]] && ok=yes
    for ((n = ${#w[@]} - 1; n > 0; n--)); do
        name="haseen-$(IFS=-; echo "${w[*]:1:n}")"
        [[ -x $REPO/bin/$name ]] && { ok=yes; break; }
        compgen -G "$REPO/bin/$name-*" >/dev/null && { ok=yes; break; }
    done
    [[ $ok == yes ]] || missing+="$line"$'\n'
done < <(skill_commands)
assert_contains "skill commands extracted" "$(skill_commands)" "haseen plugin validate"
assert_eq "every haseen command in the skill exists" "" "$missing"
# The skill's plugin steps, run hermetically (the shell reload is live-only).
sandbox aipanel-skill-steps
capture haseen plugin new alice.load --kind bar-widget
assert_status "skill step 2: new" 0 "$STATUS"
example="$(awk '/^   ```qml$/{f=1; next} f && /^   ```$/{exit} f{sub(/^   /, ""); print}' "$SKILL/plugins.md")"
assert_contains "skill example widget extracted" "$example" "BarButton {"
printf '%s\n' "$example" >"$HOME/.config/haseen/plugins/alice.load/Widget.qml"
capture haseen plugin validate alice.load
assert_status "skill step 4: validate" 0 "$STATUS"
assert_contains "skill step 4: ok line" "$OUTPUT" "ok: alice.load (user:"
capture haseen plugin enable alice.load
assert_status "skill step 5: enable" 0 "$STATUS"
assert_contains "skill step 5: in bar.right" "$(jq -c .bar.right "$HOME/.config/haseen/shell.json")" '"alice.load"'
assert_eq "skill example uses no colour literal" "" "$(grep -E '"#[0-9a-fA-F]{3,8}"' <<<"$example" || true)"
assert_contains "skill example timer >= 2 s" "$example" "interval: 10000"

# --- haseen ai skill install ---------------------------------------------------
sandbox aipanel-skill-none
capture haseen ai skill install
assert_status "no agents: exit 0" 0 "$STATUS"
assert_contains "no agents: says so" "$OUTPUT" "no AI agent found"
assert_eq "no agents: nothing created" "" "$(find "$HOME" -mindepth 1 -print -quit)"
capture haseen ai skill install extra
assert_status "extra argument: usage error" 2 "$STATUS"
capture haseen ai
assert_contains "router lists ai skill install" "$OUTPUT" "haseen ai skill install"

sandbox aipanel-skill-plan
unset CLAUDE_CONFIG_DIR CODEX_HOME
mkdir -p "$HOME/.claude" "$HOME/.codex/skills" "$HOME/.hermes/profiles/work" "$HOME/.pi"
before="$(home_state)"
capture haseen ai skill install --dry-run
assert_status "dry-run exit" 0 "$STATUS"
assert_dry_pure "skill install" "$OUTPUT"
assert_eq "dry-run changes nothing under HOME" "$before" "$(home_state)"
assert_contains "plan: claude skills dir created" "$OUTPUT" "DRYRUN: mkdir -p $HOME/.claude/skills"
assert_contains "plan: claude link" "$OUTPUT" "DRYRUN: ln -sfn $SKILL $HOME/.claude/skills/haseen"
assert_contains "plan: codex link" "$OUTPUT" "DRYRUN: ln -sfn $SKILL $HOME/.codex/skills/haseen"
assert_not_contains "plan: existing codex skills dir not re-created" "$OUTPUT" "mkdir -p $HOME/.codex/skills"
assert_contains "plan: hermes link" "$OUTPUT" "DRYRUN: ln -sfn $SKILL $HOME/.hermes/skills/haseen"
assert_contains "plan: hermes profile link" "$OUTPUT" "DRYRUN: ln -sfn $SKILL $HOME/.hermes/profiles/work/skills/haseen"
assert_eq "plan: one link per present agent home" "4" "$(grep -c '^DRYRUN: ln -sfn' <<<"$OUTPUT")"
for absent in .agents .gemini .pi/agent; do
    assert_not_contains "plan: absent $absent untouched" "$OUTPUT" "$HOME/$absent/"
done

capture haseen ai skill install
assert_status "install exit" 0 "$STATUS"
for link in .claude/skills/haseen .codex/skills/haseen .hermes/skills/haseen .hermes/profiles/work/skills/haseen; do
    assert_eq "link $link -> skill" "$SKILL" "$(readlink "$HOME/$link")"
done
assert_eq "SKILL.md reachable through the link" "name: haseen" "$(sed -n 2p "$HOME/.claude/skills/haseen/SKILL.md")"
after="$(home_state)"
capture haseen ai skill install
assert_contains "re-run: already linked" "$OUTPUT" "already linked"
assert_eq "re-run: idempotent" "$after" "$(home_state)"

# A stale link is replaced; a real directory of the user's is never touched.
ln -sfn /nonexistent/old-skill "$HOME/.codex/skills/haseen"
mkdir -p "$HOME/.agents/skills/haseen"
echo mine >"$HOME/.agents/skills/haseen/SKILL.md"
capture haseen ai skill install --dry-run
assert_contains "stale link: replace planned" "$OUTPUT" "DRYRUN: ln -sfn $SKILL $HOME/.codex/skills/haseen"
assert_contains "user dir: warned" "$OUTPUT" "$HOME/.agents/skills/haseen exists and is not a symlink"
assert_not_contains "user dir: no link planned" "$OUTPUT" "ln -sfn $SKILL $HOME/.agents"
capture haseen ai skill install
assert_eq "stale link replaced" "$SKILL" "$(readlink "$HOME/.codex/skills/haseen")"
assert_eq "user dir kept" "mine" "$(cat "$HOME/.agents/skills/haseen/SKILL.md")"

# CODEX_HOME / CLAUDE_CONFIG_DIR point at relocated agent homes.
sandbox aipanel-skill-env
mkdir -p "$SANDBOX/codex-home" "$SANDBOX/claude-home"
capture env CODEX_HOME="$SANDBOX/codex-home" CLAUDE_CONFIG_DIR="$SANDBOX/claude-home" haseen ai skill install --dry-run
assert_contains "CODEX_HOME honoured" "$OUTPUT" "DRYRUN: ln -sfn $SKILL $SANDBOX/codex-home/skills/haseen"
assert_contains "CLAUDE_CONFIG_DIR honoured" "$OUTPUT" "DRYRUN: ln -sfn $SKILL $SANDBOX/claude-home/skills/haseen"
