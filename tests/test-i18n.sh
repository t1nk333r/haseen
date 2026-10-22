# shellcheck shell=bash
# haseen:covers tools/i18n.py share/haseen/i18n/** share/haseen/lib/i18n.sh bin/haseen-language
# haseen:covers share/haseen/shell/** share/haseen/default/menu.jsonc share/haseen/default/catalog.json
# haseen:covers share/haseen/default/hypr/*.lua share/haseen/lib/{gestures,settings}.sh bin/**
# haseen:covers share/haseen/layers/base/packages.txt share/haseen/themed/fonts.conf.tpl
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# The interface language (plan 109): the catalogs are what the code says and
# every Arabic string is there with its placeholders (tools/i18n.py check);
# the bash side for
# notifications; `haseen language`; and, in the real Quickshell engine, the
# I18n singleton (switching live, Arabic plurals, dates, the menu catalog),
# the compat host's Commons.I18n and Commons.Translations, a mirrored
# TrackBar and the menu's applyTranslations.

I18N="$HASEEN_PATH/i18n"

# --- catalogs ------------------------------------------------------------------
sandbox i18n
capture python3 "$REPO/tools/i18n.py" check
assert_status "catalogs: fresh and complete" 0 "$STATUS"
[[ $STATUS == 0 ]] || head -40 <<<"$OUTPUT" >&2
assert_eq "registry: English and Arabic, Arabic right to left" "en ltr|ar rtl" \
    "$(jq -r 'to_entries | map("\(.key) \(.value.direction)") | join("|")' "$I18N/locales.json")"
assert_eq "Arabic dates: ar_AE, Western digits" "ar_AE 0" "$(jq -r '.ar | "\(.formatLocale) \(.zeroDigit)"' "$I18N/locales.json")"
assert_eq "Arabic provenance: machine translation, said so" "machine" "$(jq -r .translation "$I18N/ar/provenance.json")"
assert_contains "the provenance names the translator" "$(jq -r .translator "$I18N/ar/provenance.json")" "Claude"
assert_eq "every menu row has its Arabic label" \
    "$(jq 'length' "$I18N/en/menu.json")" "$(jq '[.[] | select(.label)] | length' "$I18N/ar/menu.json")"
assert_eq "Arabic plural entries carry all six forms" "true" \
    "$(jq '[.[] | objects | keys == ["few","many","one","other","two","zero"]] | all' "$I18N/ar/shell.json" "$I18N/ar/notify.json" | sort -u | paste -sd' ')"

# The checker itself refuses what it should, on a tree of its own.
fake="$SANDBOX/tree"
mkdir -p "$fake/share/haseen/shell/plugins/haseen.x" "$fake/share/haseen/default" "$fake/share/haseen/i18n/en" "$fake/share/haseen/i18n/ar"
cp "$I18N/locales.json" "$fake/share/haseen/i18n/"
cp "$I18N/ar/provenance.json" "$fake/share/haseen/i18n/ar/"
printf '%s\n' '{"a": {"label": "A", "description": "First"}}' >"$fake/share/haseen/default/menu.jsonc"
printf '%s\n' 'import QtQuick' 'Text { text: I18n.tr("Bar edge") }' >"$fake/share/haseen/shell/plugins/haseen.x/Panel.qml"
i18n_fake() { capture python3 "$REPO/tools/i18n.py" --root "$fake" "$@"; }
i18n_fake extract
assert_status "extract: a tree of its own" 0 "$STATUS"
assert_eq "extract: the English catalogs" '{"Bar edge":"Bar edge"}|{"a":{"description":"First","label":"A"}}|{}' \
    "$(jq -cS . "$fake/share/haseen/i18n/en/shell.json")|$(jq -cS . "$fake/share/haseen/i18n/en/menu.json")|$(jq -cS . "$fake/share/haseen/i18n/en/notify.json")"
