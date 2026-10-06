# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# AI layer (plan 006): backend package per GPU fixture, the loopback drop-in,
# idempotency, the ai.json policy and merge, keys kept out of argv, dry-run
# purity, and a real streaming round trip against a stub OpenAI server.

AI_FX="$FIXTURES/ai-ollama-applied"

# ai_layer FIXTURE_DIR VERB ARGS... — run the ai layer alone through the real
# runner (layer_run_apply/_status/_remove). `haseen layer apply ai` would also
# resolve `base`, which belongs to another slice and is tested there.
ai_layer() {
    local fx="$1" verb="$2"
    shift 2
    capture env HASEEN_SYSROOT="$fx" bash -c 'source "$HASEEN_PATH/lib/layers.sh"; verb=$1; shift; "layer_run_$verb" ai "$@"' _ "$verb" "$@"
}

# ai_sandbox NAME — sandbox plus a fake secret-tool (not in STUBBED_CMDS) and
# an ss that reports nothing listening, so no test reads live sockets.
ai_sandbox() {
    sandbox "$1"
    stub secret-tool 'echo "STUB-CALLED: secret-tool $*" >&2; exit 97'
    stub ss 'exit 0'
}

user_ai_json() { mkdir -p "$HOME/.config/haseen" && printf '%s\n' "$1" >"$HOME/.config/haseen/ai.json"; }

# --- backend package per GPU fixture ----------------------------------------
ai_sandbox ai-gpu
for row in \
    "cachyos-grub-plain|ollama|ollama ollama-vulkan" \
    "arch-sdboot-sb-enabled|ollama|ollama ollama-rocm" \
    "cachyos-limine-luks-dualboot|ollama|ollama ollama-cuda" \
    "arch-bios|ollama|ollama" \
    "cachyos-grub-plain|llama.cpp|llama-cpp ggml-vulkan" \
    "arch-sdboot-sb-enabled|llama.cpp|llama-cpp ggml-hip" \
    "cachyos-limine-luks-dualboot|llama.cpp|llama-cpp ggml-cuda" \
    "arch-bios|llama.cpp|llama-cpp"; do
    IFS='|' read -r fx backend pkgs <<<"$row"
    DRY_RUN=true ai_layer "$FIXTURES/$fx" apply --backend "$backend"
    assert_status "$fx $backend: apply exit" 0 "$STATUS"
    assert_dry_pure "$fx $backend" "$OUTPUT"
    assert_contains "$fx $backend: packages" "$OUTPUT" "DRYRUN: sudo pacman -S --needed $pkgs"$'\n'
done
assert_not_contains "hybrid intel+nvidia picks cuda, not vulkan" \
    "$(DRY_RUN=true ai_layer "$FIXTURES/cachyos-limine-luks-dualboot" apply; echo "$OUTPUT")" "ollama-vulkan"

DRY_RUN=true ai_layer "$FIXTURES/cachyos-limine-luks-dualboot" apply --accel cpu
assert_contains "--accel cpu overrides the GPU" "$OUTPUT" "pacman -S --needed ollama"$'\n'
DRY_RUN=true ai_layer "$FIXTURES/cachyos-grub-plain" apply --accel=cuda
assert_contains "--accel=cuda form" "$OUTPUT" "pacman -S --needed ollama ollama-cuda"$'\n'
DRY_RUN=true ai_layer "$FIXTURES/cachyos-grub-plain" apply --backend vllm
assert_status "unknown backend refused" 1 "$STATUS"
assert_contains "unknown backend message" "$OUTPUT" "--backend must be ollama or llama.cpp"
assert_dry_pure "unknown backend" "$OUTPUT"
assert_not_contains "nothing planned before refusal" "$OUTPUT" "DRYRUN:"
DRY_RUN=true ai_layer "$FIXTURES/nixos" apply
assert_contains "nixos goes through the flake" "$OUTPUT" "does not support distro 'nixos'"

