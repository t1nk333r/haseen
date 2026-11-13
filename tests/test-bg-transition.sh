# shellcheck shell=bash
# haseen:covers share/haseen/shell/plugins/haseen.background/**
# haseen:covers share/haseen/migrations/1794511775-background-transition.sh
# haseen:covers share/haseen/layers/theme/theme-lib.sh share/haseen/default/shell.json
# haseen:covers share/haseen/default/hypr/windowrules.lua
# haseen:covers bin/haseen-theme-set docs/architecture.md
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# The wallpaper transition (plan 161): haseen.background's service covers a
# background change while swaybg restarts. The test checks the manifest and
# defaults, that the shader is the shell's only one and that its compiled
# .qsb matches the source, the migration, the CLI's order around the restart
# (begin, wait until covered, restart, shown) against stubs, one reload at a
# time, `theme set` handing the cover the picture swaybg showed although the
# swap deleted it, the pure logic in Transition.js under Qt's JS engine, the
# service's skip and timeout paths in the real Quickshell engine, the real
# per-screen cover (TransitionCover.qml) covering, keeping its window across
# a change during a change and being freed, and the drawing: both images
# cropped as swaybg's fill crops them, the software crossfade and its
# fade-out at scales 1 and 1.25, and, where a GL context exists
# (HASEEN_GL_DISPLAY), both shader effects at progress 0, mid and 1 at
# scales 1 and 1.25.

BG="$HASEEN_PATH/shell/plugins/haseen.background"
SHELL_DIR="$HASEEN_PATH/shell"
QML_BIN=${QML_BIN:-/usr/lib/qt6/bin/qml}
QSB=${QSB:-/usr/lib/qt6/bin/qsb}
QS_BIN=${QS_BIN:-$(command -v qs || echo /usr/bin/qs)}

# --- manifest, defaults, the one shader --------------------------------------
sandbox bg-transition
capture haseen plugin validate haseen.background
assert_status "background validates" 0 "$STATUS"
assert_eq "a panel and a service" "panel service" "$(jq -r '.kinds | join(" ")' "$BG/manifest.json")"
assert_eq "the service is Transition.qml" "Transition.qml" "$(jq -r '.entry.service' "$BG/manifest.json")"
assert_eq "auto by default, 1.8 s" "auto 1800" "$(jq -r '[.settings.transition.default, .settings.transitionDuration.default] | map(tostring) | join(" ")' "$BG/manifest.json")"
assert_eq "the default shell.json starts the service" "true" "$(jq '.services | index("haseen.background") != null' "$HASEEN_PATH/default/shell.json")"
assert_eq "no transition setting overridden in the defaults" "null" "$(jq '.plugins["haseen.background"].settings.transition' "$HASEEN_PATH/default/shell.json")"

# Architecture 6's one exception: ShaderEffect appears in ShaderView.qml and
# nowhere else under the shell (ShaderEffectSource, a layer's texture
# setting, is not a shader).
assert_eq "ShaderEffect only in ShaderView.qml" "$BG/ShaderView.qml" \
    "$(grep -rlE 'ShaderEffect\b([^S]|$)' "$SHELL_DIR" --include='*.qml' --include='*.js' | sort)"
assert_eq "no other shader file in the shell" "$BG/transition-2.frag.qsb $BG/transition.frag" \
    "$(find "$SHELL_DIR" \( -name '*.frag' -o -name '*.vert' -o -name '*.qsb' \) | sort | paste -sd' ')"
assert_contains "the shader view loads the versioned .qsb" "$(cat "$BG/ShaderView.qml")" 'Qt.resolvedUrl("transition-2.frag.qsb")'
view="$(cat "$BG/TransitionView.qml")"
assert_contains "the view asks which renderer draws" "$view" "GraphicsInfo.api === GraphicsInfo.Software"
assert_contains "the shader loads only when it draws" "$view" "active: view.wantsShader"
assert_contains "the effect asks for the shader only off the software renderer" "$(cat "$BG/Transition.js")" \
    'return !software && (effect === "contagion" || effect === "outline");'
assert_contains "architecture 6 names the exception" "$(cat "$REPO/docs/architecture.md")" "haseen.background/ShaderView.qml"
svc="$(cat "$BG/Transition.qml")"
assert_contains "nothing is loaded at idle" "$svc" 'active: root.phase !== "idle"'
assert_contains "the service answers on the background target" "$svc" 'target: "background"'
win="$(cat "$BG/TransitionWindows.qml")"
assert_contains "covers sit on the Bottom layer, over swaybg" "$win" "WlrLayershell.layer: WlrLayer.Bottom"
assert_contains "covers reserve no space" "$win" "exclusionMode: ExclusionMode.Ignore"
assert_contains "covers take no input" "$win" "mask: Region {}"
assert_contains "one cover per screen" "$win" "model: Quickshell.screens"
assert_contains "Hyprland does not fade the covers" "$(cat "$HASEEN_PATH/default/hypr/windowrules.lua")" \
    'match = { namespace = "^haseen-background-transition$" }'
assert_eq "colours come from Theme" "" \
    "$(grep -nE '"#[0-9a-fA-F]{3,8}"' "$BG"/*.qml "$BG"/*.js || true)"

# The committed .qsb is the source compiled. qsb's output is deterministic
# for one version; another version may differ byte for byte, so the check
# runs with the version the file was built with (6.12, transition.frag's
# header). CI's package list has no qt6-shadertools, so it skips there.
if [[ -x $QSB ]] && "$QSB" --version 2>/dev/null | grep -q '^qsb 6\.12\.'; then
    "$QSB" --qt6 -o "$SANDBOX/fresh.qsb" "$BG/transition.frag" >/dev/null 2>&1 || true
    assert_eq "the committed .qsb matches transition.frag" "same" \
        "$(cmp -s "$SANDBOX/fresh.qsb" "$BG/transition-2.frag.qsb" && echo same || echo differs)"
