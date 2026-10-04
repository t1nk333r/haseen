# shellcheck shell=bash
# tests/test-prayers.sh — haseen.prayers (plan 026): manifest and defaults,
# naming and theme rules, the upstream pure-JS engine and model suites under
# node, a Riyadh reference check against AlAdhan, and the three plugin scripts
# (zone, notify with a stub notify-send, settings writer).

sandbox prayers
P="$REPO/share/haseen/shell/plugins/haseen.prayers"
M="$P/manifest.json"

# --- manifest ------------------------------------------------------------------
capture "$REPO/bin/haseen" plugin validate "$P"
assert_status "prayers manifest validates" 0 "$STATUS"
assert_eq "prayers id" "haseen.prayers" "$(jq -r .id "$M")"
assert_eq "prayers name" "Prayers" "$(jq -r .name "$M")"
assert_eq "prayers kinds" "service,bar-widget,panel" "$(jq -r '.kinds | join(",")' "$M")"
assert_eq "prayers provides" "prayers" "$(jq -r '.provides | join(",")' "$M")"
assert_eq "prayers debugIpc defaults off" "false" "$(jq -r .settings.debugIpc.default "$M")"
assert_eq "prayers defaults: Riyadh city centre, Umm al-Qura, English" \
    'Riyadh|الرياض|24.7136|46.6753|Asia/Riyadh|4|English|false' \
    "$(jq -r '.settings | [.locationLabel, .locationLabelAr, .latitude, .longitude, .timezone, .calculationMethod, .language, .notifications] | map(.default | tostring) | join("|")' "$M")"
assert_eq "prayers upstream defaults kept" '25|20|20|5|20|25|60|Horizon|Strip + countdown' \
    "$(jq -r '.settings | [.iqamaFajr, .iqamaDhuhr, .iqamaAsr, .iqamaMaghrib, .iqamaIsha, .iqamaJumuah, .notificationSoundVolume, .panelStyle, .barDisplay] | map(.default | tostring) | join("|")' "$M")"
assert_eq "prayers keeps upstream notices" "yes" "$([[ -f $P/LICENSE && -f $P/UPSTREAM.md ]] && echo yes)"
assert_contains "prayers LICENSE is upstream MIT" "$(cat "$P/LICENSE")" "Copyright (c) 2026 Salem Sayed"

# --- naming and theme rules -----------------------------------------------------
# Relative paths: the checkout's own path may contain the owner's user name.
code() { (cd "$P" && grep -rnI --include='*.qml' --include='*.js' --include='*.sh' --include='*.json' --exclude-dir=tests -v -E '^\s*(//|#)' .); }
assert_eq "prayers code has no oma/Omarchy identifiers" "" \
    "$(code | grep -iE 'omaprayers|omarchy|oma\.|qs\.(Commons|Ui)\b|OMARCHY_PATH|t1nk33r' || true)"
assert_eq "prayers QML has no hex colours" "" "$(grep -nE '"#[0-9a-fA-F]{3,8}"' "$P"/*.qml || true)"
assert_contains "prayers bar text uses barForeground" "$(cat "$P/Widget.qml")" "Theme.barForeground"
assert_contains "prayers notify app name" "$(cat "$P/haseen-prayers-notify.sh")" '-a "haseen prayers"'

# --- upstream suites under node ---------------------------------------------------
NODE=$(command -v node || true)
if [[ -n $NODE ]]; then
    for t in Engine Model Riyadh Aladhan; do
        capture "$NODE" "$P/tests/$t.test.js"
        assert_status "prayers $t.test.js" 0 "$STATUS"
        ((STATUS == 0)) || printf '%s\n' "$OUTPUT" | tail -20 >&2
    done
else
    echo "  skip: node not installed (prayers engine suites)"
fi

# --- zone script --------------------------------------------------------------------
capture "$P/haseen-prayers-zone.sh" --timezone Asia/Riyadh --days 3 --now 1791100800
assert_status "zone script ok" 0 "$STATUS"
assert_eq "zone script window" "true|Asia/Riyadh|2026-10-04|10800" \
    "$(jq -r '[.ok, .timezone, .today, .offsets[0].offset] | map(tostring) | join("|")' <<<"$OUTPUT")"
