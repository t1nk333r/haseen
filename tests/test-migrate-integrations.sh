# shellcheck shell=bash
# haseen:covers bin/haseen-plugin-validate share/haseen/VERSION share/haseen/default/shell.json
# haseen:covers share/haseen/migrations/17915603* share/haseen/shell/Compat/Manifest.js
# haseen:covers share/haseen/shell/lib/plugin.sh share/haseen/shell/plugin.schema.json
# haseen:covers share/haseen/shell/plugins/haseen.{monitor-settings,omaconnect,syncthing}/**
# haseen:covers share/haseen/shell/plugins/*/manifest.json
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# Plan 098: migration 1791560300-adopt-integrations re-points shell.json from
# the three adopted third-party ids to haseen.monitor-settings,
# haseen.omaconnect and haseen.syncthing: bar sections and services once,
# a native service beside a listed widget, settings the new manifests
# declare, the new entry winning; nested references and the original plugin
# directories untouched; a dry run, a second run and a HOME without the old
# ids change nothing.

M=1791560300-adopt-integrations.sh
run_m() {
    capture env HASEEN_PATH="$HASEEN_PATH" HASEEN_MIGRATION="$M" "$@" bash -Eeuo pipefail "$HASEEN_PATH/migrations/$M"
}
CFG() { printf '%s\n' "$XDG_CONFIG_HOME/haseen/shell.json"; }
write_cfg() { mkdir -p "$XDG_CONFIG_HOME/haseen" && cat >"$(CFG)"; }

assert_eq "the migration is the only one in plan 098's timestamp range" "$M" "$(find "$HASEEN_PATH/migrations" -name '17915603[0-9][0-9]-*.sh' -printf '%f\n' | LC_ALL=C sort)"

# --- a HOME like the owner's: the monitor widget in the bar, Syncthing in a
# --- drawer's items, OmaConnect in the bar under its registry id -----------------
sandbox migrate-integrations
mkdir -p "$XDG_CONFIG_HOME/omarchy/plugins/omaconnect" "$XDG_CONFIG_HOME/haseen/plugins/io.github.ilyazar.syncthing"
printf '{"id":"omaconnect"}\n' >"$XDG_CONFIG_HOME/omarchy/plugins/omaconnect/manifest.json"
printf 'x\n' >"$XDG_CONFIG_HOME/haseen/plugins/io.github.ilyazar.syncthing/keep"
write_cfg <<'EOF'
{
  "bar": {
    "left": ["haseen.logo"],
    "right": ["haseen.tray", "omarchy.omaconnect", "io.github.juliusmork-sys.monitor-settings-extender", "haseen.battery"],
    "overflow": ["io.github.juliusmork-sys.monitor-settings-extender"],
    "pinned": ["omarchy.omaconnect", "haseen.omaconnect"]
  },
  "services": ["haseen.pager", "io.github.ilyazar.syncthing"],
  "plugins": {
    "io.github.juliusmork-sys.monitor-settings-extender": { "enabled": true },
    "omarchy.omaconnect": { "settings": { "showBarBattery": true, "defaultPingMessage": "hi", "noSuchKey": 1 } },
    "io.github.ilyazar.syncthing": { "enabled": false, "settings": { "refreshIntervalSec": 120 } },
    "haseen.syncthing": { "settings": { "refreshIntervalSec": 300 } },
    "t1nk33r.nook": { "settings": { "items": [{ "id": "io.github.ilyazar.syncthing" }] } }
  }
}
EOF
before="$(cat "$(CFG)")"
dirs_before="$(find "$XDG_CONFIG_HOME/omarchy" "$XDG_CONFIG_HOME/haseen/plugins" -printf '%p %s\n' | sort)"

run_m DRY_RUN=true
assert_status "dry run succeeds" 0 "$STATUS"
assert_contains "dry run shows the write" "$OUTPUT" "DRYRUN: write"
assert_eq "dry run leaves shell.json alone" "$before" "$(cat "$(CFG)")"

