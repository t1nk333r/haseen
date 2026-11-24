# Plan 197: the launcher, wheel, panel and prayer-time findings of the 2026-11-24 audit

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: LOW. Each fix is local to one plugin or widget. Two change
  behaviour on purpose: `%` followed by `-` is now a percentage and then a
  subtraction, so modulo by a negative number needs brackets; and the
  session panel's power rows now run `haseen system`, which closes the apps
  first, as the menu's System rows always have.
- **Depends on**: 091 (BarButton's wheel accumulator), 103 (Calendar.js's
  UTC dates), 104 (`haseen system` closes the apps), 121 (row chrome), 123
  (no dim behind the menus), 177 (the boot splash follows before a reboot)
- **Category**: shell
- **Planned at**: 2026-11-24, from the owner ("fix them", after the
  35-auditor audit)
- **State**: DONE 2026-11-24 (`tests/test-wheel.sh` 10/10, `tests/test-session-panel.sh` 22/22; the affected selection's GL-context and socket-path failures reproduce on main)

## Problem

The 2026-11-24 audit of haseen (35 auditors at 2f7f472a, each finding
re-traced by a skeptic) confirmed twelve findings in this group. Every one
was re-checked on main at 9a9e82ab, after plans 182-184 merged; all twelve
still held there. Findings 3 and 4 are one defect seen by two auditors (wheel
handlers that ignore Qt's delta contract) and are fixed together, with the
calendar's wheel that finding 4's verifier also found. Line numbers below
are main's at 9a9e82ab.

## 1. The calculator read `%` before a minus as modulo

`=200 + 10% - 5` showed 200 (215 expected) while `=200 + 10% + 5` showed
225; `=50% - 10` and `=10%-5` showed 0. `isModulo` treated `% -` as modulo
by a negative operand (`haseen.calculator/Calc.js:146`) and `peekPercent`
refused the percentage before a `-` (`Calc.js:192`). The header promises
"200 + 10% → 220 (as most calculators do)".

**Fix.** A minus after `%` is a subtraction, as a plus is: both checks drop
the `-` case. Modulo by a negative number takes brackets, `10 % (-3)`, which
the header now says.

**Test.** `tests/test-calculator.sh` adds `200 + 10% - 5` = 215, `+` and
`-` agreeing, `50% - 10` = -9.5, `10%-5` = -4.9 and `10 % (-3)` = 1. On
main the first three fail ("expected 215 got 200", `["0","0"]`).

**Rejected.** Keeping modulo when the minus touches its operand (`% -3`
without a space): spacing would change the answer, and `10%-5` is exactly
the case people type.

## 2. The launcher jumped the cursor back to row 0 on any late answer

`results` is a binding over every provider's `query()`, so it is rebuilt
whenever anything a provider reads changes: a window title (haseen.windows
reads `Hyprland.toplevels`), the commands' guard batch
(`commands/Provider.qml:105`), the accounts list answering. Every rebuild ran
`onResultsChanged: list.currentIndex = 0` (`haseen.launcher/Panel.qml:153`),
so Enter could run the top row instead of the one the user moved to.

**Fix.** The keys and the pointer pick a row through one `select()`, which
remembers the row (title and subtitle) and its position. When the list's
model changes, `selectionAfterRebuild()` starts a new query at the top, and
for the same query finds the remembered row wherever it now is (else the
same position), as haseen.menu does (`MenuModel.selectionAfter`). It runs
from the ListView's `onModelChanged`, because a new model resets
`currentIndex` to 0 after every `resultsChanged` handler.

**Test.** `tests/test-launcher-providers.sh`: on `/fixture`, Down picks
"Fixture Panel" (row 2 of 2) before the guard batch; after the batch inserts
"Fixture Guarded" above it, the cursor is still on "Fixture Panel" (row 3);
a new query starts at row 0. On main the cursor is back on "Fixture Go".

**Rejected.** Resetting only in `onQueryChanged`: the ListView resets
`currentIndex` itself on every new model, so the reset has to be undone
there anyway. Keying rows by provider id: rows do not carry it, and title
plus subtitle is what the user sees.

## 3 and 4. Wheel handlers stepped on the sign of one event, or dropped fractions

Plan 091 made BarButton add `angleDelta.y` up and step once per 120
(`Haseen/Widgets/BarButton.qml:21,84-87`), Qt's `QWheelEvent` contract.
Five handlers did not:

- `haseen.audio/VolumeRow.qml:129` and `Haseen/Widgets/TrackBar.qml:125`
  (the media panel's seek bar and player volume) and
  `haseen.prayers/PrayerSlider.qml:91` moved a full step per event on the
  sign alone, so a sideways swipe (`angleDelta.y` 0) or the zero-delta end
  of a touchpad scroll stepped down, and each small touchpad event stepped;
- `haseen.workspaces/Widget.qml:218` and `haseen.calendar/Panel.qml:263`
  rounded each event alone, so the 15 or 30 a hi-res wheel sends never
  switched a workspace or a month.

**Fix.** Each adds its own `wheelDelta`, adds the event's `angleDelta.y`,
steps `Math.trunc(wheelDelta / 120)` times and keeps the remainder. A zero
or sideways delta adds nothing.

**Test.** New `tests/test-wheel.sh`: every shell QML file outside Compat
that reads `angleDelta.y` must add it up (the tray forwards raw deltas to
the item and is exempt), and none may step on `angleDelta.y > 0 ?` or
round one event. In the real Quickshell engine, TrackBar and VolumeRow get
real wheel events (QtTest's `TestEvent`): from 50 %, a sideways notch, a
zero delta, eight eighths of a notch, a notch down and two notches in one
event read `[50,50,55,50,60]`. On main the grep checks fail for all five
files and both widgets read `[45,40,80,75,80]`: the sideways notch and the
zero delta each step down, and each eighth of a notch steps a full 5 %.

**Rejected.** Scaling one step by `delta / 120`: the snapped sliders
(TrackBar with `steps`) would round small fractions away again.

## 5. haseen.kblayout coloured its xkb-id column from a property plan 121 removed

`color: Theme.subtle(row.fill)` (`haseen.kblayout/Panel.qml:123`) read a
`fill` property that 1df7f929 (plan 121) removed, so `subtle()` got
undefined, `Ink.js` threw "Cannot read property 'r' of undefined" and the
column drew Qt's default black on the dark surface.

**Fix.** The row's `CursorSurface` is named `chrome`, and the column uses
`Theme.subtle(Theme.over(chrome.color, chrome.color.a, Theme.surface))`: the
subtle ink of the row as drawn, hover or selected fill over the surface.

**Test.** `tests/test-keyboard.sh`'s three-layout run opens the list
(`KBL_PANEL=1`; the other runs count devices reads, which opening it adds
to): each of the three id columns draws `Theme.subtle(Theme.surface)` and
the output has no "Cannot read property 'r'". On main all three are false.

## 6. The menu's overlay placement was described as dimming the screen

The `placement` description (`haseen.menu/manifest.json:22`), which users
read in Settings and `haseen plugin info`, and the header comment
(`haseen.menu/Panel.qml:17`) said "a card centred over the dimmed screen";
plan 123 removed the dim on purpose (`Panel.qml:1076-1080`).

**Fix.** Both now say a card centred over the desktop, which a click
outside closes, with no dim; the header points at plan 123.

**Test.** `tests/test-surfaces.sh` asserts neither text says "dimmed".

## 7. The emoji grid held only the first 1000 of 1870 emoji

`filterEmojis(emojis, query, 1000)` (`haseen.emoji/Panel.qml:27`) cut the
empty query at entry 1000, so the last 870 (late symbols, every flag)
could be reached only by searching; `move()` clamped the arrows there too.

**Fix.** The limit is `emojis.length`. The GridView builds tiles lazily.

**Test.** `tests/test-launcher-providers.sh` loads the panel in the engine:
with an empty query its results are all 1870 entries. On main, 1000.

## 8. haseen.session's `bootEntries` worked only as JSON types its manifest does not declare

The manifest types it `"string"` (`haseen.session/manifest.json:20`), and
haseen.settings stores a string setting as typed text
(`haseen.settings/Model.js:152`), but the panel honoured only boolean
`false` (`Panel.qml:77`) and a JSON array (`Panel.qml:89`). The documented
"false" and "a list of ids or labels" did nothing from the Settings panel.

**Fix.** `bootWanted` reads every spelling: `false`, `"false"`, `"none"` or
`"off"` hide them all (and read no firmware); `"auto"` or empty is auto; any
other text is a comma-separated list of ids or labels; a JSON list still
works. In the engine a list in `settings` arrives as a Qt sequence, for
which `Array.isArray` is false, so any object with a length counts. The
description says "false (or none)" and "a comma-separated list".

**Test.** New `tests/test-session-panel.sh` loads eight panels against a
stubbed `efibootmgr` on a UEFI sysroot: unset and "auto" show 0000, 0002
and 0011; `false`, "false" and "None" show none; "0000" shows 0000;
"kali, 0011" shows 0002 and 0011; `["0000"]` shows 0000; the three hidden
cases never run `efibootmgr` (five reads for eight panels).

**Rejected.** Changing the manifest type: plugin settings have no union
type, and an array type would lose `"auto"`.

## 9. The session panel's power rows skipped `haseen system`

Log out called Hyprland's exit dispatcher and Reboot and Shut down ran
`systemctl` (`haseen.session/Panel.qml:140-151`), so they skipped
`haseen system`'s app close (plan 104, `bin/haseen-system:136,147`) and the
boot splash catch-up (plan 177, `bin/haseen-system:146,151`); the boot-entry
row's `pkexec … && exec systemctl reboot` skipped both too. Plan 104 left
routing the panel through `haseen system` as a follow-up.

**Fix.** Log out, Suspend, Reboot and Shut down run `haseen system logout`,
`suspend`, `reboot` and `shutdown` through `Apps.launch`, as the menu's
System rows do (`haseen.menu/Panel.qml:569`); the boot-entry row runs
`pkexec haseen-boot-next … && exec haseen system reboot` the same way, the
id and label still argv. Lock keeps the in-process `lock` role with the
`loginctl` fallback, which is what `haseen system lock` does.

**Test.** `tests/test-session-panel.sh` presses each row with
`systemd-run` stubbed: each runs `haseen system <verb>` in an
`app-haseen-…` scope, the boot row's argv is the pkexec-then-reboot script,
lock falls back to `loginctl lock-session`, and nothing calls `systemctl`
or `hyprctl`. `tests/test-surfaces.sh` asserts the panel holds no
`"systemctl"` and no `dsp.exit`.

**Rejected.** `Quickshell.execDetached` straight to `haseen system`: the
menu's route is `Apps.launch`, and one route keeps both behaving alike.

## 10. The image picker listed AVIF, which its default action refuses

`EXTENSIONS` includes `avif` (`haseen.imagepicker/Images.js:9`), but with
no command set a pick runs `haseen theme bg set`, whose `image_ok` accepts
only PNG, JPEG, WebP, GIF and BMP (`bin/haseen-theme-bg:52,110`). The panel
had closed by then, so an AVIF pick did nothing and said nothing.

**Fix.** `Images.extensionsFor(customCommand)`: every image for a
configured command, only the background's types for the default one. The
header comment and the `command` description say so.

**Test.** `tests/test-widgets-c.sh` checks `extensionsFor(false)` has no
avif, `extensionsFor(true)` keeps it, and `bin/haseen-theme-bg` still takes
exactly those types.

**Rejected.** Accepting AVIF in `haseen theme bg set`: every consumer of
the background link (swaybg, the lock screen, themes) would need AVIF
support. Reporting the failure in the panel: it has already closed.

## 11. Asr fell before Dhuhr, even before sunrise, in polar-circle winters

`afternoon()` uses `tan(|latitude - declination|)`
(`haseen.prayers/Engine.js:843-848`). Where the noon zenith reaches 90
degrees tan() wraps negative, and near 90 the hour-angle correction divides
by almost nothing, so Asr came out before Dhuhr, before sunrise or after
sunset, and nothing checked the order (`Engine.js:1032`). Tromso on
2026-11-24 (MWL): Fajr 05:45, Sunrise 10:32, Dhuhr 11:32, **Asr 08:31**,
Maghrib 12:29; Rovaniemi on 2026-12-03 gave Asr 12:08, the same minute as
Dhuhr. The bar counted down to Asr before sunrise, and `daySegments` drew
nothing.

**Fix.** `asrHours()` keeps adhan's shadow-rule Asr where it lands between
a minute after Dhuhr as shown (the method's Dhuhr and Asr adjustments
counted) and sunset, and the noon zenith is under 90 degrees. Elsewhere Asr
takes the middle of the Dhuhr-to-sunset span and the day is marked
approximate (`asrApproximate`, folded into `approximate`). Tromso on
2026-11-24 now reads Dhuhr 11:32, Asr 12:00, Maghrib 12:29, approximate;
Rovaniemi on 2026-12-03 Dhuhr 12:08, Asr 13:00. The approximation label
now reads "a nearer latitude or an estimated Asr used", with its Arabic.

**Test.** `Engine.test.js` adds "polar-circle winters keep Dhuhr before Asr
before Maghrib": 69 days from 2026-11-24 for Tromso, Longyearbyen,
Rovaniemi and Utqiagvik, MWL and ISNA, from the real zone script, each day
Sunrise < Dhuhr < Asr < Maghrib, and Tromso's 2026-11-24 approximate. The
adhan fidelity fuzz skips Asr only where the engine marks it approximate,
and asserts the order there instead; the rest still match within a second.
On main the suite fails: the fuzz meets no approximate Asr, and Tromso's
first day reads Asr 08:31.

**Rejected.** The nearest regular latitude's share of the afternoon: at the
edge where the shadow rule holds again Asr sits a minute or less after
transit, so it fell before the adjusted Dhuhr (fuzz case polar=65:
Dhuhr 14:33:20, Asr 14:32:44). The nearest regular day: the same edge
problem. Accepting any in-order formula result: past a 90-degree zenith the
formula wandered from 0.17 to 0.88 of the afternoon on consecutive days in
Tromso. Only the order check without the zenith limit agreed with adhan in
one more fuzz case, by chance.

## 12. The Compact card's date line showed the day before where midnight is skipped

`new Date(y, m - 1, d)` (`haseen.prayers/PanelCompact.qml:65`) is a local
midnight, and Qt's V4 resolves a skipped midnight onto the day before (the
quirk `haseen.calendar/Calendar.js:47-53` records, plan 103). Under
`TZ=America/Santiago` qml6 gave `new Date(2026, 8, 6)` as "Sat Sep 5
23:00:00 2026 GMT-0400", formatted "Sat 5 Sep", over Sunday's timetable.

**Fix.** `Model.civilDateAtNoon(date)` builds the date at local noon; the
Compact line uses it.

**Test.** `tests/test-prayers.sh` runs it in qml6 under
`TZ=America/Santiago`: `2026-09-06` is the 6th, "Sun 6 Sep", and malformed
dates give null. The panel must call the helper.

## Notes

Gates, from the worktree through the hermetic wrapper: `tools/lint.sh`
"lint OK"; `tools/check-docs.sh` OK; `tests/run.sh --affected 9a9e82ab`
selected 74 files, 6051/6074 checks passed. The 23 failures are
environmental and fail the same way on main at 9a9e82ab: test-idle,
test-pager (`tst_security.qml`), test-vapt-panel-conformance,
test-vapt-security-ui and test-vapt-ui-adversarial abort in Qt's
`QRhiGles2: Failed to create context` on this host, and test-menu-back's
IPC socket path is over the 108-byte limit from the worktree's path (34/34
from a short bind mount).

Before the fixes, the new and changed tests fail on main: the calculator
3 cases, the wheel 8 of 10, the launcher's kept row and the emoji count,
the keyboard list's ink (2), test-surfaces' menu text and session route
(6), test-session-panel 16 of 22, test-prayers' engine suite and Santiago
date (3).
