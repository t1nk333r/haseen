# shellcheck shell=bash
# Probe only framework imports, never production components: their failures must fail tests.
vapt_qml_skip() {
    printf '  skip: %s not run; %s\n' "$1" "$2" >&2
    if [[ ${HASEEN_REQUIRE_ENGINE:-0} == 1 ]]; then
        assert_eq "$1: required engine prerequisite" available unavailable
    fi
}
vapt_qml_available() {
    local label=$1 runner=${2:-} engine=${3:-qml} probe imports='' diagnostic opening='' closing='' quit='Qt.quit()'
    local -a command=()
    local -a missing=()
    VAPT_QML_READY=false
    QS_BIN=${QS_BIN:-/usr/bin/qs}
    QML_BIN=${QML_BIN:-/usr/lib/qt6/bin/qml}
    if [[ $engine == qs ]]; then
        [[ -x $QS_BIN ]] || missing+=("qs ($QS_BIN)")
        command -v dbus-run-session >/dev/null || missing+=(dbus-run-session)
        command=(dbus-run-session --config-file="$REPO/tools/smoke-session.conf" -- "$QS_BIN" -p)
        imports='import Quickshell'
        opening='ShellRoot {'
        closing='}'
        quit='Qt.callLater(Qt.quit)'
    else
        [[ -x $QML_BIN ]] || missing+=("qml ($QML_BIN)")
        command=("$QML_BIN")
    fi
    if [[ -n $runner ]]; then
        [[ -x $runner ]] || missing+=("qmltestrunner ($runner)")
        imports='import QtTest'
    fi
    if ((${#missing[@]})); then
        vapt_qml_skip "$label" "missing ${missing[*]}"
        return 1
    fi
    probe="$SANDBOX/vapt-framework-probe.qml"
    cat >"$probe" <<EOF
import QtQuick
import QtQuick.Controls
$imports
$opening
Window {
    visible: true; width: 64; height: 64
    Button { text: "Framework probe" }
    Component.onCompleted: { console.warn("VAPT-QML-READY"); $quit; }
}
$closing
EOF
    if ! diagnostic=$(QT_QPA_PLATFORM=offscreen QT_QUICK_CONTROLS_STYLE=Basic QT_FORCE_STDERR_LOGGING=1 NO_AT_BRIDGE=1 timeout 10 "${command[@]}" "$probe" 2>&1) || [[ $diagnostic != *VAPT-QML-READY* ]]; then
        vapt_qml_skip "$label" "QtQuick/Controls${runner:+/QtTest} offscreen prerequisite unavailable"
        printf '%s\n' "$diagnostic" >&2
        return 1
    fi
    VAPT_QML_READY=true
    printf '  engine: %s executing\n' "$label"
}