else
    echo "  (no qsb 6.12: the committed .qsb was not compared with its source)" >&2
fi

# --- migration -----------------------------------------------------------------
MIGRATION=1794511775-background-transition.sh
run_migration() {
    capture env HASEEN_PATH="$HASEEN_PATH" HASEEN_MIGRATION="$MIGRATION" \
        bash -Eeuo pipefail "$HASEEN_PATH/migrations/$MIGRATION"
}
sandbox bg-transition-migration
CFG="$XDG_CONFIG_HOME/haseen/shell.json"
run_migration
assert_status "no shell.json: nothing to do" 0 "$STATUS"
assert_eq "and none written" "no" "$([[ -e $CFG ]] && echo yes || echo no)"
mkdir -p "$XDG_CONFIG_HOME/haseen"
printf '{"bar":{"height":30}}\n' >"$CFG"
run_migration
assert_eq "a shell.json without its own services is left alone" '{"bar":{"height":30}}' "$(jq -c . "$CFG")"
printf '{"services":["haseen.pager","me.svc"]}\n' >"$CFG"
run_migration
assert_status "migration exits 0" 0 "$STATUS"
assert_eq "the service joins the user's own list, last" '["haseen.pager","me.svc","haseen.background"]' "$(jq -c .services "$CFG")"
run_migration
assert_eq "a second run adds nothing" '["haseen.pager","me.svc","haseen.background"]' "$(jq -c .services "$CFG")"

# --- the CLI's order around the restart ------------------------------------------
# theme_background_reload with swaybg running (the invocation link and a
# fixture /proc), and stubs for systemctl and qs that log to one file, so
# the order of the calls shows.
sandbox bg-transition-cli
ROOT="$SANDBOX/root"
mkdir -p "$ROOT/proc/4242" "$HOME/img" "$XDG_RUNTIME_DIR/systemd/units"
printf 'swaybg\0--mode\0fill\0--image\0%s\0' "$HOME/img/old.png" >"$ROOT/proc/4242/cmdline"
: >"$HOME/img/old.png"
: >"$HOME/img/new.png"
ln -s 0123 "$XDG_RUNTIME_DIR/systemd/units/invocation:haseen-background.service"
CALLS="$SANDBOX/calls.log"
stub systemctl "echo \"systemctl \$*\" >>'$CALLS'
case \"\$*\" in *show*) echo 4242 ;; esac"
# QS_ANSWER: what `begin` answers; the second `state` call answers playing.
stub qs "echo \"qs \$*\" >>'$CALLS'
case \"\$*\" in
*' begin '*) echo \"\${QS_ANSWER:-loading}\" ;;
*' state') n=\$(grep -c ' state\$' '$CALLS'); [ \"\$n\" -ge 2 ] && echo playing || echo loading ;;
*' shown') echo holding ;;
esac"
reload() {
    local envs=(HASEEN_SYSROOT="$ROOT")
    [[ -z ${2:-} ]] || envs+=(QS_ANSWER="$2")
    : >"$CALLS"
    ln -sfn "$1" "$HASEEN_USER_STATE_DIR/current/background"
    capture env "${envs[@]}" bash -c '
        source "$HASEEN_PATH/lib/common.sh"
        source "$HASEEN_PATH/layers/theme/theme-lib.sh"
        parse_common_flags "$@"
        theme_background_reload' reload ${3:+"$3"}
}
HASEEN_USER_STATE_DIR="$XDG_STATE_HOME/haseen"
mkdir -p "$HASEEN_USER_STATE_DIR/current"
shellq="qs -p $HASEEN_PATH/shell ipc call background"
reload "$HOME/img/new.png"
assert_status "reload exits 0" 0 "$STATUS"
assert_eq "begin, wait until covered, restart under the cover, then shown" \
    "systemctl --user show -p MainPID --value haseen-background.service
$shellq begin $HOME/img/old.png $HOME/img/new.png
$shellq state
$shellq state
systemctl --user try-restart haseen-background.service
$shellq shown" "$(cat "$CALLS")"
reload "$HOME/img/new.png" "skip game"
assert_eq "a skipped change restarts at once and says nothing more" \
    "systemctl --user show -p MainPID --value haseen-background.service
$shellq begin $HOME/img/old.png $HOME/img/new.png
systemctl --user try-restart haseen-background.service" "$(cat "$CALLS")"
reload "$HOME/img/old.png"
assert_eq "the same image: no transition asked for" \
    "systemctl --user show -p MainPID --value haseen-background.service
systemctl --user try-restart haseen-background.service" "$(cat "$CALLS")"
printf 'dms\n' >"$HASEEN_USER_STATE_DIR/active-shell"
reload "$HOME/img/new.png"
assert_eq "under DMS the haseen shell is not asked" \
    "systemctl --user show -p MainPID --value haseen-background.service
systemctl --user try-restart haseen-background.service" "$(cat "$CALLS")"
rm -f "$HASEEN_USER_STATE_DIR/active-shell"
stub qs "echo \"qs \$*\" >>'$CALLS'; exit 1"
reload "$HOME/img/new.png"
assert_status "no shell answering: still exits 0" 0 "$STATUS"
assert_eq "no shell answering: the restart still happens" \
    "systemctl --user show -p MainPID --value haseen-background.service