# --- the loopback drop-in ---------------------------------------------------
DRY_RUN=true ai_layer "$FIXTURES/cachyos-grub-plain" apply
out="$OUTPUT"
assert_contains "drop-in path" "$out" "DRYRUN: write /etc/systemd/system/ollama.service.d/haseen.conf (mode 0644):"
assert_contains "drop-in binds loopback" "$out" "    | Environment=OLLAMA_HOST=127.0.0.1:11434"$'\n'
assert_contains "service enabled through run_root" "$out" "DRYRUN: sudo systemctl enable --now ollama.service"
assert_contains "running server restarted onto loopback" "$out" "DRYRUN: sudo systemctl try-restart ollama.service"
assert_not_contains "never binds all interfaces" "$out" "0.0.0.0"
assert_not_contains "no firewall port opened (ufw)" "$out" "ufw"
assert_not_contains "no firewall port opened (firewalld)" "$out" "firewall-cmd"
assert_contains "model suggestion printed" "$out" "suggested model (RAM unknown): qwen3:4b"
assert_contains "never auto-downloads" "$out" "Nothing is downloaded until you run: haseen ai pull qwen3:4b"
assert_not_contains "no pull during apply" "$out" "ollama pull"
assert_contains "marker written" "$out" "DRYRUN: write /var/lib/haseen/layers/ai"

# --- idempotency on an applied host -----------------------------------------
DRY_RUN=true ai_layer "$AI_FX" apply
assert_status "re-apply exit" 0 "$STATUS"
assert_dry_pure "re-apply" "$OUTPUT"
assert_not_contains "re-apply installs nothing" "$OUTPUT" "pacman -S"
assert_not_contains "re-apply keeps the drop-in" "$OUTPUT" "ollama.service.d/haseen.conf"
assert_not_contains "re-apply does not restart" "$OUTPUT" "try-restart"
assert_contains "re-apply converges the service" "$OUTPUT" "systemctl enable --now ollama.service"
assert_contains "32 GB suggests an 8B model" "$OUTPUT" "suggested model (RAM ~31 GB): qwen3:8b"

# A stale drop-in (edited by hand) is rewritten and the server restarted.
cp -a "$AI_FX" "$SANDBOX/stale"
printf '[Service]\nEnvironment=OLLAMA_HOST=0.0.0.0\n' >"$SANDBOX/stale/etc/systemd/system/ollama.service.d/haseen.conf"
DRY_RUN=true ai_layer "$SANDBOX/stale" apply
assert_contains "stale drop-in rewritten" "$OUTPUT" "write /etc/systemd/system/ollama.service.d/haseen.conf"
assert_contains "stale drop-in: restart" "$OUTPUT" "systemctl try-restart ollama.service"

# A later drop-in that re-exposes Ollama is called out.
cp -a "$AI_FX" "$SANDBOX/shadow"
printf '[Service]\nEnvironment="OLLAMA_HOST=0.0.0.0:11434"\n' >"$SANDBOX/shadow/etc/systemd/system/ollama.service.d/override.conf"
DRY_RUN=true ai_layer "$SANDBOX/shadow" apply
assert_contains "shadowing drop-in warned at apply" "$OUTPUT" "override.conf (OLLAMA_HOST=0.0.0.0:11434) overrides haseen's loopback binding"

# RAM tiers.
for row in "6000000|qwen3:1.7b" "12000000|qwen3:4b" "15990000|qwen3:8b"; do
    IFS='|' read -r kib tag <<<"$row"
    cp -a "$AI_FX" "$SANDBOX/ram-$kib"
    printf 'MemTotal:       %s kB\n' "$kib" >"$SANDBOX/ram-$kib/proc/meminfo"
    capture env HASEEN_SYSROOT="$SANDBOX/ram-$kib" bash -c 'source "$HASEEN_PATH/layers/ai/ai.sh"; ai_suggest_model'
    assert_contains "suggestion for $kib KiB" "$OUTPUT" "$tag"$'\t'
done

# --- status -----------------------------------------------------------------
ai_layer "$FIXTURES/cachyos-grub-plain" status
assert_status "status: nothing installed" 1 "$STATUS"
assert_contains "status: missing line" "$OUTPUT" "missing: no local AI backend installed"

