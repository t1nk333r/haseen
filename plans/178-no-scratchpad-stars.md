# Plan 178: no scratchpad stars in the bar unless turned on

## Status

- **Priority**: P3
- **Effort**: XS
- **Risk**: LOW. One widget's default changes. The scratchpads and the
  console keep their keys, and the setting brings the stars back.
- **Depends on**: 105 (the SUPER + GRAVE console, a special workspace)
- **Category**: shell, bar
- **Planned at**: 2026-11-21, from the owner
- **State**: DONE 2026-11-21 (`tests/test-omarchy45-workspaces.sh`
  114/114)

## Problem

The owner, 2026-11-21: "what the fuck is the star bext to the workspace".

haseen.workspaces draws one star for every Hyprland special workspace that
exists, after the numbered workspaces
(`share/haseen/shell/plugins/haseen.workspaces/Widget.qml` on origin/main
at `a1c66d2`, the `specials` Repeater, `label: ""`). Omarchy's widget,
which this one ports, does the same. haseen has two keys that create a
special workspace (`share/haseen/default/hypr/binds.lua:293-299`):

- SUPER + GRAVE opens the console (plan 105), a terminal on
  `special:console` (`share/haseen/default/hypr/qconsole.lua:15`);
- SUPER + ALT + S moves a window to `special:scratchpad`.

When the console is hidden, its terminal keeps running, so a dim star stays
in the bar with no label and no explanation. Both have their own keys and
need no bar control.

Offered two options: hide only the console's star, or drop the stars. The
owner answered "go" without picking. The stars come out by default, behind
a setting, because that answers the complaint fully and loses nothing.

## Decision

- A `scratchpads` setting on haseen.workspaces (boolean, default `false`,
  manifest version 2.2.0). Off, the widget lists no special workspaces and
  makes no monitor refresh on Hyprland's `activespecial` events, which
  only the stars needed. On, the stars come back as before: bright while
  shown, urgent-tinted, click to toggle.
- Turning them on: `"plugins": {"haseen.workspaces": {"settings":
  {"scratchpads": true}}}` in `~/.config/haseen/shell.json`, or the
  plugin's settings.

## Rejected

- **Hiding only the console's star.** The scratchpad's star is just as
  unlabelled. The owner's question was about the star itself, not about
  which workspace it stood for.
- **Removing the stars and their code.** The setting costs one property,
  and someone who uses several scratchpads may want them.
- **A label instead of a star.** That would add text to the bar for
  something both keys already reach (no visual clutter, AGENTS.md).

## Verification

`tests/test-omarchy45-workspaces.sh` (114/114):

- the source gates `specials` and the `activespecial` refresh on
  `scratchpads`;
- the manifest default is `false`;
- in the real Quickshell engine (the existing harness), the loaded widget
  reports `scratchpads` false by default and true once its settings say so.
