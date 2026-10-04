# Plan 006: Local AI layer

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: LOW
- **Depends on**: 001
- **Category**: ai
- **Planned at**: 2026-10-04, initial architecture (docs/architecture.md)
- **State**: DONE 2026-10-04. The Ollama service has not been installed on real hardware yet (plan 014).

## Why this matters

Requirement 6. Bind to loopback only: waydots plan 020 found Ollama exposed on the LAN.

## Scope

- `layers/ai`: Ollama with the GPU-matched package, or llama.cpp.
- `share/haseen/default/ai.json`.
- `bin/haseen-ai-{status,models,pull,chat}`.

## Acceptance

- Fixture tests choose the right backend package for intel, amd and nvidia.
- The service drop-in binds to 127.0.0.1.
- `haseen ai chat` talks to any OpenAI-compatible endpoint, verified against a local stub server.

## Execution record

### What changed

| File | Role |
|---|---|
| `share/haseen/layers/ai/layer.sh` | layer: `--backend ollama\|llama.cpp`, `--accel auto\|cuda\|rocm\|vulkan\|cpu`; status; remove |
| `share/haseen/layers/ai/ai.sh` | shared lib: config merge + validation, URL/loopback policy, `ai_curl` (key via pipe), package choice, drop-in, `ss` bind check, RAM suggestion |
| `share/haseen/layers/ai/files/ai.llamacpp.json` | seeded once as `~/.config/haseen/ai.json` by `--backend llama.cpp` when the user has none |
| `share/haseen/default/ai.json` | defaults (schema below) |
| `share/haseen/systemd/user/haseen-llama.service` | user unit, `ExecStart=haseen ai serve`; enabled only by the layer with `--backend llama.cpp` once `modelPath` is set (approved by Main) |
| `bin/haseen-ai-{status,models,pull,chat,config,key-set,key-clear,serve}` | CLI; `serve` is `# haseen:hidden` (unit ExecStart) |
| `tests/test-ai.sh`, `tests/fixtures/ai-ollama-applied/` | 164 assertions; fixture = CachyOS, Intel iGPU, 32 GB, ollama + ollama-vulkan installed, drop-in in place, service enabled |

**Package choice** (verified 2026-10-04: `pacman -Si` on the live host, archlinux.org file lists, packages.cachyos.org).
Arch `extra` ships `ollama` plus add-on runners that depend on it: `ollama-cuda`, `ollama-rocm`, `ollama-vulkan` (`pacman -Si ollama-vulkan` → `Depends On: … ollama vulkan-icd-loader`). CachyOS rebuilds the same names in `cachyos-extra-v3/v4` (packages.cachyos.org/package/cachyos-extra-v3/x86_64_v3/ollama, split packages `ollama-rocm ollama-vulkan ollama-cuda ollama-docs`). llama.cpp is `extra/llama-cpp` (ships `/usr/bin/llama-server`), which loads ggml backends from `ggml-cuda`, `ggml-hip`, `ggml-vulkan` (optional deps of `extra/ggml`). No AUR needed.

| GPU_VENDORS | accel | ollama | llama.cpp |
|---|---|---|---|
| contains nvidia | cuda | `ollama ollama-cuda` | `llama-cpp ggml-cuda` |
| contains amd (no nvidia) | rocm | `ollama ollama-rocm` | `llama-cpp ggml-hip` |
| intel only | vulkan | `ollama ollama-vulkan` | `llama-cpp ggml-vulkan` |
| none | cpu | `ollama` | `llama-cpp` |

A discrete GPU wins over an Intel iGPU (hybrid laptops). `--accel` overrides.

**Loopback.** `/etc/systemd/system/ollama.service.d/haseen.conf` sets `Environment=OLLAMA_HOST=127.0.0.1:11434`; rewritten only when its content differs, then `daemon-reload` + `try-restart` (moves an already-running server off 0.0.0.0), then `systemctl enable --now ollama.service`. Arch's unit is `WantedBy=multi-user.target` (gitlab.archlinux.org/archlinux/packaging/packages/ollama `ollama.service`), so status reads the wants symlink through `sysroot_path`. Status also flags a later-sorting drop-in (e.g. `override.conf` from `systemctl edit`) that sets a non-loopback `OLLAMA_HOST`, and reads `ss -ltnH` to report who actually listens. llama-server always gets `--host 127.0.0.1`; `args` may not contain `--host`/`--port`. No firewall rule is ever written.

**Model suggestion** (printed, never downloaded): MemTotal < 7 GiB → `qwen3:1.7b`; < 15 GiB → `qwen3:4b`; otherwise `qwen3:8b` (a "16 GB" machine reports ~15.3 GiB). Tags verified on registry.ollama.ai/library/qwen3/tags. For llama.cpp the size class is printed instead of a pull command.

### ai.json schema

Effective config = `share/haseen/default/ai.json` deep-merged (`jq -s '.[0] * .[1]'`: objects merge recursively, user scalars and arrays win) with `~/.config/haseen/ai.json`. `haseen ai config` prints the merged result; the AI panel (plan 012) should read that rather than merge itself.