stub ss "echo 'LISTEN 0 4096 127.0.0.1:11434 0.0.0.0:*'; echo 'LISTEN 0 4096 [::1]:631 [::]:*'"
ai_layer "$AI_FX" status
assert_status "status: healthy" 0 "$STATUS"
assert_contains "status: accel reported" "$OUTPUT" "ok: ollama installed (accel: vulkan (ollama-vulkan))"
assert_contains "status: drop-in ok" "$OUTPUT" "ok: loopback drop-in"
assert_contains "status: enabled" "$OUTPUT" "ok: ollama.service enabled"
assert_contains "status: loopback bind" "$OUTPUT" "ok: ollama listens on loopback only (127.0.0.1:11434)"

stub ss "echo 'LISTEN 0 4096 *:11434 *:*'"
ai_layer "$AI_FX" status
assert_status "status: exposed is degraded" 2 "$STATUS"
assert_contains "status: exposure named" "$OUTPUT" "warn: ollama is reachable from the network on *:11434"

stub ss 'exit 0'
ai_layer "$SANDBOX/shadow" status
assert_status "status: shadowed drop-in degraded" 2 "$STATUS"
assert_contains "status: shadow named" "$OUTPUT" "warn: /etc/systemd/system/ollama.service.d/override.conf (OLLAMA_HOST=0.0.0.0:11434) overrides"

stub ss "echo 'LISTEN 0 4096 0.0.0.0:11434 0.0.0.0:*'"
capture env HASEEN_SYSROOT="$AI_FX" haseen ai status
assert_status "haseen ai status: exposed" 2 "$STATUS"
assert_contains "haseen ai status: endpoints" "$OUTPUT" "* ollama     http://127.0.0.1:11434/v1 (allowed)"
assert_contains "haseen ai status: unreachable models" "$OUTPUT" "(ollama at http://127.0.0.1:11434/v1 not reachable)"
assert_contains "haseen ai status: suggestion" "$OUTPUT" "suggested: qwen3:8b"
stub ss 'exit 0'

# --- remove -----------------------------------------------------------------
DRY_RUN=true ai_layer "$AI_FX" remove
assert_dry_pure "remove" "$OUTPUT"
assert_contains "remove disables ollama" "$OUTPUT" "DRYRUN: sudo systemctl disable --now ollama.service"
assert_contains "remove drops the drop-in" "$OUTPUT" "DRYRUN: sudo rm -f /etc/systemd/system/ollama.service.d/haseen.conf"
assert_not_contains "remove keeps packages" "$OUTPUT" "DRYRUN: sudo pacman -R"

# --- llama.cpp backend -------------------------------------------------------
ai_sandbox ai-llama
DRY_RUN=true ai_layer "$FIXTURES/cachyos-grub-plain" apply --backend llama.cpp
assert_dry_pure "llama apply" "$OUTPUT"
assert_contains "llama: seeds user ai.json" "$OUTPUT" "DRYRUN: seed $HOME/.config/haseen/ai.json from"
assert_not_contains "llama: no enable without a model" "$OUTPUT" "enable --now haseen-llama.service"
assert_contains "llama: asks for modelPath" "$OUTPUT" "set endpoints.llamacpp.modelPath"
assert_not_contains "llama: no ollama drop-in" "$OUTPUT" "ollama.service.d"
assert_contains "llama: size suggestion, not an ollama pull" "$OUTPUT" "suggested model size (RAM unknown): 4B parameters"
assert_not_contains "llama: no pull advice" "$OUTPUT" "haseen ai pull"
user_ai_json '{"default":"llamacpp","endpoints":{"llamacpp":{"modelPath":"~/models/tiny.gguf"}}}'
DRY_RUN=true ai_layer "$FIXTURES/cachyos-grub-plain" apply --backend llama.cpp
assert_contains "llama: user unit enabled once a model is set" "$OUTPUT" "DRYRUN: systemctl --user enable --now haseen-llama.service"
assert_not_contains "llama: user file never reseeded" "$OUTPUT" "DRYRUN: seed"
assert_not_contains "llama: user unit is not root" "$OUTPUT" "sudo systemctl --user"

