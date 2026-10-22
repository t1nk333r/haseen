# shellcheck shell=bash
# haseen:covers bin/haseen-plymouth-{apply,follow,set,status} bin/haseen-theme-set bin/haseen-branding
# haseen:covers share/haseen/lib/{plymouth,boot,branding,preflight}.sh share/haseen/layers/secureboot/secureboot.sh
# haseen:covers share/haseen/default/systemd/haseen-splash@.service share/haseen/default/polkit/**
# haseen:covers share/haseen/systemd/user/haseen-splash-follow.* share/haseen/default/plymouth/**
# haseen:covers share/haseen/migrations/1792669390-splash-follows-theme.sh tests/fixtures/polkit-harness.js
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# Plan 110: the boot splash follows the applied theme. A theme or mark change
# restarts the user's timer; when it fires, `haseen plymouth follow request`
# asks root, through a polkit-allowed template unit whose name carries the
# colours, to rebuild the boot image; the root side parses that name again and
# reads nothing in a home.
NODE="$(command -v node || true)"
sandbox splash-follow

SYS="$SANDBOX/sysroot"
CUR="$XDG_STATE_HOME/haseen/current/theme"
UNIT_LINK="$XDG_CONFIG_HOME/systemd/user/timers.target.wants/haseen-splash-follow.timer"
CALLS="$SANDBOX/calls"
mkdir -p "$SYS/usr/bin" "$SYS/etc/plymouth" "$SYS/proc" "$SYS/usr/share/plymouth/themes/haseen" \
    "$SYS/etc/mkinitcpio.conf.d" "$SYS/var/lib/haseen" "$CUR"
printf '#!/bin/sh\nexit 0\n' >"$SYS/usr/bin/plymouth-set-default-theme"
chmod +x "$SYS/usr/bin/plymouth-set-default-theme"
printf 'Theme=haseen\n' >"$SYS/etc/plymouth/plymouthd.conf"
cp "$HASEEN_PATH/default/plymouth/haseen.plymouth" "$SYS/usr/share/plymouth/themes/haseen/"
printf 'HOOKS=(base udev plymouth autodetect block filesystems fsck)\n' >"$SYS/etc/mkinitcpio.conf"
printf 'BOOT_IMAGE=/vmlinuz-linux root=/dev/mapper/root rw quiet splash\n' >"$SYS/proc/cmdline"
export HASEEN_SYSROOT="$SYS"
cat >"$CUR/colors.toml" <<'EOF'
accent = "#96D69A"
background = "#13131a"
foreground = "#e4e1ec"
EOF
WANT=13131a-e4e1ec-96d69a-kufic