$shellq begin $HOME/img/old.png $HOME/img/new.png
systemctl --user try-restart haseen-background.service" "$(cat "$CALLS")"
reload "$HOME/img/new.png" "" --dry-run
assert_eq "a dry run calls nothing" "" "$(cat "$CALLS")"
assert_contains "a dry run plans the cover" "$OUTPUT" "DRYRUN: haseen shell ipc background begin <the image swaybg shows> $HOME/img/new.png"
assert_contains "... the restart" "$OUTPUT" "DRYRUN: systemctl --user try-restart haseen-background.service"
assert_contains "... and the hand-over" "$OUTPUT" "DRYRUN: haseen shell ipc background shown"
# The old image gone (theme set deleted it before the fix below): no
# transition asked for, since the cover could not show it.
mv "$HOME/img/old.png" "$HOME/img/old.keep"
stub qs "echo \"qs \$*\" >>'$CALLS'; echo loading"
reload "$HOME/img/new.png"
assert_eq "the old image missing: no transition asked for" \
    "systemctl --user show -p MainPID --value haseen-background.service
systemctl --user try-restart haseen-background.service" "$(cat "$CALLS")"
mv "$HOME/img/old.keep" "$HOME/img/old.png"
# A shell too busy to answer `begin` within its second may still run it
# after the restart; `shown` follows anyway, so it never covers the new
# image with the old one.
stub qs "echo \"qs \$*\" >>'$CALLS'
case \"\$*\" in *' begin '*) exec sleep 3 ;; esac"
reload "$HOME/img/new.png"
assert_eq "a begin that timed out is still followed by shown" \
    "systemctl --user show -p MainPID --value haseen-background.service
$shellq begin $HOME/img/old.png $HOME/img/new.png
systemctl --user try-restart haseen-background.service
$shellq shown" "$(cat "$CALLS")"
# One reload at a time: a reload waits while another holds the lock, so a
# second `bg next` never sends its begin before the first one's shown.
stub qs "echo \"qs \$*\" >>'$CALLS'; exit 1"
lockf="$HASEEN_USER_STATE_DIR/current/.background-reload.lock"
flock "$lockf" sleep 0.8 &
holder=$!
for _ in $(seq 2000); do flock -n "$lockf" true || break; done
t0=${EPOCHREALTIME/[.,]/}
reload "$HOME/img/new.png"
waited=$(((${EPOCHREALTIME/[.,]/} - t0) / 1000))
wait "$holder" || true
assert_eq "a reload waits for one already running (${waited} ms)" yes "$( ((waited >= 400)) && echo yes || echo no)"
rm "$XDG_RUNTIME_DIR/systemd/units/invocation:haseen-background.service"
reload "$HOME/img/new.png"
assert_eq "swaybg not running: nothing at all" "" "$(cat "$CALLS")"

# --- theme set: the old picture survives the swap ---------------------------------
# swaybg's image lives in current/theme, which theme_swap deletes before the
# reload; theme set keeps it (theme_background_keep) for the cover's old
# picture. Two user themes whose backgrounds share a file name, BG1.png, with
# different bytes: the begin must name a file holding the first theme's.
sandbox bg-transition-theme-set
stub pgrep 'exit 1'
stub pkill 'exit 0'
stub gsettings 'exit 0'
export HASEEN_THEME_FETCH=0
for t in t-one t-two; do
    mkdir -p "$XDG_CONFIG_HOME/haseen/themes/$t/backgrounds"
    command cp -f "$HASEEN_PATH/themes/tokyo-night/colors.toml" "$XDG_CONFIG_HOME/haseen/themes/$t/"
done
printf 'first theme\n' >"$XDG_CONFIG_HOME/haseen/themes/t-one/backgrounds/BG1.png"
printf 'second theme\n' >"$XDG_CONFIG_HOME/haseen/themes/t-two/backgrounds/BG1.png"
capture env HASEEN_THEME_HEADLESS=1 haseen theme set t-one
assert_status "theme set t-one" 0 "$STATUS"
CUR="$XDG_STATE_HOME/haseen/current"
shown="$(readlink -f "$CUR/background")"
assert_eq "t-one's background is the copy in current/theme" "$(readlink -f "$CUR/theme")/backgrounds/BG1.png" "$shown"
ROOT="$SANDBOX/root"
mkdir -p "$ROOT/proc/4242" "$XDG_RUNTIME_DIR/systemd/units"
printf 'swaybg\0--mode\0fill\0--image\0%s\0' "$shown" >"$ROOT/proc/4242/cmdline"
ln -s 0123 "$XDG_RUNTIME_DIR/systemd/units/invocation:haseen-background.service"
CALLS="$SANDBOX/calls.log"
: >"$CALLS"
stub systemctl "case \"\$*\" in *show*) echo 4242 ;; esac"
# At begin: the old file's bytes. At shown: whether it is still there.
stub qs "case \"\$*\" in
*' begin '*) set -- \$*; old=\${7}; echo \"begin \$old \${8}\" >>'$CALLS'; echo \"old holds: \$(cat \"\$old\" 2>/dev/null || echo nothing)\" >>'$CALLS'
    echo \"\$old\" >'$SANDBOX/old.path'; echo loading ;;
*' state') echo playing ;;
*' shown') echo \"at shown: \$([ -f \"\$(cat '$SANDBOX/old.path')\" ] && echo kept || echo gone)\" >>'$CALLS'; echo holding ;;
esac"
# Another theme set still running keeps its own picture (a pid that is
# alive); one killed halfway left one behind (a pid that is not running).
sleep 300 &
live=$!
: >"$CUR/.background-shown-$live-other.png"
: >"$CUR/.background-shown-2147483646-stale.png"
capture env HASEEN_SYSROOT="$ROOT" haseen theme set t-two
assert_status "theme set t-two" 0 "$STATUS"
assert_eq "theme set: the cover gets the picture swaybg showed, kept past the swap" \
    "begin $CUR/.background-shown-PID-BG1.png $(readlink -f "$CUR/theme")/backgrounds/BG1.png
