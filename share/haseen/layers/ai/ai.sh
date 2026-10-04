# shellcheck shell=bash
# ai.sh — shared by layers/ai/layer.sh and bin/haseen-ai-*. Sourced, never
# executed.
#
# Two guarantees live here so every consumer gets them the same way:
#   1. Servers bind loopback only. Ollama gets a systemd drop-in pinning
#      OLLAMA_HOST=127.0.0.1:11434 (waydots plan 020 found it on 0.0.0.0 with
#      the firewall port pre-opened); llama.cpp is started by haseen-ai-serve,
#      which always passes --host 127.0.0.1. No firewall port is ever opened.
#   2. Clients obey ai.json "policy": "local" refuses any endpoint whose host is
#      not loopback; "any" allows remote endpoints. API keys never live in
#      ai.json: an endpoint names a "keyRef" and the key sits in the Secret
#      Service (secret-tool), passed to curl through a pipe, never argv.
#
# Socket state (ss) and service state (systemctl is-active) are live-only;
# they are not part of a sysroot fixture, so tests stub ss and systemctl.

[[ -n ${HASEEN_AI_SH:-} ]] && return 0
HASEEN_AI_SH=1
# shellcheck source=../../lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../lib/common.sh"
# shellcheck source=../../lib/packages.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../lib/packages.sh"

AI_DEFAULT_CONFIG="$HASEEN_PATH/default/ai.json"
AI_USER_CONFIG="$HASEEN_USER_CONFIG/ai.json"
AI_OLLAMA_ADDR=127.0.0.1:11434
AI_OLLAMA_DROPIN_DIR=/etc/systemd/system/ollama.service.d
AI_OLLAMA_DROPIN=$AI_OLLAMA_DROPIN_DIR/haseen.conf
AI_LLAMA_UNIT=haseen-llama.service
# secret-tool attribute name; the value is the endpoint's keyRef.
AI_SECRET_ATTR=haseen-ai

# --- configuration ---------------------------------------------------------

# ai_load_config — AI_CONFIG = default/ai.json deep-merged with the user's
# ~/.config/haseen/ai.json (jq '*': objects merge recursively, arrays and
# scalars from the user file win). Validates what consumers rely on.
ai_load_config() {
    require_cmds jq
    [[ -r $AI_DEFAULT_CONFIG ]] || die "missing $AI_DEFAULT_CONFIG"
    if [[ -e $AI_USER_CONFIG ]]; then
        jq -e 'type == "object"' "$AI_USER_CONFIG" >/dev/null 2>&1 ||
            die "$AI_USER_CONFIG is not a JSON object"
        AI_CONFIG="$(jq -s '.[0] * .[1]' "$AI_DEFAULT_CONFIG" "$AI_USER_CONFIG")"
    else
        AI_CONFIG="$(jq . "$AI_DEFAULT_CONFIG")"
    fi
    local policy leaked
    policy="$(ai_cfg '.policy // ""')"
    [[ $policy == local || $policy == any ]] ||
        die "ai.json: \"policy\" must be \"local\" or \"any\", not \"$policy\""
    # A key typed into ai.json would sit in plain text in a dotfile; refuse it
    # rather than silently use it.
    leaked="$(ai_cfg '.endpoints // {} | to_entries[]
        | select(.value | type == "object" and (keys | any(ascii_downcase | test("^(api_?key|key|token|secret|password)$"))))
        | .key')"
    [[ -z $leaked ]] || die "ai.json: endpoint(s) $(echo "$leaked" | paste -sd, -) carry a key; keys are never read from ai.json. Use \"keyRef\" and: haseen ai key set <endpoint>"
}

# ai_cfg FILTER [JQ ARGS...] — run a jq filter (raw output) over AI_CONFIG.
ai_cfg() {
    local filter="$1"
    shift
    jq -r "$@" "$filter" <<<"$AI_CONFIG"
}

