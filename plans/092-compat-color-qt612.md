# Plan 092: Compat palette under Qt 6.12

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW (a mechanical qualification of one singleton in haseen's own compat files; held by a static check and an engine probe)
- **Depends on**: 011 049 091
- **Category**: shell
- **Planned at**: 2026-10-20, found while deploying plan 091 to IO
- **State**: DONE 2026-10-20

## Problem

After plan 091 was installed on IO and `haseen-shell.service` restarted, the
journal filled with compat colour warnings: 2,173 lines in the first minute,
for example `@Ui/Button.qml[83:-1]: TypeError: Cannot read property 'border'
of undefined` (203 times) and `@Ui/CursorSurface.qml[26:3]: Unable to assign
[undefined] to QColor` (168 times). The previous run of the same unit, six
hours of it, logged none (`journalctl --user -u haseen-shell.service | grep -c
'Ui/Button.qml\[83'`: 406, all after 14:35:22).

The cause is not plan 091. `omarchy-update` had upgraded IO at 09:11 the same
morning (`/var/log/pacman.log`): `qt6-base` and `qt6-declarative` 6.11.2 →
6.12.0, `quickshell` 0.3.1 → 0.3.2.r7. The old shell process predated that and
kept the old libraries; the restart was the first haseen run under Qt 6.12.

Qt 6.12 exports a new QtQuick singleton named `Color`
(`/usr/lib/qt6/qml/QtQuick/plugins.qmltypes`: `name: "QQuickColor"`,
`exports: ["QtQuick/Color 6.12"]`, `isSingleton: true`). A minimal shell on IO
with `qs.Commons` providing a `Color` singleton (`foreground: "red"`) and a
second one named `Hue`:

| imports | `Color` resolves to | `Color.foreground` |
| --- | --- | --- |
| `QtQuick`, `Quickshell`, `qs.Commons` | `QQuickColor(0x…)` | `undefined` (`Hue.foreground` is `#ff0000`) |
| `qs.Commons` first, then `QtQuick` | `QQuickColor(0x…)` | `undefined` |
| `qs.Commons as C`, `C.Color` | ours | `#ff0000` |
| `QtQml` instead of `QtQuick` | ours | `#ff0000` |

Every compat `Ui` control and the `Style` and `Border` singletons import
QtQuick and read `Color.<role>` bare (82 lines in 24 files on `8a21c0a`), so
under Qt 6.12 every Omarchy control draws with undefined colours. Of haseen's
compat singleton and type names, `Color` is the only one any of QtQuick,
QtQml, QtQuick.Controls, QtQuick.Layouts or Quickshell exports (each name
checked against the installed `qmltypes` on IO).

## Change

The fix follows Omarchy 4.0.6, installed on IO by the same update: its own
`Ui/Button.qml`, `Commons/Style.qml` and `Commons/Border.qml` add `import
qs.Commons as Commons` and read `Commons.Color.<role>`. Its shell has 54
files with that import.

- `share/haseen/shell/Compat/Omarchy/Ui/*.qml` (22 files) and
  `Compat/Omarchy/Commons/{Style,Border}.qml`: `import qs.Commons as
  Commons`, every bare `Color.` becomes `Commons.Color.` (the bare import
  stays for `Style`, `Util` and `Border`).
- `tests/test-compat.sh`:
  - a static check that no compat QML or JS line outside a comment reads a
    bare `Color.`;
  - an engine probe that builds a compat `Button` and reads
    `Commons.Color.tooltip.border`, the button's `tooltipBorder` and
    `foreground`, `Border.value("tooltip", "border")` and `Style`'s fallback,
    and fails on any `of undefined` or `Unable to assign [undefined]` line.
- `docs/architecture.md` §5.4 states the constraint.

## Evidence

- On IO (Qt 6.12.0) the probe against the installed `8a21c0a` tree printed
  the same warnings as the live journal (`Button.qml[38]`, `[40]`, `[60]`,
  `[61]`, `[62]`, `[83]`, `Border.qml[28]`). Against this change it printed
  `{"qualified":"#3b3c3c","tooltipBorder":"#3b3c3c","foreground":"#ccd0cf",
  "borderValue":"#3b3c3c","styleFallback":"#ccd0cf"}` and no warning.
- `tests/run.sh tests/test-compat.sh` on IO (Qt 6.12.0): 167/167 with this
  change. With `share/haseen/shell/Compat` reverted to `8a21c0a` and the new
  test kept: 158/163, failing the static check and all four engine checks.
- On the author's laptop (Qt 6.11.2, where the bug does not occur) the same
  file passes 167/167. CI runs `archlinux:latest`, which already ships Qt
  6.12, so the engine probe runs there for real.

## Rejected

- **Make bare `Color` resolve to haseen's singleton.** A real QML module on
  `QML_IMPORT_PATH` providing `Color` still loses to QtQuick's, whether it is
  imported before or after QtQuick (`QQuickColor(0x…) undefined` both ways,
  on IO). Only a qualified name reaches ours, and that requires editing the
  file that reads it.
- **Rewrite plugins' `Color.` at load.** The owner's plugin directories are
  read-only sources (CLAUDE.md); a rewritten copy would also drift from them.
- **Hold Qt at 6.11.** Not haseen's to pin, and it only defers this.

## Remaining

Plugins that read a bare `Color.` themselves still get QtQuick's singleton
under Qt 6.12. On IO that is 45 plugin directories, most of them the owner's
own; each author must add `import qs.Commons as Commons` and qualify the
reads, as Omarchy 4.0.6 does. haseen does not edit them.
