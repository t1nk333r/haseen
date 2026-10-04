#!/usr/bin/env bash
# haseen.prayers: deliver one prayer notification, at most once per event key,
# and play its sound with it.
#
#   haseen-prayers-notify.sh <event-key> [title] [body] [sound] [volume-percent] [--dry-run]
#
# sound: "off" for silence, a path to a sound file, or empty for the bundled
# assets/prayer-chime.ogg beside this script. The sound follows the
# deduplication key, so a shell reload or a retried delivery cannot repeat the
# chime for one prayer. With the haseen `dnd` flag on, the notification still
# goes to the notification service (which keeps it quiet) but nothing plays.
#
# Adapted from prayer-notify.sh in OmaPrayers (MIT, Copyright (c) 2026 Salem
# Sayed); see LICENSE and UPSTREAM.md beside this file. Changes: notify-send
# with the app name "haseen prayers" instead of omarchy-notification-send,
# state under $XDG_STATE_HOME/haseen/prayers, writes through common.sh.
set -Eeuo pipefail
here="$(dirname "$(readlink -f -- "${BASH_SOURCE[0]}")")"
# shellcheck source=../../../lib/common.sh
source "${HASEEN_PATH:-$here/../../..}/lib/common.sh"
umask 077

parse_common_flags "$@"
set -- "${REST[@]}"

event_key="${1:-}"
title="${2:-Prayer time}"
body="${3:-}"
sound="${4:-}"
volume_percent="${5:-60}"

[[ -n $event_key ]] || die "usage: haseen-prayers-notify.sh <event-key> [title] [body] [sound] [volume]"

state_dir="$HASEEN_USER_STATE/prayers"
last_event_file="$state_dir/last-notification"
lock_file="$state_dir/notification.lock"

run mkdir -p "$state_dir"
run chmod 700 "$state_dir"

if ! $DRY_RUN; then
    exec 9>"$lock_file"
    flock -w 5 9 || exit 75
fi

last_event=""
if [[ -f $last_event_file ]]; then
    IFS= read -r last_event <"$last_event_file" || true
fi
[[ $last_event == "$event_key" ]] && exit 0

args=(-a "haseen prayers" "$title")
[[ -n $body ]] && args+=("$body")
run notify-send "${args[@]}"

# The chime, once the notification actually went out. Best-effort and bounded:
# the notification is the contract, the sound is the courtesy, so a missing
# player, a dead audio server or an unreadable file is silence, never a
# failure and never a retry. PipeWire first, PulseAudio's paplay second.
play_sound() {
    local file="$1" percent="$2" player
    [[ -z $file || $file == off ]] && return 0
    [[ -r $file ]] || return 0
    [[ -e $HASEEN_USER_STATE/flags/dnd ]] && return 0
    [[ $percent =~ ^[0-9]+$ ]] || percent=60
    ((percent > 100)) && percent=100
    for player in pw-play paplay; do
        have "$player" || continue
        case "$player" in
        pw-play) run timeout 10 pw-play --volume "$(awk -v p="$percent" 'BEGIN { printf "%.2f", p / 100 }')" -- "$file" >/dev/null 2>&1 || true ;;
        paplay) run timeout 10 paplay --volume "$((percent * 65536 / 100))" -- "$file" >/dev/null 2>&1 || true ;;
        esac
        return 0
    done
    return 0
}

[[ -n $sound ]] || sound="$here/assets/prayer-chime.ogg"
play_sound "$sound" "$volume_percent"

# Commit the deduplication key only after notify-send succeeded. If the
# notification service is briefly away, the service's retry can deliver it.
stage=""
cleanup() {
    [[ -z $stage ]] || rm -f -- "$stage"
}
trap cleanup EXIT

if $DRY_RUN; then
    printf '%s\n' "$event_key" | write_user_file "$last_event_file"
else
    stage="$(mktemp "$state_dir/.notification.XXXXXX")"
    printf '%s\n' "$event_key" | write_user_file "$stage"
    run mv -f -- "$stage" "$last_event_file"
    stage=""
fi
