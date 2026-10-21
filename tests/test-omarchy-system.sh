# shellcheck shell=bash
# haseen:covers bin/haseen-{audio-tuning,bar-add,bar-move,bar-position,bar-transparent,brightness}
# haseen:covers bin/haseen-{capture-screenrecord,capture-screenshot,config-edit,config-terminal}
# haseen:covers bin/haseen-{drive-info,drive-select,hook,install,layer-apply,menu,menu-select}
# haseen:covers bin/haseen-{notification-send,plugin-settings,remove,setup-ddc,setup-default}
# haseen:covers bin/haseen-{setup-dns,shell-ipc,terminal-run,theme-list,theme-set,upload}
# haseen:covers bin/haseen-browser-* bin/haseen-screen-* share/haseen/VERSION
# haseen:covers share/haseen/default/{menu.jsonc,shell.json} share/haseen/layers/base/lib.sh
# haseen:covers share/haseen/layers/dms/ipc-translate share/haseen/layers/theme/theme-lib.sh
# haseen:covers share/haseen/lib/{catalog,hardware,layers,ledger,omarchy-import,packages}.sh
# haseen:covers share/haseen/lib/{preflight,screen,shellrc,terminal}.sh
# haseen:covers share/haseen/omarchy/bin/omarchy-agent-* share/haseen/omarchy/bin/omarchy-audio-*
# haseen:covers share/haseen/omarchy/bin/omarchy-bluetooth-*
# haseen:covers share/haseen/omarchy/bin/omarchy-brightness-*
# haseen:covers share/haseen/omarchy/bin/omarchy-chromium-*
# haseen:covers share/haseen/omarchy/bin/omarchy-clipboard-* share/haseen/omarchy/bin/omarchy-cmd-*
# haseen:covers share/haseen/omarchy/bin/omarchy-{agent,bar,battery-low,battery-present}
# haseen:covers share/haseen/omarchy/bin/omarchy-capture-region
# haseen:covers share/haseen/omarchy/bin/omarchy-capture-screenrecording-with-webcam
# haseen:covers share/haseen/omarchy/bin/omarchy-{capture-screenshot,capture-webcam-list}
# haseen:covers share/haseen/omarchy/bin/omarchy-{capture-webcam-resize,default-agent}
# haseen:covers share/haseen/omarchy/bin/omarchy-{default-editor,dev-theme-preview,disk-speedtest}
# haseen:covers share/haseen/omarchy/bin/omarchy-{display-text-size,dns,done,drive-select}
# haseen:covers share/haseen/omarchy/bin/omarchy-{hyprland-focus-app,install-openclaw-cli}
# haseen:covers share/haseen/omarchy/bin/omarchy-launch-browser
# haseen:covers share/haseen/omarchy/bin/omarchy-launch-floating-terminal-with-presentation
# haseen:covers share/haseen/omarchy/bin/omarchy-{launch-openclaw,launch-webapp,openclaw-onboard}
# haseen:covers share/haseen/omarchy/bin/omarchy-{show-done,theme-color,theme-osc}
# haseen:covers share/haseen/omarchy/lib.sh share/haseen/omarchy/themed/**
# haseen:covers share/haseen/shell/Compat/Manifest.js share/haseen/shell/lib/plugin.sh
# haseen:covers share/haseen/shell/plugin.schema.json share/haseen/shell/plugins/*/manifest.json
# haseen:covers share/haseen/themes/catppuccin/**
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# haseen's answers to Omarchy's agent, audio, bar, battery, Bluetooth,
# brightness, capture, Chromium host, clipboard, cmd, default, DNS, done and
# drive commands (plan 093, g1). System tools are stubs that answer queries
# from files under $SANDBOX and log every change to $SYS (marked
# STUB-CALLED, so a dry run that reaches one fails its purity check); haseen's
# own commands are recorders in a fake tree (HASEEN_PATH=$FAKE/share/haseen)
# that log their arguments, and {dry} when DRY_RUN reached them, to $CALLS.
# Nothing reaches the network but a loopback server this file starts.

OMA="$HASEEN_PATH/omarchy/bin"

MINE=(omarchy-agent omarchy-agent-prompt omarchy-agent-usage-claude omarchy-agent-usage-codex
    omarchy-agent-usage-fireworks omarchy-agent-usage-update omarchy-audio-input-mute
    omarchy-audio-input-set-default omarchy-audio-output-set-default omarchy-audio-output-sink
    omarchy-audio-output-switch omarchy-audio-output-volume omarchy-audio-sink-availability
    omarchy-audio-source-switch omarchy-audio-tuning omarchy-bar omarchy-battery-low
    omarchy-battery-present omarchy-bluetooth-device omarchy-bluetooth-power
    omarchy-brightness-display omarchy-brightness-display-ddc omarchy-brightness-keyboard
    omarchy-brightness-keyboard-mute omarchy-capture-region
    omarchy-capture-screenrecording-with-webcam omarchy-capture-screenshot
    omarchy-capture-webcam-list omarchy-capture-webcam-resize omarchy-chromium-copy-url-host
    omarchy-chromium-ytdlp-host omarchy-clipboard-open omarchy-clipboard-paste-file
    omarchy-clipboard-paste-text omarchy-cmd-browser-handoff omarchy-cmd-default-browser
    omarchy-cmd-missing omarchy-cmd-present omarchy-cmd-terminal-cwd omarchy-default-agent
    omarchy-default-editor omarchy-dev-theme-preview omarchy-disk-speedtest
    omarchy-display-text-size omarchy-dns omarchy-done omarchy-drive-select)

# haseen commands the scripts reach; in the fake tree each is a recorder.
RECORDED=(haseen-setup-default haseen-terminal-run haseen-menu haseen-notification-send haseen-hook
    haseen-audio-tuning haseen-brightness haseen-screen-off haseen-screen-on haseen-capture-screenshot
    haseen-capture-screenrecord haseen-menu-select haseen-config-edit haseen-setup-dns
    haseen-drive-select haseen-bar-add haseen-bar-move haseen-bar-position haseen-bar-transparent
    haseen-plugin-settings)