old holds: first theme
at shown: kept" "$(sed 's/\.background-shown-[0-9]*-/.background-shown-PID-/' "$CALLS")"
assert_eq "theme set: and removes only its own kept copy and the dead run's" "./.background-shown-$live-other.png" \
    "$(cd "$CUR" && find . -maxdepth 1 -name '.background-shown-*')"
kill "$live" 2>/dev/null || true
wait "$live" 2>/dev/null || true
rm -f "$CUR/.background-shown-$live-other.png"

if [[ ! -x $QML_BIN ]]; then
    echo "  (no $QML_BIN: the transition's logic and drawing were not exercised)" >&2
    return 0
fi
sandbox bg-transition-engine

# --- the pure logic, under the Qt JS engine ----------------------------------------
harness="$SANDBOX/logic"
mkdir -p "$harness"
cat >"$harness/Logic.qml" <<EOF
import QtQuick
import "file://$BG/Transition.js" as T
Item {
    function out(k, v) { console.warn("RESULT " + k + " " + JSON.stringify(v)); }
    function run(events) {
        let s = T.initial();
        const names = [];
        for (const e of events) { s = T.reduce(s, e); names.push(s.name); }
        return names;
    }
    Component.onCompleted: {
        out("settings", [T.setting("outline"), T.setting("sparkle"), T.setting(undefined), T.setting("none")]);
        out("duration", [T.durationMs(undefined), T.durationMs(2000), T.durationMs(10), T.durationMs(99999), T.durationMs("x")]);
        out("pick", [T.pick("auto", "", 0.2), T.pick("auto", "", 0.8), T.pick("auto", "contagion", 0.2), T.pick("auto", "outline", 0.9),
            T.pick("fade", "contagion", 0.1), T.pick("none", "", 0.1), T.pick("bogus", "outline", 0.1)]);
        out("shader", [T.drawsWithShader("contagion", false), T.drawsWithShader("outline", false), T.drawsWithShader("fade", false),
            T.drawsWithShader("contagion", true), T.drawsWithShader("outline", true)]);
        const base = { effect: "contagion", oldPath: "/a.png", newPath: "/b.png", reduceMotion: false, context: "" };
        const why = o => T.skipReason(Object.assign({}, base, o));
        out("skip", [why({}), why({ effect: "none" }), why({ oldPath: "" }), why({ newPath: "" }), why({ newPath: "/a.png" }),
            why({ reduceMotion: true }), why({ context: "game" }), why({ context: "present" })]);
        // A 16:10 picture on a 16:9 screen loses some height; a 4:3 one
        // more; a wide one loses width; equal aspects lose nothing.
        const c = (W, H, w, h) => { const s = T.coverScale(W, H, w, h); return [Math.round(s.x * 1000) / 1000, Math.round(s.y * 1000) / 1000]; };
        out("cover", [c(1920, 1080, 1920, 1200), c(1920, 1080, 1024, 768), c(1920, 1080, 3840, 1080), c(2560, 1440, 3840, 2160), c(0, 0, 10, 10)]);
        out("cells", [T.cellPx(1), T.cellPx(1.25), T.cellPx(2), T.cellPx(0)]);
        out("normal", run(["begin", "ready", "shown", "settled", "played", "left"]));
        out("late", run(["begin", "ready", "played", "shown", "settled", "left"]));
        out("noShown", run(["begin", "ready", "played", "settled", "left"]));
        out("slow", run(["begin", "timeout", "ready"]));
        out("first", run(["begin", "shown", "ready"]));
        out("again", run(["begin", "ready", "begin", "ready"]));
        out("abort", run(["begin", "ready", "abort", "played"]));
        out("covered", ["idle", "loading", "playing", "holding", "leaving"].map(n => T.covered({ name: n })));
        Qt.quit();
    }
}
EOF
qml_out="$(cd "$harness" && QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 timeout 30 "$QML_BIN" Logic.qml 2>&1)"
r() { sed -n "s/^.*RESULT $1 //p" <<<"$qml_out"; }
assert_eq "the setting: one of four, else auto" '["outline","auto","auto","none"]' "$(r settings)"
assert_eq "the duration: 1.8 s by default, held to 0.4-5 s" '[1800,2000,400,5000,1800]' "$(r duration)"
assert_eq "auto takes turns; a fixed effect stays" '["contagion","outline","outline","contagion","fade","none","contagion"]' "$(r pick)"
assert_eq "only contagion and outline, only on a GPU, use the shader" '[true,true,false,false,false]' "$(r shader)"
assert_eq "why a change is instant" '["","off","no old image","no new image","same image","animations off","game",""]' "$(r skip)"
assert_eq "cover: the texture share a screen shows, as swaybg's fill" \
    '[[1,0.9],[1,0.75],[0.5,1],[1,1],[1,1]]' "$(r cover)"
assert_eq "cells are 4 logical pixels" '[4,5,8,4]' "$(r cells)"
assert_eq "shown during the effect: it ends, then leaves" '["loading","playing","playing","playing","leaving","idle"]' "$(r normal)"
assert_eq "shown after the effect: it holds until settled" '["loading","playing","holding","holding","leaving","idle"]' "$(r late)"
assert_eq "no shown at all: the safety bound settles it" '["loading","playing","holding","leaving","idle"]' "$(r noShown)"
assert_eq "images too slow: back to idle, a late ready ignored" '["loading","idle","idle"]' "$(r slow)"
assert_eq "swaybg restarted before the cover: no cover" '["loading","idle","idle"]' "$(r first)"
assert_eq "a change during a change starts over" '["loading","playing","loading","playing"]' "$(r again)"
assert_eq "abort ends it at once" '["loading","playing","idle","idle"]' "$(r abort)"
assert_eq "covered: playing, holding and leaving" '[false,false,true,true,true]' "$(r covered)"