mkdir -p "$HOME/models" && : >"$HOME/models/tiny.gguf"
user_ai_json '{"endpoints":{"llamacpp":{"modelPath":"~/models/tiny.gguf","model":"tiny","url":"http://127.0.0.1:8099/v1","args":["--ctx-size","4096"]}}}'
capture haseen ai serve --dry-run
assert_status "serve dry-run" 0 "$STATUS"
assert_eq "serve binds loopback on the url port" "DRYRUN: llama-server --host 127.0.0.1 --port 8099 -m $HOME/models/tiny.gguf --alias tiny --ctx-size 4096" "$OUTPUT"
user_ai_json '{"endpoints":{"llamacpp":{"modelPath":"~/models/tiny.gguf","args":["--host","0.0.0.0"]}}}'
capture haseen ai serve --dry-run
assert_status "serve refuses --host in args" 1 "$STATUS"
assert_not_contains "serve: no command planned" "$OUTPUT" "DRYRUN:"
user_ai_json '{"endpoints":{"llamacpp":{"modelPath":"~/models/tiny.gguf","url":"http://192.168.1.5:8080/v1"}}}'
capture haseen ai serve --dry-run
assert_status "serve refuses a non-loopback url" 1 "$STATUS"
grep -q '^ExecStart=haseen ai serve$' "$REPO/share/haseen/systemd/user/haseen-llama.service"
assert_status "unit runs haseen ai serve" 0 "$?"

# --- ai.json merge and validation --------------------------------------------
ai_sandbox ai-config
capture haseen ai config
assert_eq "no user file: defaults" "$(jq -S . "$HASEEN_PATH/default/ai.json")" "$(jq -S . <<<"$OUTPUT")"
user_ai_json '{"policy":"any","endpoints":{"ollama":{"model":"qwen3:4b"},"work":{"kind":"openai","url":"https://ai.example.com/v1","model":"big","keyRef":"work"}}}'
capture haseen ai config
assert_status "merge exit" 0 "$STATUS"
assert_eq "merge: user scalar wins" "any" "$(jq -r .policy <<<"$OUTPUT")"
assert_eq "merge: nested override" "qwen3:4b" "$(jq -r .endpoints.ollama.model <<<"$OUTPUT")"
assert_eq "merge: sibling keys kept" "http://127.0.0.1:11434/v1" "$(jq -r .endpoints.ollama.url <<<"$OUTPUT")"
assert_eq "merge: untouched endpoint kept" "http://127.0.0.1:8080/v1" "$(jq -r .endpoints.llamacpp.url <<<"$OUTPUT")"
assert_eq "merge: user endpoint added" "work" "$(jq -r .endpoints.work.keyRef <<<"$OUTPUT")"
assert_eq "merge: default kept" "ollama" "$(jq -r .default <<<"$OUTPUT")"
user_ai_json '[1,2]'
capture haseen ai config
assert_status "non-object user file refused" 1 "$STATUS"
user_ai_json '{"policy":"open"}'
capture haseen ai config
assert_contains "unknown policy refused" "$OUTPUT" "\"policy\" must be \"local\" or \"any\""
user_ai_json '{"endpoints":{"work":{"url":"https://ai.example.com/v1","apiKey":"sk-plain"}}}'
capture haseen ai config
assert_status "plain-text key refused" 1 "$STATUS"
assert_contains "plain-text key message" "$OUTPUT" "keys are never read from ai.json"

# --- policy -----------------------------------------------------------------
ai_sandbox ai-policy
for url in "https://api.example.com/v1" "http://127.0.0.1.evil.example/v1" "http://localhost@evil.example/v1" "http://192.168.1.20:11434/v1" "http://[::ffff:10.0.0.1]/v1"; do
    user_ai_json "{\"default\":\"r\",\"endpoints\":{\"r\":{\"kind\":\"openai\",\"url\":\"$url\",\"model\":\"m\"}}}"
    capture haseen ai chat "hello" </dev/null
    assert_status "local refuses $url" 1 "$STATUS"
    assert_contains "local refusal names the policy ($url)" "$OUTPUT" "policy is \"local\""
    assert_not_contains "refused before any request ($url)" "$OUTPUT" "STUB-CALLED: curl"
done
capture haseen ai models --endpoint r
assert_contains "models obeys the policy too" "$OUTPUT" "policy is \"local\""
capture haseen ai pull qwen3:4b --endpoint r --dry-run
assert_contains "pull obeys the policy too" "$OUTPUT" "policy is \"local\""