# box NAME — a sandbox whose system files are the fixture tree $ROOT
# (HASEEN_SYSROOT), with the recorders in $FAKE/bin and no credential or
# agent setting of the session leaking in.
box() {
    sandbox "$1"
    export SANDBOX
    ROOT="$SANDBOX/root"
    FAKE="$SANDBOX/fake"
    mkdir -p "$ROOT" "$FAKE/bin" "$FAKE/share/haseen" "$SANDBOX/answers"
    export HASEEN_SYSROOT="$ROOT"
    local d t
    for d in lib omarchy shell default layers themes; do ln -s "$HASEEN_PATH/$d" "$FAKE/share/haseen/$d"; done
    export CALLS="$SANDBOX/calls" SYS="$SANDBOX/sys.log" ANSWERS="$SANDBOX/answers"
    : >"$CALLS"
    : >"$SYS"
    for t in "${RECORDED[@]}"; do
        cat >"$FAKE/bin/$t" <<'REC'
#!/bin/sh
{ printf %s "${0##*/}"; for a in "$@"; do printf ' [%s]' "$a"; done
  [ "${DRY_RUN:-}" = true ] && printf ' {dry}'; echo; } >>"$CALLS"
[ -x "$ANSWERS/${0##*/}" ] && exec "$ANSWERS/${0##*/}" "$@"
exit 0
REC
        chmod +x "$FAKE/bin/$t"
    done
    unset CLAUDE_CONFIG_DIR CODEX_HOME FIREWORKS_API_KEY FIREWORKS_ACCOUNT_ID FIREWORKS_AUTH_PATH \
        FIREWORKS_API_BASE_URL HASEEN_AGENT HASEEN_AGENT_USAGE_DIR OMARCHY_SCREENSHOT_DIR \
        HASEEN_SCREENSHOT_DIR CHROME_USER_DATA_DIR CHROME_CONFIG_HOME BROWSER EDITOR \
        XDG_CURRENT_DESKTOP DRY_RUN HASEEN_YTDLP_DIR
    export XDG_CONFIG_DIRS="$SANDBOX/etc-xdg" XDG_DATA_DIRS="$SANDBOX/data-dirs"
}

# fk NAME ARGS... — run an Omarchy command against the fake haseen tree.
fk() { env HASEEN_PATH="$FAKE/share/haseen" "$OMA/$1" "${@:2}"; }

# ans NAME BODY — what recorder NAME prints (a /bin/sh body, given its args).
ans() {
    printf '#!/bin/sh\n%s\n' "$2" >"$ANSWERS/$1"
    chmod +x "$ANSWERS/$1"
}

# sys NAME ARMS — a system tool whose `case "$*"` ARMS answer queries (each
# arm exits); any other call is a change: logged and marked STUB-CALLED.
sys() {
    stub "$1" "case \"\$*\" in
$2
__never__) ;;
esac
echo \"$1 \$*\" >>\"\$SYS\"
echo \"STUB-CALLED: $1 \$*\" >&2
exit 0"
}

# --- every script ------------------------------------------------------------
box omarchy-system-help
bad=""
notice=""
for name in "${MINE[@]}"; do
    capture "$OMA/$name" --help
    [[ $STATUS == 0 && $OUTPUT == *Usage* && $OUTPUT != *STUB-CALLED* ]] || bad+="$name($STATUS) "
    [[ -x $OMA/$name && ! -L $OMA/$name ]] || bad+="$name(not a script) "
    tr -s ' \n#' ' ' <"$OMA/$name" | grep -q 'MIT, Copyright (c) David Heinemeier Hansson' || notice+="$name "
done
assert_eq "every g1 script answers --help and runs nothing" "" "$bad"
assert_eq "every g1 script names Omarchy's MIT notice" "" "$notice"
assert_eq "no g1 help reached a haseen command" "" "$(<"$CALLS")"
assert_eq "omarchy-brightness-display never reaches Omarchy's Apple commands" "" \
    "$(grep -n 'display-apple\|focused-apple\|asdcontrol' "$OMA/omarchy-brightness-display" | grep -v '^[0-9]*:#')"

# --- agents ------------------------------------------------------------------
box omarchy-system-agent
capture fk omarchy-agent --dry-run
assert_status "omarchy-agent without a default agent fails" 1 "$STATUS"
assert_contains "omarchy-agent says how to choose one" "$OUTPUT" "haseen setup default agent <name>"
ans haseen-setup-default '[ $# -eq 1 ] && echo claude; exit 0'
stub claude 'echo "STUB-CALLED: claude $*" >&2; exit 97'
capture fk omarchy-agent --inline --dry-run
assert_eq "omarchy-agent --inline starts the agent unattended" "DRYRUN: claude --permission-mode auto" "$OUTPUT"
assert_dry_pure "omarchy-agent --inline" "$OUTPUT"
: >"$CALLS"
capture fk omarchy-agent --dry-run
assert_contains "omarchy-agent opens a terminal through haseen" "$(<"$CALLS")" \
    "haseen-terminal-run [claude] [--permission-mode] [auto] {dry}"
capture fk omarchy-agent-prompt --dry-run --inline fix the tests
assert_eq "omarchy-agent-prompt passes the prompt" "DRYRUN: claude --permission-mode auto -- fix the tests" "$OUTPUT"
capture fk omarchy-agent-prompt
assert_status "omarchy-agent-prompt needs a prompt" 1 "$STATUS"
capture fk omarchy-default-agent
assert_eq "omarchy-default-agent prints haseen's default" "claude" "$OUTPUT"
: >"$CALLS"
capture fk omarchy-default-agent claude-code --dry-run
assert_contains "omarchy-default-agent maps Omarchy's alias" "$(<"$CALLS")" "haseen-setup-default [agent] [claude] {dry}"
assert_dry_pure "omarchy-default-agent" "$OUTPUT"
capture fk omarchy-default-agent nonsense
assert_status "omarchy-default-agent refuses an unknown agent" 1 "$STATUS"

# Claude: transcripts are read, the token never leaves the credential file.
box omarchy-system-claude
CLAUDE="$HOME/.claude"
mkdir -p "$CLAUDE/projects/p"
now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf '{"type":"assistant","sessionId":"s1","timestamp":"%s","message":{"id":"m1","role":"assistant","model":"claude-test","usage":{"input_tokens":100,"output_tokens":20}}}\n' \
    "$now" >"$CLAUDE/projects/p/s.jsonl"
capture "$OMA/omarchy-agent-usage-claude" --force
assert_status "the Claude collector succeeds" 0 "$STATUS"
assert_eq "the Claude record carries the transcript stats" "claude true 1 100 Waiting for auth" \
    "$(jq -r '[.id, .ready, .totalPrompts, .modelUsage["claude-test"].inputTokens, .usageStatusText] | join(" ")' <<<"$OUTPUT")"
assert_eq "the Claude collector caches under haseen" "yes no" \
    "$([[ -n $(ls "$HOME/.cache/haseen/agent-usage" 2>/dev/null) ]] && echo yes || echo no) $([[ -e $HOME/.cache/omarchy ]] && echo yes || echo no)"