# Every systemctl and notify-send call is recorded; SYSTEMCTL_FAIL makes a
# `start` fail as a refused polkit check does.
stub systemctl "echo \"systemctl \$*\" >>'$CALLS'
case \"\$*\" in
start*) if [ -n \"\${SYSTEMCTL_FAIL:-}\" ]; then echo 'Failed to start x.service: Access denied' >&2; exit 1; fi
        if [ -n \"\${SYSTEMCTL_RETHEME:-}\" ]; then printf 'background = \"#000000\"\\n' >'$CUR/colors.toml'; fi ;;
esac
exit 0"
stub notify-send "echo \"notify-send \$*\" >>'$CALLS'; exit 0"
stub bootctl 'exit 0'
calls() { cat "$CALLS" 2>/dev/null || true; }
reset_calls() { rm -f "$CALLS"; }
follow_on() { mkdir -p "${UNIT_LINK%/*}" && ln -sfn /dev/null "$UNIT_LINK"; }
follow_off() { rm -f "$UNIT_LINK"; }
lib() { bash -c 'source "$HASEEN_PATH/lib/plymouth.sh"; '"$1"; }

# --- the request: the colours and the mark in a unit name -----------------------
assert_eq "the current theme's request: lowercase hex, no '#', then the mark" "$WANT" "$(lib plymouth_current_request)"
mkdir -p "$XDG_CONFIG_HOME/haseen"
echo '{"branding": {"mark": "gate"}}' >"$XDG_CONFIG_HOME/haseen/shell.json"
assert_eq "the selected mark is part of it" "13131a-e4e1ec-96d69a-gate" "$(lib plymouth_current_request)"
rm -f "$XDG_CONFIG_HOME/haseen/shell.json"
parse() {
    capture env REQ="$1" bash -c 'source "$HASEEN_PATH/lib/plymouth.sh"; plymouth_request_parse "$REQ" && echo "${PLYMOUTH_REQUEST[*]}"'
}
parse "$WANT"
assert_status "a well-formed request parses" 0 "$STATUS"
assert_eq "into three colours and a mark" "#13131a #e4e1ec #96d69a kufic" "$OUTPUT"
for bad in '' 13131A-e4e1ec-96d69a-kufic 13131-e4e1ec-96d69a-kufic 13131aa-e4e1ec-96d69a-kufic \
    13131a-e4e1ec-96d69a-evil 13131a-e4e1ec-96d69a-Kufic 13131a-e4e1ec-96d69a 13131a-e4e1ec-96d69a-kufic-x \
    '13131a-e4e1ec-96d69a-kufic;id' '13131a-e4e1ec-96d69a-$(id)' $'13131a-e4e1ec-96d69a-kufic\nx' \
    '../13131a-e4e1ec-96d69a-kufic' '13131a-e4e1ec-96d69a-kufic ' '#13131a-e4e1ec-96d69a-kufic' \
    'g3131a-e4e1ec-96d69a-kufic' '13131a_e4e1ec_96d69a_kufic'; do
    parse "$bad"
    assert_status "refused: $(printf '%q' "$bad")" 1 "$STATUS"
    assert_eq "and nothing set for it" "" "$OUTPUT"
done

# --- the polkit rule ------------------------------------------------------------
RULE="$HASEEN_PATH/default/polkit/50-haseen-splash.rules"
assert_eq "the rule's marks are haseen's marks" "kufic|shield|gate" \
    "$(grep -o '(kufic|[a-z|]*)' "$RULE" | tr -d '()')"
assert_eq "and branding.sh's list is the same" "kufic shield gate" \
    "$(bash -c 'source "$HASEEN_PATH/lib/branding.sh"; echo "${BRANDING_MARKS[*]}"')"
# polkitd runs rules in duktape (ES5): no let, const or arrow functions.
assert_eq "the rule is ES5" "" "$(grep -nE '\b(let|const)\b|=>' "$RULE" || true)"
if [[ -z $NODE ]]; then
    echo "  SKIP polkit rule checks: node not found" >&2
else
    START="Authentication is required to start '\$(unit)'."
    TRANSIENT="Authentication is required to start transient unit '\$(unit)'."
    MU=org.freedesktop.systemd1.manage-units
    case_json() { # NAME UNIT VERB MESSAGE GROUPS [ACTION]
        jq -cn --arg n "$1" --arg u "$2" --arg v "$3" --arg m "$4" --arg g "$5" --arg a "${6:-$MU}" \
            '{name: $n, action: {id: $a, details: ({unit: $u, verb: $v, "polkit.message": $m} | with_entries(select(.value != "")))},
              subject: {user: "owner", groups: ($g | split(" ") | map(select(. != "")))}}'
    }
    ok_unit="haseen-splash@$WANT.service"
    {
        case_json allowed "$ok_unit" start "$START" "users wheel"
        case_json shield "haseen-splash@13131a-e4e1ec-96d69a-shield.service" start "$START" wheel
        case_json transient-257 "$ok_unit" start "$TRANSIENT" wheel
        case_json transient-256 "" "" "" wheel
        case_json no-message "$ok_unit" start "" wheel
        case_json not-wheel "$ok_unit" start "$START" "users video"
        for v in stop restart try-restart reload-or-restart reload kill reset-failed set-property; do
            case_json "verb-$v" "$ok_unit" "$v" "$START" wheel
        done
        for u in haseen-splash@.service "haseen-splash@$WANT.socket" "haseen-splash@$WANT.service.d" \
            "xhaseen-splash@$WANT.service" "haseen-splash@13131A-e4e1ec-96d69a-kufic.service" \
            haseen-splash@13131a-e4e1ec-96d69a-evil.service "haseen-splash@$WANT-x.service" \
            "haseen-splash@$WANT.service"$'\n' sshd.service haseen-charge-limit.service; do
            case_json "unit-$(printf '%q' "$u")" "$u" start "$START" wheel
        done
        case_json other-action "$ok_unit" start "$START" wheel org.freedesktop.systemd1.manage-unit-files
        case_json reload-daemon "$ok_unit" start "$START" wheel org.freedesktop.systemd1.reload-daemon
    } | jq -s . >"$SANDBOX/cases.json"
    capture "$NODE" "$REPO/tests/fixtures/polkit-harness.js" "$RULE" "$SANDBOX/cases.json"
    assert_status "the rule loads in the fake polkitd" 0 "$STATUS"
    res="$OUTPUT"
    r() { jq -r --arg k "$1" '.results[$k]' <<<"$res"; }
    assert_eq "one rule is added" 1 "$(jq .rules <<<"$res")"
    assert_eq "a wheel member may start a well-formed instance" yes "$(r allowed)"
    assert_eq "with any of haseen's marks" yes "$(r shield)"
    assert_eq "a transient unit of that name (systemd >= 257) is not allowed" not_handled "$(r transient-257)"
    assert_eq "nor a transient start without details (systemd <= 256)" not_handled "$(r transient-256)"
    assert_eq "nor a start without systemd's message" not_handled "$(r no-message)"
    assert_eq "nor a user outside wheel" not_handled "$(r not-wheel)"
    for v in stop restart try-restart reload-or-restart reload kill reset-failed set-property; do
        assert_eq "verb $v is not allowed" not_handled "$(r "verb-$v")"
    done
    while IFS= read -r k; do
        assert_eq "$k is not allowed" not_handled "$(r "$k")"
    done < <(jq -r '.results | keys[] | select(startswith("unit-"))' <<<"$res")
    assert_eq "another action is not allowed" not_handled "$(r other-action)"
    assert_eq "nor reloading the daemon" not_handled "$(r reload-daemon)"
    assert_eq "every case was answered" 26 "$(jq '.results | length' <<<"$res")"
fi

# --- the units --------------------------------------------------------------------
SU="$HASEEN_PATH/default/systemd/haseen-splash@.service"
for line in 'Type=oneshot' 'ExecStart=@HASEEN_BIN@ plymouth apply %i' 'Nice=19' 'IOSchedulingClass=idle' \
    'KillMode=mixed' 'TimeoutStopSec=5min' 'ProtectHome=tmpfs' 'StartLimitBurst=3' 'RequiresMountsFor=@ESP@ /usr /var/lib'; do
    assert_contains "root unit: $line" "$(<"$SU")" $'\n'"$line"$'\n'
done
assert_not_contains "the root unit has no [Install]: only a request starts it" "$(<"$SU")" "[Install]"
TU="$HASEEN_PATH/systemd/user/haseen-splash-follow.timer"
assert_contains "the timer waits 2 minutes from its (re)start" "$(<"$TU")" $'\nOnActiveSec=2min\n'
assert_contains "and starts the request" "$(<"$TU")" $'\nUnit=haseen-splash-follow.service\n'
assert_contains "enabled, it runs with the user manager" "$(<"$TU")" $'\nWantedBy=timers.target'
assert_contains "the request service runs the request" "$(<"$HASEEN_PATH/systemd/user/haseen-splash-follow.service")" \
    $'\nExecStart=/usr/bin/env haseen plymouth follow request\n'
capture lib plymouth_follow_unit_render
assert_contains "rendered: this tree's router" "$OUTPUT" "ExecStart=$REPO/bin/haseen plymouth apply %i"
assert_contains "rendered: the ESP" "$OUTPUT" "RequiresMountsFor=/boot /usr /var/lib"
assert_not_contains "rendered: no router placeholder left" "$OUTPUT" "@HASEEN_BIN@"
assert_not_contains "rendered: no ESP placeholder left" "$OUTPUT" "@ESP@"
if command -v systemd-analyze >/dev/null; then
    mkdir -p "$SANDBOX/units"
    lib plymouth_follow_unit_render >"$SANDBOX/units/haseen-splash@.service"
    sed -i 's|^RequiresMountsFor=.*|RequiresMountsFor=/|' "$SANDBOX/units/haseen-splash@.service"
    cp "$TU" "$HASEEN_PATH/systemd/user/haseen-splash-follow.service" "$SANDBOX/units/"
    # Each unit's syntax; a missing executable or bus is not this test's concern.
    for u in haseen-splash@abcdef-abcdef-abcdef-kufic.service haseen-splash-follow.timer haseen-splash-follow.service; do
        capture env SYSTEMD_UNIT_PATH="$SANDBOX/units:" systemd-analyze verify --man=no "$SANDBOX/units/$u"
        assert_not_contains "systemd-analyze: $u has no unknown key" "$OUTPUT" "Unknown key"
        assert_not_contains "systemd-analyze: $u has no bad value" "$OUTPUT" "Failed to parse"
    done
else
    echo "  SKIP systemd-analyze verify: not installed" >&2
fi

# --- the trigger: a change restarts the wait, only when following is on -----------
follow_off
reset_calls
capture haseen plymouth follow poke
assert_status "poke with following off" 0 "$STATUS"
assert_eq "starts nothing" "" "$(calls)"
capture haseen theme set kanagawa --dry-run
assert_not_contains "theme set --dry-run, following off: no splash step" "$OUTPUT" "haseen-splash-follow"
follow_on
capture haseen plymouth follow poke
assert_eq "following on: the timer is restarted, so the 2 minutes begin again" \
    "systemctl --user restart --no-block haseen-splash-follow.timer" "$(calls)"
capture haseen theme set kanagawa --dry-run
assert_dry_pure "theme set --dry-run" "$OUTPUT"
assert_contains "theme set --dry-run plans the restart" "$OUTPUT" \
    "DRYRUN: systemctl --user restart --no-block haseen-splash-follow.timer"
assert_contains "theme set --help says so" "$(haseen theme set --help)" "2-minute wait starts again"
# A real theme set, with the reload fakes quiet.
for c in hyprctl pkill gsettings qs quickshell; do stub "$c" 'exit 0'; done
reset_calls
capture env HASEEN_THEME_FETCH=0 haseen theme set kanagawa
assert_status "theme set" 0 "$STATUS"
assert_contains "theme set restarts the splash timer" "$(calls)" "systemctl --user restart --no-block haseen-splash-follow.timer"
assert_not_contains "and never asks root itself" "$(calls)" "haseen-splash@"
reset_calls
capture env HASEEN_THEME_HEADLESS=1 HASEEN_THEME_FETCH=0 haseen theme set kanagawa
assert_not_contains "a headless theme set leaves the splash alone" "$(calls)" "haseen-splash"
reset_calls
capture haseen branding mark shield
assert_status "branding mark" 0 "$STATUS"
assert_eq "a mark change restarts the timer too" "systemctl --user restart --no-block haseen-splash-follow.timer" "$(calls)"
capture haseen branding mark gate --dry-run
assert_contains "branding mark --dry-run plans it" "$OUTPUT" "DRYRUN: systemctl --user restart --no-block haseen-splash-follow.timer"
assert_contains "branding --help says the splash follows" "$(haseen branding --help)" "when it follows the theme (haseen plymouth follow)"
follow_off
reset_calls
capture haseen branding mark kufic
assert_eq "following off: a mark change starts nothing" "" "$(calls)"
rm -f "$XDG_CONFIG_HOME/haseen/shell.json"
# theme set rendered kanagawa: back to the fixture's colours.
cat >"$CUR/colors.toml" <<'EOF'
accent = "#96D69A"
background = "#13131a"
foreground = "#e4e1ec"
EOF

# --- the request: compare, then ask root ------------------------------------------
cp "$HASEEN_PATH/default/systemd/haseen-splash@.service" "$SANDBOX/unit.tpl"
install_unit() { mkdir -p "$SYS/etc/systemd/system" && lib plymouth_follow_unit_render >"$SYS/etc/systemd/system/haseen-splash@.service"; }
record() { cat "$XDG_STATE_HOME/haseen/splash-follow" 2>/dev/null || true; }
install_unit
follow_off
reset_calls
capture haseen plymouth follow request
assert_status "request with following off" 0 "$STATUS"
assert_eq "asks nothing" "" "$(calls)"
follow_on
printf '%s\n' "$WANT" >"$SYS/var/lib/haseen/splash"
capture haseen plymouth follow request
assert_status "request when the boot image matches" 0 "$STATUS"
assert_eq "asks nothing" "" "$(calls)"
assert_eq "and records it" "ok $WANT" "$(record)"
capture haseen plymouth status
assert_contains "status: matches" "$OUTPUT" "matches:   yes"
assert_contains "status: follows" "$OUTPUT" "follows:   on"

printf '1f1f28-dcd7ba-dcd7ba-kufic\n' >"$SYS/var/lib/haseen/splash"
capture haseen plymouth status
assert_contains "status: a different image is pending while following is on" "$OUTPUT" "matches:   pending"
reset_calls
capture haseen plymouth follow request
assert_status "a differing image is requested" 0 "$STATUS"
assert_eq "root is asked for exactly that instance, without a password prompt" \
    "systemctl start --no-ask-password haseen-splash@$WANT.service" "$(calls)"
assert_eq "success is silent" "" "$(grep notify-send "$CALLS" || true)"
assert_eq "and recorded" "ok $WANT" "$(record)"

reset_calls
capture env SYSTEMCTL_FAIL=1 haseen plymouth follow request
assert_status "a refused or failed rebuild fails the request" 1 "$STATUS"
assert_contains "and is notified, critical" "$(calls)" "notify-send -a haseen -u critical -i haseen Boot splash not rebuilt Failed to start x.service: Access denied."
assert_eq "recorded as failed" "failed $WANT" "$(record)"
capture haseen plymouth status
assert_contains "status: no, the rebuild failed" "$OUTPUT" "matches:   no (the rebuild failed"

reset_calls
capture env SYSTEMCTL_RETHEME=1 haseen plymouth follow request
assert_status "a theme change during the rebuild" 0 "$STATUS"
assert_eq "waits again: the timer is restarted after the rebuild" \
    "systemctl start --no-ask-password haseen-splash@$WANT.service
systemctl --user restart --no-block haseen-splash-follow.timer" "$(calls)"
cat >"$CUR/colors.toml" <<'EOF'
accent = "#96D69A"
background = "#13131a"
foreground = "#e4e1ec"
EOF

rm -f "$SYS/etc/systemd/system/haseen-splash@.service"
reset_calls
capture haseen plymouth follow request
assert_status "no root unit: failure" 1 "$STATUS"
assert_contains "notified" "$(calls)" "Its root service is not installed: haseen plymouth follow on."
assert_not_contains "and root is not asked" "$(calls)" "systemctl start"
install_unit
printf '# an older unit\n' >>"$SYS/etc/systemd/system/haseen-splash@.service"
reset_calls
capture haseen plymouth follow request
assert_contains "an out-of-date unit is still tried" "$(calls)" "systemctl start --no-ask-password haseen-splash@$WANT.service"
capture haseen plymouth follow status
assert_contains "and status says it is out of date" "$OUTPUT" "service:   out of date (haseen plymouth follow on)"
install_unit
printf '1f1f28-dcd7ba-dcd7ba-kufic\n' >"$SYS/var/lib/haseen/splash"

printf 'Theme=bgrt\n' >"$SYS/etc/plymouth/plymouthd.conf"
reset_calls
capture haseen plymouth follow request
assert_status "another splash chosen: nothing to follow" 0 "$STATUS"
assert_eq "silently" "" "$(calls)"
printf 'Theme=haseen\n' >"$SYS/etc/plymouth/plymouthd.conf"

# A machine that checks its boot files: never rebuilt in the background,
# notified once.
EFIVARS="$SYS/sys/firmware/efi/efivars"
SBVAR="$EFIVARS/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c"
mkdir -p "$EFIVARS"
printf '\x06\x00\x00\x00\x01' >"$SBVAR"
rm -f "$XDG_STATE_HOME/haseen/splash-follow"
reset_calls
capture haseen plymouth follow request
assert_status "Secure Boot on: the request stops" 0 "$STATUS"
assert_not_contains "without asking root" "$(calls)" "systemctl start"
assert_contains "and says why, once" "$(calls)" "notify-send -a haseen -u critical -i haseen Boot splash not rebuilt Secure Boot is on"
assert_eq "recorded as skipped" "skipped $WANT Secure Boot is on" "$(record)"
reset_calls
capture haseen plymouth follow request
assert_eq "the next request does not notify again" "" "$(calls)"
capture haseen plymouth status
assert_contains "status: no, and what to do" "$OUTPUT" "matches:   no (Secure Boot is on: run haseen plymouth set"
printf '\x06\x00\x00\x00\x00' >"$SBVAR"
capture lib plymouth_signed_boot
assert_status "Secure Boot off and nothing enrolled: not signed" 1 "$STATUS"
rm -f "$SBVAR"
capture lib plymouth_signed_boot
assert_eq "an unreadable Secure Boot state on UEFI counts as signed" "the firmware's Secure Boot state cannot be read" "$OUTPUT"
rm -rf "$SYS/sys"
mkdir -p "$SYS/var/lib/sbctl/keys/db"
: >"$SYS/var/lib/sbctl/keys/db/db.key"
capture lib plymouth_signed_boot
assert_eq "sbctl keys count" "sbctl holds Secure Boot keys" "$OUTPUT"
rm -rf "$SYS/var/lib/sbctl"
mkdir -p "$SYS/etc/default"
printf 'ESP_PATH="/boot"\nENABLE_ENROLL_LIMINE_CONFIG=yes\n' >"$SYS/etc/default/limine"
capture lib plymouth_signed_boot
assert_eq "an enrolled Limine config counts" "Limine's config hash is enrolled" "$OUTPUT"
rm -f "$SYS/etc/default/limine"
capture lib plymouth_signed_boot
assert_status "none of them: not signed" 1 "$STATUS"
rm -f "$XDG_STATE_HOME/haseen/splash-follow"

# sbctl keeps its keys where only root can look (review round 1): for a user,
# an sbctl state or key directory it cannot read counts as keys, so following
# refuses and a request is skipped and notified once instead of asking root
# for what root refuses. Mode 000 stands in for root's 0700 (CI runs as ci).
for locked in /var/lib/sbctl/keys /var/lib/sbctl; do
    mkdir -p "$SYS/var/lib/sbctl/keys/db"
    : >"$SYS/var/lib/sbctl/keys/db/db.key"
    chmod 000 "$SYS$locked"
    if [[ -r $SYS$locked ]]; then
        echo "  SKIP unreadable sbctl directory: this test runs as root" >&2
        chmod 755 "$SYS$locked"
        rm -rf "$SYS/var/lib/sbctl"
        break
    fi
    capture lib plymouth_signed_boot
    assert_eq "$locked unreadable: sbctl may hold keys" \
        "sbctl may hold Secure Boot keys (its key directory is readable only by root)" "$OUTPUT"
    rm -f "$XDG_STATE_HOME/haseen/splash-follow"
    reset_calls
    capture haseen plymouth follow request
    assert_status "$locked unreadable: the request stops" 0 "$STATUS"
    assert_not_contains "$locked unreadable: root is not asked" "$(calls)" "systemctl start"
    assert_contains "$locked unreadable: notified" "$(calls)" "Boot splash not rebuilt sbctl may hold Secure Boot keys"
    reset_calls
    capture haseen plymouth follow request
    assert_eq "$locked unreadable: once" "" "$(calls)"
    capture haseen plymouth status
    assert_contains "$locked unreadable: status says why" "$OUTPUT" "matches:   no (sbctl may hold Secure Boot keys"
    capture haseen plymouth follow on --dry-run
    assert_status "$locked unreadable: follow on refuses" 1 "$STATUS"
    assert_contains "$locked unreadable: and says why" "$OUTPUT" "the splash does not follow the theme here: sbctl may hold Secure Boot keys"
    assert_not_contains "$locked unreadable: planning nothing" "$OUTPUT" "DRYRUN"
    chmod 755 "$SYS$locked"
    rm -rf "$SYS/var/lib/sbctl"
done
rm -f "$XDG_STATE_HOME/haseen/splash-follow"

# --- root's side: haseen plymouth apply ------------------------------------------
printf '1f1f28-dcd7ba-dcd7ba-kufic\n' >"$SYS/var/lib/haseen/splash"
# The root unit has HOME=/root and nothing of a user's: the user's mark (gate
# here) must not reach it, and a HOME it cannot read changes nothing.
echo '{"branding": {"mark": "gate"}}' >"$XDG_CONFIG_HOME/haseen/shell.json"
apply() { capture env -i PATH="$PATH" HASEEN_PATH="$HASEEN_PATH" HASEEN_SYSROOT="$SYS" HOME=/nonexistent haseen plymouth apply "$@"; }
apply 13131a-e4e1ec-96d69a-shield --dry-run
assert_status "apply plans" 0 "$STATUS"
assert_dry_pure "apply --dry-run" "$OUTPUT"
assert_contains "the colours come from the name" "$OUTPUT" "boot splash: background #13131a, text #e4e1ec, accent #96d69a, mark shield"
assert_contains "the mark too, not the user's" "$OUTPUT" "render $HASEEN_PATH/branding/shield/mark.svg in #96d69a -> logo.png (mark: shield)"
assert_contains "the script is installed" "$OUTPUT" "write /usr/share/plymouth/themes/haseen/haseen.script"
assert_contains "in those colours (0x13/255)" "$OUTPUT" "bg_r = 0.075"
assert_contains "one rebuild at a time, locked where only root can write" "$OUTPUT" "DRYRUN: lock /run/haseen/splash.lock"
assert_contains "counted against the hourly limit" "$OUTPUT" "count this rebuild in /run/haseen/splash-rebuilds (at most 6 an hour)"
assert_contains "the initramfs is rebuilt as haseen plymouth set does" "$OUTPUT" "DRYRUN: sudo mkinitcpio -P"
assert_contains "and recorded" "$OUTPUT" "DRYRUN: write /var/lib/haseen/splash (mode 0644):"$'\n'"    | 13131a-e4e1ec-96d69a-shield"
rebuild_at="$(grep -n 'mkinitcpio -P' <<<"$OUTPUT" | cut -d: -f1)"
stamp_at="$(grep -n 'write /var/lib/haseen/splash' <<<"$OUTPUT" | cut -d: -f1)"
assert_eq "the record is written only after the rebuild" 1 "$((rebuild_at < stamp_at))"
apply "13131a-e4e1ec-96d69a-kufic;id" --dry-run
assert_status "a malformed request is refused" 2 "$STATUS"
assert_not_contains "and not echoed back" "$OUTPUT" ";id"
assert_not_contains "nothing is planned" "$OUTPUT" "DRYRUN"
apply 1f1f28-dcd7ba-dcd7ba-kufic --dry-run
assert_status "the image already carries it" 0 "$STATUS"
assert_contains "and says so" "$OUTPUT" "already carries 1f1f28-dcd7ba-dcd7ba-kufic"
assert_not_contains "without a rebuild" "$OUTPUT" "mkinitcpio"
apply 13131a-e4e1ec-96d69a-kufic
assert_status "not as root, and not a dry run: refused" 1 "$STATUS"
assert_contains "pointing at the by-hand way" "$OUTPUT" "by hand: haseen plymouth set"
printf 'Theme=bgrt\n' >"$SYS/etc/plymouth/plymouthd.conf"
apply 13131a-e4e1ec-96d69a-kufic --dry-run
assert_status "another splash chosen: refused" 1 "$STATUS"
printf 'Theme=haseen\n' >"$SYS/etc/plymouth/plymouthd.conf"
mkdir -p "$EFIVARS"
printf '\x06\x00\x00\x00\x01' >"$SBVAR"
apply 13131a-e4e1ec-96d69a-kufic --dry-run
assert_status "Secure Boot on: refused on root's side too" 1 "$STATUS"
assert_contains "with the reason" "$OUTPUT" "Secure Boot is on: a rebuild here must be signed again"
assert_not_contains "nothing is rebuilt" "$OUTPUT" "mkinitcpio"
rm -rf "$SYS/sys"
printf 'HOOKS=(base udev plymouth)\nfalse\n' >"$SYS/etc/mkinitcpio.conf.d/zz-broken.conf"
apply 13131a-e4e1ec-96d69a-kufic --dry-run
assert_status "an mkinitcpio configuration that does not evaluate: refused" 1 "$STATUS"
rm -f "$SYS/etc/mkinitcpio.conf.d/zz-broken.conf"
rm -f "$XDG_CONFIG_HOME/haseen/shell.json"
apply 13131a-13131a-13131a-kufic --dry-run
assert_status "a request whose colours do not read is still applied" 0 "$STATUS"
assert_contains "with the prompt drawn readable" "$OUTPUT" \
    "the theme's accent #13131a reads at 1.00:1 on #13131a, under 4.5:1: drawn in #ffffff"
assert_contains "in white" "$OUTPUT" "accent_r = 1.000"
assert_contains "and recorded as asked" "$OUTPUT" "    | 13131a-13131a-13131a-kufic"

# The root helpers' sudo becomes a plain call only for root (review round 1).
assert_eq "apply refuses a non-root run before it changes sudo" 1 \
    "$(( $(grep -n '^((EUID == 0)) || \$DRY_RUN || die' "$REPO/bin/haseen-plymouth-apply" | cut -d: -f1) < $(grep -n '^plymouth_as_root$' "$REPO/bin/haseen-plymouth-apply" | cut -d: -f1) ))"
as_root_probe='source "$HASEEN_PATH/lib/plymouth.sh"; plymouth_as_root; type -t sudo; run_root echo ran-directly'
capture bash -c "$as_root_probe"
assert_eq "not root: sudo is still the sudo on PATH" file "${OUTPUT%%$'\n'*}"
assert_contains "and the root helpers go through it" "$OUTPUT" "STUB-CALLED: sudo echo ran-directly"
if unshare --map-root-user true 2>/dev/null; then
    capture unshare --map-root-user bash -c "$as_root_probe"
    assert_eq "as root (EUID 0): sudo is the plain call" function "${OUTPUT%%$'\n'*}"
    assert_contains "which runs the command itself" "$OUTPUT" $'\nran-directly'
    assert_not_contains "without sudo(8)" "$OUTPUT" "STUB-CALLED"
else
    echo "  SKIP sudo override as root: user namespaces are not available here" >&2
fi
assert_contains "apply is hidden from the command list" "$(haseen commands plymouth)" "follow"
assert_not_contains "apply is hidden from the command list" "$(haseen commands plymouth)" "plymouth apply"

# A stop during the rebuild: the rebuild finishes, then the stop is reported.
cat >"$SANDBOX/guard.sh" <<'EOF'
source "$HASEEN_PATH/lib/plymouth.sh"
plymouth_guard_stops
echo started >"$1/state"
bash -c 'sleep 1; echo written >"$1/image"' _ "$1"
echo "stopped=$PLYMOUTH_STOPPED" >>"$1/state"
EOF
mkdir -p "$SANDBOX/guard"
bash "$SANDBOX/guard.sh" "$SANDBOX/guard" &
gpid=$!
for _ in $(seq 50); do [[ -e $SANDBOX/guard/state ]] && break; sleep 0.05; done
kill -TERM "$gpid"
wait "$gpid" || true
assert_eq "a SIGTERM to the main process lets the rebuild finish" written "$(cat "$SANDBOX/guard/image" 2>/dev/null)"
assert_eq "and is seen afterwards" $'started\nstopped=true' "$(cat "$SANDBOX/guard/state")"

# A stop while another rebuild holds the lock ends the wait, without the lock
# (review round 1): the wait is taken a step at a time.
cat >"$SANDBOX/lock.sh" <<'EOF'
source "$HASEEN_PATH/lib/plymouth.sh"
plymouth_guard_stops
PLYMOUTH_LOCK_STEP=1
echo waiting >"$2/lockstate"
if plymouth_lock "$1"; then echo locked >>"$2/lockstate"; else echo "gave up stopped=$PLYMOUTH_STOPPED" >>"$2/lockstate"; fi
EOF
lockfile="$SANDBOX/guard/splash.lock"
flock "$lockfile" sleep 4 &
hpid=$!
for _ in $(seq 50); do [[ -e $lockfile ]] && break; sleep 0.05; done
bash "$SANDBOX/lock.sh" "$lockfile" "$SANDBOX/guard" &
lpid=$!
for _ in $(seq 50); do [[ -e $SANDBOX/guard/lockstate ]] && break; sleep 0.05; done
sleep 0.3
kill -TERM "$lpid"
wait "$lpid" || true
held=no
kill -0 "$hpid" 2>/dev/null && held=yes
assert_eq "a stop while the lock is held: the wait ends, unlocked" $'waiting\ngave up stopped=true' "$(cat "$SANDBOX/guard/lockstate")"
assert_eq "while the other rebuild still holds it" yes "$held"
wait "$hpid" || true
rm -f "$SANDBOX/guard/lockstate"
capture bash "$SANDBOX/lock.sh" "$lockfile" "$SANDBOX/guard"
assert_eq "an unheld lock is taken" $'waiting\nlocked' "$(cat "$SANDBOX/guard/lockstate")"

# --- follow on / off / status ----------------------------------------------------
follow_off
rm -f "$SYS/etc/systemd/system/haseen-splash@.service"
reset_calls
capture haseen plymouth follow on --dry-run
assert_status "from a checkout a user owns: refused" 1 "$STATUS"
assert_contains "and says why" "$OUTPUT" "its root service would run $REPO/bin/haseen, but / is owned by uid $(id -u), not root"
assert_not_contains "nothing root is planned" "$OUTPUT" "DRYRUN"

# plant_tree — this tree's router, the apply command and what it sources or
# reads as root, at their own paths in the sysroot, writable by root alone.
plant_tree() {
    local d
    mkdir -p "$SYS$REPO/bin" "$SYS$REPO/share/haseen"
    cp "$REPO/bin/haseen" "$REPO/bin/haseen-plymouth-apply" "$SYS$REPO/bin/"
    for d in lib layers/secureboot default/plymouth branding; do
        mkdir -p "$SYS$REPO/share/haseen/$d"
        cp -R "$REPO/share/haseen/$d/." "$SYS$REPO/share/haseen/$d/"
    done
    chmod -R go-w "$SYS"
}
REAL_STAT="$(command -v stat)"
root_stat() {
    if [[ $1 == off ]]; then
        rm -f "$SANDBOX/stubs/stat"
        return 0
    fi
    stub stat "$(sed "s|@STAT@|$REAL_STAT|g" <<'EOF'
if [ "$1" = --printf ] && [ "$2" = '%u %a %F\t%n\0' ]; then
    shift 2
    exec @STAT@ --printf '0 %a %F\t%n\0' "$@"
fi
exec @STAT@ "$@"
EOF
)"
}
plant_tree
root_stat on
capture haseen plymouth follow on --dry-run
assert_status "from a root-owned tree: on" 0 "$STATUS"
assert_dry_pure "follow on --dry-run" "$OUTPUT"
assert_contains "the root unit is written, rendered" "$OUTPUT" "DRYRUN: write /etc/systemd/system/haseen-splash@.service (mode 0644):"
assert_contains "running this tree's router" "$OUTPUT" "| ExecStart=$REPO/bin/haseen plymouth apply %i"
assert_contains "the rule is installed" "$OUTPUT" "DRYRUN: sudo install -Dm0644 $RULE /etc/polkit-1/rules.d/50-haseen-splash.rules"
assert_contains "the timer is enabled and started" "$OUTPUT" "DRYRUN: systemctl --user enable --now haseen-splash-follow.timer"
unit_at="$(grep -n 'write /etc/systemd/system/haseen-splash@.service' <<<"$OUTPUT" | cut -d: -f1)"
reload_at="$(grep -n 'sudo systemctl daemon-reload' <<<"$OUTPUT" | cut -d: -f1)"
rule_at="$(grep -n 'sudo install -Dm0644 .*/50-haseen-splash.rules' <<<"$OUTPUT" | cut -d: -f1)"
assert_eq "the unit, then daemon-reload, then the rule" 1 "$((unit_at < reload_at && reload_at < rule_at))"
for f in lib/plymouth.sh layers/secureboot/secureboot.sh default/plymouth/haseen.script branding/kufic/mark.svg; do
    chmod o+w "$SYS$REPO/share/haseen/$f"
    capture haseen plymouth follow on --dry-run
    assert_status "$f writable by others: refused" 1 "$STATUS"
    assert_contains "$f is named" "$OUTPUT" "but $REPO/share/haseen/$f is writable by its group or by others"
    chmod o-w "$SYS$REPO/share/haseen/$f"