# --- the service in the real engine ---------------------------------------------------
# No layer shell offscreen, so no cover ever draws: a change that is not
# skipped waits for its screens and goes back to idle at the load bound,
# unless the harness reports the screens covered itself.
if [[ -x $QS_BIN ]]; then
    qsh="$SANDBOX/qs"
    mkdir -p "$qsh"
    for module in Haseen Compat Ui Commons; do
        ln -s "$SHELL_DIR/$module" "$qsh/$module"
    done
    ln -s "$SHELL_DIR/plugins" "$qsh/plugins"
    cat >"$qsh/shell.qml" <<'QML'
import QtQuick
import Quickshell
import qs.Haseen
import "plugins/haseen.background" as Background
ShellRoot {
    id: shell
    function out(k, v) { console.warn("RESULT " + k + " " + JSON.stringify(v)); }
    Background.Transition {
        id: svc
        pluginId: "haseen.background"
        settings: ({ transition: Quickshell.env("FX") || "auto", transitionDuration: 400 })
    }
    // MODE skips: the skip rules and the load bound. MODE glue: the screens
    // report covered by hand (there is no layer shell to draw them), then
    // the effect, the CLI's shown, the hold and the fade-out run for real.
    readonly property string mode: Quickshell.env("MODE")
    property int tick: 0
    Component.onCompleted: {
        if (mode === "glue") {
            shell.out("begin", svc.begin("/nonexistent/a.png", "/nonexistent/b.png"));
            // Two screens: one covered is not enough to restart swaybg
            // under, the other would show the gap.
            svc.screenCount = 2;
            svc.screenCovered();
            shell.out("oneOfTwo", svc.phase);
            svc.screenCovered();
            shell.out("covered", svc.phase);
        } else {
            shell.out("same", svc.begin("/a.png", "/a.png"));
            shell.out("relative", svc.begin("a.png", "/b.png"));
            shell.out("idleAfterSkip", svc.phase);
            shell.out("begin", svc.begin("/nonexistent/a.png", "/nonexistent/b.png"));
            shell.out("phase", svc.phase);
            shell.out("effect", svc.effect);
        }
        later.start();
    }
    // haseen:ui-timeout
    Timer {
        id: later
        interval: shell.mode === "glue" ? 700 : 2200
        onTriggered: {
            if (shell.mode !== "glue") {
                shell.out("after", svc.phase);
                shell.out("status", JSON.parse(svc.status()).last);
                Qt.quit();
                return;
            }
            // 0.7 s: the 0.4 s effect has ended and waits for shown; then
            // shown, and 0.8 s later the hold and the fade are over.
            shell.tick++;
            if (shell.tick === 1) {
                shell.out("played", svc.phase);
                svc.shown();
                shell.out("shown", svc.phase);
                later.interval = 800;
                later.start();
            } else {
                shell.out("end", svc.phase);
                shell.out("last", JSON.parse(svc.status()).last);
                Qt.quit();
            }
        }
    }
}
QML
    svc_run() {
        local run
        run="$(mktemp -d "$SANDBOX/run.XXXXXX")"
        chmod 700 "$run"
        setsid env XDG_RUNTIME_DIR="$run" QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME='' QT_QUICK_BACKEND=software \
            QT_NO_XDG_DESKTOP_PORTAL=1 FX="$1" MODE="${2:-skips}" timeout -k 5 30 "$QS_BIN" -p "$qsh" >"$SANDBOX/svc.out" 2>&1 &
        local group=$!
        STATUS=0
        wait "$group" || STATUS=$?
        kill -- -"$group" 2>/dev/null || true
        OUTPUT="$(cat "$SANDBOX/svc.out")"
    }
    s() { sed -n "s/^.*RESULT $1 //p" <<<"$OUTPUT"; }
    svc_run auto
    assert_eq "service: the same image is skipped" '"skip same image"' "$(s same)"
    assert_eq "service: a relative path is skipped" '"skip not a path"' "$(s relative)"
    assert_eq "service: a skip leaves it idle" '"idle"' "$(s idleAfterSkip)"
    assert_eq "service: a change starts loading" '"loading"' "$(s begin)"
    assert_eq "service: auto picks a drawn effect" "yes" "$([[ $(s effect) == '"contagion"' || $(s effect) == '"outline"' ]] && echo yes || echo no)"
    assert_eq "service: images that never draw end at the load bound" '"idle"' "$(s after)"
    assert_eq "service: and it says why" '"too slow to load"' "$(s status)"
    svc_run none
    assert_eq "service: transition none is a cut" '"skip off"' "$(s begin)"
    svc_run fade glue
    assert_eq "service: glue: a change loads" '"loading"' "$(s begin)"
    assert_eq "service: glue: one screen of two covered still loads" '"loading"' "$(s oneOfTwo)"
    assert_eq "service: glue: every screen covered starts the effect" '"playing"' "$(s covered)"
    assert_eq "service: glue: the effect ends and waits for swaybg" '"holding"' "$(s played)"
    assert_eq "service: glue: shown keeps it until the hold passes" '"holding"' "$(s shown)"
    assert_eq "service: glue: then it fades out and frees everything" '"idle"' "$(s end)"
    assert_eq "service: glue: and says it played" '"played"' "$(s last)"

    # The covers themselves: the plugin's real TransitionCover.qml (the old
    # and new pictures, the two-frame wait, the report to the service) in a
    # plain window per screen, standing in for TransitionWindows.qml's layer
    # surface, which needs a compositor. Real images, so each screen covers
    # by itself; then a second change while the first holds, which keeps the
    # cover and starts from the picture the first ended on; then shown.
    qsc="$SANDBOX/qsc"
    mkdir -p "$qsc/plugins/haseen.background" "$qsc/img"
    for module in Haseen Compat Ui Commons; do
        ln -s "$SHELL_DIR/$module" "$qsc/$module"
    done
    command cp -f "$BG"/* "$qsc/plugins/haseen.background/"
    # Large, so a decode takes long enough to see what a cover shows while
    # it runs.
    magick -size 6000x3375 xc:red "$qsc/img/old.png" 2>/dev/null &&
        magick -size 6000x3375 xc:blue "$qsc/img/new.png" &&
        magick -size 6000x3375 xc:lime "$qsc/img/third.png" || : >"$qsc/img/none"
    cat >"$qsc/plugins/haseen.background/TransitionWindows.qml" <<QML
import QtQuick
import QtQuick.Window
import Quickshell
Variants {
    id: covers
    property var service: null
    model: Quickshell.screens
    Window {
        id: win
        required property var modelData
        width: 320; height: 180; visible: true; color: "black"
        Component.onCompleted: console.warn("COVER made")
        Component.onDestruction: console.warn("COVER gone")
        TransitionCover {
            id: cover
            anchors.fill: parent
            service: covers.service
            onCoveringChanged: if (covering) {
                const g = covers.service.generation;
                console.warn("COVER covered frames " + frames + " generation " + g);
                grabToImage(r => r.saveToFile("$qsc/covered-" + g + ".png"));
            }
        }
        // What the screen shows just after a change during a change starts.
        Connections {
            target: covers.service
            function onGenerationChanged(): void {
                const g = covers.service.generation;
                Qt.callLater(() => cover.grabToImage(r => r.saveToFile("$qsc/gen-" + g + ".png")));
            }
        }
    }
}
QML
    cat >"$qsc/shell.qml" <<QML
import QtQuick
import Quickshell
import "plugins/haseen.background" as Background
ShellRoot {
    id: shell
    property int step: 0
    property var seen: []
    function out(k, v) { console.warn("RESULT " + k + " " + JSON.stringify(v)); }
    Background.Transition {
        id: svc
        pluginId: "haseen.background"
        settings: ({ transition: "fade", transitionDuration: 400 })
        onPhaseChanged: shell.advance(phase)
    }
    // Each step runs after the phase change that caused it has been
    // delivered, not inside it.
    function advance(p) {
        if (seen.length === 0 && p === "idle")
            return; // the binding's first value, before any change
        seen.push(p);
        Qt.callLater(() => act(p));
    }
    function act(p) {
        if (p === "holding" && step === 0) {
            step = 1;
            shell.out("again", svc.begin("$qsc/img/new.png", "$qsc/img/third.png"));
        } else if (p === "holding" && step === 1) {
            step = 2;
            svc.shown();
        } else if (p === "idle" && step === 2) {
            shell.out("seen", seen);
            shell.out("last", JSON.parse(svc.status()).last);
            done.start();
        }
    }
    Component.onCompleted: Qt.callLater(() => shell.out("begin", svc.begin("$qsc/img/old.png", "$qsc/img/new.png")))
    // Destruction is deferred to the event loop; then stop.
    // haseen:ui-timeout
    Timer { id: done; interval: 300; repeat: false; onTriggered: Qt.quit() }
    // haseen:ui-timeout
    Timer { interval: 8000; repeat: false; running: true; onTriggered: { shell.out("seen", shell.seen); Qt.quit(); } }
}
QML
    covers_run() {
        local run
        run="$(mktemp -d "$SANDBOX/run.XXXXXX")"
        chmod 700 "$run"
        setsid env XDG_RUNTIME_DIR="$run" QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME='' QT_QUICK_BACKEND=software \
            QT_NO_XDG_DESKTOP_PORTAL=1 timeout -k 5 30 "$QS_BIN" -p "$qsc" >"$SANDBOX/covers.out" 2>&1 &
        local group=$!
        wait "$group" || true
        kill -- -"$group" 2>/dev/null || true
        OUTPUT="$(cat "$SANDBOX/covers.out")"
    }
    if [[ -e $qsc/img/none ]]; then
        echo "  (magick missing: the covers were not run)" >&2
        [[ ${HASEEN_REQUIRE_ENGINE:-0} != 1 ]] || assert_eq "bg-transition: required magick prerequisite" available unavailable
    else
        covers_run
        assert_eq "covers: a change covers by itself, holds, a second change re-covers in the same cover, then shown ends it" \
            '["loading","playing","holding","loading","playing","holding","leaving","idle"]' "$(s seen)"
        assert_eq "covers: the second change starts loading" '"loading"' "$(s again)"
        assert_eq "covers: and ends played" '"played"' "$(s last)"
        assert_eq "covers: one cover per screen, made once and kept across both changes" 1 "$(grep -c 'COVER made' <<<"$OUTPUT")"
        assert_eq "covers: freed when the change ends" 1 "$(grep -c 'COVER gone' <<<"$OUTPUT")"
        assert_eq "covers: covered only two frames after the old image was ready, each change" \
            "COVER covered frames 2 generation 1
COVER covered frames 2 generation 2" "$(grep -o 'COVER covered.*' <<<"$OUTPUT")"
        rgb() { magick "$1" -crop 1x1+160+90 -depth 8 -format '%[fx:int(255*r)],%[fx:int(255*g)],%[fx:int(255*b)]' info: 2>/dev/null; }
        assert_eq "covers: covered means the old image is on screen" "255,0,0" "$(rgb "$qsc/covered-1.png")"
        assert_eq "covers: a second change opens on the picture the first ended on, not the first's old one" "0,0,255" "$(rgb "$qsc/gen-2.png")"
        assert_eq "covers: and is covered on it" "0,0,255" "$(rgb "$qsc/covered-2.png")"
    fi
else
    echo "  (no qs: the service was not run in the real engine)" >&2
fi

# --- drawing ----------------------------------------------------------------------
command -v magick >/dev/null || {
    echo "  (magick missing: the transition's pixels were not read back)" >&2
    [[ ${HASEEN_REQUIRE_ENGINE:-0} != 1 ]] || assert_eq "bg-transition: required magick prerequisite" available unavailable
    return 0
}
draw="$SANDBOX/draw"
mkdir -p "$draw"
# Old: red, 320x200 (a 16:10 picture on the 16:9 window), with a white block
# at x 100-219, y 60-139; covering the window it loses 10 px top and bottom,
# so the block spans y 50-129 on screen (stretched, it would start at 54).
# New: blue, 400x200, with a white block in the middle; covering the
# 320x180 window it is scaled by 0.9 and loses 20 px each side, so the block
# spans x 115-205.
magick -size 320x200 xc:red -fill white -draw "rectangle 100,60 219,139" "$draw/old.png"
magick -size 400x200 xc:blue -fill white -draw "rectangle 150,70 249,129" "$draw/new.png"
cat >"$draw/Draw.qml" <<EOF
import QtQuick
import QtQuick.Window
import "file://$BG"
Window {
    id: win
    width: 320; height: 180; visible: true; color: "black"
    // The last frame is the fade-out at its middle: progress 1, the cover
    // at half opacity (Transition.qml fadeOut).
    readonly property var stops: [0, 0.6, 1, 1]
    property int i: 0
    function out(k, v) { console.warn("RESULT " + k + " " + JSON.stringify(v)); }
    // Grabbed through a frame: a grab ignores its own root's opacity.
    Item {
        id: frame
        anchors.fill: parent
        TransitionView {
            id: v
            anchors.fill: parent
            oldSource: "file://$draw/old.png"
            newSource: "file://$draw/new.png"
            effect: Qt.application.arguments[Qt.application.arguments.length - 1]
            seed: 23.4
            pixelRatio: Screen.devicePixelRatio > 0 ? Screen.devicePixelRatio : 1
            glow: "orange"
            pencil: Qt.rgba(1, 1, 1, 0.75)
            onReadyChanged: if (ready) Qt.callLater(win.shot)
        }
    }
    function shot() {
        v.progress = stops[i];
        v.opacity = i === 3 ? 0.5 : 1;
        Qt.callLater(() => frame.grabToImage(r => {
            r.saveToFile("$draw/" + v.effect + "-" + i + ".png");
            i++;
            if (i < stops.length) { win.shot(); return; }
            win.out("drawn", { api: GraphicsInfo.api, software: v.software, shader: v.useShader, loaded: v.shaderLoaded });
            Qt.quit();
        }));
    }
}
EOF
# pixel FILE X Y SCALE -> "r,g,b"; share FILE COLOUR -> fraction of pixels
# within 12 % of COLOUR.
pixel() {
    local x y
    x=$(awk -v s="$4" -v v="$2" 'BEGIN { printf "%d", v * s }')
    y=$(awk -v s="$4" -v v="$3" 'BEGIN { printf "%d", v * s }')
    magick "$1" -crop "1x1+$x+$y" -depth 8 txt:- | sed -n 's/^0,0: *(\([0-9]*\),\([0-9]*\),\([0-9]*\).*/\1,\2,\3/p'
}
share() {
    magick "$1" -alpha off -fuzz 12% -fill white -opaque "$2" -fill black +opaque white -colorspace gray -format '%[fx:mean]' info:
}
near() { # near "r,g,b" "R,G,B" -> yes when every channel is within 40
    awk -v a="$1" -v b="$2" 'BEGIN { split(a, p, ","); split(b, q, ","); ok = "yes";
        for (i = 1; i <= 3; i++) if (p[i] - q[i] > 40 || q[i] - p[i] > 40) ok = "no"; print ok }'
}
draw_run() { # draw_run EFFECT SCALE BACKEND [DISPLAY]
    rm -f "$draw/$1"-[0-9].png
    draw_out="$(cd "$draw" && env ${4:+DISPLAY="$4"} QT_SCALE_FACTOR="$2" QT_QUICK_BACKEND="$3" QSG_RHI_BACKEND=opengl \
        QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 timeout 30 "$QML_BIN" Draw.qml -- "$1" 2>&1)"
}
# The three frames: progress 0 is the old image, 1 the new one with the
# block where swaybg's fill puts it; MID is the middle frame's file.
check_frames() { # check_frames EFFECT SCALE LABEL
    local f0="$draw/$1-0.png" f1="$draw/$1-1.png" f2="$draw/$1-2.png" f3="$draw/$1-3.png" at=" ($3)"
    assert_eq "t=0 is the old image, centre$at" yes "$(near "$(pixel "$f0" 160 90 "$2")" 255,255,255)"
    assert_eq "t=0 is the old image, corner$at" yes "$(near "$(pixel "$f0" 10 10 "$2")" 255,0,0)"
    assert_eq "t=0: inside the old block's top edge$at" yes "$(near "$(pixel "$f0" 160 52 "$2")" 255,255,255)"
    assert_eq "t=0: above it, as swaybg's fill crops the old image$at" yes "$(near "$(pixel "$f0" 160 47 "$2")" 255,0,0)"
    assert_eq "t=0: inside the old block's left edge$at" yes "$(near "$(pixel "$f0" 103 90 "$2")" 255,255,255)"
    assert_eq "t=0: left of it$at" yes "$(near "$(pixel "$f0" 96 90 "$2")" 255,0,0)"
    assert_eq "t=1 is the new image: the block in the middle$at" yes "$(near "$(pixel "$f2" 160 90 "$2")" 255,255,255)"
    assert_eq "t=1: inside the block's left edge$at" yes "$(near "$(pixel "$f2" 119 90 "$2")" 255,255,255)"
    assert_eq "t=1: outside it, as swaybg's fill crops$at" yes "$(near "$(pixel "$f2" 111 90 "$2")" 0,0,255)"
    assert_eq "t=1: the corner$at" yes "$(near "$(pixel "$f2" 10 10 "$2")" 0,0,255)"
    assert_eq "fading out at t=1 shows only the new image, no old one through it$at" yes "$(near "$(pixel "$f3" 10 10 "$2")" 0,0,255)"
    MID="$f1"
}
for scale in 1 1.25; do
    draw_run contagion "$scale" software
    assert_eq "software at $scale: no ShaderEffect is created" \
        '{"api":1,"software":true,"shader":false,"loaded":false}' "$(sed -n 's/^.*RESULT drawn //p' <<<"$draw_out")"
    check_frames contagion "$scale" "software crossfade, scale $scale"
    m="$(pixel "$MID" 40 90 "$scale")"
    assert_eq "software at $scale: mid (0.6) mixes the two" yes \
        "$(awk -v p="$m" 'BEGIN { split(p, c, ","); print (c[1] > 90 && c[1] < 170 && c[3] > 90 && c[3] < 170) ? "yes" : "no" }')"
