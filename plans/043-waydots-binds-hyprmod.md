# Plan 043: Keybinds follow waydots, and hyprmod gets a place in the load order

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MEDIUM (every key the owner uses changes at once; `--verify-config` and a stub-Lua harness are the guard)
- **Depends on**: 003 030
- **Category**: desktop
- **Planned at**: 2026-10-05, owner request (items 12 and 16)
- **State**: DONE 2026-10-05

## Problem

haseen's Hyprland defaults were **Omarchy's** layout with haseen commands. The
owner's instruction is that the keybinds follow his own waydots overlay, which
is a set of deliberate overrides on top of Omarchy: vim directions, `SUPER+Q`,
ALT for split/layout/clipboard, `SUPER+F1` for the sheet, a silent
`SUPER+SHIFT+<n>` on keycodes (so the number row works under the Arabic
layout), a CapsLock-HYPER snap layer, and the screen-search keys.

Separately, hyprmod — a GTK4 settings GUI for Hyprland — had to be given a
place in the load order, and an unambiguous one: a GUI that silently loses to a
CLI toggle is worse than no GUI.

## Decision

- **The layout moves into `share/haseen/default/hypr/binds.lua`**, not into the
  user's `bindings.lua`. Hyprland *stacks* binds, so expressing the layout as
  personal overrides needs an `hl.unbind()` per changed key, spelled exactly as
  the default spells it — waydots carries nine of them. In the default there is
  no unbind dance and `haseen keybinds` shows one bind per key. 99 binds → 122.
- **Both habits kept where they cost nothing**: `SUPER+W` still closes beside
  `SUPER+Q`, and the arrows keep focus/swap beside the vim keys. That is what
  the owner's session actually does.
- **`ALT+TAB` is one Lua bind** that dispatches `cycle_next` then
  `bring_to_top`. Omarchy stacks two binds on the key, so the sheet lists it
  twice with two descriptions; one function is one bind, one description, same
  behaviour.
- **The HYPER snap layer is pure Hyprland Lua** inside `binds.lua`: nothing to
  install, nothing in `bin/`, no subprocess per keypress. Usable area = monitor
  logical size minus the reserved edges; the box is a percentage of that,
  anchored to an edge; pressing the same snap again restores. Snap state is one
  record on the `haseen` global — a local would be forgotten on `hyprctl
  reload` (one Lua VM, config re-run), and a table keyed by window address would
  accumulate records for closed windows.
- **hyprmod loads last among haseen's own files**: one
  `haseen.include_optional(config_home .. "/hypr/hyprland-gui.lua")` after the
  modules and after `$XDG_STATE_HOME/haseen/toggles/hypr/*.lua`, before the
  theme and the user's own Lua. The owner's call — the GUI wins over
  `haseen toggle` and `haseen hw`; the user's hand-written Lua still wins over
  the GUI. The consequence is written in the comment, not left to be discovered.
- **Existing users are told once** (landing review, 2026-10-08). `binds.lua`
  is loaded from the installed tree, so nothing moves, but SUPER + / and
  SUPER + CTRL + V stop working and a key a user's `bindings.lua` already
  binds now fires twice. Migration `1791466290-keybinds-notice.sh` only prints
  what changed and how to `hl.unbind()` a clash, in `haseen migrate`'s output
  (the login notice runs it in a terminal that stays open). A fresh install
  seals it, so a new user sees nothing.

## Rejected

- **Binding the snap layer to the owner's `scripts/snap`** (or a new
  `bin/haseen-window-snap`): that script spawns `hyprctl -j activewindow` twice,
  `hyprctl -j monitors`, `jq` and `awk` on every press. Hyprland's Lua API
  exposes `get_active_window`, `get_active_monitor`, `get_monitors` and
  `dispatch`, so the same result is in-process with zero subprocesses.
- **Hyprland's percentage forms** (`resizeactive exact 50% 100%`): percentages
  are relative to the *full* monitor, so the bar's reserved strip would be
  covered. A live probe confirmed `reserved.top = 24.0` on this machine.
- **Pruning snap state with `hl.on("window.destroy", …)`**: `binds.lua` is
  `dofile`'d on every reload, so each reload would add another subscription.
  One record needs no cleanup.
- **`SUPER+ALT+B` → `haseen screensaver`** for the blackout key: the screensaver
  exits on the first key and draws effects, not black. The bind is left out
  rather than pointed at a command that does not exist.
- **Loading hyprmod's file before the toggles**: `haseen toggle gaps` would
  silently undo what the user just clicked.

## Verification

- **Hyprland 0.56.2 `--verify-config`** against a scratch `HOME` (no compositor
  started, the live session untouched): `config ok` for seed-only, for
  seed + toggles + `hyprland-gui.lua` + user `bindings.lua`, and for the final
  tree. Two negative controls prove it really parses the new files: a bogus
  dispatcher in `binds.lua` →
  `binds.lua:266: attempt to call a nil value (field 'nonexistent')`; a bogus
  key in `hyprland-gui.lua` → `unknown config key 'decoration.blurx'`.
- **Load-order proof inside verify-config**: default `gaps_in = 2`, the toggle
  file sets `0`, `hyprland-gui.lua` sets `7`; a probe
  `hl.get_config("general.gaps_in")` printed `7` — hyprmod won, as decided.
- **Snap arithmetic asserted exactly**: 1920×1080 at scale 1.25 with a 24 px
  reserved top (usable 1536×840 at y=24) → snap left resizes to {768,840} and
  moves to {0,24}; the same key again unfloats; snap right moves to {768,24};
  snap 80 % centred → {1228,672} at {154,108}.
- `tests/test-keybinds.sh` (62) loads the **real** `binds.lua` under a stub `hl`
  that records binds, descriptions and actions and replays key presses, and
  walks every bound command through `bin/haseen`'s own longest-prefix
  resolution — a bind to a command that does not exist fails the suite.
  `tests/test-desktop.sh` 136/136 (its stub `hl.bind` had to learn to render
  Lua-function binds). Perturbation check: renaming `SUPER+Q` and deleting the
  hyprmod include each fail exactly one named assertion.
- `luac -p` on all seven Hyprland Lua files.

## Open

No key was pressed on the live session: binds are proven by parse, by the stub
harness and by `--verify-config`, not by use. Injecting keystrokes into the
owner's session is forbidden (handoff.md).

## Execution record

`share/haseen/default/hypr/{binds,init}.lua`,
`share/haseen/shell/plugins/haseen.keybinds/Overlay.qml` (one stale comment),
`share/haseen/agents/skills/haseen/hyprland.md`, `README.md`,
`tests/test-keybinds.sh`, `tests/test-desktop.sh`;
landing review: `share/haseen/migrations/1791466290-keybinds-notice.sh`,
`tests/test-migrate-defaults.sh` (the notice writes nothing, and every key it
names is bound in `binds.lua`).
