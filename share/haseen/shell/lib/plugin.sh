# shellcheck shell=bash
# plugin.sh — plugin manifests and shell.json edits for bin/haseen-plugin-*.
# Sourced, never executed. jq and bash only (no python in the shell path).
#
# The checks mirror share/haseen/shell/plugin.schema.json (architecture 5.2);
# Haseen/Plugins.qml repeats the minimal subset the running shell needs.
#
# Compat (architecture 5.4): Omarchy manifests (`entryPoints`) and DMS
# plugin.json files are adapted to the native shape by plugin_adapt, the jq
# twin of share/haseen/shell/Compat/Manifest.js, then checked like native
# ones. ~/.config/omarchy/plugins and ~/.config/DankMaterialShell/plugins
# are searched (read-only) after the user and built-in directories.

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
PLUGIN_OMARCHY_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins"
PLUGIN_DMS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/DankMaterialShell/plugins"

require_cmds jq

plugin_kind_known() {
    local k
    for k in "${PLUGIN_KINDS[@]}"; do
        [[ $k == "$1" ]] && return 0
    done
    return 1
}

# plugin_compat DIR — "" (native), omarchy or dms, from the manifest format.
plugin_compat() {
    if [[ -r $1/manifest.json ]]; then
        jq -e 'type == "object" and (.entryPoints | type) == "object" and (has("entry") | not)' \
            "$1/manifest.json" >/dev/null 2>&1 && echo omarchy
    elif [[ -r $1/plugin.json ]]; then
        echo dms
    fi
    return 0
}

# Compat/Manifest.js in jq: an Omarchy manifest or a DMS plugin.json ->
# {compat, upstreamId, id, problems, unsupported, manifest}. Keep the two in
# step; tests/test-compat.sh runs both over the same fixtures.
# shellcheck disable=SC2016  # jq program, not shell expansions
PLUGIN_ADAPT_JQ='
def isobj: type == "object";
def truthy: . != null and . != false and . != "" and . != 0;
def kebab: gsub("(?<a>[a-z0-9])(?<b>[A-Z])"; "\(.a)-\(.b)") | gsub("(?<a>[A-Z])(?<b>[A-Z][a-z])"; "\(.a)-\(.b)")
    | ascii_downcase | gsub("[^a-z0-9-]+"; "-") | gsub("^-+|-+$"; "");
def dmsid: "dms." + (kebab | if . == "" then "unnamed" else . end);
def omid: if test("^[a-z0-9-]+$") then "omarchy." + . else . end;
def omsupported: ["bar-widget", "service", "panel", "overlay"];
def omentry: {"bar-widget": "barWidget", "service": "service", "panel": "panel", "overlay": "overlay"};
def settype($t; $v): if (["string", "number", "integer", "boolean", "array", "object"] | index([$t])) then $t
    elif ($v | type) == "array" or ($v | type) == "boolean" or ($v | type) == "number" or ($v | type) == "object" then ($v | type)
    else "string" end;
def omsection: (if isobj then . else {} end) as $bw
    | (if ($bw.defaults | isobj) then $bw.defaults else {} end) as $d
    | (if ($bw.schema | type) == "array" then $bw.schema else [] end) as $s
    | reduce ($s[] | select(isobj and (.key | type) == "string" and .key != "")) as $e ({};
        (if ($d | has($e.key)) then {v: $d[$e.key]} elif ($e | has("defaultValue")) then {v: $e.defaultValue} else {} end) as $val
        | . + {($e.key): ({type: settype($e.type; $val.v)}
            + (if ($val | has("v")) then {default: $val.v} else {} end)
            + (if ($e.description | type) == "string" then {description: $e.description}
               elif ($e.label | type) == "string" then {description: $e.label} else {} end))})
    | reduce ($d | keys_unsorted[]) as $k (.; if has($k) then . else . + {($k): {type: settype(""; $d[$k]), default: $d[$k]}} end);
