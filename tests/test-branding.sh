# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# haseen's mark (plan 059): `haseen branding mark` keeps branding.mark in
# shell.json, `haseen about --logo` prints the selected mark's terminal logo,
# and Haseen/Branding.qml resolves the same choice in the real engine.

QS_BIN=${QS_BIN:-/usr/bin/qs}
MARKS=(kufic shield gate)

sandbox branding-mark
CFG="$XDG_CONFIG_HOME/haseen/shell.json"
ICONS="$XDG_DATA_HOME/icons/hicolor"
mkdir -p "$SANDBOX/sysroot"
export HASEEN_SYSROOT="$SANDBOX/sysroot"

# --- the command ----------------------------------------------------------------
capture haseen branding --help
assert_contains "help names the mark target" "$OUTPUT" "haseen branding mark [kufic|shield|gate]"
assert_contains "help keeps the screensaver/about targets" "$OUTPUT" "haseen branding <screensaver|about> image"
assert_contains "the header lists --dry-run" "$(sed -n 's/^# haseen:args //p' "$REPO/bin/haseen-branding")" "--dry-run"

capture haseen branding mark
assert_status "mark without a name exits 0" 0 "$STATUS"
assert_eq "the default mark is kufic" "kufic" "$OUTPUT"

capture haseen branding mark shield --dry-run
assert_status "mark --dry-run exits 0" 0 "$STATUS"
assert_dry_pure "mark --dry-run" "$OUTPUT"
assert_contains "the dry run shows the shell.json it would write" "$OUTPUT" '"mark": "shield"'
assert_contains "and the app icon" "$OUTPUT" "$ICONS/scalable/apps/haseen.svg"
assert_eq "a dry run writes no shell.json" "no" "$([[ -e $CFG ]] && echo yes || echo no)"
assert_eq "nor an icon" "no" "$([[ -e $ICONS/scalable/apps/haseen.svg ]] && echo yes || echo no)"

mkdir -p "${CFG%/*}"
echo '{"bar": {"transparent": true}}' >"$CFG"
capture haseen branding mark shield
assert_status "mark shield exits 0" 0 "$STATUS"
assert_eq "it sets branding.mark" "shield" "$(jq -r .branding.mark "$CFG")"
assert_eq "and keeps the rest of shell.json" "true" "$(jq -r .bar.transparent "$CFG")"
assert_eq "mark prints the new choice" "shield" "$(haseen branding mark)"
assert_contains "the app icon is the shield, coloured" "$(cat "$ICONS/scalable/apps/haseen.svg")" "haseen — shield"
assert_not_contains "with no currentColor left for an icon loader" "$(cat "$ICONS/scalable/apps/haseen.svg")" "currentColor"
assert_contains "the symbolic icon keeps currentColor for GTK" "$(cat "$ICONS/symbolic/apps/haseen-symbolic.svg")" "currentColor"

before="$(cat "$CFG")"
capture haseen branding mark crescent
assert_status "an unknown mark is refused" 1 "$STATUS"
assert_contains "and the error lists the marks" "$OUTPUT" "kufic shield gate"
assert_eq "shell.json is untouched" "$before" "$(cat "$CFG")"
capture haseen branding mark shield gate
assert_status "two names is a usage error" 2 "$STATUS"

# --- haseen about --logo: the selected mark's logo, then the facts ----------------
for m in "${MARKS[@]}"; do
    haseen branding mark "$m" >/dev/null
    capture haseen about --logo
    assert_status "about --logo ($m) exits 0" 0 "$STATUS"
    logo="$HASEEN_PATH/branding/logo-$m.txt"
    assert_eq "about --logo prints the $m logo first" "$(cat "$logo")" "$(head -n "$(wc -l <"$logo")" <<<"$OUTPUT")"
    assert_contains "and the facts under it ($m)" "$OUTPUT" "  haseen   $(cat "$HASEEN_PATH/VERSION")"
    assert_eq "the $m logo fits 81 columns" "yes" "$(awk '{ if (length > 81) bad = 1 } END { print bad ? "no" : "yes" }' "$logo")"
