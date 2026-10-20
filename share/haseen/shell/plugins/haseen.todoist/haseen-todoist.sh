#!/usr/bin/env bash
# haseen.todoist: the plugin's one way to its private settings file and to the
# Todoist API. The shell never holds the API token: `set` takes it once on
# stdin, and `api` reads it from the file for each request and hands it to
# curl through a pipe, so it is in no argv and in no shell property.
#
#   haseen-todoist.sh dir                       print the state directory in use
#   haseen-todoist.sh api METHOD PATH [JSON]    one request to Todoist's API
#   haseen-todoist.sh set [--dry-run] < OBJECT  merge settings into settings.json
#   haseen-todoist.sh clear-token [--dry-run]   remove the token
#
# `api` sends METHOD (GET, POST or DELETE) to https://api.todoist.com/api/v1/
# followed by PATH (a path and query, never a URL: the token goes to that host
# only), with JSON as the body. It prints the response body, a newline and the
# HTTP status, and exits with curl's status (3 when there is no token). It
# never uses -f, which drops the error body the API explains itself in.
#
# State directory: $HASEEN_USER_STATE/todoist (~/.local/state/haseen/todoist).
# A HOME that already keeps upstream's ~/.local/state/omarchy/t1nk33r.todoist
# and has no haseen one keeps using that one in place, so a token stored there
# is never copied or moved (plan 097). The directory is 0700 and the file 0600.
# A curl-headers.conf left there by upstream holds a copy of the token; haseen
# does not use it, and empties it whenever the token changes or is removed.
#
# Adapted from Panel.qml in omarchy-todoist (MIT, Copyright (c) 2026
# aryan-techie), as the owner's fork t1nk33r.todoist 1.14.0; see LICENSE and
# UPSTREAM.md beside this file: the settings file and its keys, the request
# rules (-w status, no -f, a 10 s limit) and the private directory and file.
set -Eeuo pipefail
here="$(dirname "$(readlink -f -- "${BASH_SOURCE[0]}")")"
# shellcheck source=../../../lib/common.sh
source "${HASEEN_PATH:-$here/../../..}/lib/common.sh"
umask 077

usage() {
    cat <<'EOF'
Usage: haseen-todoist.sh dir
       haseen-todoist.sh api GET|POST|DELETE PATH [JSON-OBJECT]
       haseen-todoist.sh set [--dry-run] < JSON-OBJECT
       haseen-todoist.sh clear-token [--dry-run]

`set` keys: apiToken, filter, quickView, barCountMode, panelWidth, panelHeight.
EOF
}

API_BASE="https://api.todoist.com/api/v1"
new_dir="$HASEEN_USER_STATE/todoist"
legacy_dir="$HOME/.local/state/omarchy/t1nk33r.todoist"

state_dir() {
    if [[ ! -e $new_dir && ! -L $new_dir && -d $legacy_dir && ! -L $legacy_dir && -O $legacy_dir ]]; then
        printf '%s\n' "$legacy_dir"
    else
        printf '%s\n' "$new_dir"
    fi
}

# The directory, made private if it is not: 0700, owned by this user, not a
# symlink. mkdir -m applies only to a directory it creates, hence the chmod.
ensure_dir() {
    local dir=$1
    [[ ! -L $dir ]] || die "$dir is a symlink"
    run mkdir -p -m 700 -- "$dir"
    run chmod 700 -- "$dir"
    $DRY_RUN || [[ -d $dir && -O $dir ]] || die "$dir is not a directory of this user"
}

# Writes the settings document atomically at 0600. Not write_user_file: under
# --dry-run that prints the content, and the content is the token.
write_settings() {
    local dir=$1 doc=$2 file="$1/settings.json" tmp
    if $DRY_RUN; then
        echo "DRYRUN: write $file (mode 600, keys: $(jq -r 'keys | join(",")' <<<"$doc"))"
        return 0
    fi
    tmp="$(mktemp -p "$dir" .settings.XXXXXX)"
    if ! { printf '%s\n' "$doc" >"$tmp" && chmod 600 -- "$tmp" && mv -f -T -- "$tmp" "$file"; }; then
        rm -f -- "$tmp"
        die "cannot write $file"
    fi
}