def omsettings:
    . as $m | (if (.settings | isobj) then .settings else {} end) as $top
    | (if ($top.defaults | isobj) or ($top.schema | type) == "array" then ($top | omsection)
       else reduce ($top | keys_unsorted[]) as $key ({};
         $top[$key] as $d
         | (if ($d | isobj) and ($d | has("default")) then {v: $d.default}
            elif ($d | isobj | not) then {v: $d} else {} end) as $val
         | . + {($key): ({type: settype((if $d | isobj then $d.type else "" end); $val.v)}
             + (if $val | has("v") then {default: $val.v} else {} end)
             + (if ($d | isobj) and ($d.description | type) == "string" then {description: $d.description} else {} end))}) end) as $settings
    | ($m | omsection) + ($m.service | omsection) + ($m.panel | omsection)
      + ($m.overlay | omsection) + $settings + ($m.barWidget | omsection);
def omarchy($dirname):
    (if (.kinds | type) == "array" then [.kinds[] | select(type == "string")] else [] end) as $kinds
    | (if (.entryPoints | isobj) then .entryPoints else {} end) as $ep
    | ($kinds | map(select(. as $kind | omsupported | index($kind)))) as $sup
    | {compat: "omarchy", upstreamId: (if (.id | type) == "string" then .id else "" end), id: ($dirname | omid),
       problems: (if ($kinds | length) == 0 then ["omarchy: kinds must be a non-empty array"]
                  elif ($sup | length) == 0 then ["omarchy: no supported kind (has \($kinds | join(", ")); supported: \(omsupported | join(", ")))"]
                  else [] end),
       unsupported: ($kinds | map(select(. as $kind | omsupported | index($kind) | not))),
       manifest: {schemaVersion: .schemaVersion, id: (if (.id | type) == "string" then (.id | omid) else .id end), name: .name, version: .version,
                  description: (if (.description | type) == "string" then .description else "" end),
                  kinds: $sup, entry: (reduce $sup[] as $k ({}; . + {($k): $ep[(omentry | .[$k])]})),
                  settings: omsettings, permissions: [], provides: []}};
def dmssurfaces: (if (.capabilities | type) == "array" then .capabilities else [] end) as $caps
    | if (.components | isobj) then (.components | with_entries(select(.value | truthy)))
      elif (.component | truthy) then
        {(if .type == "daemon" then "daemon"
          elif .type == "launcher" or ($caps | index(["launcher"])) then "launcher"
          elif .type == "desktop" or .type == "dash" or .type == "dashCard" then .type
          else "widget" end): .component}
      else {} end;
def dmskinds: [["widget", "bar-widget"], ["daemon", "service"]];
def dms($dirname):
    ((.id | type) == "string" and (.id | test("^[a-zA-Z][a-zA-Z0-9]*$"))) as $valid
    | ((if $valid then .id else $dirname end) | dmsid) as $id
    | dmssurfaces as $surf
    | ($surf | keys_unsorted) as $names
    | [dmskinds[] | select(.[0] as $s | $surf | has($s))] as $loaded
    | ((if (.permissions | type) == "string" then (.permissions | split(","))
        elif (.permissions | type) == "array" then .permissions else [] end)
       | reduce (.[] | tostring | gsub("^\\s+|\\s+$"; "") | {"process": "exec", "network": "network"}[.] // empty) as $p
           ([]; if index([$p]) then . else . + [$p] end)) as $perms
    | {compat: "dms", upstreamId: (if $valid then .id else "" end), id: $id,
       problems: ((if $valid then [] else ["dms: id must match ^[a-zA-Z][a-zA-Z0-9]*$"] end)
                  + (if ($loaded | length) > 0 then []
                     else ["dms: no bar widget or daemon surface (\(if ($names | length) > 0 then "has " + ($names | join(", ")) else "no component" end); the compat adapter loads bar widgets and daemons only)"] end)),
       unsupported: [$names[] | select(. as $s | [dmskinds[][0]] | index([$s]) | not) | "dms:" + .],
       manifest: {schemaVersion: 1, id: $id, name: .name, version: .version,
                  description: (if (.description | type) == "string" then .description else "" end),
                  kinds: [$loaded[][1]],
                  entry: (reduce $loaded[] as $k ({}; . + {($k[1]): ($surf[$k[0]] | if type == "string" and startswith("./") then .[2:] else . end)})),
                  settings: {}, permissions: $perms, provides: []}};
'

# plugin_adapt DIR — the adapter result for an Omarchy or DMS plugin (see
# PLUGIN_ADAPT_JQ); a native directory comes back as compat "".
plugin_adapt() {
    local dir="$1" name compat
    name="$(basename "$dir")"
    compat="$(plugin_compat "$dir")"
    case "$compat" in
    omarchy) jq --arg d "$name" "$PLUGIN_ADAPT_JQ omarchy(\$d)" "$dir/manifest.json" ;;
    dms)
        if jq empty "$dir/plugin.json" 2>/dev/null && jq -e 'type == "object"' "$dir/plugin.json" >/dev/null 2>&1; then
            jq --arg d "$name" "$PLUGIN_ADAPT_JQ dms(\$d)" "$dir/plugin.json"
        else
            jq -n --arg d "$name" "$PLUGIN_ADAPT_JQ"' {compat: "dms", upstreamId: "", id: ($d | dmsid), problems: ["plugin.json is not a valid JSON object"], unsupported: [], manifest: null}'
        fi
        ;;
    *) jq -n --arg d "$name" '{compat: "", upstreamId: "", id: $d, problems: [], unsupported: [], manifest: null}' ;;
    esac
}

