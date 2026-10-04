# shellcheck shell=bash disable=SC2034  # LAYER_* are read by lib/layers.sh
# layers/ai — local AI: Ollama (default) or llama.cpp, GPU-matched, loopback
# only. Contract: share/haseen/lib/layers.sh. Plan: plans/006-ai-layer.md.

LAYER_SUMMARY="Ollama (or llama.cpp) on 127.0.0.1, GPU-matched backend"
LAYER_REQUIRES=(base)
LAYER_CONFLICTS=()
LAYER_DISTROS=(cachyos arch omarchy)

# BASH_SOURCE, not LAYER_DIR: layer_field sources this file without the env.
# shellcheck source=ai.sh
source "$(dirname "${BASH_SOURCE[0]}")/ai.sh"

layer_usage() {
    cat <<'EOF'
ai layer flags (after --):
  --backend ollama|llama.cpp   server to install (default: ollama)
  --accel auto|cuda|rocm|vulkan|cpu
                               GPU runtime (default: auto from the detected GPU:
                               nvidia->cuda, amd->rocm, intel->vulkan, none->cpu)
EOF
}

# ai_parse_layer_args ARGS... — AI_BACKEND, AI_ACCEL (resolved, never "auto").
ai_parse_layer_args() {
    AI_BACKEND=ollama
    AI_ACCEL=auto
    while (($# > 0)); do
        case "$1" in
        --backend) AI_BACKEND="${2:-}"; shift ;;
        --backend=*) AI_BACKEND="${1#*=}" ;;
        --accel) AI_ACCEL="${2:-}"; shift ;;
        --accel=*) AI_ACCEL="${1#*=}" ;;
        *) layer_usage >&2; die "ai layer: unknown argument '$1'" ;;
        esac
        shift
    done
    case "$AI_BACKEND" in
    ollama | llama.cpp) ;;
    llamacpp | llama-cpp) AI_BACKEND=llama.cpp ;;
    *) die "ai layer: --backend must be ollama or llama.cpp (got '$AI_BACKEND')" ;;
    esac
    case "$AI_ACCEL" in
    auto) AI_ACCEL="$(ai_pick_accel)" ;;
    cuda | rocm | vulkan | cpu) ;;
    *) die "ai layer: --accel must be auto, cuda, rocm, vulkan or cpu (got '$AI_ACCEL')" ;;
    esac
}

ai_apply_ollama() {
    local pkgs=()
    mapfile -t pkgs < <(ai_packages ollama "$AI_ACCEL")
    pkg_install "${pkgs[@]}"
    if ! ai_dropin_current; then
        ai_ollama_dropin | write_root_file "$AI_OLLAMA_DROPIN" 0644
        run_root systemctl daemon-reload
        # A server started before the drop-in existed may be on 0.0.0.0;
        # try-restart only touches it when it is running.
        run_root systemctl try-restart ollama.service
    fi
    run_root systemctl enable --now ollama.service
    local shadow
    while read -r shadow; do
        [[ -z $shadow ]] || warn "$shadow overrides haseen's loopback binding; remove it"
    done < <(ai_dropin_shadows)
}

ai_apply_llamacpp() {
    local pkgs=() model_path def
    mapfile -t pkgs < <(ai_packages llama.cpp "$AI_ACCEL")
    pkg_install "${pkgs[@]}"
    # Point the CLI at llama.cpp. Seeded once; after that the file is the user's.
    if [[ -e $AI_USER_CONFIG ]]; then
        def="$(ai_cfg '.default // ""')"
        [[ $def == llamacpp ]] ||
            info "$AI_USER_CONFIG exists with \"default\": \"$def\"; set it to \"llamacpp\" to make llama.cpp the default endpoint"
    else
        seed_user_file "$LAYER_DIR/files/ai.llamacpp.json" "$AI_USER_CONFIG"
    fi
    # haseen-llama.service ships in PREFIX/lib/systemd/user (install.sh).
    run systemctl --user daemon-reload
    model_path="$(ai_cfg '.endpoints.llamacpp.modelPath // ""')"
    if [[ -n $model_path ]]; then
        run systemctl --user enable --now "$AI_LLAMA_UNIT"
    else
        info "llama.cpp needs a model: set endpoints.llamacpp.modelPath to a .gguf file in $AI_USER_CONFIG, then re-run: haseen layer apply ai -- --backend llama.cpp"
    fi
}

layer_apply() {
    ai_parse_layer_args "$@"
    ai_load_config
    info "GPU: ${GPU_VENDORS:-none}; backend $AI_BACKEND with $AI_ACCEL acceleration"
    case "$AI_BACKEND" in
    ollama) ai_apply_ollama ;;
    llama.cpp) ai_apply_llamacpp ;;
    esac
    info "no firewall port is opened: the API is reachable from this machine only"
    ai_print_suggestion "$AI_BACKEND"
}

layer_status() {
    ai_load_config
    ai_status_lines
}

# Services and the drop-in go; packages and downloaded models stay (models are
# large and the user may want them back).
layer_remove() {
    if pkg_installed ollama; then
        run_root systemctl disable --now ollama.service
    fi
    if [[ -e $(sysroot_path "$AI_OLLAMA_DROPIN") ]]; then
        run_root rm -f "$AI_OLLAMA_DROPIN"
        run_root rmdir --ignore-fail-on-non-empty "$AI_OLLAMA_DROPIN_DIR"
        run_root systemctl daemon-reload
    fi
    if ai_user_unit_wanted; then
        run systemctl --user disable --now "$AI_LLAMA_UNIT"
    fi
    info "packages and models kept; to remove them: pacman -Rns ollama llama-cpp (models: /var/lib/ollama)"
}