printf '{"claudeAiOauth":{"accessToken":"sk-ant-test-SECRET","expiresAt":1000,"subscriptionType":"pro"}}\n' >"$CLAUDE/.credentials.json"
capture "$OMA/omarchy-agent-usage-claude" --force
assert_eq "an expired sign-in is reported, not probed" "Sign-in expired" "$(jq -r .usageStatusText <<<"$OUTPUT")"
assert_not_contains "the Claude token is never printed" "$OUTPUT" "SECRET"
assert_eq "the Claude token is never cached" "" "$(grep -rl SECRET "$HOME/.cache" 2>/dev/null)"
capture "$OMA/omarchy-agent-usage-claude" --bogus
assert_status "the Claude collector rejects an unknown flag" 2 "$STATUS"

# Codex: the app server answers over stdin/stdout; the stub plays it.
box omarchy-system-codex
stub codex 'printf "%s\n" "$*" >"$SANDBOX/codex.args"
while IFS= read -r line; do
    printf "%s\n" "$line" >>"$SANDBOX/codex.in"
    case $line in
    *"\"id\": 1,"*) echo "{\"id\":1,\"result\":{}}" ;;
    *"\"id\": 2,"*) echo "{\"id\":2,\"result\":{\"account\":{\"type\":\"chatgpt\",\"planType\":\"plus\"}}}" ;;
    *"\"id\": 3,"*) echo "{\"id\":3,\"result\":{\"rateLimits\":{\"primary\":{\"usedPercent\":40,\"windowDurationMins\":300,\"resetsAt\":1900000000},\"secondary\":{\"usedPercent\":10,\"windowDurationMins\":10080}}}}" ;;
    esac
done'
capture "$OMA/omarchy-agent-usage-codex" --force
assert_status "the Codex collector succeeds" 0 "$STATUS"
assert_eq "the Codex record carries the plan and limits" "codex plus 5h window 0.4 Weekly (7-day) 0.1" \
    "$(jq -r '[.id, .tierLabel, .limits[0].label, .limits[0].percent, .limits[1].label, .limits[1].percent] | join(" ")' <<<"$OUTPUT")"
assert_eq "the app server is started read-only" "-s read-only -a on-request app-server" "$(<"$SANDBOX/codex.args")"
assert_contains "haseen introduces itself to the app server" "$(<"$SANDBOX/codex.in")" '"name": "haseen-agent-usage"'
assert_eq "the Codex collector caches under haseen" "yes no" \
    "$([[ -n $(ls "$HOME/.cache/haseen/agent-usage" 2>/dev/null) ]] && echo yes || echo no) $([[ -e $HOME/.cache/omarchy ]] && echo yes || echo no)"

# Fireworks: no key, no request; with one, a loopback billing API.
box omarchy-system-fireworks
capture "$OMA/omarchy-agent-usage-fireworks"
assert_eq "without a key nothing is asked" "fireworks Fireworks unavailable false" \
    "$(jq -r '[.id, .usageStatusText, .ready] | join(" ")' <<<"$OUTPUT")"
mkdir -p "$HOME/.config/haseen/agents" "$HOME/.config/omarchy/agents"
echo '{"accountId":"acct-haseen","fundedAmount":10}' >"$HOME/.config/haseen/agents/fireworks.json"
echo '{"accountId":"acct-omarchy","fundedAmount":99}' >"$HOME/.config/omarchy/agents/fireworks.json"
cat >"$SANDBOX/fw.py" <<'PY'
import http.server, json, os, sys
port_file, log_file = sys.argv[1], sys.argv[2]
class Handler(http.server.BaseHTTPRequestHandler):
    def reply(self, body):
        data = json.dumps(body).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)
    def do_GET(self):
        auth = "ok" if self.headers.get("Authorization") == "Bearer fw-test-key" else "bad"
        with open(log_file, "a") as log:
            log.write(f"GET {self.path.split('?')[0]} auth={auth}\n")
        if self.path.split("?")[0].endswith(":getBalance"):
            self.reply({"balance": {"units": "7", "nanos": 500000000}})
        elif "/billingUsage" in self.path:
            self.reply({"serverlessCosts": []})
        else:
            self.send_response(404)
            self.end_headers()
    def log_message(self, *args):
        pass
server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
with open(port_file + ".new", "w") as f:
    f.write(str(server.server_address[1]))
os.rename(port_file + ".new", port_file)
server.serve_forever()
PY
/usr/bin/python3 -I "$SANDBOX/fw.py" "$SANDBOX/fw.port" "$SANDBOX/fw.log" >/dev/null 2>&1 &
fw_pid=$!
for _ in $(seq 50); do
    [[ -s $SANDBOX/fw.port ]] && break
    sleep 0.1
done
capture env FIREWORKS_API_KEY=fw-test-key "$OMA/omarchy-agent-usage-fireworks" \
    --api-base-url "http://127.0.0.1:$(<"$SANDBOX/fw.port")"
kill "$fw_pid" 2>/dev/null || true
wait "$fw_pid" 2>/dev/null || true
assert_eq "the Fireworks record carries the live balance and haseen's funding" "true 7.5 10 2.5" \
    "$(jq -r '[.ready, .balance.remaining * 1, .balance.funded * 1, .balance.spent * 1] | map(tostring) | join(" ")' <<<"$OUTPUT")"
assert_contains "the account comes from haseen's fireworks.json" "$(<"$SANDBOX/fw.log")" \
    "GET /v1/accounts/acct-haseen/billingUsage auth=ok"
assert_not_contains "Omarchy's fireworks.json is not read" "$(<"$SANDBOX/fw.log")" "acct-omarchy"
assert_not_contains "the Fireworks key is never printed" "$OUTPUT" "fw-test-key"

# The updater runs every collector beside it into haseen's state.
box omarchy-system-usage
stub codex 'exit 1'
capture "$OMA/omarchy-agent-usage-update" --dry-run
assert_contains "a dry update lists the collectors" "$OUTPUT" "omarchy-agent-usage-claude"
assert_eq "a dry update writes nothing" "no" "$([[ -e $HOME/.local/state/haseen ]] && echo yes || echo no)"
assert_dry_pure "omarchy-agent-usage-update" "$OUTPUT"
capture "$OMA/omarchy-agent-usage-update" claude fireworks
assert_status "the updater succeeds" 0 "$STATUS"
assert_eq "the updater stores each record in haseen's state" "claude fireworks" \
    "$(jq -r .id "$HOME/.local/state/haseen/agents/usage/"*.json | tr '\n' ' ' | sed 's/ $//')"

# --- the bar -----------------------------------------------------------------
box omarchy-system-bar
capture fk omarchy-bar position left --dry-run
assert_contains "position goes to haseen bar position" "$(<"$CALLS")" "haseen-bar-position [left] [--dry-run]"
: >"$CALLS"
fk omarchy-bar transparent true >/dev/null
fk omarchy-bar transparent toggle >/dev/null
assert_eq "transparent true|toggle become on|toggle" \
    "haseen-bar-transparent [on]