done
install_unit
capture haseen plymouth follow on --dry-run
assert_not_contains "a current unit is not written again" "$OUTPUT" "write /etc/systemd/system/haseen-splash@.service"
assert_contains "the rule is (users cannot see it)" "$OUTPUT" "50-haseen-splash.rules"
mkdir -p "$EFIVARS"
printf '\x06\x00\x00\x00\x01' >"$SBVAR"
capture haseen plymouth follow on --dry-run
assert_status "Secure Boot on: follow on refuses" 1 "$STATUS"
assert_contains "and says what to do instead" "$OUTPUT" "run haseen plymouth set after a theme change (then haseen secureboot sign"
rm -rf "$SYS/sys"
follow_on
capture haseen plymouth follow off --dry-run
assert_status "follow off" 0 "$STATUS"
assert_dry_pure "follow off --dry-run" "$OUTPUT"
off_timer="$(grep -n 'systemctl --user disable --now haseen-splash-follow.timer' <<<"$OUTPUT" | cut -d: -f1)"
off_rule="$(grep -n 'rm -f /etc/polkit-1/rules.d/50-haseen-splash.rules' <<<"$OUTPUT" | cut -d: -f1)"
off_unit="$(grep -n 'rm -f /etc/systemd/system/haseen-splash@.service' <<<"$OUTPUT" | cut -d: -f1)"
assert_eq "off: the timer, then the rule, then the unit" 1 "$((off_timer < off_rule && off_rule < off_unit))"
capture haseen plymouth follow status
assert_contains "follow status: on" "$OUTPUT" "follows:   on"
assert_contains "follow status: the service" "$OUTPUT" "service:   installed"
follow_off
capture haseen plymouth follow status
assert_contains "follow status: off" "$OUTPUT" "follows:   off (haseen plymouth follow on)"
assert_contains "follow --help explains it" "$(haseen plymouth follow --help)" "rebuilt in the background at idle priority, without a password"
capture haseen plymouth follow sideways
assert_status "an unknown verb is a usage error" 2 "$STATUS"