printf '%s\n' '{"Bar edge": "حافة %1"}' >"$fake/share/haseen/i18n/ar/shell.json"
printf '%s\n' '{"a": {"label": "أ"}}' >"$fake/share/haseen/i18n/ar/menu.json"
printf '%s\n' '{}' >"$fake/share/haseen/i18n/ar/notify.json"
i18n_fake check
assert_status "check: refuses a broken catalog" 1 "$STATUS"
assert_contains "check: a placeholder the English lacks" "$OUTPUT" "'Bar edge': placeholders ['%1']"
assert_contains "check: a menu field left untranslated" "$OUTPUT" "'a.description' has no translation"
printf '%s\n' '{"Bar edge": "حافة الشريط"}' >"$fake/share/haseen/i18n/ar/shell.json"
printf '%s\n' '{"a": {"label": "أ", "description": "الأول"}}' >"$fake/share/haseen/i18n/ar/menu.json"
i18n_fake check
assert_status "check: passes once complete" 0 "$STATUS"
printf '%s\n' 'function N_(t) { return t; }' 'function f(n) { return n ? N_("A new string") : ""; }' >"$fake/share/haseen/shell/plugins/haseen.x/Model.js"
i18n_fake check
assert_contains "check: a new marked string makes the English stale" "$OUTPUT" "en/shell.json is not what the code says"
i18n_fake extract
i18n_fake check
assert_contains "check: a string with no Arabic is named" "$OUTPUT" "'A new string' is not translated"
jq '. + {"A new string": "سلسلة جديدة", "Stale": "قديم"}' "$fake/share/haseen/i18n/ar/shell.json" >"$fake/x" && mv "$fake/x" "$fake/share/haseen/i18n/ar/shell.json"
i18n_fake check
assert_contains "check: a translation of nothing is stale" "$OUTPUT" "'Stale' is not in the English catalog (stale)"
printf '%s\n' 'import QtQuick' 'Text { text: I18n.tr(`x ${y}`) }' >"$fake/share/haseen/shell/plugins/haseen.x/Panel.qml"
i18n_fake extract
assert_contains "extract: a template literal cannot be collected" "$OUTPUT" "template literal"
rm -rf "$fake"

# --- fonts -------------------------------------------------------------------------
# Inter and the Nerd fonts carry no Arabic: the base layer's noto-fonts does
# (Noto Sans Arabic, Naskh, Kufi and their UI cuts), and the theme's
# fontconfig lists it after the theme's family (plan 047).
assert_contains "base installs noto-fonts" "$(grep -E '^noto-fonts\b' "$HASEEN_PATH/layers/base/packages.txt")" "noto-fonts"
assert_contains "sans falls back to Noto Sans Arabic" "$(cat "$HASEEN_PATH/themed/fonts.conf.tpl")" "<string>Noto Sans Arabic</string>"

# --- bash: notifications ----------------------------------------------------------
cfg="$XDG_CONFIG_HOME/haseen"
mkdir -p "$cfg"
i18n_run() { HASEEN_USER_CONFIG="$cfg" bash -c 'source "$HASEEN_PATH/lib/common.sh"; source "$HASEEN_PATH/lib/i18n.sh"; '"$1"; }
assert_eq "bash: English without a language file" "Reminder set for 10:00 %2|3 reminders|1 reminder|en" \
    "$(i18n_run 'printf "%s|" "$(i18n "Reminder set for %1" "10:00 %2")" "$(i18n_n "%1 reminder" "%1 reminders" 3)" "$(i18n_n "%1 reminder" "%1 reminders" 1)"; i18n_language')"
echo ar >"$cfg/language"
assert_eq "bash: Arabic, %n filled once" "ضُبط التذكير على 10:00 %2|ar" \
    "$(i18n_run 'printf "%s|" "$(i18n "Reminder set for %1" "10:00 %2")"; i18n_language')"
assert_eq "bash: Arabic plural forms (0 1 2 3 11 100)" \
    "لا توجد ترحيلات معلّقة.|انقر لتشغيل ترحيل معلّق واحد.|انقر لتشغيل ترحيلين معلّقين.|انقر لتشغيل 3 ترحيلات معلّقة.|انقر لتشغيل 11 ترحيلًا معلّقًا.|انقر لتشغيل 100 ترحيل معلّق." \
    "$(i18n_run 'for n in 0 1 2 3 11 100; do i18n_n "Click to run %1 pending migration." "Click to run %1 pending migrations." "$n"; done | paste -sd"|"')"
assert_eq "bash: a string the catalog lacks stays English" "Not in any catalog x" \
    "$(i18n_run 'i18n "Not in any catalog %1" x')"