for url in "http://127.0.0.1:11434/v1" "http://localhost:8080/v1" "http://[::1]:8080/v1" "http://127.1.2.3:9/v1"; do
    user_ai_json "{\"default\":\"r\",\"endpoints\":{\"r\":{\"kind\":\"openai\",\"url\":\"$url\",\"model\":\"m\"}}}"
    capture haseen ai chat "hello" </dev/null
    assert_contains "local allows loopback $url" "$OUTPUT" "STUB-CALLED: curl"
    assert_contains "request goes to $url" "$OUTPUT" "$url/chat/completions"
done

user_ai_json '{"policy":"any","default":"r","endpoints":{"r":{"kind":"openai","url":"https://api.example.com/v1","model":"m"}}}'
capture haseen ai chat "hello" </dev/null
assert_contains "any allows remote" "$OUTPUT" "STUB-CALLED: curl"
assert_contains "remote request url" "$OUTPUT" "https://api.example.com/v1/chat/completions"
capture haseen ai chat --endpoint nope "hello" </dev/null
assert_contains "unknown endpoint named" "$OUTPUT" "unknown endpoint 'nope'"

# The key travels in a header file descriptor, never in curl's argv.
user_ai_json '{"policy":"any","default":"r","endpoints":{"r":{"kind":"openai","url":"https://api.example.com/v1","model":"m","keyRef":"r"}}}'
stub secret-tool '[ "$1 $2 $3" = "lookup haseen-ai r" ] && echo sk-secret-123'
stub curl 'echo "ARGV: $*" >&2; for a; do case $a in @/*) echo "HDR: $(cat "${a#@}")" >&2;; esac; done; cat >/dev/null'
capture haseen ai chat "hello" </dev/null
assert_contains "key sent as a header" "$OUTPUT" "HDR: Authorization: Bearer sk-secret-123"
assert_not_contains "key not in argv" "$(grep '^ARGV' <<<"$OUTPUT")" "sk-secret-123"
stub secret-tool 'exit 1'
capture haseen ai chat "hello" </dev/null
assert_status "missing key refused" 1 "$STATUS"
assert_contains "missing key message" "$OUTPUT" "no API key stored under keyRef 'r'"

# --- key set / clear ----------------------------------------------------------
ai_sandbox ai-key
user_ai_json '{"endpoints":{"work":{"url":"https://ai.example.com/v1"},"r":{"url":"https://ai.example.com/v1","keyRef":"r-ref"}}}'
capture haseen ai key set work --dry-run
assert_status "key set needs keyRef" 1 "$STATUS"
assert_contains "key set explains keyRef" "$OUTPUT" "add \"keyRef\": \"work\" to endpoints.work"
capture haseen ai key set r --dry-run
assert_dry_pure "key set" "$OUTPUT"
assert_contains "key set via secret-tool" "$OUTPUT" "DRYRUN: secret-tool store --label=haseen ai: r haseen-ai r-ref"
capture haseen ai key clear r --dry-run
assert_dry_pure "key clear" "$OUTPUT"
assert_contains "key clear via secret-tool" "$OUTPUT" "DRYRUN: secret-tool clear haseen-ai r-ref"
capture haseen ai key set ghost --dry-run
assert_contains "key set unknown endpoint" "$OUTPUT" "unknown endpoint 'ghost'"

# --- pull ---------------------------------------------------------------------
ai_sandbox ai-pull
capture env HASEEN_SYSROOT="$AI_FX" haseen ai pull qwen3:4b --dry-run
assert_status "pull dry-run" 0 "$STATUS"
assert_dry_pure "pull" "$OUTPUT"
assert_eq "pull pins OLLAMA_HOST from ai.json" "DRYRUN: env OLLAMA_HOST=http://127.0.0.1:11434 ollama pull qwen3:4b" "$OUTPUT"
capture env HASEEN_SYSROOT="$AI_FX" haseen ai pull
assert_status "pull without model is usage" 2 "$STATUS"
assert_contains "pull prints the suggestion" "$OUTPUT" "haseen ai pull qwen3:8b"
capture haseen ai pull 'x;rm -rf ~' --dry-run
assert_status "pull rejects odd names" 1 "$STATUS"