| Key | Type | Meaning |
|---|---|---|
| `policy` | `"local"` \| `"any"` | `local` refuses every endpoint whose host is not `127.0.0.0/8`, `::1` or `localhost` (exact; userinfo stripped first, so `http://localhost@evil/` is remote). `any` allows remote and warns on plain http. Anything else is an error. |
| `default` | string | endpoint name used when `--endpoint` is not given |
| `endpoints.<name>.kind` | `"openai"` | only kind supported (OpenAI-compatible `/v1`) |
| `endpoints.<name>.url` | string | base URL including `/v1`, `http(s)://` required |
| `endpoints.<name>.model` | string | default model; empty = first id from `GET /models` |
| `endpoints.<name>.keyRef` | string, optional | Secret Service lookup value: the key is `secret-tool lookup haseen-ai <keyRef>`; stored by `haseen ai key set <name>`. Sent as `Authorization: Bearer` through a pipe (`curl -H @/dev/fd/N`), never argv. |
| `endpoints.llamacpp.modelPath` | string | `.gguf` file for `haseen-llama.service` (`~/` allowed) |
| `endpoints.llamacpp.args` | string[] | extra `llama-server` arguments; `--host`/`--port` refused (port comes from `url`) |

An endpoint carrying `key`, `apiKey`, `api_key`, `token`, `secret` or `password` is refused: keys never live in ai.json.

### Evidence

- `/tmp/tools/shellcheck --severity=warning -x bin/haseen-ai-* share/haseen/layers/ai/*.sh tests/test-ai.sh` → clean; `bash -n` on each → ok; `jq empty share/haseen/default/ai.json share/haseen/layers/ai/files/ai.llamacpp.json` → ok.
- `tests/run.sh tests/test-ai.sh` → `164/164 passed`. Covers: package set for intel / amd / intel+nvidia / no-GPU fixtures on both backends, `--accel` override, unknown backend and NixOS refused; drop-in content (`    | Environment=OLLAMA_HOST=127.0.0.1:11434`, no `0.0.0.0`, no ufw/firewall-cmd); re-apply on `ai-ollama-applied` installs nothing, keeps the drop-in, no restart; a stale drop-in is rewritten + restarted; a shadowing `override.conf` is warned at apply and degrades status (exit 2); `ss` showing `*:11434` → status exit 2; RAM tiers; policy refuses `https://api.example.com`, `127.0.0.1.evil.example`, `localhost@evil.example`, LAN IP, `[::ffff:10.0.0.1]` before any curl call and allows `127.x`, `localhost`, `[::1]`; `any` allows remote; the API key appears in the header fd and not in curl argv; ai.json merge; plain-text key refused; dry-run purity for apply / remove / pull / key set / key clear; a live stub-server round trip (models, streamed chat, stdin appended, HTTP error body shown, connect failure).
- `HASEEN_SYSROOT=tests/fixtures/arch-sdboot-sb-enabled haseen layer apply ai --dry-run -- --backend llama.cpp` → `apply order: base ai`, `DRYRUN: sudo pacman -S --needed llama-cpp ggml-hip`.
- Real smoke (scratch `HOME`, real curl, python3 `http.server` stub on 127.0.0.1, random port, killed afterwards):

  ```
  server pid=1342768 port=45997
  LISTEN 0      5                       127.0.0.1:45997 0.0.0.0:*
  $ haseen ai models
  stub-model
  rc=0
  $ haseen ai chat "hello from haseen"
  [stub-model] echo: hello from haseen
  rc=0
  $ printf "ctx line" | haseen ai chat --model qwen3:4b "summarize"
  [qwen3:4b] echo: summarize

  ctx line
  rc=0
  server killed
  ```

  Streaming is incremental: with the stub sleeping 0.7 s between chunks, words arrived at `0.08s '[slow]'`, `0.78s echo:`, `2.18s 'stream'` (last word timed at stream end).

### Rejected

- **AMD → Vulkan by default.** ROCm (`ollama-rocm`, `ggml-hip`) pulls a multi-GB `hipblas` stack and supports fewer GPUs, but it is the GPU-matched runtime the task asks for and is faster where supported. `--accel vulkan` is the escape hatch.
- **Writing the unit into `~/.config/systemd/user`.** That directory belongs to the user; the unit ships with the tree via `share/haseen/systemd/user/` (architecture §2) and `ExecStart=haseen ai serve` (bare name; systemd searches `/usr/local/bin` and `/usr/bin`), so it is prefix-independent.
- **Baking the model path into the unit.** `haseen ai serve` reads ai.json at start, so changing `modelPath` needs only a restart.
- **Using llama-cpp's own `llama-server.service`.** It does not take the model or bind address from ai.json.
- **Naming the drop-in `zz-haseen.conf`** so it sorts last. The task fixes `haseen.conf`; instead, status and apply detect later drop-ins that re-expose the port.
- **Passing the key with `-H "Authorization: …"`.** It would show in `ps`; `-H @<(printf …)` keeps it in a pipe.

### Open risks

- [INFERENCE] Not run on a real Ollama or llama-server: the OpenAI streaming format was exercised against the stub only. Ollama's `/v1` (documented OpenAI compatibility) and llama-server's `/v1` use the same `data:` chunks.
- `ss` and `systemctl is-active` are live probes: under a fixture sysroot they still read the live machine unless stubbed (tests stub them).
- `haseen ai chat` reads stdin when it is a pipe or file; a caller that leaves a pipe open without writing would block it. The panel should call the HTTP API or close stdin.
- Reasoning models (qwen3) may spend tokens in `delta.reasoning`/`reasoning_content`, which chat does not print; only `delta.content` is shown.
- `ollama-rocm`/`ggml-hip` support only some AMD GPUs; unsupported ones fall back to CPU inside Ollama.