# --- haseen plymouth set turns following on ---------------------------------------
capture haseen plymouth set --dry-run
assert_status "plymouth set" 0 "$STATUS"
assert_dry_pure "plymouth set --dry-run" "$OUTPUT"
assert_contains "records what the image carries" "$OUTPUT" "DRYRUN: write /var/lib/haseen/splash (mode 0644):"$'\n'"    | $WANT"
assert_contains "and turns following on" "$OUTPUT" "DRYRUN: systemctl --user enable --now haseen-splash-follow.timer"
capture haseen plymouth set --dry-run --no-follow
assert_not_contains "--no-follow leaves it" "$OUTPUT" "haseen-splash-follow.timer"
capture haseen plymouth set --dry-run --theme kanagawa
assert_not_contains "--theme NAME does not turn it on" "$OUTPUT" "haseen-splash-follow.timer"
capture haseen plymouth set --dry-run --no-rebuild
assert_not_contains "--no-rebuild records nothing" "$OUTPUT" "/var/lib/haseen/splash"
follow_on
capture haseen plymouth set --dry-run --theme kanagawa
assert_contains "--theme with following on: told the colours will not last" "$OUTPUT" "kanagawa's colours last until the next theme change or login"
follow_off
assert_contains "plymouth set --help says it follows" "$(haseen plymouth set --help)" "Then the splash follows the theme"