haseen-bar-transparent [toggle]" "$(<"$CALLS")"
capture fk omarchy-bar transparent maybe
assert_status "transparent takes true, false or toggle" 1 "$STATUS"
: >"$CALLS"
capture fk omarchy-bar put omarchy.clock
assert_eq "a widget already in the bar stays where it is" "0 omarchy.clock is on the bar " "$STATUS $OUTPUT $(<"$CALLS")"
capture fk omarchy-bar put omarchy.kblayout --after omarchy.clock --dry-run
assert_eq "put places after the anchor in the anchor's section" \
    "haseen-bar-add [haseen.kblayout] [center] [--before] [haseen.media] [--dry-run]" "$(<"$CALLS")"
: >"$CALLS"
fk omarchy-bar put omarchy.kblayout --before omarchy.nowhere >/dev/null
assert_eq "put without a usable anchor goes to the usual spot" "haseen-bar-add [haseen.kblayout] [center]" "$(<"$CALLS")"
: >"$CALLS"
fk omarchy-bar move omarchy.power --section left --index 0 >/dev/null
fk omarchy-bar move omarchy.media left >/dev/null
fk omarchy-bar move omarchy.clock --after omarchy.network >/dev/null
assert_eq "move maps ids, --index and --after onto haseen bar move" \
    "haseen-bar-move [haseen.battery] [left] [--before] [haseen.logo]
haseen-bar-move [haseen.media] [left]
haseen-bar-move [haseen.clock] [right] [--before] [haseen.battery]" "$(<"$CALLS")"
capture fk omarchy-bar move omarchy.clock --before omarchy.nowhere
assert_status "move refuses an anchor the bar does not carry" 1 "$STATUS"
assert_contains "and says which" "$OUTPUT" "could not find target widget"
: >"$CALLS"
ans haseen-plugin-settings 'cat >>"$SANDBOX/settings.json"'
fk omarchy-bar set omarchy.clock format HH:mm >/dev/null
fk omarchy-bar set omarchy.indicators items '["mic"]' --json --dry-run >/dev/null
assert_eq "set sends one setting to haseen plugin settings on stdin" \
    "haseen-plugin-settings [haseen.clock]
haseen-plugin-settings [haseen.indicators] [--dry-run]" "$(<"$CALLS")"
assert_eq "set's request is the setting, JSON values kept" \
    '{"settings":{"format":"HH:mm"}}
{"settings":{"items":["mic"]}}' "$(<"$SANDBOX/settings.json")"
capture fk omarchy-bar set omarchy.clock format '{bad' --json
assert_status "set refuses invalid JSON" 1 "$STATUS"
capture fk omarchy-bar use default
assert_status "use default keeps haseen's bar" 0 "$STATUS"
capture fk omarchy-bar reset
assert_status "reset keeps haseen's bar" 0 "$STATUS"
capture fk omarchy-bar use local.neon-bar
assert_status "a whole-bar plugin is not available" 1 "$STATUS"
capture fk omarchy-bar defaults
assert_status "defaults is not available" 1 "$STATUS"
assert_contains "and says the haseen way" "$OUTPUT" "haseen bar add|move|arrange"
# Through the real haseen commands, a dry run changes nothing.
capture "$OMA/omarchy-bar" position bottom --dry-run
assert_dry_pure "omarchy-bar position" "$OUTPUT"
capture "$OMA/omarchy-bar" put omarchy.kblayout center --dry-run
assert_dry_pure "omarchy-bar put" "$OUTPUT"
assert_eq "a dry bar edit writes no shell.json" "no" "$([[ -e $HOME/.config/haseen/shell.json ]] && echo yes || echo no)"

# --- audio -------------------------------------------------------------------
box omarchy-system-audio
mkdir -p "$ROOT/sys/class/leds/platform::micmute"
echo 0 >"$ROOT/sys/class/leds/platform::micmute/brightness"
sys wpctl 'get-volume*) if [ -e "$SANDBOX/muted" ]; then echo "Volume: 0.50 [MUTED]"; else echo "Volume: 0.50"; fi; exit 0 ;;
set-mute*) echo "wpctl $*" >>"$SYS"; if [ -e "$SANDBOX/muted" ]; then rm "$SANDBOX/muted"; else : >"$SANDBOX/muted"; fi; echo "STUB-CALLED: wpctl $*" >&2; exit 0 ;;'
sys brightnessctl ''
capture fk omarchy-audio-input-mute --dry-run
assert_contains "a dry mic mute says what it would do" "$OUTPUT" "DRYRUN: brightnessctl --device=platform::micmute set 1"
assert_dry_pure "omarchy-audio-input-mute" "$OUTPUT"
fk omarchy-audio-input-mute >/dev/null 2>&1
assert_eq "the mic mute toggles and the LED follows" \
    "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle
brightnessctl --device=platform::micmute set 1" "$(<"$SYS")"
: >"$SYS"
sys pactl 'list\ short\ source-outputs) printf "7\t1\tx\n9\t1\ty\n"; exit 0 ;;
list\ sink-inputs) printf "Sink Input #4\n\tapplication.name = \"Firefox\"\nSink Input #5\n\tapplication.name = \"EasyEffects\"\n"; exit 0 ;;'
capture fk omarchy-audio-input-set-default 51 alsa_input.mic --dry-run
assert_dry_pure "omarchy-audio-input-set-default" "$OUTPUT"
fk omarchy-audio-input-set-default 51 alsa_input.mic >/dev/null 2>&1
assert_eq "the input becomes the default and recordings move" \
    "wpctl set-default 51
pactl set-default-source alsa_input.mic
pactl move-source-output 7 alsa_input.mic
pactl move-source-output 9 alsa_input.mic" "$(<"$SYS")"
: >"$SYS"
capture fk omarchy-audio-output-set-default 52 alsa_output.hdmi --dry-run
assert_dry_pure "omarchy-audio-output-set-default" "$OUTPUT"
fk omarchy-audio-output-set-default 52 alsa_output.hdmi >/dev/null 2>&1
assert_eq "the output becomes the default; EasyEffects' stream stays" \
    "wpctl set-default 52
pactl set-default-sink alsa_output.hdmi
pactl move-sink-input 4 alsa_output.hdmi" "$(<"$SYS")"