# ai_resolve_endpoint [NAME] — sets EP_NAME EP_URL EP_MODEL EP_KEYREF for NAME
# (default: ai.json "default") and enforces the policy. Dies on refusal.
# shellcheck disable=SC2034  # EP_* are this function's output
ai_resolve_endpoint() {
    EP_NAME="${1:-$(ai_cfg '.default // ""')}"
    [[ -n $EP_NAME ]] || die "ai.json: no \"default\" endpoint and none given (--endpoint)"
    ai_cfg '.endpoints[$n] | type == "object"' --arg n "$EP_NAME" | grep -qx true ||
        die "unknown endpoint '$EP_NAME' (known: $(ai_cfg '.endpoints // {} | keys | join(", ")'))"
    local kind
    kind="$(ai_cfg '.endpoints[$n].kind // "openai"' --arg n "$EP_NAME")"
    [[ $kind == openai ]] || die "endpoint '$EP_NAME': kind '$kind' is not supported (only \"openai\")"
    EP_URL="$(ai_cfg '.endpoints[$n].url // ""' --arg n "$EP_NAME")"
    EP_URL="${EP_URL%/}"
    EP_MODEL="$(ai_cfg '.endpoints[$n].model // ""' --arg n "$EP_NAME")"
    EP_KEYREF="$(ai_cfg '.endpoints[$n].keyRef // ""' --arg n "$EP_NAME")"
    ai_check_policy "$EP_NAME" "$EP_URL"
}

# --- URLs and the local policy ---------------------------------------------

# ai_url_host URL — the host part, lowercased, brackets stripped from IPv6.
# Userinfo is dropped first so http://localhost@evil.example/ yields
# evil.example (what curl actually connects to).
ai_url_host() {
    local rest="${1#*://}" host
    rest="${rest%%[/?#]*}"
    rest="${rest##*@}"
    if [[ $rest == \[* ]]; then
        host="${rest%%]*}"
        host="${host#[}"
    else
        host="${rest%%:*}"
    fi
    printf '%s\n' "${host,,}"
}

# ai_url_port URL — explicit port, else the scheme default.
ai_url_port() {
    local rest="${1#*://}" port=""
    rest="${rest%%[/?#]*}"
    rest="${rest##*@}"
    if [[ $rest == \[* ]]; then
        [[ $rest == *]:* ]] && port="${rest##*]:}"
    elif [[ $rest == *:* ]]; then
        port="${rest##*:}"
    fi
    if [[ -z $port ]]; then
        [[ ${1,,} == https://* ]] && port=443 || port=80
    fi
    printf '%s\n' "$port"
}

# ai_host_is_loopback HOST — 127.0.0.0/8, ::1 or localhost. Exact matches
# only: 127.0.0.1.example.com is a remote name.
ai_host_is_loopback() {
    local h="${1#[}"
    h="${h%]}"
    case "${h,,}" in
    localhost | ::1 | 0:0:0:0:0:0:0:1) return 0 ;;
    esac
    [[ $h =~ ^127\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]] || return 1
    ((BASH_REMATCH[1] <= 255 && BASH_REMATCH[2] <= 255 && BASH_REMATCH[3] <= 255))
}

# ai_check_policy NAME URL — die unless URL is allowed by ai.json "policy".
ai_check_policy() {
    local name="$1" url="$2" host policy
    [[ $url =~ ^https?://[^/?#]+ ]] || die "endpoint '$name': url must start with http:// or https:// (got '$url')"
    host="$(ai_url_host "$url")"
    [[ -n $host ]] || die "endpoint '$name': no host in '$url'"
    policy="$(ai_cfg '.policy')"
    if ai_host_is_loopback "$host"; then
        return 0
    fi
    if [[ $policy != any ]]; then
        die "endpoint '$name' ($host) is not on this machine and ai.json policy is \"local\". Set \"policy\": \"any\" in $AI_USER_CONFIG to allow remote endpoints."
    fi
    [[ ${url,,} == https://* ]] || warn "endpoint '$name' is remote and not https: prompts travel in clear text"
}

# --- HTTP ------------------------------------------------------------------

ai_key_lookup() { secret-tool lookup "$AI_SECRET_ATTR" "$1" 2>/dev/null; }

# ai_curl KEYREF CURL_ARGS... — curl with "Authorization: Bearer" read from the
# Secret Service when KEYREF is set. The header goes through a pipe (curl -H
# @file), so the key never appears in argv or on disk.
ai_curl() {
    local ref="$1" key
    shift
    if [[ -z $ref ]]; then
        curl "$@"
        return
    fi
    key="$(ai_key_lookup "$ref")" || true
    [[ -n $key ]] || die "no API key stored under keyRef '$ref' (haseen ai key set <endpoint>)"
    curl -H @<(printf 'Authorization: Bearer %s\n' "$key") "$@"
}

# ai_models — model ids served by the resolved endpoint, one per line.
ai_models() {
    ai_curl "$EP_KEYREF" -fsS -m 10 "$EP_URL/models" | jq -r '.data[]?.id // empty'
}

# --- backends and packages -------------------------------------------------

# ai_pick_accel — the GPU-matched acceleration for GPU_VENDORS: a discrete
# NVIDIA or AMD GPU wins over an Intel iGPU (hybrid laptops); Intel uses
# Vulkan; no GPU means CPU.
ai_pick_accel() {
    case " ${GPU_VENDORS:-} " in
    *" nvidia "*) echo cuda ;;
    *" amd "*) echo rocm ;;
    *" intel "*) echo vulkan ;;
    *) echo cpu ;;
    esac
}

# ai_packages BACKEND ACCEL — repo packages (Arch extra; CachyOS rebuilds the
# same names in cachyos-extra-v3/v4). The GPU runners are add-ons that depend
# on the base package: ollama-{cuda,rocm,vulkan}; llama-cpp loads ggml
# backends from ggml-{cuda,hip,vulkan}.
ai_packages() {
    local backend="$1" accel="$2"
    case "$backend" in
    ollama)
        echo ollama
        case "$accel" in
        cuda) echo ollama-cuda ;;
        rocm) echo ollama-rocm ;;
        vulkan) echo ollama-vulkan ;;
        esac
        ;;
    llama.cpp)
        echo llama-cpp
        case "$accel" in
        cuda) echo ggml-cuda ;;
        rocm) echo ggml-hip ;;
        vulkan) echo ggml-vulkan ;;
        esac
        ;;
    *) die "unknown backend '$backend' (ollama | llama.cpp)" ;;
    esac
}