# Readable before pretty (review round 1): a text or accent colour under
# 4.5:1 on the background is drawn in white or black, whichever reads better;
# the record keeps the theme's own colours, so following still compares them.
assert_eq "contrast: black on white" 2100 "$(lib 'plymouth_contrast "#000000" "#FFFFFF"')"
assert_eq "contrast: a colour on itself" 100 "$(lib 'plymouth_contrast "#13131a" "#13131a"')"
worst=2100
for v in 00 11 22 33 44 55 66 77 88 99 aa bb cc dd ee ff; do
    g="#$v$v$v"
    r="$(lib "plymouth_contrast '$g' \"\$(plymouth_readable '$g' '$g')\"")"
    ((r < worst)) && worst=$r
done
assert_eq "on every grey, the replacement reads at 4.5:1 or more" 1 "$((worst >= 450))"
cp "$CUR/colors.toml" "$SANDBOX/colors.keep"
printf 'accent = "#13131a"\nbackground = "#13131a"\nforeground = "#13131a"\n' >"$CUR/colors.toml"
capture haseen plymouth set --dry-run --no-follow
assert_status "plymouth set with unreadable colours" 0 "$STATUS"
assert_contains "says the text is replaced" "$OUTPUT" "the theme's text #13131a reads at 1.00:1 on #13131a, under 4.5:1: drawn in #ffffff"
assert_contains "and the accent, which the prompt is drawn in" "$OUTPUT" "the theme's accent #13131a reads at 1.00:1 on #13131a, under 4.5:1: drawn in #ffffff"
assert_contains "the prompt is white" "$OUTPUT" "accent_r = 1.000"
assert_contains "the text colour too" "$OUTPUT" "fg_r = 1.000"
assert_contains "and so is the mark" "$OUTPUT" "in #ffffff -> logo.png"
assert_contains "the record keeps the theme's colours" "$OUTPUT" "    | 13131a-13131a-13131a-kufic"
capture haseen plymouth status
assert_contains "status says so" "$OUTPUT" "readable:  the theme's accent #13131a reads at 1.00:1 on #13131a, under 4.5:1: drawn in #ffffff"
printf 'accent = "#787878"\nbackground = "#777777"\nforeground = "#ffffff"\n' >"$CUR/colors.toml"
capture haseen plymouth set --dry-run --no-follow
assert_contains "on a light grey, black" "$OUTPUT" "the theme's accent #787878 reads at 1.01:1 on #777777, under 4.5:1: drawn in #000000"
assert_contains "the prompt is black" "$OUTPUT" "accent_r = 0.000"
assert_contains "white text there reads at 4.47:1, just under: black too" "$OUTPUT" "the theme's text #ffffff reads at 4.47:1 on #777777, under 4.5:1: drawn in #000000"
cp "$SANDBOX/colors.keep" "$CUR/colors.toml"
capture haseen plymouth set --dry-run --no-follow
assert_not_contains "a theme that reads well is drawn as it is" "$OUTPUT" "under 4.5:1"
assert_contains "in its own accent" "$OUTPUT" "accent_r = 0.588"
capture haseen plymouth status
assert_not_contains "and status has nothing to say" "$OUTPUT" "readable:"