run_m
assert_status "the migration succeeds" 0 "$STATUS"
cfg="$(cat "$(CFG)")"
assert_eq "bar.right: new ids in place" '["haseen.tray","haseen.omaconnect","haseen.monitor-settings","haseen.battery"]' "$(jq -c .bar.right <<<"$cfg")"
assert_eq "bar.overflow re-pointed" '["haseen.monitor-settings"]' "$(jq -c .bar.overflow <<<"$cfg")"
assert_eq "bar.pinned: once, where the new id was already listed" '["haseen.omaconnect"]' "$(jq -c .bar.pinned <<<"$cfg")"
assert_eq "services: re-pointed, and OmaConnect's service beside its widget" '["haseen.pager","haseen.syncthing","haseen.omaconnect"]' "$(jq -c .services <<<"$cfg")"
assert_eq "monitor: enabled kept, no settings invented" '{"enabled":true}' "$(jq -c '.plugins["haseen.monitor-settings"]' <<<"$cfg")"
assert_eq "omaconnect: the declared settings move, an unknown key does not" '{"settings":{"showBarBattery":true,"defaultPingMessage":"hi"}}' "$(jq -c '.plugins["haseen.omaconnect"]' <<<"$cfg")"
assert_eq "syncthing: an existing new entry wins, enabled: false is kept" '{"enabled":false,"settings":{"refreshIntervalSec":300}}' "$(jq -c '.plugins["haseen.syncthing"]' <<<"$cfg")"
assert_eq "no old entry is left" "[]" "$(jq -c '[.plugins | keys[] | select(test("juliusmork|omaconnect$|ilyazar"))] - ["haseen.omaconnect"]' <<<"$cfg")"
assert_eq "a drawer's own items are left as they are" '[{"id":"io.github.ilyazar.syncthing"}]' "$(jq -c '.plugins["t1nk33r.nook"].settings.items' <<<"$cfg")"
assert_contains "and reported" "$OUTPUT" "t1nk33r.nook still names an old plugin id"
assert_contains "the change is reported" "$OUTPUT" "omarchy.omaconnect is now haseen.omaconnect"
assert_eq "the original plugin directories are untouched" "$dirs_before" "$(find "$XDG_CONFIG_HOME/omarchy" "$XDG_CONFIG_HOME/haseen/plugins" -printf '%p %s\n' | sort)"
# validate enforces each manifest's requires.bins; stub OmaConnect's (KDE
# Connect is not on every machine, CI's image included) so the check is about
# the ids, not the host. hyprctl and curl are stubbed by the sandbox already.
for c in kdeconnect-cli gdbus dbus-monitor; do stub "$c" ":"; done
capture haseen plugin validate haseen.monitor-settings haseen.omaconnect haseen.syncthing
assert_status "the migrated config names valid plugins" 0 "$STATUS"
assert_not_contains "no requirement is unmet" "$OUTPUT" "unmet"

run_m
assert_status "a second run succeeds" 0 "$STATUS"
assert_eq "a second run changes nothing" "$cfg" "$(cat "$(CFG)")"
assert_contains "it still reports the drawer" "$OUTPUT" "left as it is"

# --- a widget in the bar and no services array of its own: the default
# --- services stay and the new service joins them --------------------------------
sandbox migrate-integrations-defaults
write_cfg <<'EOF'
{ "bar": { "center": ["haseen.clock", "io.github.ilyazar.syncthing"] }, "plugins": { "omaconnect": { "settings": { "showTailscale": false } } } }
EOF
run_m
cfg="$(cat "$(CFG)")"
assert_eq "bar.center re-pointed" '["haseen.clock","haseen.syncthing"]' "$(jq -c .bar.center <<<"$cfg")"
assert_eq "services: the defaults plus Syncthing" "$(jq -c '.services + ["haseen.syncthing"]' "$HASEEN_PATH/default/shell.json")" "$(jq -c .services <<<"$cfg")"
assert_eq "plain omaconnect settings move too" '{"settings":{"showTailscale":false}}' "$(jq -c '.plugins["haseen.omaconnect"]' <<<"$cfg")"
assert_eq "no service for a plugin that is in no bar" "false" "$(jq '.services | index("haseen.omaconnect") != null' <<<"$cfg")"

# --- nothing to do --------------------------------------------------------------
sandbox migrate-integrations-none
run_m
assert_status "no shell.json: nothing to do" 0 "$STATUS"
assert_eq "and none is created" "no" "$([[ -e $(CFG) ]] && echo yes || echo no)"
write_cfg <<<'{"bar":{"right":["haseen.tray"]}}'
before="$(cat "$(CFG)")"
run_m
assert_eq "a shell.json without the old ids is left alone" "$before" "$(cat "$(CFG)")"
write_cfg <<<'{"bar": '
run_m
assert_status "a broken shell.json stops the migration" 1 "$STATUS"
assert_eq "and is not overwritten" '{"bar": ' "$(cat "$(CFG)")"