box omarchy-system-sinks
sys pactl 'get-default-sink) cat "$SANDBOX/default-sink"; exit 0 ;;
list\ sinks\ short) printf "3\talsa_output.speaker\n6\thaseen_speaker_tuning\n8\talsa_output.hdmi\n"; exit 0 ;;
list\ sink-inputs) printf "Sink Input #11\n\tSink: 3\n\t\tnode.name = \"haseen_speaker_tuning.output\"\n"; exit 0 ;;
list\ sinks) cat "$SANDBOX/sinks.txt"; exit 0 ;;
"-f json list sinks") cat "$SANDBOX/sinks.json"; exit 0 ;;
get-sink-volume*) echo "Volume: front-left: 32768 /  $(cat "$SANDBOX/volume")% / -18.06 dB"; exit 0 ;;
get-sink-mute*) echo "Mute: no"; exit 0 ;;'
echo haseen_speaker_tuning >"$SANDBOX/default-sink"
assert_eq "the loudness sink of a tuning is the speaker behind it" "alsa_output.speaker" "$(fk omarchy-audio-output-sink)"
assert_eq "a physical sink is its own loudness sink" "alsa_output.hdmi" "$(fk omarchy-audio-output-sink alsa_output.hdmi)"
ans haseen-audio-tuning 'case "$1" in show) echo "Speaker sink: alsa_output.speaker" ;; esac'
printf 'Sink #3\n\tName: alsa_output.speaker\n\tPorts:\n\t\tspeaker: Speaker (available)\n\tActive Port: speaker\nSink #8\n\tName: alsa_output.hdmi\n\tPorts:\n\t\thdmi: HDMI (not available)\n\tActive Port: hdmi\nSink #6\n\tName: haseen_speaker_tuning\n' >"$SANDBOX/sinks.txt"
assert_eq "the speaker behind a tuning and an unplugged port are unavailable" \
    "alsa_output.speaker	0
alsa_output.hdmi	0
haseen_speaker_tuning	1" "$(fk omarchy-audio-sink-availability)"
assert_eq "the tuning's fronted sink comes from haseen audio tuning" "alsa_output.speaker" "$(fk omarchy-audio-tuning fronted-sink)"
: >"$CALLS"
fk omarchy-audio-tuning on --force --dry-run >/dev/null
fk omarchy-audio-tuning off >/dev/null
fk omarchy-audio-tuning >/dev/null
assert_eq "tuning verbs go to haseen audio tuning" \
    "haseen-audio-tuning [apply] [--dry-run] [--force]
haseen-audio-tuning [remove]
haseen-audio-tuning [show]" "$(<"$CALLS")"
echo 50 >"$SANDBOX/volume"
echo alsa_output.hdmi >"$SANDBOX/default-sink"
capture fk omarchy-audio-output-volume raise --dry-run
assert_eq "a volume step unmutes and sets the next level" \
    "DRYRUN: pactl set-sink-mute alsa_output.hdmi 0
DRYRUN: pactl set-sink-volume alsa_output.hdmi 55%" "$OUTPUT"
echo 3 >"$SANDBOX/volume"
capture fk omarchy-audio-output-volume -10 --dry-run
assert_contains "the volume stops at 0 %" "$OUTPUT" "set-sink-volume alsa_output.hdmi 0%"
capture fk omarchy-audio-output-volume mute-toggle --dry-run
assert_eq "mute-toggle toggles the loudness sink" "DRYRUN: pactl set-sink-mute alsa_output.hdmi toggle" "$OUTPUT"
assert_eq "a dry mute-toggle leaves no debounce file" "no" "$([[ -e $XDG_RUNTIME_DIR/haseen ]] && echo yes || echo no)"
# The switch skips the speaker the tuning fronts and the unplugged HDMI.
echo '[{"index":6,"name":"haseen_speaker_tuning","description":"Speaker tuning","ports":[]},{"index":3,"name":"alsa_output.speaker","ports":[{"availability":"available"}]},{"index":9,"name":"alsa_output.usb","description":"USB DAC","ports":[{"availability":"available"}]}]' >"$SANDBOX/sinks.json"
echo haseen_speaker_tuning >"$SANDBOX/default-sink"
echo 80 >"$SANDBOX/volume"
ans haseen-notification-send 'echo 41'
: >"$CALLS"
: >"$SYS"
capture fk omarchy-audio-output-switch --dry-run
assert_dry_pure "omarchy-audio-output-switch" "$OUTPUT"
assert_contains "the switch picks the next available sink" "$OUTPUT" "DRYRUN: timeout 2 pactl set-default-sink alsa_output.usb"
assert_contains "and names it" "$(<"$CALLS")" "[-i] [audio-volume-high] [USB DAC] {dry}"

box omarchy-system-media
sys playerctl '-l) printf "spotify\nmpv\n"; exit 0 ;;
"-p spotify status") echo Playing; exit 0 ;;
"-p mpv status") echo Paused; exit 0 ;;
*metadata*) echo "mpv: clip"; exit 0 ;;'
capture fk omarchy-audio-source-switch --dry-run
assert_dry_pure "omarchy-audio-source-switch" "$OUTPUT"
assert_contains "a dry switch only says which player is next" "$OUTPUT" "DRYRUN: remember mpv"
fk omarchy-audio-source-switch >/dev/null 2>&1
assert_eq "playback moves to the next player" "playerctl -p mpv play
playerctl -p spotify pause" "$(<"$SYS")"
assert_eq "the pick is remembered for the media keys" "mpv" "$(<"$XDG_RUNTIME_DIR/haseen/media-source")"
assert_contains "and announced" "$(<"$CALLS")" "[Media source] [mpv: clip]"

# --- battery and Bluetooth ---------------------------------------------------
box omarchy-system-battery
capture fk omarchy-battery-low 9 --dry-run
assert_dry_pure "omarchy-battery-low" "$OUTPUT"
assert_eq "a low battery is a critical toast and the battery-low hooks" \
    "haseen-notification-send [-u] [critical] [-i] [battery-caution] [-t] [30000] [Time to recharge!] [Battery is down to 9%] {dry}
haseen-hook [run] [battery-low] [9] {dry}" "$(<"$CALLS")"
capture fk omarchy-battery-present
assert_status "no battery, no success" 1 "$STATUS"
mkdir -p "$ROOT/sys/class/power_supply/BAT0"
echo 1 >"$ROOT/sys/class/power_supply/BAT0/present"
echo Battery >"$ROOT/sys/class/power_supply/BAT0/type"
capture fk omarchy-battery-present
assert_eq "a present battery answers 0 and prints nothing" "0 " "$STATUS $OUTPUT"