# --- the migration ----------------------------------------------------------------
MIG="$HASEEN_PATH/migrations/1792669390-splash-follows-theme.sh"
migrate() { capture env DRY_RUN=true bash -Eeuo pipefail "$MIG"; }
migrate
assert_status "migration: haseen's splash shown, following off" 0 "$STATUS"
assert_dry_pure "migration --dry-run" "$OUTPUT"
assert_contains "turns following on" "$OUTPUT" "DRYRUN: systemctl --user enable --now haseen-splash-follow.timer"
follow_on
migrate
assert_eq "already on with a current unit: nothing to do" "" "$OUTPUT"
follow_off
printf 'Theme=bgrt\n' >"$SYS/etc/plymouth/plymouthd.conf"
migrate
assert_eq "another splash: nothing" "" "$OUTPUT"
printf 'Theme=haseen\n' >"$SYS/etc/plymouth/plymouthd.conf"
mv "$SYS/usr/bin/plymouth-set-default-theme" "$SANDBOX/psdt"
migrate
assert_status "no plymouth: nothing" 0 "$STATUS"
assert_eq "silently" "" "$OUTPUT"
mv "$SANDBOX/psdt" "$SYS/usr/bin/plymouth-set-default-theme"
mkdir -p "$EFIVARS"
printf '\x06\x00\x00\x00\x01' >"$SBVAR"
migrate
assert_status "Secure Boot on: the migration completes" 0 "$STATUS"
assert_contains "leaving it as it is, and saying why" "$OUTPUT" "left as it is; haseen plymouth set rebuilds the splash by hand"
assert_not_contains "and turning nothing on" "$OUTPUT" "enable --now"
rm -rf "$SYS/sys"
root_stat off
migrate
assert_status "a tree root does not own: the migration completes" 0 "$STATUS"
assert_contains "and says why" "$OUTPUT" "install haseen as root (./install.sh)"
assert_not_contains "turning nothing on" "$OUTPUT" "enable --now"
