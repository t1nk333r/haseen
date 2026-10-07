# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# Plugin requirement gates (plan 064): a manifest's `requires` (commands on
# PATH, applied layers, a minimum haseen version; DMS `dependencies` and an
# Omarchy manifest's `requires`) refuses the plugin while unmet. The CLI
# (validate, list, info, enable) and the running shell (Haseen/Plugins.qml in
# Quickshell, when installed) must refuse the same plugins for the same
# reasons, and an unmet plugin must not affect the others.

SHELL_DIR="$HASEEN_PATH/shell"
QS_BIN=${QS_BIN:-/usr/bin/qs}

# put DIR FILE JSON [ENTRY...] — a plugin directory with one manifest file.
put() {
    local dir="$1" file="$2" json="$3" f
    shift 3
    mkdir -p "$dir"
    printf '%s\n' "$json" >"$dir/$file"
    for f in "$@"; do : >"$dir/$f"; done
}

# native ID REQUIRES_JSON — a user bar widget with that requires object.
native() {
    put "$P/$1" manifest.json "{\"schemaVersion\":1,\"id\":\"$1\",\"name\":\"$1\",\"version\":\"1.0.0\",\"kinds\":[\"bar-widget\"],\"entry\":{\"bar-widget\":\"W.qml\"}${2:+,\"requires\":$2}}"
    printf 'import QtQuick\nItem {}\n' >"$P/$1/W.qml"
}

# fixtures DIR — every scenario, shared by the CLI and the shell checks.
fixtures() {
    P="$XDG_CONFIG_HOME/haseen/plugins"
    O="$XDG_CONFIG_HOME/omarchy/plugins"
    D="$XDG_CONFIG_HOME/DankMaterialShell/plugins"
    mkdir -p "$P"
    export HASEEN_SYSROOT="$SANDBOX/root"
    mkdir -p "$HASEEN_SYSROOT/var/lib/haseen/layers"
    : >"$HASEEN_SYSROOT/var/lib/haseen/layers/theme"
    native me.plain ''
    native me.met '{"bins":["sh"],"layers":["theme"],"haseen":"0.1.0"}'
    native me.gated '{"bins":["sh","haseen-no-such-tool"],"layers":["gaming"],"haseen":"99.0.0"}'
    native me.badbins '{"bins":"jq"}'
    native me.badfield '{"packages":["jq"]}'
    # bins are strict: an installed package of that name is not a command.
    native me.strictbin '{"bins":["python-opencv"]}'
    # DMS dependencies mix commands, Arch packages, other distributions'
    # packages and prose. Here pacman knows python-opencv (installed) and
    # haseen-known-pkg (in a repository, not installed); pulseaudio-utils is
    # a Debian name no repository knows.
    put "$D/Deps" plugin.json '{"id":"depsFixture","name":"Deps","version":"1.0.0","type":"widget","component":"./W.qml",
        "dependencies":["python-opencv","haseen-known-pkg","pulseaudio-utils","gpu screen recorder"],"requires":["sh"]}' W.qml
    put "$D/NoDeps" plugin.json '{"id":"noDepsFixture","name":"NoDeps","version":"1.0.0","type":"widget","component":"./W.qml"}' W.qml
    put "$O/me.omgated" manifest.json '{"schemaVersion":1,"id":"me.omgated","name":"OmGated","version":"1.0.0","kinds":["bar-widget"],
        "entryPoints":{"barWidget":"W.qml"},"requires":{"bins":["haseen-no-such-om-tool"]}}' W.qml
    put "$O/me.omlist" manifest.json '{"schemaVersion":1,"id":"me.omlist","name":"OmList","version":"1.0.0","kinds":["bar-widget"],
        "entryPoints":{"barWidget":"W.qml"},"requires":["sh"]}' W.qml
    stub pacman 'case "$1:$2" in -T:python-opencv | -Si:python-opencv | -Si:haseen-known-pkg) exit 0 ;; -T:*) exit 127 ;; esac; exit 1'
    stub notify-send "printf '%s\n' \"\$*\" >>'$SANDBOX/notify.log'"
}

# --- CLI: validate --------------------------------------------------------
sandbox plugin-gates-cli
fixtures

capture haseen plugin validate me.met
assert_status "met requirements validate" 0 "$STATUS"
assert_contains "met: ok" "$OUTPUT" "ok: me.met"
assert_contains "met: requirements listed" "$OUTPUT" "needs: commands sh; layers theme; haseen >= 0.1.0"

