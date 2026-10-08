# shellcheck shell=bash
# Explicit mutation/exposure orchestration; metadata stays in Python.
source "$HASEEN_PATH/layers/vapt/workflow.sh"
source "$HASEEN_PATH/layers/vapt/pacman.sh"

vapt_actions() { /usr/bin/python3 -B "$HASEEN_PATH/layers/vapt/workflow_actions.py" "$@"; }
vapt_action_refuse_fixture() {
    if in_sysroot && ! $DRY_RUN; then
        warn 'VAPT action refuses HASEEN_SYSROOT; fixture evidence cannot drive live actions; use --dry-run'
        return 1
    fi
}
vapt_json_field() {
    /usr/bin/python3 -B -c 'import json,sys; v=json.load(sys.stdin); print(v[sys.argv[1]])' "$1"
}

vapt_service_action() {
    local verb="$1" service="$2" first second unit
    case "$verb" in start|stop|restart) ;; *) warn 'unsupported service operation'; return 2 ;; esac
    case "$service" in ssh|postgresql|apache|nginx|beef) ;; *) warn 'unknown service id'; return 2 ;; esac
    first="$(vapt_actions service-plan "$service")" || return 1
    unit="$(printf '%s' "$first" | vapt_json_field unit)" || return 1
    printf '%s %s: unit %s; exposure unknown (local configuration may bind ports).\n' "$verb" "$service" "$unit"
    if $DRY_RUN; then
        [[ $verb == stop ]] || echo 'DRYRUN: start/restart requires explicit exposure confirmation'
        echo "DRYRUN: revalidate FragmentPath/ownership immediately before systemctl $verb; never enable"
        return 0
    fi
    vapt_action_refuse_fixture || return 1
    source "$HASEEN_PATH/lib/terminal.sh"
    local terminal_args=("$service")
    $ASSUME_YES && terminal_args+=(--yes)
    in_floating_terminal "${terminal_args[@]}"
    if [[ $verb != stop ]]; then
        confirm "Accept exposure uncertainty and $verb $unit?" || { warn 'cancelled; no service operation'; return 1; }
    fi
    second="$(vapt_actions service-plan "$service")" || return 1
    [[ $first == "$second" ]] || { warn 'service state/FragmentPath changed during review; no operation'; return 1; }
    vapt_root_exec /usr/bin/systemctl "$verb" -- "$unit"
}

