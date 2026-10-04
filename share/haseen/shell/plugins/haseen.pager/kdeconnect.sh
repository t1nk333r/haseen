#!/usr/bin/env bash
# haseen.pager: the phone's side of a notification, for inline replies.
#
#   kdeconnect.sh find APP BODY              {"path","title","appName"} of the one
#                                            repliable phone notification matching
#                                            APP and BODY exactly, or nothing
#   kdeconnect.sh reply PATH TEXT APP BODY   re-match, send TEXT, dismiss on the phone
#
# Adapted from omapager's bin/omapager-kdeconnect (https://github.com/njpatel/omapager,
# MIT, Copyright (c) 2026 Neil Jagdish Patel), rewritten in bash with busctl and
# jq because the shell path carries no Python (docs/architecture.md section 6).
#
# KDE Connect posts phone notifications to the desktop bus like any other app,
# and that is all the freedesktop spec can carry. It also keeps an object per
# notification on its own bus with a replyId and a sendReply method. Matching
# the two is by app name and body text, because the desktop notification
# carries no handle to the object; ambiguous matches are refused.
#
# Nothing here writes local state: the only effect is the reply (and the
# dismissal) sent over the user bus, so common.sh's state helpers do not apply.
set -Eeuo pipefail

readonly BUS=org.kde.kdeconnect
readonly IFACE=org.kde.kdeconnect.device.notifications.notification
readonly PATH_RE='^/modules/kdeconnect/devices/[A-Za-z0-9_]+/notifications/[0-9]+$'

call() { timeout 5 busctl --user "$@" 2>/dev/null; }

# normalise TEXT - comparable text: typographic quotes and dashes folded,
# whitespace collapsed, lower case.
normalise() {
    jq -rn --arg t "$1" '$t
        | gsub("[\u2018\u2019]"; "'"'"'") | gsub("[\u201c\u201d]"; "\"")
        | gsub("[\u2013\u2014]"; "-") | gsub("\u2026"; "...")
        | [splits("\\s+")] | map(select(. != "")) | join(" ") | ascii_downcase'
}

# find APP BODY - print the single match as JSON; nothing when none or several.
find_note() {
    local want_app want_body path props matches=()
    want_app="$(normalise "$1")"
    want_body="$(normalise "$2")"
    [[ -n $want_app && -n $want_body && ${#want_app} -le 256 && ${#want_body} -le 32768 ]] || return 0
    local n=0
    while read -r path; do
        [[ $path =~ $PATH_RE ]] || continue
        ((++n <= 100)) || break
        props="$(call --json=short -- call "$BUS" "$path" org.freedesktop.DBus.Properties GetAll s "$IFACE")" || continue
        if jq -e --arg app "$want_app" --arg body "$want_body" '
            def norm: tostring
                | gsub("[\u2018\u2019]"; "'"'"'") | gsub("[\u201c\u201d]"; "\"")
                | gsub("[\u2013\u2014]"; "-") | gsub("\u2026"; "...")
                | [splits("\\s+")] | map(select(. != "")) | join(" ") | ascii_downcase;
            .data[0] as $p
            | (($p.replyId.data // "") != "")
              and (($p.appName.data // "") | norm) == $app
              and ([($p.ticker.data // ""), ($p.text.data // "")] | map(norm) | index($body)) != null
        ' <<<"$props" >/dev/null 2>&1; then
            matches+=("$(jq -c --arg path "$path" '.data[0] as $p
                | {path: $path, title: ($p.title.data // ""), appName: ($p.appName.data // "")}' <<<"$props")")
        fi
    done < <(call --list -- tree "$BUS" || true)
    ((${#matches[@]} == 1)) && printf '%s\n' "${matches[0]}"
    return 0
}

case "${1:-}" in
find)
    (($# == 3)) || exit 2
    find_note "$2" "$3"
    ;;
reply)
    (($# == 5)) || exit 2
    path=$2 text=$3
    [[ $path =~ $PATH_RE ]] || exit 1
    [[ -n ${text//[[:space:]]/} && ${#text} -le 4096 ]] || exit 1
    # Re-discover and re-match at send time: the object may have gone, or a
    # second notification may now make the match ambiguous.
    found="$(find_note "$4" "$5")"
    [[ -n $found && $(jq -r .path <<<"$found") == "$path" ]] || exit 1
    call -- call "$BUS" "$path" "$IFACE" sendReply s "$text" >/dev/null || exit 1
    # Answered means dealt with on the phone too; otherwise KDE Connect forwards
    # it again. Best effort: the reply already went through.
    call -- call "$BUS" "$path" "$IFACE" dismiss >/dev/null || true
    ;;
*)
    exit 2
    ;;
esac