box omarchy-system-bluetooth
sys bluetoothctl 'show*) cat "$SANDBOX/bt-show" 2>/dev/null; exit 0 ;;
list) echo "Controller 00:11:22:33:44:55 host [default]"; exit 0 ;;'
sys rfkill ''
echo "Powered: yes" >"$SANDBOX/bt-show"
capture fk omarchy-bluetooth-device connect AA:BB:CC:DD:EE:FF --dry-run
assert_dry_pure "omarchy-bluetooth-device" "$OUTPUT"
fk omarchy-bluetooth-device connect AA:BB:CC:DD:EE:FF >/dev/null 2>&1
assert_eq "connect trusts and connects the device" "bluetoothctl trust AA:BB:CC:DD:EE:FF
bluetoothctl connect AA:BB:CC:DD:EE:FF" "$(<"$SYS")"
capture fk omarchy-bluetooth-device pair not-an-address
assert_status "a malformed address is refused" 1 "$STATUS"
capture fk omarchy-bluetooth-power is-on
assert_status "is-on answers 0 for a powered controller" 0 "$STATUS"
: >"$SYS"
capture fk omarchy-bluetooth-power on --dry-run
assert_eq "a dry power-on unblocks nothing" "DRYRUN: rfkill unblock bluetooth" "$OUTPUT"
fk omarchy-bluetooth-power off >/dev/null 2>&1
assert_eq "power off is the rfkill soft block" "rfkill block bluetooth" "$(<"$SYS")"

# --- brightness ----------------------------------------------------------------
box omarchy-system-brightness
sys hyprctl 'monitors\ -j) cat "$SANDBOX/monitors.json"; exit 0 ;;'
echo '[{"id":0,"name":"eDP-1","focused":true,"disabled":false,"dpmsStatus":true,"x":0,"y":0,"width":1920,"height":1080,"scale":1,"transform":0,"activeWorkspace":{"id":1}}]' >"$SANDBOX/monitors.json"
ans haseen-brightness 'case "$1" in get) printf "%s\tbacklight\t40\t4\t10\n" "${2:-panel}" ;; esac'
assert_eq "the focused panel's brightness is the bare percent" "40" "$(fk omarchy-brightness-display)"
: >"$CALLS"
fk omarchy-brightness-display 5%- --dry-run >/dev/null
fk omarchy-brightness-display --monitor DP-1 +10% >/dev/null
fk omarchy-brightness-display off >/dev/null
assert_eq "steps go to haseen brightness, off to haseen screen off" \
    "haseen-brightness [down] [backlight] {dry}
haseen-brightness [set] [ddc:DP-1] [+10%]
haseen-screen-off [--delay] [0]" "$(<"$CALLS")"
assert_dry_pure "omarchy-brightness-display" "$(fk omarchy-brightness-display +5% --dry-run 2>&1)"
: >"$CALLS"
assert_eq "a DDC monitor's brightness after a change" "40" "$(fk omarchy-brightness-display-ddc DP-2 30%)"
assert_eq "DDC goes through haseen brightness" "haseen-brightness [set] [ddc:DP-2] [30%]
haseen-brightness [get] [ddc:DP-2]" "$(<"$CALLS")"
capture fk omarchy-brightness-display-ddc DP-2 lots
assert_status "a malformed step fails" 1 "$STATUS"
: >"$CALLS"
fk omarchy-brightness-keyboard up >/dev/null
fk omarchy-brightness-keyboard off >/dev/null
fk omarchy-brightness-keyboard restore >/dev/null
assert_eq "the keyboard backlight steps, turns off and comes back" \
    "haseen-brightness [get] [kbd]
haseen-brightness [up] [kbd] [--step] [10]
haseen-brightness [get] [kbd]
haseen-brightness [set] [kbd] [0]
haseen-brightness [get] [kbd]
haseen-brightness [set] [kbd] [4]" "$(<"$CALLS")"
rm -rf "$XDG_RUNTIME_DIR/haseen"
capture fk omarchy-brightness-keyboard off --dry-run
assert_contains "a dry off only says it would remember the level" "$OUTPUT" "DRYRUN: remember 4"
assert_eq "and remembers nothing" "no" "$([[ -e $XDG_RUNTIME_DIR/haseen/kbd-brightness ]] && echo yes || echo no)"
sys brightnessctl ''
capture fk omarchy-brightness-keyboard-mute on
assert_eq "no mic-mute LED: nothing to do" "0 " "$STATUS $(<"$SYS")"
mkdir -p "$ROOT/sys/class/leds/platform::micmute"
echo 0 >"$ROOT/sys/class/leds/platform::micmute/brightness"
capture fk omarchy-brightness-keyboard-mute off --dry-run
assert_dry_pure "omarchy-brightness-keyboard-mute" "$OUTPUT"
fk omarchy-brightness-keyboard-mute on >/dev/null 2>&1
assert_eq "the mic-mute LED is set" "brightnessctl --device=platform::micmute set 1" "$(<"$SYS")"

# --- capture -------------------------------------------------------------------
box omarchy-system-capture
sys hyprctl 'monitors\ -j) cat "$SANDBOX/monitors.json"; exit 0 ;;
clients\ -j) cat "$SANDBOX/clients.json" 2>/dev/null || echo "[]"; exit 0 ;;'
echo '[{"id":0,"name":"eDP-1","focused":true,"disabled":false,"x":0,"y":0,"width":1920,"height":1080,"scale":1,"transform":0,"activeWorkspace":{"id":1}}]' >"$SANDBOX/monitors.json"
stub hyprpicker 'exit 0'
stub slurp 'cat "$SANDBOX/slurp.txt" 2>/dev/null'
assert_eq "fullscreen is the focused monitor" "0,0 1920x1080" "$(fk omarchy-capture-region fullscreen)"
assert_eq "an exact monitor pick names it" "monitor:eDP-1" "$(fk omarchy-capture-region fullscreen --match-monitor)"
echo "10,20 300x200" >"$SANDBOX/slurp.txt"
assert_eq "a region pick prints slurp's geometry" "10,20 300x200" "$(fk omarchy-capture-region region)"
: >"$SANDBOX/slurp.txt"
capture fk omarchy-capture-region region
assert_status "a cancelled pick fails" 1 "$STATUS"
: >"$CALLS"
capture fk omarchy-capture-screenshot fullscreen copy --dry-run
capture fk omarchy-capture-screenshot region save --dry-run
assert_dry_pure "omarchy-capture-screenshot" "$OUTPUT"
echo "1,2 30x40" >"$SANDBOX/slurp.txt"
fk omarchy-capture-screenshot windows >/dev/null 2>&1
assert_eq "screenshot modes go to haseen capture screenshot" \
    "haseen-capture-screenshot [output] [--no-save] [--dry-run] {dry}
haseen-capture-screenshot [region] [--no-copy] [--no-notify] [--dry-run] {dry}
haseen-capture-screenshot [--geometry] [1,2 30x40]" "$(<"$CALLS")"
capture fk omarchy-capture-screenshot sideways
assert_status "an unknown mode fails" 1 "$STATUS"
stub v4l2-ctl 'case $1 in
--list-devices) printf "Integrated Camera (usb-0000:00:14.0-8):\n\t/dev/video0\n\t/dev/video1\n\t/dev/media0\n\nIR Camera (usb-0000:00:14.0-9):\n\t/dev/video2\n" ;;
--device) [ "$2" = /dev/video0 ] && printf "Driver Info:\n\tDevice Caps      : 0x04200001\n\t\tVideo Capture\n" ;;
esac
exit 0'
assert_eq "only capture-capable cameras are listed" "/dev/video0  Integrated Camera (usb-0000:00:14.0-8):" \
    "$(fk omarchy-capture-webcam-list)"