capture haseen plugin validate me.gated
assert_status "unmet requirements fail validate" 1 "$STATUS"
assert_contains "unmet header" "$OUTPUT" "unmet: me.gated"
assert_contains "missing command named" "$OUTPUT" "requires: command 'haseen-no-such-tool' is not on PATH"
assert_not_contains "a present command is not reported" "$OUTPUT" "command 'sh'"
assert_contains "missing layer named with its fix" "$OUTPUT" "requires: layer 'gaming' is not applied (haseen layer apply gaming)"
assert_contains "newer haseen named with the installed version" "$OUTPUT" "requires: haseen 99.0.0 or newer (installed: $(cat "$HASEEN_PATH/VERSION"))"

capture haseen plugin validate me.gated me.plain
assert_status "one unmet plugin fails the batch" 1 "$STATUS"
assert_contains "the other is still ok" "$OUTPUT" "ok: me.plain"

capture haseen plugin validate me.badbins
assert_status "requires.bins of the wrong type is invalid" 1 "$STATUS"
assert_contains "bins shape reported" "$OUTPUT" "error: requires.bins must be an array of command names"
capture haseen plugin validate me.badfield
assert_contains "unknown requires field reported" "$OUTPUT" "error: requires: unknown field 'packages'"

# Layers come from the applied-state directory under the sysroot.
: >"$HASEEN_SYSROOT/var/lib/haseen/layers/gaming"
capture haseen plugin validate me.gated
assert_not_contains "an applied layer satisfies the gate" "$OUTPUT" "layer 'gaming'"
rm "$HASEEN_SYSROOT/var/lib/haseen/layers/gaming"

capture haseen plugin validate me.strictbin
assert_contains "bins ignore installed packages" "$OUTPUT" "requires: command 'python-opencv' is not on PATH"

# --- CLI: compat mappings ------------------------------------------------
capture haseen plugin info dms.deps-fixture
assert_contains "DMS dependencies become tools (prose dropped, alias merged)" "$OUTPUT" \
    "needs:       tools python-opencv, haseen-known-pkg, pulseaudio-utils, sh"
capture haseen plugin validate dms.deps-fixture
assert_status "a DMS plugin with a missing dependency is unmet" 1 "$STATUS"
assert_contains "the missing one is named" "$OUTPUT" "requires: 'haseen-known-pkg' is neither a command on PATH nor an installed package"
assert_not_contains "an installed package satisfies a dependency" "$OUTPUT" "'python-opencv' is"
assert_not_contains "a name no repository knows is not held against it" "$OUTPUT" "pulseaudio-utils' is"
assert_not_contains "a command satisfies a dependency" "$OUTPUT" "'sh' is"
capture haseen plugin validate dms.no-deps-fixture
assert_status "a DMS plugin without dependencies is not gated" 0 "$STATUS"
capture haseen plugin validate me.omgated
assert_contains "an Omarchy manifest's requires object is honoured" "$OUTPUT" "requires: command 'haseen-no-such-om-tool' is not on PATH"
capture haseen plugin validate me.omlist
assert_status "an Omarchy requires array is read as tools" 0 "$STATUS"
assert_contains "and listed" "$OUTPUT" "needs: tools sh"

# --- CLI: list, info, enable -------------------------------------------
capture haseen plugin list
assert_contains "list: unmet state with the reason" "$(grep '^me.gated ' <<<"$OUTPUT")" \
    "unmet      bar-widget               me.gated (requires: command 'haseen-no-such-tool' is not on PATH; requires: layer 'gaming'"
assert_contains "list: a met plugin keeps its state" "$(grep '^me.met ' <<<"$OUTPUT")" "available"
assert_contains "list: a plugin without requires is unaffected" "$(grep '^me.plain ' <<<"$OUTPUT")" "available"
capture haseen plugin info me.gated
assert_contains "info: unmet state" "$OUTPUT" "state:       unmet (the shell does not load it)"
capture haseen plugin enable me.gated --dry-run
assert_status "enabling an unmet plugin is allowed" 0 "$STATUS"
assert_dry_pure "enable unmet" "$OUTPUT"
assert_contains "enable warns why the shell will not load it" "$OUTPUT" "the shell will not load me.gated until its requirements are met"

# --- shell: Haseen/Plugins.qml refuses the same plugins ------------------
if [[ ! -x $QS_BIN ]]; then
    echo "  skip: Quickshell not installed; the shell's requirement gate not exercised" >&2