# ai_installed_accel BACKEND — which acceleration package is installed.
ai_installed_accel() {
    local backend="$1" a p
    for a in cuda rocm vulkan; do
        p="$(ai_packages "$backend" "$a" | sed -n 2p)"
        pkg_installed "$p" && {
            echo "$a ($p)"
            return 0
        }
    done
    echo cpu
}

ai_ollama_dropin() {
    cat <<EOF
# Managed by haseen (layer ai). Ollama's API has no authentication: keep it on
# loopback. Do not open port 11434 in the firewall. Undo: haseen layer remove ai
[Service]
Environment=OLLAMA_HOST=$AI_OLLAMA_ADDR
EOF
}

# ai_dropin_current — 0 when the installed drop-in matches ai_ollama_dropin.
ai_dropin_current() {
    local f
    f="$(sysroot_path "$AI_OLLAMA_DROPIN")"
    [[ -r $f && "$(<"$f")" == "$(ai_ollama_dropin)" ]]
}

# ai_dropin_shadows — drop-ins that sort after haseen.conf (so they win) and
# set OLLAMA_HOST to something that is not loopback. Printed one per line.
ai_dropin_shadows() {
    local dir f val host
    dir="$(sysroot_path "$AI_OLLAMA_DROPIN_DIR")"
    [[ -d $dir ]] || return 0
    for f in "$dir"/*.conf; do
        [[ -r $f && ${f##*/} > haseen.conf ]] || continue
        val="$(sed -n 's/^[[:space:]]*Environment=.*OLLAMA_HOST=\([^"[:space:]]*\).*/\1/p' "$f" | tail -n1)"
        [[ -n $val ]] || continue
        [[ $val == *://* ]] || val="http://$val"
        host="$(ai_url_host "$val")"
        ai_host_is_loopback "$host" || printf '%s (OLLAMA_HOST=%s)\n' "${f#"$HASEEN_SYSROOT"}" "${val#http://}"
    done
}

# ai_listen_addrs PORT — local addresses with a TCP listener on PORT (ss).
ai_listen_addrs() {
    have ss || return 0
    ss -ltnH 2>/dev/null | awk -v p=":$1" '{
        a = $4; sub(/%[^:]*:/, ":", a)
        if (length(a) > length(p) && substr(a, length(a) - length(p) + 1) == p)
            print substr(a, 1, length(a) - length(p))
    }' | sort -u
}