echo xx >"$cfg/language"
assert_eq "bash: an unknown code is English" "en" "$(i18n_run i18n_language)"
# A command's notification in Arabic, its terminal line in English.
echo ar >"$cfg/language"
stub hyprctl 'exit 0'
stub notify-send 'printf "%s\n" "$@" >>"$HOME/notified"'
capture haseen toggle gaps on
assert_status "toggle gaps on" 0 "$STATUS"
assert_contains "the terminal line stays English" "$OUTPUT" "No-gaps mode"
assert_contains "the notification is Arabic" "$(cat "$HOME/notified")" "وضع إلغاء الفجوات مُشغّل"
rm -f "$cfg/language" "$HOME/notified"

# --- haseen language ----------------------------------------------------------------
capture haseen language
assert_status "language: status by default" 0 "$STATUS"
assert_contains "language: English by default" "$OUTPUT" "language: en (English, left to right)"
capture haseen language list
assert_eq "language: list" "en	English	English	ltr
ar	العربية	Arabic	rtl" "$OUTPUT"
capture haseen language ar --dry-run
assert_status "language ar --dry-run" 0 "$STATUS"
assert_contains "language ar --dry-run: plans the write" "$OUTPUT" "DRYRUN: write $cfg/language"
assert_dry_pure "language ar --dry-run" "$OUTPUT"
assert_eq "language ar --dry-run: writes nothing" "absent" "$([[ -e $cfg/language ]] && echo present || echo absent)"
capture haseen language ar
assert_status "language ar" 0 "$STATUS"
assert_eq "language ar: the file holds the code" "ar" "$(cat "$cfg/language")"
assert_contains "language ar: says so in English" "$OUTPUT" "Interface language: Arabic"
assert_contains "language ar: notifies in Arabic" "$(cat "$HOME/notified")" "لغة الواجهة: العربية"
capture haseen language status
assert_contains "status: Arabic, right to left" "$OUTPUT" "language: ar (العربية, right to left)"
assert_contains "status: machine translation and its review count" "$OUTPUT" "translation: machine, by Claude"
assert_contains "status: reviewed count" "$OUTPUT" "0 of "
LANG=en_US.UTF-8 capture haseen language status
assert_contains "status: proposes the session locale, does not set it" "$OUTPUT" "haseen does not do this for you"
capture haseen language fr
assert_status "language fr: refused" 1 "$STATUS"
assert_contains "language fr: points at the list" "$OUTPUT" "haseen language list"
capture haseen language ar en
assert_status "language: one argument" 2 "$STATUS"
capture haseen settings list
assert_contains "settings index: the language row" "$OUTPUT" "language"
capture haseen language en
assert_status "language en" 0 "$STATUS"
assert_eq "language en: English is no file" "absent" "$([[ -e $cfg/language ]] && echo present || echo absent)"
rm -f "$HOME/notified"

# --- statics --------------------------------------------------------------------------
assert_contains "panels mirror in a right-to-left language" "$(cat "$HASEEN_PATH/shell/PanelPopup.qml")" \
    "LayoutMirroring.enabled: I18n.rightToLeft && (Plugins.registry[popup.pluginId] || {}).compat === \"\""
assert_eq "the bar is never mirrored" "" "$(grep -l 'LayoutMirroring' "$HASEEN_PATH/shell/Bar.qml" "$HASEEN_PATH/shell/BarSection.qml" || true)"
assert_contains "the shell's run creates the config dir the language watch needs" \
    "$(cat "$REPO/bin/haseen-shell-run")" 'mkdir -p -- "$HASEEN_USER_STATE" "$HASEEN_USER_CONFIG"'
assert_eq "compat exports I18n and Translations" "singleton I18n 1.0 I18n.qml|Translations 1.0 Translations.qml" \
    "$(grep -E '^(singleton I18n|Translations) ' "$HASEEN_PATH/shell/Compat/Omarchy/Commons/qmldir" | paste -sd'|')"

# --- the real engine ------------------------------------------------------------------
QS_BIN=${QS_BIN:-/usr/bin/qs}
if [[ ! -x $QS_BIN ]] || ! command -v dbus-run-session >/dev/null; then
    echo "  skip: qs or dbus-run-session missing; the I18n singleton was not run" >&2
    [[ ${HASEEN_REQUIRE_ENGINE:-} != 1 ]] || _fail "engine required (HASEEN_REQUIRE_ENGINE=1) but qs is missing"