else
    sandbox plugin-gates-shell
    fixtures
    XDG_RUNTIME_DIR="$SANDBOX/run"
    mkdir -p "$XDG_RUNTIME_DIR"
    chmod 700 "$XDG_RUNTIME_DIR"
    export XDG_RUNTIME_DIR
    unset DISPLAY WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE DBUS_SESSION_BUS_ADDRESS
    harness="$SANDBOX/shell"
    mkdir -p "$harness"
    for module in Haseen Compat Common Services Widgets Modules; do
        ln -s "$SHELL_DIR/$module" "$harness/$module"
    done
    ln -s "$SHELL_DIR/plugins" "$harness/plugins"
    cat >"$harness/shell.qml" <<'QML'
import QtQuick
import Quickshell
import qs.Haseen
ShellRoot {
    Timer {
        interval: 50
        repeat: true
        running: true
        onTriggered: {
            if (!Plugins.ready)
                return;
            running = false;
            const r = {};
            for (const id of ["me.plain", "me.met", "me.gated", "me.badbins", "me.strictbin", "dms.deps-fixture", "dms.no-deps-fixture", "me.omgated", "me.omlist"]) {
                const rec = Plugins.registry[id];
                if (rec)
                    r[id] = { valid: rec.valid, unmet: rec.unmet, url: Plugins.entryUrl(id, "bar-widget") !== "" };
            }
            r.errors = Plugins.errors.filter(e => e.id === "me.gated").map(e => e.message);
            Plugins.noteMissing("me.gated", "bar-widget");
            Plugins.noteMissing("me.gated", "bar-widget");
            console.log("RESULT " + JSON.stringify(r));
            Qt.callLater(Qt.quit);
        }
    }
}
QML
    capture env QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME='' QT_QUICK_BACKEND=software QT_NO_XDG_DESKTOP_PORTAL=1 \
        DBUS_SYSTEM_BUS_ADDRESS="unix:path=$SANDBOX/no-system-bus" HASEEN_PATH="$HASEEN_PATH" \
        timeout 40 dbus-run-session --config-file="$REPO/tools/smoke-session.conf" -- "$QS_BIN" -p "$harness"
    result="$(sed -n 's/^.*RESULT //p' <<<"$OUTPUT")"
    if [[ -n $result ]]; then
        get() { jq -c "$1" <<<"$result"; }
        assert_eq "shell: a plugin without requires loads" '{"valid":true,"unmet":[],"url":true}' "$(get '."me.plain"')"
        assert_eq "shell: met requirements load" '{"valid":true,"unmet":[],"url":true}' "$(get '."me.met"')"
        assert_eq "shell: unmet requirements refuse the plugin" '[false,false]' "$(get '."me.gated" | [.valid, .url]')"
        reasons() { haseen plugin validate "$1" | grep '^requires:' | jq -Rsc 'split("\n") | map(select(. != ""))' || true; }
        cli="$(reasons me.gated)"
        assert_eq "shell: the same reasons as the CLI" "$cli" "$(get '."me.gated".unmet')"
        assert_eq "shell: the reasons are plugin errors" "$cli" "$(get .errors)"
        assert_eq "shell: a malformed requires is invalid" false "$(get '."me.badbins".valid')"
        assert_eq "shell: bins ignore installed packages, as the CLI" "$(reasons me.strictbin)" "$(get '."me.strictbin".unmet')"
        assert_eq "shell: DMS dependencies gate as tools (the known, uninstalled package refuses)" \
            '["requires: '\''haseen-known-pkg'\'' is neither a command on PATH nor an installed package"]' "$(get '."dms.deps-fixture".unmet')"
        assert_eq "shell: and agree with the CLI" "$(reasons dms.deps-fixture)" "$(get '."dms.deps-fixture".unmet')"
        assert_eq "shell: a DMS plugin without dependencies loads" true "$(get '."dms.no-deps-fixture".valid')"
        assert_eq "shell: an Omarchy requires object gates" \
            '["requires: command '\''haseen-no-such-om-tool'\'' is not on PATH"]' "$(get '."me.omgated".unmet')"
        assert_eq "shell: an Omarchy requires array of present commands loads" true "$(get '."me.omlist".valid')"
        notes="$(cat "$SANDBOX/notify.log" 2>/dev/null || true)"
        assert_eq "shell: one notification for a refused plugin asked for twice" 1 "$(grep -c 'me.gated not loaded' <<<"$notes")"
        assert_contains "shell: the notification names the reason" "$notes" "command 'haseen-no-such-tool' is not on PATH"
        assert_not_contains "no QML type errors" "$OUTPUT" "TypeError"
    else
        _fail "plugin gate shell result not produced" "$OUTPUT"
    fi
fi