done
kufic_logo="$(cat "$HASEEN_PATH/branding/logo-kufic.txt")"
assert_not_contains "each mark has its own logo" "$(haseen about --logo)" "$kufic_logo"
# A hand-edited bad value falls back to kufic instead of failing.
echo '{"branding": {"mark": "crescent"}}' >"$CFG"
capture haseen about --logo
assert_contains "a bad branding.mark shows kufic" "$OUTPUT" "$kufic_logo"
echo '{"branding": ' >"$CFG"
capture haseen about --logo
assert_status "a broken shell.json does not stop about --logo" 0 "$STATUS"
assert_contains "and shows kufic" "$OUTPUT" "$kufic_logo"

# --- Haseen/Branding.qml in the real engine ---------------------------------------
if [[ ! -x $QS_BIN ]]; then
    echo "  skip: Quickshell not installed; Branding singleton not run" >&2
else
    XDG_RUNTIME_DIR="$(mktemp -d "${TMPDIR:-/tmp}/haseen-branding.XXXXXX")"
    export XDG_RUNTIME_DIR
    chmod 700 "$XDG_RUNTIME_DIR"
    trap 'rm -rf "$XDG_RUNTIME_DIR"' EXIT
    unset DISPLAY WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE DBUS_SESSION_BUS_ADDRESS
    harness="$SANDBOX/shell"
    mkdir -p "$harness"
    for module in Haseen Compat Ui Commons; do
        ln -s "$HASEEN_PATH/shell/$module" "$harness/$module"
    done
    ln -s "$HASEEN_PATH/shell/plugins" "$harness/plugins"
    # The paths for every mark and the resolved choice, once Config has read
    # shell.json (the default file always has branding.mark).
    cat >"$harness/shell.qml" <<'EOF'
import QtQuick
import Quickshell
import qs.Haseen

ShellRoot {
    Timer {
        interval: 100
        repeat: true
        running: true
        onTriggered: {
            if (!Config.merged.branding)
                return;
            const all = {};
            for (const m of Branding.marks.concat(["crescent"]))
                all[m] = Branding.pathsFor(m);
            console.log("RESULT " + JSON.stringify({ mark: Branding.mark, paths: Branding.paths, logo: Branding.logoPath, wordmark: Branding.wordmarkPath, all: all }));
            Qt.quit();
        }
    }
}
EOF
    run_branding() { # USER-SHELL-JSON
        printf '%s\n' "$1" >"$CFG"
        capture env HASEEN_PATH="$HASEEN_PATH" QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME='' QT_QUICK_BACKEND=software \
            timeout 30 "$QS_BIN" -p "$harness"
        result="$(sed -n 's/^.*RESULT //p' <<<"$OUTPUT" | tail -n1)"
        [[ -n $result ]] || _fail "Branding produced no result" "$OUTPUT"
    }
    br() { jq -r "$1" <<<"$result"; }

    run_branding '{"branding": {"mark": "gate"}}'
    assert_eq "Branding: the configured mark" "gate" "$(br .mark)"
    assert_eq "Branding: its logo" "$HASEEN_PATH/branding/logo-gate.txt" "$(br .logo)"
    assert_eq "Branding: its wordmark" "$HASEEN_PATH/branding/gate/wordmark.svg" "$(br .wordmark)"
    for m in "${MARKS[@]}"; do
        for k in mark symbolic symbolic24 wordmark logo; do
            p="$(br ".all.$m.$k")"
            assert_contains "Branding: $m $k is the $m file" "$p" "$m"
            assert_eq "Branding: $m $k exists ($p)" "yes" "$([[ -s $p ]] && echo yes || echo no)"
        done
    done
    assert_eq "Branding: an unknown name resolves to kufic" "$(br .all.kufic)" "$(br .all.crescent)"

    run_branding '{"branding": {"mark": "crescent"}}'
    assert_eq "Branding: a bad value falls back to kufic" "kufic" "$(br .mark)"
    assert_eq "Branding: with kufic's paths" "$HASEEN_PATH/branding/kufic/symbolic.svg" "$(br .paths.symbolic)"
    run_branding '{"branding": {"mark": 7}}'
    assert_eq "Branding: a non-string falls back to kufic" "kufic" "$(br .mark)"
    run_branding '{}'
    assert_eq "Branding: unset is kufic" "kufic" "$(br .mark)"
fi
