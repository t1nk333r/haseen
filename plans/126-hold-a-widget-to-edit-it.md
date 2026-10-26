# Plan 126: Hold a bar widget to edit it with an agent

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MEDIUM. A new gesture on every bar widget, and a command that
  starts the default coding agent. Nothing changes unless it is held, and the
  widget's own press still does what it did.
- **Depends on**: 112, 119
- **Category**: shell
- **Planned at**: 2026-10-26
- **State**: DONE 2026-10-26 (owner, "on right click or long press … the
  ability to edit the thing with an agent"; the reference is omalauncher).

## Why

The owner's Android launcher, omalauncher
(`~/Projects/omalauncher-phone-updates`), lets a home-screen widget be changed
by an agent: a long press opens the item's menu with **edit**
(`ui/AppDrawer.kt:1002`), and edit starts the default coding agent on the
widget's file with a request that says which widget it is, where the file is
and to ask what to change (`widgets/WidgetPrompts.kt:51-75`; the same `[ edit ]`
row under settings › gestures, `ui/Gestures.kt:653`).

haseen's bar widgets have the same shape — a plugin directory with
`manifest.json` and the QML it names — but nothing in the bar can change one.
Right-click is not the place for it here: eleven widgets use it for their own
action (bluetooth, kblayout, vpn, updates, pager, typist, weather, nook, power,
prayers, monitor-settings) and the bar uses it for arrange mode.

## What changed

- **`bin/haseen-bar-edit`** (`haseen bar edit <id> [--dir DIR] [--prompt
  TEXT] [--dry-run]`) starts the default agent in the widget's directory with
  a request in omalauncher's style: the widget's id and directory, its
  `manifest.json` and QML, the plugin skill, `haseen plugin validate <id>`,
  and "Ask me what to change." `--prompt` replaces the words.
  Where it points, in order: `--dir`; the checkout named by `$HASEEN_SOURCE`
  or `~/.config/haseen/source` (one line), so a developer edits the real
  source; the plugin's own directory when it is a user plugin; else a **copy**
  of the built-in into `~/.config/haseen/plugins/<id>`, because the installed
  tree belongs to root — the notification says the copy now wins over haseen's
  updates.
- **`share/haseen/shell/BarSlot.qml`** — the passive `PointHandler` that
  already reports presses arms a 700 ms timer on a left press; when it fires
  with the pointer still within 3 px of where it was pressed, the slot asks
  the bar to edit the widget. A drag, a slider or a scroll moves the pointer
  first, and the slot's `DragHandler` stops the timer when it takes over.
- **`share/haseen/shell/BarStrip.qml`** — `editWidget(id)` runs
  `haseen bar edit <id>` detached.
- The four notices the command can send (the copy, and no agent configured)
  are in the `en` and `ar` catalogs.

## Evidence

- `tests/run.sh test-bar-edit test-bar-drag` — 140/140: the command resolves a
  user plugin, a checkout from `~/.config/haseen/source`, and a built-in (as a
  copy, with nothing written by a dry run); a given prompt is passed through;
  an unknown id fails; and the slot and the strip carry the gesture and the
  command.
- `tools/i18n.py check` — catalogs fresh and complete for en, ar.

## Known limits

- A hold still ends in the widget's own click: this handler takes only a
  passive grab, so holding a widget that opens a panel opens that panel once
  as well. Taking the pointer over at 700 ms is the follow-up that removes it.
- A widget that uses its right button keeps that action; the hold is the
  gesture that works on all of them.
- Built-in widgets on a machine with no checkout are edited as a user copy
  from then on (the notification says so).

## Rejected options

- **Right-click as the gesture**: taken by eleven widgets and by arrange mode.
- **A menu first, an "edit" row second** (omalauncher's shape): the bar has no
  room for a popup per widget, and the agent asks what to change anyway; a
  menu can come when there are more rows to offer.
- **Editing the installed tree in place**: it is root-owned, and haseen
  replaces it on every install.
- **A prompt box before the agent starts**: the agent asks; a second box in
  the bar would ask the same question twice.
