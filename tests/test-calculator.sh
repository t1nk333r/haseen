# shellcheck shell=bash
# The launcher's calculator: `=expression`. Calc.js runs under the real Qt JS
# engine; it must compute what a person expects and never run anything but
# arithmetic.

PLUGIN="$HASEEN_PATH/shell/plugins/haseen.calculator"

sandbox calculator
capture haseen plugin validate haseen.calculator
assert_status "calculator validates" 0 "$STATUS"
assert_eq "it answers the = prefix in the launcher" "launcher-provider" "$(jq -r '.kinds | join(" ")' "$PLUGIN/manifest.json")"

QML=/usr/lib/qt6/bin/qml
H="$SANDBOX/js"
mkdir -p "$H"
cat >"$H/Units.qml" <<EOF
import QtQuick
import "file://$PLUGIN/Calc.js" as C

Window {
    property int failures: 0

    function eq(name, expected, actual) {
        const e = JSON.stringify(expected), a = JSON.stringify(actual);
        if (e === a)
            console.warn("UNIT-PASS " + name);
        else {
            failures++;
            console.warn("UNIT-FAIL " + name + " expected " + e + " got " + a);
        }
    }
    function val(text) {
        const r = C.evaluate(text);
        return r.ok ? C.format(r.value) : "error";
    }

    Component.onCompleted: {
        try {
            eq("precedence", "26", val("2+3*8"));
            eq("parentheses", "40", val("(2+3)*8"));
            eq("power is right-associative", "512", val("2^3^2"));
            eq("unary minus binds tighter than +, looser than ^", "-4", val("-2^2"));
            eq("division gives decimals", "0.333333333333", val("1/3"));
            eq("floating noise is trimmed", "0.3", val("0.1+0.2"));
            eq("percent alone", "0.5", val("50%"));
            eq("adding a percentage of the left side", "220", val("200 + 10%"));
            eq("subtracting a percentage", "180", val("200 - 10%"));
            eq("percent of a product", "30", val("200 * 15%"));
            eq("modulo", "1", val("10 % 3"));
            eq("x as times between numbers", "12", val("3x4"));
            eq("× and ÷", "6", val("12 × 2 ÷ 4"));
            eq("functions", "1.41421356237", val("sqrt(2)"));
            eq("max inside a word is not x", "7", val("max(3, 7, 5)"));
            eq("log is base 10, ln natural", ["2", "1"], [val("log(100)"), val("ln(e)")]);
            eq("pi", "3.14159265359", val("pi"));
            eq("factorial", "120", val("5!"));
            eq("hex and underscores", ["31", "1000000"], [val("0x1f"), val("1_000_000")]);
            eq("scientific notation", "1500", val("1.5e3"));
            eq("division by zero is infinity", "∞", val("1/0"));
            eq("an incomplete expression is an error, not a crash", "error", val("2+"));
            eq("unknown names are refused", "error", val("foo(1)"));
            eq("no code runs: property access is refused", "error", val("constructor.constructor"));
            eq("no code runs: strings are refused", "error", val("'a'"));
            eq("empty input is not a result", false, C.evaluate("  ").ok);
        } catch (e) {
            failures++;
            console.warn("UNIT-FAIL exception " + e);
        }
        Qt.exit(failures > 0 ? 1 : 0);
    }
}
EOF
if [[ -x $QML ]]; then
    set +e
    units="$(QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 timeout 60 "$QML" "$H/Units.qml" 2>&1)"
    set -e
    while read -r line; do
        _fail "js: ${line#*UNIT-FAIL }"
    done < <(grep 'UNIT-FAIL' <<<"$units" || true)
    assert_eq "calculator unit count" "26" "$(grep -c 'UNIT-PASS' <<<"$units")"
else
    _fail "qml runner missing: $QML"
fi
