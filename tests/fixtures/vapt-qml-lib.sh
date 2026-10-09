# shellcheck shell=bash
# Match the complete desktop-engine qualification used by battery/media tests.
# Probe only framework imports, never production components: their failures must fail tests.
vapt_qml_available() {
    local label=$1 runner=${2:-} probe imports='' diagnostic
    local -a missing=()
    VAPT_QML_READY=false
    QS_BIN=${QS_BIN:-/usr/bin/qs}
    QML_BIN=${QML_BIN:-/usr/lib/qt6/bin/qml}
    [[ -x $QS_BIN ]] || missing+=("qs ($QS_BIN)")
    command -v dbus-daemon >/dev/null || missing+=(dbus-daemon)
    command -v dbus-run-session >/dev/null || missing+=(dbus-run-session)
    python3 -c 'import dbus, gi' 2>/dev/null || missing+=(python3-dbus/python3-gobject)
    [[ -x $QML_BIN ]] || missing+=("qml ($QML_BIN)")
    if [[ -n $runner ]]; then
        [[ -x $runner ]] || missing+=("qmltestrunner ($runner)")
        imports='import QtTest'
    fi
    if ((${#missing[@]})); then
        printf '  skip: %s not run; missing %s\n' "$label" "${missing[*]}" >&2
        return 1
    fi
    probe="$SANDBOX/vapt-framework-probe.qml"
    cat >"$probe" <<EOF
import QtQuick
import QtQuick.Controls
$imports
Window {
    visible: true; width: 64; height: 64
    Button { text: "Framework probe" }
    Component.onCompleted: { console.warn("VAPT-QML-READY"); Qt.quit(); }
}
EOF
    if ! diagnostic=$(QT_QPA_PLATFORM=offscreen QT_QUICK_CONTROLS_STYLE=Basic QT_FORCE_STDERR_LOGGING=1 NO_AT_BRIDGE=1 timeout 10 "$QML_BIN" "$probe" 2>&1) || [[ $diagnostic != *VAPT-QML-READY* ]]; then
        printf '  skip: %s not run; QtQuick/Controls%s offscreen prerequisite unavailable\n%s\n' "$label" "${runner:+/QtTest}" "$diagnostic" >&2
        return 1
    fi
    VAPT_QML_READY=true
}