# --- router -------------------------------------------------------------------
capture haseen ai
for c in status models pull chat config "key set" "key clear"; do
    assert_contains "router lists ai $c" "$OUTPUT" "haseen ai $c"
done
assert_not_contains "serve is hidden" "$OUTPUT" "haseen ai serve"

# --- real round trip: stub OpenAI server on loopback ---------------------------
if command -v python3 >/dev/null; then
    ai_sandbox ai-live
    rm -f "$SANDBOX/stubs/curl"
    cat >"$SANDBOX/server.py" <<'PY'
import http.server, json, sys, time

class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def send_json(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/v1/models":
            self.send_json(200, {"object": "list", "data": [{"id": "stub-model", "object": "model"}]})
        else:
            self.send_json(404, {"error": {"message": "not found"}})

    def do_POST(self):
        req = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))))
        if self.path != "/v1/chat/completions" or req.get("model") == "missing":
            self.send_json(404, {"error": {"message": 'model "%s" not found' % req.get("model")}})
            return
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.end_headers()
        prompt = req["messages"][-1]["content"]
        for tok in ["[%s] " % req["model"], "echo: ", prompt]:
            chunk = {"object": "chat.completion.chunk", "choices": [{"index": 0, "delta": {"content": tok}}]}
            self.wfile.write(("data: %s\r\n\r\n" % json.dumps(chunk)).encode())
            self.wfile.flush()
            time.sleep(0.02)
        self.wfile.write(b'data: {"choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}\n\n')
        self.wfile.write(b"data: [DONE]\n\n")

srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), H)
with open(sys.argv[1], "w") as f:
    f.write(str(srv.server_address[1]))
srv.serve_forever()
PY
    python3 "$SANDBOX/server.py" "$SANDBOX/port" &
    srv_pid=$!
    for _ in $(seq 50); do [[ -s $SANDBOX/port ]] && break; sleep 0.1; done
    port="$(cat "$SANDBOX/port" 2>/dev/null || true)"
    user_ai_json "{\"default\":\"stub\",\"endpoints\":{\"stub\":{\"kind\":\"openai\",\"url\":\"http://127.0.0.1:$port/v1\",\"model\":\"\"}}}"
    capture haseen ai models
    assert_eq "live: models" "stub-model" "$OUTPUT"
    capture haseen ai chat "hello world" </dev/null
    assert_status "live: chat exit" 0 "$STATUS"
    assert_eq "live: streamed reply, first model picked" "[stub-model] echo: hello world" "$OUTPUT"
    capture bash -c 'printf "line one\nline two" | haseen ai chat --model m2 summarize'
    assert_eq "live: stdin appended to the prompt" "[m2] echo: summarize"$'\n\n'"line one"$'\n'"line two" "$OUTPUT"
    capture haseen ai chat --model missing "hi" </dev/null
    assert_status "live: http error exit" 1 "$STATUS"
    assert_contains "live: server error shown" "$OUTPUT" 'error: model "missing" not found'
    printf '%s' '[{"role":"system","content":"be brief"},{"role":"user","content":"first"},{"role":"assistant","content":"a"},{"role":"user","content":"second"}]' >"$SANDBOX/history.json"
    capture haseen ai chat --model m3 --messages-file "$SANDBOX/history.json" </dev/null
    assert_eq "live: messages file sent as the conversation" "[m3] echo: second" "$OUTPUT"
    capture haseen ai chat --model m3 --messages-file "$SANDBOX/history.json" "third" </dev/null
    assert_eq "live: prompt appended after the history" "[m3] echo: third" "$OUTPUT"
    printf '%s' '[{"role":"tool","content":"x"}]' >"$SANDBOX/bad.json"
    capture haseen ai chat --model m3 --messages-file "$SANDBOX/bad.json" </dev/null
    assert_status "live: invalid messages file refused" 1 "$STATUS"
    assert_contains "live: invalid messages file named" "$OUTPUT" "invalid messages file"
    kill "$srv_pid" 2>/dev/null || true
    wait "$srv_pid" 2>/dev/null || true
    capture haseen ai chat "hello" </dev/null
    assert_status "live: server gone" 1 "$STATUS"
    assert_contains "live: connect failure explained" "$OUTPUT" "cannot reach http://127.0.0.1:$port/v1"
fi