vapt_endpoint_action() {
    local kind="$1"
    shift
    local original=("$@")
    $ASSUME_YES && original+=(--yes)
    local address='' port='' path='' arg value plan nonloop adapter family
    while (($#)); do
        arg="$1"; shift
        case "$arg" in
        --bind|--file)
            (($#)) || { usage >&2; return 2; }
            value="$1"; shift
            [[ -n $value && $value != --* ]] || { usage >&2; return 2; }
            if [[ $arg == --bind ]]; then
                [[ -z $address ]] || { usage >&2; return 2; }; address="$value"
            else
                [[ $kind == enumeration-host && -z $path ]] || { usage >&2; return 2; }; path="$value"
            fi ;;
        --*) usage >&2; return 2 ;;
        *)
            if [[ $kind == http-server && -z $path ]]; then path="$arg"
            elif [[ -z $port ]]; then port="$arg"
            else usage >&2; return 2
            fi ;;
        esac
    done
    if [[ -z $port || ( $kind == http-server && -z $path ) ]]; then
        if $DRY_RUN; then warn 'explicit directory/port selection required; dry-run performs no prompt or bind'; return 1; fi
        vapt_action_refuse_fixture || return 1
        source "$HASEEN_PATH/lib/terminal.sh"
        in_floating_terminal "${original[@]}"
        [[ $kind != http-server || -n $path ]] || read -r -p 'Local directory: ' path || return 1
        [[ -n $port ]] || read -r -p 'Local port (1024-65535): ' port || return 1
    fi
    if [[ $kind == enumeration-host && -z $path ]]; then
        path="$(vapt_actions selection)" || return 1
        # endpoint-plan also reads the setting; when unset ask only explicitly.
        if [[ -z $path ]] && ! $DRY_RUN; then
            vapt_action_refuse_fixture || return 1
            source "$HASEEN_PATH/lib/terminal.sh"
            in_floating_terminal "${original[@]}"
            read -r -p 'Verified installed package-owned file: ' path || return 1
        fi
    fi
    plan="$(vapt_actions endpoint-plan "$kind" "$address" "$port" "$path")" || return 1
    printf '%s\n' "$plan"
    if $DRY_RUN; then
        echo 'DRYRUN: validate again before foreground action; no writes, bind, serving or execution performed'
        return 0
    fi
    vapt_action_refuse_fixture || return 1
    source "$HASEEN_PATH/lib/terminal.sh"
    in_floating_terminal "${original[@]}"
    nonloop="$(printf '%s' "$plan" | /usr/bin/python3 -B -c 'import json,sys; print("yes" if json.load(sys.stdin)["endpoint"]["requiresConfirmation"] else "no")')"
    if [[ $kind != listener || $nonloop == yes ]]; then
        confirm 'Accept this explicit byte-serving/listening scope and exposure?' || { warn 'cancelled; no foreground action'; return 1; }
    fi
    [[ $plan == "$(vapt_actions endpoint-plan "$kind" "$address" "$port" "$path")" ]] || { warn 'selected adapter/path changed; no action'; return 1; }
    address="$(printf '%s' "$plan" | /usr/bin/python3 -B -c 'import json,sys; print(json.load(sys.stdin)["endpoint"]["address"])')"
    adapter="$(printf '%s' "$plan" | vapt_json_field adapter)"
    if [[ $kind == listener ]]; then
        family="$(printf '%s' "$plan" | /usr/bin/python3 -B -c 'import json,sys; print("-4" if json.load(sys.stdin)["endpoint"]["family"] == "ipv4" else "-6")')"
        run "$adapter" "$family" -l -n -- "$address" "$port"
    else
        run "$adapter" -B "$HASEEN_PATH/layers/vapt/workflow_actions.py" serve "$kind" "$address" "$port" "$path" "$plan"
    fi
}

vapt_ca_action() {
    local verb="$1" operand="${2:-}" result fingerprint payload
    case "$verb" in
    status) vapt_actions ca-status "${CA_FLAGS[@]}" ;;
    inspect) vapt_actions inspect "$operand" "${CA_FLAGS[@]}" ;;
    trust)
        result="$(vapt_actions inspect "$operand" --json)" || { printf '%s\n' "$result"; return 1; }
        printf '%s\n' "$result"
        fingerprint="$(printf '%s' "$result" | /usr/bin/python3 -B -c 'import json,sys; print(json.load(sys.stdin)["certificate"]["sha256"])')" || return 1
        /usr/bin/python3 -B "$HASEEN_PATH/layers/vapt/workflow_actions.py" adapter proxy-ca >/dev/null || return 1
        vapt_actions ca-trust-check "$fingerprint" || return 1
        if $DRY_RUN; then
            echo "DRYRUN: require typed SHA-256 $fingerprint; recheck immutable certificate bytes and owned trust updater; install only fingerprint-bound owned anchor and update system trust"
            return 0
        fi
        vapt_action_refuse_fixture || return 1
        source "$HASEEN_PATH/lib/terminal.sh"
        local terminal_args=(trust "$operand")
        $ASSUME_YES && terminal_args+=(--yes)
        in_floating_terminal "${terminal_args[@]}"
        confirm_typed 'System-wide CA trust can permit interception. --yes cannot accept this gate.' "$fingerprint" || { warn 'fingerprint not accepted; no trust change'; return 1; }
        payload="$(vapt_actions ca-payload "$operand" "$fingerprint")" || return 1
        vapt_actions adapter proxy-ca >/dev/null || return 1
        vapt_actions ca-trust-check "$fingerprint" || return 1
        printf '%s' "$payload" | vapt_root_exec /usr/bin/python3 -I -S -B "$HASEEN_PATH/layers/vapt/workflow_ca.py" trust "$fingerprint" ;;
    remove)
        [[ $operand =~ ^[A-F0-9]{64}$ ]] || { usage >&2; return 2; }
        result="$(vapt_actions ca-status --json)" || { printf '%s\n' "$result"; return 1; }
        fingerprint="$(printf '%s' "$result" | /usr/bin/python3 -B -c 'import json,sys; r=json.load(sys.stdin); assert r["state"]=="owned" and r["anchor"]["unchanged"]; print(r["anchor"]["sha256"])')" || return 1
        [[ $operand == "$fingerprint" ]] || { warn 'fingerprint does not match unchanged owned anchor'; return 1; }
        printf '%s\n' "$result"
        vapt_actions ca-updater || return 1
        if $DRY_RUN; then echo 'DRYRUN: revalidate unchanged owned anchor; remove only this anchor and update system trust'; return 0; fi
        vapt_action_refuse_fixture || return 1
        source "$HASEEN_PATH/lib/terminal.sh"
        local terminal_args=(remove "$operand")
        $ASSUME_YES && terminal_args+=(--yes)
        in_floating_terminal "${terminal_args[@]}"
        confirm 'Remove this unchanged haseen-owned system CA anchor?' || { warn 'cancelled; no trust change'; return 1; }
        vapt_actions ca-updater || return 1
        vapt_root_exec /usr/bin/python3 -I -S -B "$HASEEN_PATH/layers/vapt/workflow_ca.py" remove "$fingerprint" ;;
    *) usage >&2; return 2 ;;
    esac
}