else
    sandbox i18n-engine
    # A tree whose Arabic catalog also carries a counted test string, so the
    # six forms are checked whatever the shipped strings count.
    tree="$SANDBOX/tree"
    mkdir -p "$tree"
    for entry in "$HASEEN_PATH"/*; do
        [[ $(basename "$entry") == i18n ]] || ln -s "$entry" "$tree/$(basename "$entry")"
    done
    cp -r "$HASEEN_PATH/i18n" "$tree/i18n"
    jq '.["%1 test files"] = {zero: "لا ملفات", one: "ملف واحد", two: "ملفان", few: "%1 ملفات", many: "%1 ملفًا", other: "%1 ملف"}' \
        "$HASEEN_PATH/i18n/ar/shell.json" >"$tree/i18n/ar/shell.json"
    # Omarchy's own catalogs, as its package would install them.
    omarchy="$SANDBOX/omarchy"
    mkdir -p "$omarchy/default/i18n/en" "$omarchy/default/i18n/ar" "$SANDBOX/plugin/i18n"
    printf '%s\n' '{"common.search": "Search", "x.files": {"one": "%1 file", "other": "%1 files"}}' >"$omarchy/default/i18n/en/shell.json"
    printf '%s\n' '{"common.search": "بحث", "x.files": {"zero": "لا ملفات", "one": "ملف واحد", "two": "ملفان", "few": "%1 ملفات", "many": "%1 ملفًا", "other": "%1 ملف"}}' >"$omarchy/default/i18n/ar/shell.json"
    printf '%s\n' '{"panel.title": "Title", "panel.only": "English only"}' >"$SANDBOX/plugin/i18n/en.json"
    printf '%s\n' '{"panel.title": "العنوان"}' >"$SANDBOX/plugin/i18n/ar.json"
    mkdir -p "$XDG_CONFIG_HOME/haseen"
    harness="$SANDBOX/shell"
    mkdir -p "$harness"
    for module in Haseen Compat Ui Commons; do
        ln -s "$HASEEN_PATH/shell/$module" "$harness/$module"
    done
    cat >"$harness/shell.qml" <<QML
import QtQuick
import Quickshell
import qs.Haseen
import qs.Haseen.Widgets
import qs.Commons as Commons
import "file://$HASEEN_PATH/shell/plugins/haseen.menu/MenuModel.js" as Menu
ShellRoot {
    id: shell

    property int step: 0
    // Created with the shell, as the bars' bindings create them.
    readonly property string warm: I18n.language + Commons.I18n.language + strings.language

    function state(): string {
        const fill = track.children[0].children[0], knob = track.children[1];
        const items = Menu.mergeMenuSources(Menu.applyTranslations([{id: "apps", label: "Apps"}, {id: "learn", label: "Learn"}], {apps: {label: "التطبيقات", description: "وصف"}}), [{id: "learn", label: "Mine"}]).items;
        return JSON.stringify({
            lang: I18n.language,
            rtl: I18n.rightToLeft,
            tr: I18n.tr("Bar edge"),
            missing: I18n.tr("No such string %1", "x"),
            plural: [0, 1, 2, 3, 11, 100].map(n => I18n.tn("%1 test file", "%1 test files", n)).join("|"),
            date: I18n.formatDate(new Date(2026, 9, 22, 14, 5), "dddd HH:mm"),
            menu: I18n.menuEntry("setup.language").label || "",
            asArg: [1].map(n => (I18n.tr)("Done"))[0],
            compat: [Commons.I18n.t("common.search", "Search!"), Commons.I18n.t("nope.key", "Fallback"), Commons.I18n.tn("x.files", 3), Commons.I18n.rightToLeft, Commons.I18n.formatNumber(13.14, 1), Commons.I18n.language].join("|"),
            plugin: [strings.t("panel.title"), strings.t("panel.only"), strings.t("panel.none", "fb")].join("|"),
            track: [Math.round(fill.x), Math.round(fill.width), Math.round(knob.x - (track.width - knob.width) * 0.75)].join(" "),
            menuRow: [items.apps.label, items.apps.description, items.apps.searchTerms.join(","), items.learn.label, Menu.matchesQuery(items.apps, "apps")].join("|")
        });
    }

    Commons.Translations {
        id: strings

        directory: "file://$SANDBOX/plugin/i18n"
    }

    FloatingWindow {
        implicitWidth: 220
        implicitHeight: 40
        visible: true

        Item {
            width: 200
            height: 20
            LayoutMirroring.enabled: true
            LayoutMirroring.childrenInherit: true

            TrackBar {
                id: track

                width: 200
                value: 0.25
            }
        }
    }

    // One step a second: the state, then the next language change through
    // the real command (an atomic replace) or a raw write.
    Timer {
        interval: 1000 // haseen:ui-timeout
        repeat: true
        running: true
        onTriggered: {
            console.warn("STATE " + shell.step + " " + shell.state());
            const steps = [["haseen", "language", "ar"], ["sh", "-c", "printf 'xx\\\\n' >\"\$0\"", "$XDG_CONFIG_HOME/haseen/language"], ["haseen", "language", "ar"], ["haseen", "language", "en"]];
            if (shell.step < steps.length)
                Quickshell.execDetached(steps[shell.step]);
            else
                Qt.quit();
            shell.step++;
        }
    }
}
QML
    stub notify-send 'exit 0'
    run="$(mktemp -d "$SANDBOX/run.XXXXXX")"
    chmod 700 "$run"
    setsid env XDG_RUNTIME_DIR="$run" HASEEN_PATH="$tree" OMARCHY_PATH="$omarchy" QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME='' \
        QT_QUICK_BACKEND=software QT_NO_XDG_DESKTOP_PORTAL=1 \
        timeout -k 5 60 dbus-run-session --config-file="$REPO/tools/smoke-session.conf" -- "$QS_BIN" -p "$harness" \
        >"$SANDBOX/qs.out" 2>&1 &
    group=$!
    STATUS=0
    wait "$group" || STATUS=$?
    kill -- -"$group" 2>/dev/null || true
    OUTPUT="$(cat "$SANDBOX/qs.out")"
    assert_status "engine: the harness completes" 0 "$STATUS"
    st() { sed -n "s/^.*STATE $1 //p" <<<"$OUTPUT" | head -1 | jq -r "$2" 2>/dev/null; }
    assert_eq "engine: English by default" "en false Bar edge" "$(st 0 '"\(.lang) \(.rtl) \(.tr)"')"
    assert_eq "engine: English plural forms" "0 test files|1 test file|2 test files|3 test files|11 test files|100 test files" "$(st 0 .plural)"
    assert_eq "engine: English day name" "Thursday 14:05" "$(st 0 .date)"
    assert_eq "engine: a missing string stays English, filled" "No such string x" "$(st 0 .missing)"
    assert_eq "engine: no menu catalog in English" "" "$(st 0 .menu)"
    assert_eq "engine: compat English from Omarchy's catalog, else the fallback" "Search|Fallback|%1 files|false|13.1|en" "$(st 0 .compat)"
    assert_eq "engine: a plugin's own English catalog" "Title|English only|fb" "$(st 0 .plugin)"
    assert_eq "engine: a mirrored track fills and puts its knob from the right" "150 50 0" "$(st 0 .track)"
    assert_eq "engine: the menu catalog relabels by id; the overlay wins; English stays searchable" \
        "التطبيقات|وصف|Apps|Mine|true" "$(st 0 .menuRow)"
    assert_eq "engine: haseen language ar switches live" "ar true $(jq -r '.["Bar edge"]' "$tree/i18n/ar/shell.json")" "$(st 1 '"\(.lang) \(.rtl) \(.tr)"')"
    assert_eq "engine: Arabic's six plural forms" "لا ملفات|ملف واحد|ملفان|3 ملفات|11 ملفًا|100 ملف" "$(st 1 .plural)"
    assert_eq "engine: Arabic day name, Western digits" "الخميس 14:05" "$(st 1 .date)"
    assert_eq "engine: the menu catalog follows" "اللغة" "$(st 1 .menu)"
    assert_eq "engine: tr passed as a function value" "$(jq -r '.["Done"]' "$tree/i18n/ar/shell.json")" "$(st 1 .asArg)"
    assert_eq "engine: compat Arabic, plural, direction" "بحث|Fallback|%1 ملفات|true|13.1|ar" "$(st 1 .compat)"
    assert_eq "engine: a plugin's Arabic, English underneath" "العنوان|English only|fb" "$(st 1 .plugin)"
    assert_eq "engine: an unknown code is English" "en false" "$(st 2 '"\(.lang) \(.rtl)"')"
    assert_eq "engine: Arabic again" "ar" "$(st 3 .lang)"
    assert_eq "engine: haseen language en returns to English" "en false Bar edge" "$(st 4 '"\(.lang) \(.rtl) \(.tr)"')"
    [[ $(st 4 .lang) == en ]] || tail -30 <<<"$OUTPUT" >&2
fi