# Upstream mirrored the token into curl-headers.conf beside the settings; a
# token that changed or went must not live on in that copy.
empty_legacy_header() {
    local file="$1/curl-headers.conf"
    [[ -f $file && ! -L $file && -s $file ]] || return 0
    if $DRY_RUN; then
        echo "DRYRUN: empty $file"
    else
        : >"$file"
    fi
}

current_settings() {
    local file="$1/settings.json"
    if [[ -f $file ]]; then
        jq -e 'if type == "object" then . else error("not an object") end' "$file" 2>/dev/null ||
            die "$file is not a JSON object; fix or remove it first"
    else
        echo '{}'
    fi
}

cmd_set() {
    local dir request merged
    dir="$(state_dir)"
    request="$(cat)"
    jq -e 'type == "object" and ((keys - ["apiToken","filter","quickView","barCountMode","panelWidth","panelHeight"]) | length == 0)
        and ((.apiToken // "") | type == "string") and ((.filter // "") | type == "string")
        and ((.quickView // "today") | IN("today","inbox","all","custom"))
        and ((.barCountMode // "hide") | IN("hide","today","inbox","all"))
        and ((.panelWidth // 340) | type == "number") and ((.panelHeight // 480) | type == "number")' \
        <<<"$request" >/dev/null 2>&1 || die "settings must be a JSON object of known keys"
    ensure_dir "$dir"
    merged="$(jq -s '.[0] * .[1]' <(current_settings "$dir") <(printf '%s\n' "$request"))"
    write_settings "$dir" "$merged"
    if jq -e 'has("apiToken")' <<<"$request" >/dev/null; then
        empty_legacy_header "$dir"
    fi
}

cmd_clear_token() {
    local dir
    dir="$(state_dir)"
    [[ -e $dir/settings.json ]] || return 0
    ensure_dir "$dir"
    write_settings "$dir" "$(current_settings "$dir" | jq 'del(.apiToken)')"
    empty_legacy_header "$dir"
}

cmd_api() {
    local method=${1-} path=${2-} body=${3-} dir token
    [[ $method == GET || $method == POST || $method == DELETE ]] || die "method must be GET, POST or DELETE"
    # A path and query only: no scheme, host, "..", space or fragment can make
    # the request (and its token) leave https://api.todoist.com/api/v1/.
    [[ $path =~ ^[A-Za-z0-9][A-Za-z0-9_/-]*(\?[A-Za-z0-9._~%\&=+!*\'\(\)-]*)?$ && $path != *..* && $path != *//* ]] ||
        die "invalid API path: $path"
    dir="$(state_dir)"
    token="$(jq -r 'if (.apiToken | type) == "string" then .apiToken else "" end' "$dir/settings.json" 2>/dev/null || true)"
    # A quote, backslash or newline would break the config line, and no token
    # Todoist issues contains one.
    token=${token//[$'"\\\r\n']/}
    if [[ -z $token ]]; then
        echo "no Todoist API token: paste one in the panel's settings" >&2
        exit 3
    fi
    local args=(-sS --max-time 10 --proto "=https" -X "$method" -w '\n%{http_code}')
    if [[ -n $body ]]; then
        jq -e 'type == "object"' <<<"$body" >/dev/null 2>&1 || die "the body must be a JSON object"
        args+=(-H 'Content-Type: application/json' --data-binary "$body")
    fi
    # The header reaches curl as a config file on a pipe: printf is a builtin,
    # so the token is never an argument of any process.
    curl "${args[@]}" -K <(printf 'header = "Authorization: Bearer %s"\n' "$token") -- "$API_BASE/$path"
}

parse_common_flags "$@"
set -- "${REST[@]}"
case "${1-}" in
dir) state_dir ;;
api)
    shift
    (($# == 2 || $# == 3)) || {
        usage >&2
        exit 2
    }
    cmd_api "$@"
    ;;
set) cmd_set ;;
clear-token) cmd_clear_token ;;
*)
    usage >&2
    exit 2
    ;;
esac
