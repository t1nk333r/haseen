# shellcheck shell=bash
# plugin.sh — plugin manifests and shell.json edits for bin/haseen-plugin-*.
# Sourced, never executed. jq and bash only (no python in the shell path).
#
# The checks mirror share/haseen/shell/plugin.schema.json (architecture 5.2);
# Haseen/Plugins.qml repeats the minimal subset the running shell needs.

[[ -n ${HASEEN_PLUGIN_SH:-} ]] && return 0
HASEEN_PLUGIN_SH=1
# shellcheck source=../../lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../lib/common.sh"

PLUGIN_ID_RE='^[a-z0-9-]+(\.[a-z0-9-]+)+$'
PLUGIN_KINDS=(bar-widget panel service launcher-provider overlay)
PLUGIN_USER_DIR="$HASEEN_USER_CONFIG/plugins"
PLUGIN_BUILTIN_DIR="$HASEEN_PATH/shell/plugins"
SHELL_DEFAULT_CONFIG="$HASEEN_PATH/default/shell.json"
SHELL_USER_CONFIG="$HASEEN_USER_CONFIG/shell.json"

require_cmds jq

plugin_kind_known() {
    local k
    for k in "${PLUGIN_KINDS[@]}"; do
        [[ $k == "$1" ]] && return 0
    done
    return 1
}

# plugin_dir ID — the directory that wins for ID (user copy first).
plugin_dir() {
    local d
    for d in "$PLUGIN_USER_DIR/$1" "$PLUGIN_BUILTIN_DIR/$1"; do
        [[ -d $d ]] && {
            printf '%s\n' "$d"
            return 0
        }
    done
    return 1
}

# plugin_origin DIR — user | builtin | path (a checkout outside both dirs).
plugin_origin() {
    case "$(dirname "$1")" in
    "$PLUGIN_USER_DIR") echo user ;;
    "$PLUGIN_BUILTIN_DIR") echo builtin ;;
    *) echo path ;;
    esac
}

# plugin_resolve ARG — ARG is an id, a plugin directory or its manifest.json.
plugin_resolve() {
    local arg="$1"
    if [[ $arg == */* || $arg == . || $arg == .. ]]; then
        [[ -f $arg && ${arg##*/} == manifest.json ]] && arg="$(dirname "$arg")"
        [[ -d $arg ]] || die "no such plugin directory: $arg"
        (cd "$arg" && pwd)
        return 0
    fi
    plugin_dir "$arg" && return 0
    die "unknown plugin: $arg (looked in $PLUGIN_USER_DIR and $PLUGIN_BUILTIN_DIR)"
}

# plugin_ids — every plugin directory name in both locations, sorted, unique.
plugin_ids() {
    local d
    for d in "$PLUGIN_USER_DIR"/*/ "$PLUGIN_BUILTIN_DIR"/*/; do
        [[ -d $d ]] && basename "$d"
    done | sort -u
}