: >"$CALLS"
capture fk omarchy-capture-screenrecording-with-webcam --dry-run
assert_eq "one camera records straight away" \
    "haseen-capture-screenrecord [--desktop-audio] [--microphone] [--webcam-device=/dev/video0] {dry}" "$(<"$CALLS")"
stub v4l2-ctl 'exit 0'
capture fk omarchy-capture-screenrecording-with-webcam --dry-run
assert_status "no camera, no recording" 1 "$STATUS"
capture fk omarchy-capture-webcam-resize medium --dry-run
assert_eq "no overlay window: nothing to resize" "0 " "$STATUS $OUTPUT"
echo '[{"address":"0xabc","title":"WebcamOverlay","size":[480,270],"monitor":0}]' >"$SANDBOX/clients.json"
capture fk omarchy-capture-webcam-resize medium --dry-run
assert_dry_pure "omarchy-capture-webcam-resize" "$OUTPUT"
assert_contains "the overlay is resized to Omarchy's medium" "$OUTPUT" 'x = 240, y = 270'
assert_contains "and kept in the corner" "$OUTPUT" 'x = 1640, y = 770'
capture fk omarchy-capture-webcam-resize huge
assert_status "an unknown size fails" 1 "$STATUS"

# --- Chromium native-messaging hosts -------------------------------------------
box omarchy-system-chromium
stub wl-copy 'cat >"$SANDBOX/clipboard"'
# frame JSON — Chromium's framing: a little-endian 32-bit length, then JSON.
frame() {
    local n=${#1}
    printf "\\x$(printf %02x $((n & 255)))\\x$(printf %02x $((n >> 8 & 255)))\\x00\\x00%s" "$1"
}
reply="$(frame '{"url":"https://example.org/a"}' | fk omarchy-chromium-copy-url-host | od -An -c -w64 | tr -s ' ')"
assert_contains "the copy host answers copied" "$reply" '{ " c o p i e d " : t r u e }'
assert_eq "the URL is on the clipboard" "https://example.org/a" "$(<"$SANDBOX/clipboard")"
reply="$(frame '{"nourl":1}' | fk omarchy-chromium-copy-url-host | od -An -c -w64 | tr -s ' ')"
assert_contains "no URL, nothing copied" "$reply" 'f a l s e'
stub setsid 'echo "$*" >>"$SANDBOX/setsid.log"'
reply="$(frame '{"url":"https://videos.example/watch?v=1"}' | fk omarchy-chromium-ytdlp-host | od -An -tx1 | tr -d ' \n')"
assert_eq "the yt-dlp host acknowledges at once" "020000007b7d" "$reply"
assert_contains "and downloads in a detached worker" "$(<"$SANDBOX/setsid.log")" "--download https://videos.example/watch?v=1"
: >"$SANDBOX/setsid.log"
frame '{"url":"ftp://videos.example/x"}' | fk omarchy-chromium-ytdlp-host >/dev/null
assert_eq "a non-web URL starts nothing" "" "$(<"$SANDBOX/setsid.log")"
stub yt-dlp 'exit 1'
: >"$CALLS"
fk omarchy-chromium-ytdlp-host --download https://videos.example/none >/dev/null 2>&1
assert_contains "no video, a critical toast" "$(<"$CALLS")" "[-u] [critical] [No video found for download]"

# --- clipboard -----------------------------------------------------------------
box omarchy-system-clipboard
stub cliphist 'case $1 in
list) printf "0\thttps://example.org/page\n1\t[[ binary data 12 KiB png 10x10 ]]\n2\tplain note\n" ;;
decode) cut -f2- ;;
esac'
sys wl-copy ''
sys wtype ''
sys xdg-open ''
capture fk omarchy-clipboard-open --history-index 0 --dry-run
assert_contains "a link opens in the browser" "$OUTPUT" "https://example.org/page"
assert_dry_pure "omarchy-clipboard-open link" "$OUTPUT"
capture fk omarchy-clipboard-open --history-index 1 --dry-run
assert_contains "an image opens in Tensaku" "$OUTPUT" "DRYRUN: tensaku-edit"
capture fk omarchy-clipboard-open --history-index 2 --dry-run
assert_contains "other text opens in the editor" "$OUTPUT" "haseen-config-edit"
assert_eq "a dry open writes no file" "no" "$([[ -e $HOME/.local/state/haseen/clipboard-open ]] && echo yes || echo no)"
capture fk omarchy-clipboard-open --history-index 9
assert_status "a missing entry fails" 1 "$STATUS"
echo "image bytes" >"$SANDBOX/pic.png"
capture fk omarchy-clipboard-paste-file image/png "$SANDBOX/pic.png" --dry-run
assert_dry_pure "omarchy-clipboard-paste-file" "$OUTPUT"
assert_contains "the file goes to the clipboard as its type" "$OUTPUT" "DRYRUN: wl-copy --type image/png"
fk omarchy-clipboard-paste-file --copy-only image/png "$SANDBOX/pic.png" >/dev/null 2>&1
assert_eq "--copy-only copies and does not paste" "wl-copy --type image/png" "$(<"$SYS")"
capture fk omarchy-clipboard-paste-file image/png "$SANDBOX/none.png"
assert_status "a missing file fails" 1 "$STATUS"
: >"$SYS"
capture fk omarchy-clipboard-paste-text hello --dry-run
assert_eq "text is copied and typed" "DRYRUN: wl-copy <<< (5 characters)
DRYRUN: wtype (5 characters)" "$OUTPUT"
capture fk omarchy-clipboard-paste-text --history-index 0 --dry-run
assert_contains "a history entry is pasted with Shift+Insert" "$OUTPUT" "DRYRUN: wtype -M shift -k Insert -m shift"
assert_dry_pure "omarchy-clipboard-paste-text" "$OUTPUT"
capture fk omarchy-clipboard-paste-text --history-index 1
assert_status "an image entry is not pasted as text" 1 "$STATUS"
capture fk omarchy-clipboard-paste-text ""
assert_status "empty text fails" 1 "$STATUS"
assert_eq "nothing reached the clipboard tools" "" "$(<"$SYS")"

