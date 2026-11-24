# shellcheck shell=bash
# haseen:covers share/haseen/shell/plugins/haseen.session/**
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# The haseen.session panel in the real Quickshell engine (plan 197):
#   - Log out, Suspend, Reboot and Shut down run `haseen system`, which closes
#     the apps first and brings the boot splash up to date, as the menu does;
#     a boot entry's row reboots through it too, after pkexec's BootNext;
#   - settings.bootEntries takes the boolean and a JSON list from a
#     hand-edited shell.json, and the text the Settings panel saves for its
#     declared string type ("false", "0000, kali").
# systemd-run (Apps.launch's scope) and every other command only log their
# argv, so nothing here reboots or logs anyone out.

QS_BIN=${QS_BIN:-/usr/bin/qs}
if [[ ! -x $QS_BIN ]]; then
    echo "  skip: qs missing; the session panel not loaded" >&2
else
    sandbox session-panel
    harness="$SANDBOX/shell"
    mkdir -p "$harness"
    for module in Haseen Compat Ui Commons; do
        ln -s "$HASEEN_PATH/shell/$module" "$harness/$module"
    done
    ln -s "$HASEEN_PATH/shell/plugins" "$harness/plugins"

    # A UEFI machine running Limine (0001) beside Windows and kali, with an
    # inactive Setup entry, as tests/test-boot.sh lists it.
    sysroot="$SANDBOX/sysroot"
    mkdir -p "$sysroot/sys/firmware/efi"
    printf '%s\n' "BootCurrent: 0001" \
        "Boot0000* Windows Boot Manager	HD(1,GPT,5240f4f3,0x800,0x32000)" \
        "Boot0001* Limine	HD(1,GPT,b0ab8fe1,0x800,0x400000)" \
        "Boot0002* kali	HD(1,GPT,b8a63faa,0x800,0x1e8000)" \
        "Boot0010  Setup	FvFile(721c8b66)" \
        "Boot0011* Windows Boot Manager	HD(2,GPT,aaaa,0x800,0x1000)" >"$SANDBOX/efibootmgr.out"
    LOG="$SANDBOX/argv.log"
    stub efibootmgr "echo efibootmgr >>'$LOG'; cat '$SANDBOX/efibootmgr.out'"
    # Each stub logs "name|arg|arg…" in one write and exits 0.
    for name in systemd-run uwsm-app systemctl pkexec loginctl hyprctl; do
        stub "$name" "l='$name'; for a; do l=\"\$l|\$a\"; done; printf '%s\n' \"\$l\" >>'$LOG'"
    done

    cat >"$harness/shell.qml" <<'QML'
import QtQuick
import Quickshell
import qs.Haseen
import "plugins/haseen.session" as Session

ShellRoot {
    id: probe

    // settings.bootEntries as each spelling reaches the panel.
    readonly property var cases: ({
            unset: {},
            auto: { bootEntries: "auto" },
            boolFalse: { bootEntries: false },
            textFalse: { bootEntries: "false" },
            textNone: { bootEntries: "None" },
            oneId: { bootEntries: "0000" },
            idAndLabel: { bootEntries: "kali, 0011" },
            jsonList: { bootEntries: ["0000"] }
        })
    property var panels: ({})

    Component {
        id: panelComponent

        Session.Panel {
            pluginId: "haseen.session"
        }
    }

    Component.onCompleted: {
        const made = {};
        for (const name of Object.keys(cases))
            made[name] = panelComponent.createObject(null, {
                settings: Object.assign({ confirm: false }, cases[name])
            });
        panels = made;
    }

    Timer {
        interval: 2500
        running: true
        onTriggered: {
            const boot = {};
            for (const name of Object.keys(probe.panels))
                boot[name] = probe.panels[name].bootActions.map(a => a.id.slice(5));
            const p = probe.panels.unset;
            for (const id of ["lock", "logout", "suspend", "reboot", "poweroff", "boot:0000"])
                p.run(id);
            console.warn("RESULT " + JSON.stringify({ boot: boot }));
            quit.start();
        }
    }

    // Time for the detached runs to log.
    Timer {
        id: quit

        interval: 1500
        onTriggered: Qt.quit()
    }
}
QML
    capture env QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QT_NO_XDG_DESKTOP_PORTAL=1 \
        HASEEN_SYSROOT="$sysroot" timeout 60 "$QS_BIN" -p "$harness"
    assert_status "the session panels run in the real engine" 0 "$STATUS"
    RESULT="$(sed -n 's/^.*RESULT //p' <<<"$OUTPUT" | head -1)"
    ARGV="$(cat "$LOG" 2>/dev/null || true)"
    b() { jq -c ".boot.$1" <<<"${RESULT:-null}"; }

    # --- which boot entries show ---------------------------------------------
    assert_eq "unset is auto: every other active entry" '["0000","0002","0011"]' "$(b unset)"
    assert_eq "\"auto\": every other active entry" '["0000","0002","0011"]' "$(b auto)"
    assert_eq "false hides them all" '[]' "$(b boolFalse)"
    assert_eq "the text \"false\" (the Settings panel's string) hides them all" '[]' "$(b textFalse)"
    assert_eq "the text \"none\" hides them all" '[]' "$(b textNone)"
    assert_eq "one id as text shows that entry" '["0000"]' "$(b oneId)"
    assert_eq "a comma-separated id and label show those entries" '["0002","0011"]' "$(b idAndLabel)"
    assert_eq "a JSON list still works" '["0000"]' "$(b jsonList)"
    assert_eq "hidden entries read no firmware: five lists of eight panels" "5" "$(grep -cx efibootmgr <<<"$ARGV")"

    # --- the rows run haseen system ------------------------------------------
    cli="$HASEEN_PATH/../../bin/haseen"
    for verb in logout suspend reboot shutdown; do
        assert_contains "$verb runs haseen system $verb in its own scope" "$ARGV" \
            "systemd-run|--user|--scope|--slice=app-graphical.slice|--collect|--quiet|--unit=app-haseen-haseen-"
        assert_contains "$verb: the argv is haseen system $verb" "$ARGV" "|--|$cli|system|$verb"
    done
    assert_contains "a boot entry sets BootNext through pkexec, then reboots through haseen system" "$ARGV" \
        "|--|bash|-c|pkexec \"\${@:2}\" && exec \"\$1\" system reboot|haseen-session|$cli|$cli-boot-next|0000|--label|Windows Boot Manager|--yes"
    assert_contains "lock without a lock role falls back to loginctl" "$ARGV" "loginctl|lock-session"
    assert_not_contains "no row calls systemctl itself" "$ARGV" "systemctl|"
    assert_not_contains "no row calls Hyprland's exit dispatcher" "$ARGV" "hyprctl|"
fi