# plugin_check DIR — prints "error: …" / "warning: …" lines; returns 1 on any
# error. The schema rules live in the jq program; bash adds what jq cannot
# see: the directory name and the entry files on disk.
plugin_check() {
    local dir="$1" manifest="$1/manifest.json" name errors=0 line entry
    name="$(basename "$dir")"
    if [[ ! -r $manifest ]]; then
        echo "error: $manifest is missing"
        return 1
    fi
    if ! jq empty "$manifest" 2>/dev/null; then
        echo "error: manifest.json is not valid JSON"
        return 1
    fi
    while IFS= read -r line; do
        [[ -n $line ]] || continue
        case "$line" in
        entry:*)
            entry="${line#entry:}"
            [[ -f $dir/$entry ]] || {
                echo "error: entry file '$entry' does not exist"
                errors=1
            }
            ;;
        warning:*) echo "$line" ;;
        *)
            echo "error: $line"
            errors=1
            ;;
        esac
    done < <(jq -r --arg re "$PLUGIN_ID_RE" --arg dirname "$name" '
        def kinds: ["bar-widget", "panel", "service", "launcher-provider", "overlay"];
        def perms: ["exec", "network", "network:local", "files:read", "files:write", "notifications"];
        def fields: ["schemaVersion", "id", "name", "version", "description", "kinds", "entry", "settings", "permissions", "provides"];
        def settypes: ["string", "number", "integer", "boolean", "array", "object"];
        def is_str: type == "string";
        def typeok($t): if $t == "integer" then (type == "number" and . == floor)
            elif $t == "number" then type == "number"
            elif $t == "string" then type == "string"
            elif $t == "boolean" then type == "boolean"
            elif $t == "array" then type == "array"
            else type == "object" end;
        if type != "object" then "manifest is not a JSON object" else
        (keys - fields | .[] | "unknown field \u0027\(.)\u0027"),
        (if .schemaVersion != 1 then "schemaVersion must be 1" else empty end),
        (if (.id | is_str) and (.id | test($re)) then
            (if .id != $dirname then "id \u0027\(.id)\u0027 does not match its directory \u0027\($dirname)\u0027" else empty end)
         else "id must be a string matching \($re)" end),
        (if (.name | is_str) and (.name | length) > 0 then empty else "name is required" end),
        (if (.version | is_str) and (.version | test("^[0-9]+\\.[0-9]+\\.[0-9]+([-+][0-9A-Za-z.-]+)?$")) then empty
         else "version must be semver (e.g. 1.0.0)" end),
        (if has("description") and (.description | is_str | not) then "description must be a string" else empty end),
        (if (.kinds | type) != "array" or (.kinds | length) == 0 then "kinds must be a non-empty array"
         else
            (.kinds[] | select(. as $k | kinds | index([$k]) | not) | "unknown kind \u0027\(.)\u0027"),
            (if (.kinds | length) != (.kinds | unique | length) then "kinds has duplicates" else empty end)
         end),
        (if (.entry | type) != "object" then "entry must be an object mapping kind to a .qml file"
         else
            (.entry | keys[] | select(. as $k | kinds | index([$k]) | not) | "entry for unknown kind \u0027\(.)\u0027"),
            (.entry | to_entries[] | select((.value | is_str | not) or (.value | test("^/|(^|/)\\.\\.(/|$)")) or (.value | test("\\.qml$") | not))
                | "entry \u0027\(.key)\u0027 must be a relative .qml path inside the plugin"),
            (if (.kinds | type) == "array" then
                . as $m | $m.kinds[] | select(is_str) | . as $k
                    | select(kinds | index([$k])) | select($m.entry | has($k) | not)
                    | "kind \u0027\($k)\u0027 has no entry"
             else empty end)
         end),
        (if has("settings") then
            if (.settings | type) != "object" then "settings must be an object"
            else .settings | to_entries[] |
                if (.value | type) != "object" then "setting \u0027\(.key)\u0027 must be an object"
                elif (.value.type as $t | settypes | index([$t]) | not) then "setting \u0027\(.key)\u0027 has an unknown type"
                elif (.value | keys - ["type", "default", "description"] | length) > 0 then "setting \u0027\(.key)\u0027 has unknown fields"
                elif (.value | has("default")) and (.value.type as $t | .value.default | typeok($t) | not) then "setting \u0027\(.key)\u0027 default is not of type \(.value.type)"
                else empty end
            end
         else empty end),
        (if has("permissions") then
            if (.permissions | type) != "array" then "permissions must be an array"
            else
                (.permissions[] | select(. as $p | perms | index([$p]) | not) | "unknown permission \u0027\(.)\u0027"),
                (if (.permissions | length) != (.permissions | unique | length) then "permissions has duplicates" else empty end)
            end
         else empty end),
        (if has("provides") then
            if (.provides | type) != "array" then "provides must be an array"
            else
                (.provides[] | select((is_str | not) or (test("^[a-z][a-z0-9-]*$") | not)) | "invalid role \u0027\(.)\u0027 in provides"),
                (if (.provides | length) != (.provides | unique | length) then "provides has duplicates" else empty end)
            end
         else empty end),
        (if (.entry | type) == "object" then .entry | to_entries[]
            | select((.value | is_str) and (.value | test("^/|(^|/)\\.\\.(/|$)") | not) and (.value | test("\\.qml$")))
            | "entry:\(.value)"
         else empty end)
        end
    ' "$manifest" 2>&1)
    return "$errors"
}

# plugin_field DIR JQ_FILTER — read one value from a (valid) manifest.
plugin_field() { jq -r "$2" "$1/manifest.json"; }

# plugin_permissions DIR — prints the permission summary; warns on network.
plugin_permissions() {
    local perms
    perms="$(jq -r '(.permissions // []) | join(", ")' "$1/manifest.json")"
    echo "permissions: ${perms:-none}"
    if jq -e '(.permissions // []) | index(["network"])' "$1/manifest.json" >/dev/null; then
        echo "warning: requests unrestricted 'network' access. QML cannot sandbox plugins; review the code before enabling it."
    fi
}

# shell_user_json — the user shell.json (or {} when absent). Dies on invalid
# JSON rather than overwrite a file the user is editing.
shell_user_json() {
    if [[ -e $SHELL_USER_CONFIG ]]; then
        jq -e 'type == "object"' "$SHELL_USER_CONFIG" >/dev/null 2>&1 ||
            die "$SHELL_USER_CONFIG is not a JSON object; fix it first"
        jq . "$SHELL_USER_CONFIG"
    else
        echo '{}'
    fi
}

# shell_merged_json — default/shell.json deep-merged with the user file, the
# same rule as Haseen/Config.qml (objects merge, arrays replace).
shell_merged_json() {
    local user
    user="$(shell_user_json)"
    jq --argjson u "$user" '. * $u' "$SHELL_DEFAULT_CONFIG"
}

# shell_config_write — stdin becomes the user shell.json. Written next to it
# and renamed into place, so the running shell (FileView watch) never reads a
# half-written file. FileView cannot see a file that did not exist when the
# shell started, so a first-time write asks for a reload.
shell_config_write() {
    local existed=true
    [[ -e $SHELL_USER_CONFIG ]] || existed=false
    write_user_file "$SHELL_USER_CONFIG.new"
    run mv -f -- "$SHELL_USER_CONFIG.new" "$SHELL_USER_CONFIG"
    $existed || info "new $SHELL_USER_CONFIG: apply it to a running shell with: haseen shell ipc shell reload"
}

# plugin_state ID KINDS... — enabled | disabled | available | on-demand.
plugin_state() {
    local id="$1"
    shift
    local kinds_json
    kinds_json="$(printf '%s\n' "$@" | jq -R . | jq -s .)"
    shell_merged_json | jq -r --arg id "$id" --argjson kinds "$kinds_json" '
        def listed: [(.bar.left // []), (.bar.center // []), (.bar.right // []), (.services // [])] | add | index([$id]);
        if .plugins[$id].enabled == false then "disabled"
        elif listed then "enabled"
        elif ($kinds | index(["bar-widget"])) or ($kinds | index(["service"])) then "available"
        else "on-demand" end'
}