# --- cmd helpers ---------------------------------------------------------------
box omarchy-system-cmd
capture fk omarchy-cmd-present bash jq
assert_status "present: every command is there" 0 "$STATUS"
capture fk omarchy-cmd-present bash haseen-no-such-command
assert_status "present: one is missing" 1 "$STATUS"
capture fk omarchy-cmd-missing bash haseen-no-such-command
assert_status "missing: one is missing" 0 "$STATUS"
capture fk omarchy-cmd-missing bash
assert_status "missing: none is missing" 1 "$STATUS"
capture fk omarchy-cmd-browser-handoff firefox https://example.org
assert_status "only Chromium-family browsers take a handoff" 1 "$STATUS"
capture fk omarchy-cmd-browser-handoff
assert_status "a handoff needs a browser" 1 "$STATUS"
mkdir -p "$HOME/.config" "$HOME/.local/share/applications"
printf '[Default Applications]\nx-scheme-handler/http=omarchy-browser.desktop;helium.desktop\n' >"$HOME/.config/mimeapps.list"
printf '[Desktop Entry]\nExec=helium-browser %%U\n' >"$HOME/.local/share/applications/helium.desktop"
stub helium-browser 'exit 0'
assert_eq "the default browser comes from mimeapps.list, skipping Omarchy's wrapper" "helium.desktop" \
    "$(fk omarchy-cmd-default-browser)"
rm "$HOME/.config/mimeapps.list"
stub xdg-settings 'echo firefox.desktop'
assert_eq "else xdg-settings answers" "firefox.desktop" "$(fk omarchy-cmd-default-browser)"
sys hyprctl 'activewindow) cat "$SANDBOX/activewindow" 2>/dev/null; exit 0 ;;'
assert_eq "no terminal focused: home" "$HOME" "$(fk omarchy-cmd-terminal-cwd)"
printf 'Window 1 -> kitty:\n\tpid: 123\n' >"$SANDBOX/activewindow"
mkdir -p "$ROOT/proc/123/task/123" "$ROOT/proc/456" "$ROOT/etc" "$SANDBOX/work"
echo 456 >"$ROOT/proc/123/task/123/children"
ln -s "$SANDBOX/work" "$ROOT/proc/456/cwd"
ln -s "$(readlink -f /bin/bash)" "$ROOT/proc/456/exe"
readlink -f /bin/bash >"$ROOT/etc/shells"
assert_eq "the focused terminal's shell directory" "$(readlink -f "$SANDBOX/work")" "$(fk omarchy-cmd-terminal-cwd)"
: >"$ROOT/etc/shells"
assert_eq "a child that is not a login shell does not count" "$HOME" "$(fk omarchy-cmd-terminal-cwd)"

# --- defaults, DNS, done, drives, display, dev ---------------------------------
box omarchy-system-misc
assert_eq "no editor set: nvim, as Omarchy's menu expects" "nvim" "$(fk omarchy-default-editor)"
ans haseen-setup-default '[ "$1 $#" = "editor 1" ] && echo zed; exit 0'
assert_eq "zed is printed as its command" "zeditor" "$(fk omarchy-default-editor)"
: >"$CALLS"
fk omarchy-default-editor sublime_text --dry-run >/dev/null
assert_eq "an Omarchy editor name maps to haseen's" "haseen-setup-default [editor] [sublime] [--dry-run]" "$(<"$CALLS")"
capture fk omarchy-default-editor notepad
assert_status "an unknown editor is refused" 1 "$STATUS"
ans haseen-setup-dns 'echo cloudflare'
assert_eq "the DNS provider is printed Omarchy's way" "Cloudflare" "$(fk omarchy-dns)"
: >"$CALLS"
fk omarchy-dns Google --dry-run >/dev/null
assert_eq "a provider goes to haseen setup dns" "haseen-setup-dns [google] [--dry-run]" "$(<"$CALLS")"
capture fk omarchy-dns Quad9
assert_status "an unknown provider is refused" 1 "$STATUS"
DONE="$HOME/.local/state/haseen/done"
capture fk omarchy-done mark first-run --dry-run
assert_dry_pure "omarchy-done mark" "$OUTPUT"
assert_eq "a dry mark creates nothing" "no" "$([[ -e $DONE/first-run ]] && echo yes || echo no)"
capture fk omarchy-done mark first-run
capture fk omarchy-done check first-run
assert_status "a marked name checks out" 0 "$STATUS"
capture fk omarchy-done ensure claimed
assert_status "ensure claims a new marker" 0 "$STATUS"
capture fk omarchy-done ensure claimed
assert_status "ensure fails on an existing marker" 1 "$STATUS"
capture fk omarchy-done mark ../escape
assert_status "a marker name cannot leave the directory" 1 "$STATUS"
assert_eq "markers live in haseen's state only" "no" "$([[ -e $HOME/.local/state/omarchy ]] && echo yes || echo no)"
: >"$CALLS"
fk omarchy-drive-select $'/dev/sda\n/dev/nvme0n1' >/dev/null
assert_eq "Omarchy's newline-separated drives become arguments" "haseen-drive-select [/dev/sda] [/dev/nvme0n1]" "$(<"$CALLS")"
sys gsettings "\"get org.gnome.desktop.interface font-name\") echo \"'Adwaita Sans 11'\"; exit 0 ;;
\"get org.gnome.desktop.interface text-scaling-factor\") echo 1.0; exit 0 ;;"
capture fk omarchy-display-text-size 16 --dry-run
assert_dry_pure "omarchy-display-text-size" "$OUTPUT"
assert_contains "16 px is GTK's factor on whole points" "$OUTPUT" "DRYRUN: gsettings set org.gnome.desktop.interface text-scaling-factor 1.3636"
fk omarchy-display-text-size reset >/dev/null 2>&1
assert_eq "reset returns GTK's factor to its default" "gsettings reset org.gnome.desktop.interface text-scaling-factor" "$(<"$SYS")"
capture fk omarchy-display-text-size 40
assert_status "a size outside 9-20 px is refused" 1 "$STATUS"
capture fk omarchy-display-text-size
assert_contains "without a size the sizes are printed" "$OUTPUT" "gtk text-scaling-factor: 1.0"
capture fk omarchy-disk-speedtest --dry-run
assert_contains "a dry speed test only describes the run" "$OUTPUT" "DRYRUN: measure $HOME/.cache/haseen"
assert_dry_pure "omarchy-disk-speedtest" "$OUTPUT"
capture fk omarchy-disk-speedtest "$SANDBOX/no-such-dir"
assert_status "the speed test needs an existing directory" 2 "$STATUS"
capture fk omarchy-dev-theme-preview catppuccin --no-color --no-osc
assert_contains "a stock theme previews" "$OUTPUT" "Theme: catppuccin"
capture fk omarchy-dev-theme-preview no-such-theme --no-color --no-osc
assert_status "an unknown theme fails" 1 "$STATUS"