# plugin_manifest DIR — the manifest as haseen sees it (native as written,
# compat ones adapted).
plugin_manifest() {
    if [[ -z $(plugin_compat "$1") ]]; then
        cat "$1/manifest.json"
    else
        plugin_adapt "$1" | jq .manifest
    fi
}

# plugin_id_of DIR — the registry id: native directory name, a namespaced
# Omarchy id (single-segment upstream ids receive omarchy.), or dms.<kebab>.
plugin_id_of() {
    if [[ -n $(plugin_compat "$1") ]]; then
        plugin_adapt "$1" | jq -r .id
    else
        basename "$1"
    fi
}

# plugin_index — "id<TAB>dir" for every plugin directory in search order:
# user, built-in, then the read-only Omarchy and DMS directories.
plugin_index() {
    local d
    for d in "$PLUGIN_USER_DIR"/*/ "$PLUGIN_BUILTIN_DIR"/*/ "$PLUGIN_OMARCHY_DIR"/*/ "$PLUGIN_DMS_DIR"/*/; do
        [[ -d $d ]] || continue
        d="${d%/}"
        printf '%s\t%s\n' "$(plugin_id_of "$d")" "$d"
    done
}

# plugin_dir ID — the directory that wins for ID. Resolution must agree with
# the running shell: Haseen/Plugins.qml scans user, built-in, Omarchy and DMS
# in that order and keeps the first directory whose *adapted* id matches
# (later ones only set `overrides`). plugin_index yields exactly that order,
# one line at a time, so the loop below stops at the first hit. Matching on
# the directory name first would be faster but wrong: a directory merely
# named ID in a low-priority root (an adapted id such as
# dms.example-emoji-plugin) would beat the user's copy of the same plugin
# under its upstream name (ExampleEmojiPlugin), and the CLI would then edit a
# manifest the shell never loads.
plugin_dir() {
    local id dir
    while IFS=$'\t' read -r id dir; do
        if [[ $id == "$1" ]]; then
            printf '%s\n' "$dir"
            return 0
        fi
    done < <(plugin_index)
    return 1
}

# plugin_origin DIR — user | builtin | omarchy | dms | path (a checkout
# outside those dirs). An adapted plugin in the user dir is user:<compat>.
plugin_origin() {
    local compat
    case "$(dirname "$1")" in
    "$PLUGIN_USER_DIR")
        compat="$(plugin_compat "$1")"
        echo "user${compat:+:$compat}"
        ;;
    "$PLUGIN_BUILTIN_DIR") echo builtin ;;
    "$PLUGIN_OMARCHY_DIR") echo omarchy ;;
    "$PLUGIN_DMS_DIR") echo dms ;;
    *) echo path ;;
    esac
}