done

# The shader needs a GL context: offscreen, Qt makes one through an X
# display. The sandbox has none, so this runs only when HASEEN_GL_DISPLAY
# names one (`HASEEN_GL_DISPLAY=:0 tests/run.sh tests/test-bg-transition.sh`).
if [[ -z ${HASEEN_GL_DISPLAY:-} ]]; then
    echo "  (no HASEEN_GL_DISPLAY: the shader effects were not drawn)" >&2
    return 0
fi
# thin FILE -> the share of pixels in old-image (red) runs under 3 px wide.
# Cells are 4 or 5 device pixels, so a correct frame has none; the outline
# once left a 1 px grid of the old image between cells at scale 1.25 (5 px
# cells), where 2x2 pixel quads across a cell edge picked a blurrier mip
# level (2.2 % of the 0.6 frame then, 0 since textureLod).
thin() {
    magick "$1" -alpha off -fuzz 12% -fill white -opaque red -fill black +opaque white -colorspace gray \
        \( +clone -morphology Open Rectangle:3x1 \) -compose difference -composite -format '%[fx:mean]' info:
}
for scale in 1 1.25; do
    for fx in contagion outline; do
        draw_run "$fx" "$scale" rhi "$HASEEN_GL_DISPLAY"
        drawn="$(sed -n 's/^.*RESULT drawn //p' <<<"$draw_out")"
        if [[ $(jq -r .shader <<<"${drawn:-{\}}" 2>/dev/null) != true ]]; then
            echo "  (no GL context on $HASEEN_GL_DISPLAY: $fx was not drawn)" >&2
            continue
        fi
        at="rhi $fx, scale $scale"
        assert_eq "$at: draws with the shader" "true" "$(jq -r .loaded <<<"$drawn")"
        check_frames "$fx" "$scale" "$at"
        red="$(share "$MID" red)"
        newer="$(share "$MID" blue)"
        assert_eq "$at: mid still shows the old image" yes "$(awk -v v="$red" 'BEGIN { print (v > 0.05) ? "yes" : "no" }')"
        assert_eq "$at: mid already shows the new one" yes "$(awk -v v="$newer" 'BEGIN { print (v > 0.05) ? "yes" : "no" }')"
        assert_eq "$at: no grid of the old image between cells" yes "$(awk -v v="$(thin "$MID")" 'BEGIN { print (v < 0.002) ? "yes" : "no" }')"
    done
