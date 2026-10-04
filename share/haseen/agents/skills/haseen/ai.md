# Local AI

haseen's AI runs on the machine: Ollama (or llama.cpp's `llama-server`)
bound to 127.0.0.1 only, installed by `haseen layer apply ai`. The AI panel
(SUPER+A, plugin `haseen.ai`) and `haseen ai chat` talk to any
OpenAI-compatible `/v1` endpoint listed in `ai.json`.

```bash
haseen ai status            # backend, service, bound address, models
haseen ai models            # models the default endpoint serves
haseen ai pull qwen3:4b     # download a model into Ollama
haseen ai chat "hello"      # streamed reply; piped stdin is appended
haseen ai config            # the effective ai.json (defaults + the user's)
```

## `~/.config/haseen/ai.json`

Deep-merged over `$HASEEN_PATH/default/ai.json` (objects merge, the user's
scalars and arrays win). Write only the keys you change.

```json
{
  "default": "ollama",
  "endpoints": {
    "ollama": { "kind": "openai", "url": "http://127.0.0.1:11434/v1", "model": "qwen3:4b" }
  }
}
```

| Key | Meaning |
|---|---|
| `policy` | `"local"` (default): only `127.0.0.0/8`, `::1`, `localhost` endpoints are used. `"any"`: remote endpoints allowed. |
| `default` | endpoint name used when none is given |
| `endpoints.<name>.kind` | `"openai"` |
| `endpoints.<name>.url` | base URL including `/v1` |
| `endpoints.<name>.model` | default model; empty = the first one served |
| `endpoints.<name>.keyRef` | name of a key stored with `haseen ai key set <name>` |
| `endpoints.llamacpp.modelPath`, `.args` | the `.gguf` and extra `llama-server` arguments (`--host`/`--port` refused) |

Rules:

- **Never put an API key in `ai.json`** (`key`, `apiKey`, `token`, … are
  refused). Use `haseen ai key set <endpoint>`: it goes to the Secret Service
  and reaches curl through a pipe, never argv.
- **Do not switch `policy` to `"any"` on your own.** It sends the user's
  prompts off the machine; only do it when the user asks for a remote
  endpoint, and say so.
- Never re-bind Ollama to `0.0.0.0` (no `OLLAMA_HOST` overrides, no firewall
  openings). `haseen ai status` flags a non-loopback listener.

## The AI panel

`haseen shell ipc panel toggle haseen.ai` (SUPER+A). It uses the
`ai.json` default endpoint; to pin another one, set
`"plugins": {"haseen.ai": {"settings": {"endpoint": "<name>"}}}` in
`~/.config/haseen/shell.json`. The model picker lists `haseen ai models`.
Enter sends, Shift+Enter breaks the line, Escape stops a running reply (and
closes the panel when idle), the + button starts a new chat. The conversation
is kept in `~/.local/state/haseen/ai/chat.json`.

## Verify

```bash
haseen ai status                     # service active, listening on 127.0.0.1
haseen ai chat "say ok" </dev/null   # a streamed reply
```