# plugin_resolve ARG — ARG is an id, a plugin directory or its manifest.json
# (plugin.json for a DMS plugin).
plugin_resolve() {
    local arg="$1"
    if [[ $arg == */* || $arg == . || $arg == .. ]]; then
        [[ -f $arg && (${arg##*/} == manifest.json || ${arg##*/} == plugin.json) ]] && arg="$(dirname "$arg")"
        [[ -d $arg ]] || die "no such plugin directory: $arg"
        (cd "$arg" && pwd)
        return 0
    fi
    plugin_dir "$arg" && return 0
    die "unknown plugin: $arg (looked in $PLUGIN_USER_DIR, $PLUGIN_BUILTIN_DIR, $PLUGIN_OMARCHY_DIR and $PLUGIN_DMS_DIR)"
}

# plugin_ids — every plugin id in all locations, sorted, unique.
plugin_ids() {
    plugin_index | cut -f1 | sort -u
}

# plugin_check DIR — prints "error: …" / "warning: …" lines; returns 1 on any
# error. The schema rules live in the jq program; bash adds what jq cannot
# see: the directory name and the entry files on disk.
plugin_check() {
    local dir="$1" manifest="$1/manifest.json" name errors=0 line entry adapted json
    name="$(basename "$dir")"
    if [[ -n $(plugin_compat "$dir") ]]; then
        json="$(plugin_adapt "$dir")"
        if jq -e '.problems | length > 0' <<<"$json" >/dev/null; then
            jq -r '.problems[] | "error: \(.)"' <<<"$json"
            return 1
        fi
        name="$(jq -r .id <<<"$json")"
        adapted="$(jq .manifest <<<"$json")"
    else
        if [[ ! -r $manifest ]]; then
            echo "error: $manifest is missing"
            return 1
        fi
        if ! jq empty "$manifest" 2>/dev/null; then
            echo "error: manifest.json is not valid JSON"
            return 1
        fi
        adapted="$(cat "$manifest")"
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
    ' <<<"$adapted" 2>&1)
    return "$errors"
}

# plugin_field DIR JQ_FILTER — read one value from a (valid) manifest.
plugin_field() { plugin_manifest "$1" | jq -r "$2"; }

# plugin_permissions DIR — prints the permission summary; warns on network.
plugin_permissions() {
    local manifest perms
    manifest="$(plugin_manifest "$1")"
    perms="$(jq -r '(.permissions // []) | join(", ")' <<<"$manifest")"
    echo "permissions: ${perms:-none}"
    if jq -e '(.permissions // []) | index(["network"])' <<<"$manifest" >/dev/null; then
        echo "warning: requests unrestricted 'network' access. QML cannot sandbox plugins; review the code before enabling it."
    fi
}

# The shell.json transaction lock. Every read-modify-write of the user
# shell.json — a CLI command, a panel calling `haseen plugin settings`, the
# same widget on two screens — must hold it across *both* the read and the
# rename, or one writer computes its update from a snapshot another writer
# has already replaced and silently drops it.
SHELL_CONFIG_LOCK="$HASEEN_USER_CONFIG/.shell.json.lock"

# shell_config_lock — take the transaction lock for the rest of this process
# (released when it exits). Idempotent: a second call sees the fd and returns,
# which matters because flock(2) locks belong to the open file description, so
# opening the same file twice in one process would deadlock against itself.
# A dry run changes nothing, so it neither creates the lock file nor waits.
shell_config_lock() {
    if $DRY_RUN || [[ -n ${SHELL_CONFIG_LOCK_FD:-} ]]; then
        return 0
    fi
    mkdir -p "$HASEEN_USER_CONFIG"
    # The lock inode must survive, and must not be world-readable state.
    (umask 077 && : >>"$SHELL_CONFIG_LOCK")
    exec {SHELL_CONFIG_LOCK_FD}<"$SHELL_CONFIG_LOCK"
    flock -x "$SHELL_CONFIG_LOCK_FD"
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
#
# The staging name carries the writer's pid, so two writers never stage into
# one file and rename each other's bytes. shell_config_lock is called here as
# well: callers take it before their read (that is the part that needs it),
# and this keeps the rename serialised even if one forgets.
shell_config_write() {
    local existed=true tmp="$SHELL_USER_CONFIG.new"
    [[ -e $SHELL_USER_CONFIG ]] || existed=false
    if ! $DRY_RUN; then
        shell_config_lock
        tmp="$SHELL_USER_CONFIG.new.$$"
    fi
    write_user_file "$tmp"
    run mv -f -- "$tmp" "$SHELL_USER_CONFIG"
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