done

# A second change in the same shell (plan 161, found live on luna): Qt keeps
# the compiled shader by URL, and the next change's ShaderEffect draws from
# that cache but reports Uncompiled for good. A cover that waited for Compiled
# never reported ready, and every change after the first was cut to the new
# image. Two covers, one after the other, each in a new window as the service
# makes them: both must become ready and draw the new image at progress 1.
cat >"$draw/Twice.qml" <<EOF
import QtQuick
import QtQuick.Window
import "file://$BG"
Item {
    id: root
    property int made: 0
    property var readyAt: []
    function out(k, v) { console.warn("RESULT " + k + " " + JSON.stringify(v)); }
    Component {
        id: cover
        Window {
            id: w
            width: 320; height: 180; visible: true; color: "black"
            TransitionView {
                anchors.fill: parent
                oldSource: "file://$draw/old.png"
                newSource: "file://$draw/new.png"
                effect: "contagion"
                onReadyChanged: if (ready) {
                    progress = 1;
                    const shader = useShader;
                    Qt.callLater(() => grabToImage(r => {
                        r.saveToFile("$draw/twice-" + root.made + ".png");
                        root.readyAt.push(shader);
                        w.destroy();
                        root.next();
                    }));
                }
            }
        }
    }
    function next() {
        if (made === 2) { out("twice", readyAt); Qt.quit(); return; }
        made++;
        Qt.callLater(() => cover.createObject(root));
    }
    Component.onCompleted: next()
    // haseen:ui-timeout
    Timer { interval: 5000; repeat: false; running: true; onTriggered: { root.out("twice", root.readyAt); Qt.quit(); } }
}
EOF
twice="$(cd "$draw" && env DISPLAY="$HASEEN_GL_DISPLAY" QT_QUICK_BACKEND=rhi QSG_RHI_BACKEND=opengl \
    QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 timeout 30 "$QML_BIN" Twice.qml 2>&1 | sed -n 's/^.*RESULT twice //p')"
if [[ $twice == "[]" || -z $twice ]]; then
    echo "  (no GL context on $HASEEN_GL_DISPLAY: the second cover was not drawn)" >&2
else
    assert_eq "rhi: a second change in the same shell is ready too, with the shader" "[true,true]" "$twice"
    for n in 1 2; do
        assert_eq "rhi: change $n in the same shell draws the new image at t=1" yes \
            "$(near "$(pixel "$draw/twice-$n.png" 160 90 1)" 255,255,255)"
    done
fi