# ai_bind_check LABEL PORT — status line about who listens on PORT.
# Returns 0 loopback only, 1 nothing listening, 2 exposed to the network.
ai_bind_check() {
    local label="$1" port="$2" a exposed=() addrs=()
    mapfile -t addrs < <(ai_listen_addrs "$port")
    if ((${#addrs[@]} == 0)); then
        echo "missing: nothing listens on port $port ($label not running?)"
        return 1
    fi
    for a in "${addrs[@]}"; do
        ai_host_is_loopback "$a" || exposed+=("$a:$port")
    done
    if ((${#exposed[@]} > 0)); then
        echo "warn: $label is reachable from the network on ${exposed[*]}; it must bind 127.0.0.1 only"
        return 2
    fi
    echo "ok: $label listens on loopback only (${addrs[*]/%/:$port})"
}

# ai_unit_wanted UNIT TARGET — is a system unit enabled (wants symlink)?
ai_unit_wanted() { [[ -L $(sysroot_path "/etc/systemd/system/$2.wants/$1") ]]; }

ai_user_unit_wanted() { [[ -L ${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/default.target.wants/$AI_LLAMA_UNIT ]]; }

# ai_status_lines — the layer's health. Same "ok:/missing:/warn:" contract as
# layer_status; returns 0 healthy, 1 no backend installed, 2 degraded.
ai_status_lines() {
    local rc=0 any=false shadow
    if pkg_installed ollama; then
        any=true
        echo "ok: ollama installed (accel: $(ai_installed_accel ollama))"
        if ai_dropin_current; then
            echo "ok: loopback drop-in $AI_OLLAMA_DROPIN"
        else
            echo "missing: loopback drop-in $AI_OLLAMA_DROPIN (haseen layer apply ai)"
            rc=2
        fi
        while read -r shadow; do
            [[ -n $shadow ]] || continue
            echo "warn: $shadow overrides the loopback drop-in"
            rc=2
        done < <(ai_dropin_shadows)
        if ai_unit_wanted ollama.service multi-user.target; then
            echo "ok: ollama.service enabled"
        else
            echo "missing: ollama.service not enabled"
            rc=2
        fi
        ai_bind_check ollama "${AI_OLLAMA_ADDR##*:}" || rc=2
    fi
    if pkg_installed llama-cpp; then
        any=true
        echo "ok: llama-cpp installed (accel: $(ai_installed_accel llama.cpp))"
        if ai_user_unit_wanted; then
            echo "ok: $AI_LLAMA_UNIT enabled (user)"
            ai_bind_check llama-server "$(ai_url_port "$(ai_cfg '.endpoints.llamacpp.url // ""')")" || rc=2
        else
            echo "warn: $AI_LLAMA_UNIT not enabled (set endpoints.llamacpp.modelPath, then: haseen layer apply ai -- --backend llama.cpp)"
        fi
    fi
    if ! $any; then
        echo "missing: no local AI backend installed (haseen layer apply ai)"
        return 1
    fi
    return "$rc"
}

# --- model suggestion ------------------------------------------------------

# ai_mem_kib — MemTotal in KiB from (sysroot) /proc/meminfo; empty if unknown.
ai_mem_kib() {
    local f
    f="$(sysroot_path /proc/meminfo)"
    [[ -r $f ]] || return 0
    awk '/^MemTotal:/ { print $2; exit }' "$f"
}

# ai_suggest_model — "TAG<TAB>why". Sized so the model plus a desktop fit in
# RAM on CPU inference. A "16 GB" machine reports ~15.3 GiB MemTotal, hence
# the 15 GiB cut-off. Suggestions only: nothing is downloaded automatically.
ai_suggest_model() {
    local kib gib
    kib="$(ai_mem_kib)"
    if [[ -z $kib ]]; then
        printf 'qwen3:4b\tRAM unknown\n'
        return 0
    fi
    gib=$(((kib + 524288) / 1048576))
    if ((kib < 7 * 1048576)); then
        printf 'qwen3:1.7b\tRAM ~%s GB\n' "$gib"
    elif ((kib < 15 * 1048576)); then
        printf 'qwen3:4b\tRAM ~%s GB\n' "$gib"
    else
        printf 'qwen3:8b\tRAM ~%s GB\n' "$gib"
    fi
}

# ai_print_suggestion BACKEND — Ollama pulls by tag; llama.cpp loads a .gguf
# the user downloads, so it gets the size class instead of a pull command.
ai_print_suggestion() {
    local tag why size
    IFS=$'\t' read -r tag why < <(ai_suggest_model)
    if [[ ${1:-ollama} == llama.cpp ]]; then
        size="${tag#*:}"
        info "suggested model size ($why): ${size^^} parameters (e.g. Qwen3-${size^^} as a Q4_K_M .gguf); haseen downloads nothing"
    else
        info "suggested model ($why): $tag. Nothing is downloaded until you run: haseen ai pull $tag"
    fi
}