capture "$P/haseen-prayers-zone.sh" --timezone '../etc/passwd'
assert_status "zone script refuses a bad timezone" 1 "$STATUS"
assert_contains "zone script error is JSON" "$OUTPUT" '"ok":false'
assert_eq "zone script writes no state" "" "$(ls -A "$XDG_STATE_HOME" 2>/dev/null || true)"

# --- notify script (stub notify-send and players) ---------------------------------
log="$SANDBOX/calls.log"
stub notify-send "echo \"notify-send \$*\" >>'$log'"
stub pw-play "echo \"pw-play \$*\" >>'$log'"
N="$P/haseen-prayers-notify.sh"
state="$XDG_STATE_HOME/haseen/prayers"

capture "$N" 2026-10-04:Fajr:adhan "It is time for Fajr" "04:29" off 60 --dry-run
assert_status "notify dry-run ok" 0 "$STATUS"
assert_dry_pure "notify" "$OUTPUT"
assert_contains "notify dry-run shows notify-send" "$OUTPUT" "DRYRUN: notify-send -a haseen prayers It is time for Fajr 04:29"
assert_eq "notify dry-run sends nothing" "no" "$([[ -e $log ]] && echo yes || echo no)"
assert_eq "notify dry-run writes no key" "no" "$([[ -e $state/last-notification ]] && echo yes || echo no)"

capture "$N" 2026-10-04:Fajr:adhan "It is time for Fajr" "04:29" "" 50
assert_status "notify delivers" 0 "$STATUS"
assert_eq "notify sends once with app name, chime at 50%" \
    "notify-send -a haseen prayers It is time for Fajr 04:29|pw-play --volume 0.50 -- $P/assets/prayer-chime.ogg" \
    "$(paste -sd'|' "$log")"
assert_eq "notify records the key" "2026-10-04:Fajr:adhan" "$(cat "$state/last-notification")"
capture "$N" 2026-10-04:Fajr:adhan "It is time for Fajr" "04:29" "" 50
assert_eq "notify dedups the same event" "2" "$(wc -l <"$log")"

: >"$log"
mkdir -p "$XDG_STATE_HOME/haseen/flags" && : >"$XDG_STATE_HOME/haseen/flags/dnd"
capture "$N" 2026-10-04:Dhuhr:adhan "It is time for Dhuhr" "11:42" "" 50
assert_eq "notify under dnd: notification, no chime" "notify-send -a haseen prayers It is time for Dhuhr 11:42" "$(cat "$log")"
rm -f "$XDG_STATE_HOME/haseen/flags/dnd"

: >"$log"
capture "$N" 2026-10-04:Asr:adhan "It is time for Asr" "" off
assert_eq "notify with sound off" "notify-send -a haseen prayers It is time for Asr" "$(cat "$log")"

stub notify-send "exit 1"
capture "$N" 2026-10-04:Isha:adhan "It is time for Isha" "19:07" off
assert_status "notify failure propagates (service retries)" 1 "$STATUS"
assert_eq "notify failure keeps the previous key" "2026-10-04:Asr:adhan" "$(cat "$state/last-notification")"

# --- settings writer ----------------------------------------------------------------
W="$P/haseen-prayers-set.sh"
cfg="$XDG_CONFIG_HOME/haseen/shell.json"
capture "$W" '{"panelStyle":"Compact"}' --dry-run
assert_dry_pure "prayers set" "$OUTPUT"
assert_eq "set dry-run writes nothing" "no" "$([[ -e $cfg ]] && echo yes || echo no)"
mkdir -p "$(dirname "$cfg")" && printf '{"bar":{"height":30}}\n' >"$cfg"
capture "$W" '{"panelStyle":"Compact","iqamaFajr":30}'
assert_status "set writes" 0 "$STATUS"
assert_eq "set merges into plugins.haseen.prayers.settings" '30|Compact|30' \
    "$(jq -r '[.bar.height, .plugins["haseen.prayers"].settings.panelStyle, .plugins["haseen.prayers"].settings.iqamaFajr] | map(tostring) | join("|")' "$cfg")"
capture "$W" '{"language":"Arabic"}'
assert_eq "set keeps earlier keys" 'Compact|Arabic' \
    "$(jq -r '.plugins["haseen.prayers"].settings | [.panelStyle, .language] | join("|")' "$cfg")"
capture "$W" '"not an object"'
assert_status "set refuses a non-object" 1 "$STATUS"
