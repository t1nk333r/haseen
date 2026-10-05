#!/usr/bin/env bash
# haseen.prayers: persist panel setting changes into ~/.config/haseen/shell.json
# under plugins."haseen.prayers".settings. The panel applies the same values
# to the running shell at once (Config.setRuntime); this makes them survive.
#
#   haseen-prayers-set.sh '<json object of settings>' [--dry-run]
#
# The object is merged key by key over the existing settings, so one click
# writes one key and leaves the rest of the file alone.
set -Eeuo pipefail
here="$(dirname "$(readlink -f -- "${BASH_SOURCE[0]}")")"
# shellcheck source=../../lib/plugin.sh
source "${HASEEN_PATH:-$here/../../..}/shell/lib/plugin.sh"

usage() {
    echo "Usage: haseen-prayers-set.sh '<json object>' [--dry-run]"
}

parse_common_flags "$@"
((${#REST[@]} == 1)) || {
    usage >&2
    exit 2
}
values="${REST[0]}"
jq -e 'type == "object"' <<<"$values" >/dev/null 2>&1 || die "settings must be a JSON object"

# One panel click writes one key, but two screens can click at once: read and
# write under the shared shell.json transaction lock.
shell_config_lock
current="$(shell_user_json)"
updated="$(jq --argjson v "$values" '.plugins["haseen.prayers"].settings += $v' <<<"$current")"
[[ $updated == "$current" ]] && exit 0
printf '%s\n' "$updated" | shell_config_write
