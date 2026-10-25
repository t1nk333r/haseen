# Plan 046: Window corners follow the shell's screen frame

## Status

- **Priority**: P3
- **Effort**: S
- **Risk**: LOW (one rendered Hyprland value and one shell binding)
- **Depends on**: 004 015 068
- **Category**: shell
- **Planned at**: 2026-10-05, owner request ("corners of the windows match the radius of the frame"); reworked 2026-10-08 (owner decision: one shared radius rule for the menu and the windows that also works on the default theme)
- **State**: DONE 2026-10-08

## Problem

Three radii, set independently. The shell's screen frame draws its inner
corners at `Config.frameRadius`: `shell.json`'s `frame.radius`, or twice the
theme's `radius` token, 12 px by default
(`share/haseen/shell/Haseen/Config.qml:39`). Hyprland rounded windows at the
theme's own `rounding` (`haseen` shipped 4), else `looknfeel.lua`'s 4. Plan
068's menu took its radius from that Hyprland value. A window tucked into a
frame corner cut across the frame's curve.

## Decision

One rule, used by all three: the frame's inner radius, by `Config.qml`'s rule.
That is `frame.radius` from the user's `shell.json` over the shipped default
when it is a number from 0 to 64 (rounded), otherwise twice the theme's
`radius` token.

- **The menu** binds `Config.frameRadius`, the frame's own property
  (`share/haseen/shell/plugins/haseen.menu/Panel.qml:81`), so a `frame.radius`
  edit reaches the frame and the menu at once.
- **Hyprland**: `_theme_window_radius` in
  `share/haseen/layers/theme/theme-lib.sh:469` resolves the rule at each theme
  render, and `_theme_window_rounding` (`:503`) writes the staged
  `current/theme/rounding.lua`, `hl.config({ decoration = { rounding = <radius> } })`.
  `init.lua` loads it right after its own modules, as a default
  (`share/haseen/default/hypr/init.lua:161`): `haseen toggle gaps on`, hyprmod's
  `hyprland-gui.lua` and the user's `monitors/bindings/local.lua` load after it
  and still win. A `frame.radius` edit reaches the windows at the next
  `haseen theme set`; the settings index says so.
- **A theme's own `rounding` is dropped.** The staged `hyprland.lua`, rendered
  or the theme's own, loads after hyprmod, so it is prefixed with
  `local hl = haseen.theme_hl(hl)`: an `hl` whose `config` drops
  `decoration.rounding` (`init.lua:131`). A prefix, not a suffix, keeps a file
  that ends in `return` valid. The staged file is rewritten, never written
  through, because a user theme may link its `hyprland.lua` elsewhere; a
  dangling link is replaced by the template render in the staging copy.
- The `haseen` theme's own `rounding = 4` is removed (dead under the rule).
  `solitude` keeps upstream's file; its `rounding = 6` is dropped.
- A fractional `radius` token truncates (7.5 → 7 → 14), as `Theme.qml`'s int
  property does, so bash and QML cannot drift.
- The unrendered fallback follows the rule at the default radius:
  `looknfeel.lua` `rounding = 12` (`share/haseen/default/hypr/looknfeel.lua:25`).
  `Config.frameRadius` needs no fallback: it uses twice `Theme.radius`, 12 on
  the built-in palette.
- **An existing HOME** gets the new render from migration
  `1791466289-theme-rounding.sh`: when `current/theme` has no `rounding.lua`,
  it runs `haseen theme set` on the current theme once (no theme, or a render
  that already has the file: nothing to do; a theme that cannot render warns
  and keeps the old render).

## Rejected

- **Rendering `rounding = {{ frame_radius }}` from `themed/hyprland.lua.tpl`**
  (the first version, 2026-10-05): a theme that ships its own `hyprland.lua` is
  never overwritten by a template, and `haseen` and `solitude` ship one, so
  nothing changed on the default theme. It also left the menu on the old value.
- **Appending the rounding to the staged theme file** (the first rework,
  2026-10-08): it loaded after the toggles and hyprmod, so
  `haseen toggle gaps on` no longer squared the corners and hyprmod's rounding
  never applied; it also broke a theme file ending in `return` and wrote
  through a dangling link.
- **A `windowRadius` token in the rendered `shell.json`** for the menu: a
  `frame.radius` edit left the frame and the menu disagreeing until the next
  theme set. The token is gone from `shell.json` and `Theme.qml`; nothing else
  read it.
- **Reading `shell.json` from Lua at Hyprland config time.** Hyprland's Lua VM
  would need a JSON parser, and the file is not guaranteed to exist.
- **Adding an include after the theme in `~/.config/hypr/hyprland.lua`.** That
  file is seeded once and never rewritten, so existing users would not get it.
- **Pushing `hyprctl keyword decoration:rounding` from the shell** when the
  frame radius changes: a second writer of Hyprland state, racing config
  reloads.
- **Making the frame follow Hyprland instead.** The frame is the shell's own
  surface and the theme owns `radius`; a compositor value would decide a theme
  token.

## Verification

- `tests/test-theme.sh`: `window_rounding` runs the seeded
  `~/.config/hypr/hyprland.lua` (defaults, `rounding.lua`, toggles, hyprmod,
  the theme, the user's files) under Lua with a recording `hl`. Every stock
  theme ends at 2 × its `radius`, including `haseen` and `solitude`, which ship
  their own file. Under a user `shell.json`: `frame.radius` 20 gives 20; 7.6
  gives 8; 0 gives 0; 65, `"20"` and an unreadable file fall back to 12, and
  the theme still sets. Load order, on `solitude` with `frame.radius` 20: 20,
  then `haseen toggle gaps on` gives 0 and `off` 20 again, a hyprmod
  `rounding = 5` gives 5, a user `local.lua` 9 gives 9. A linked theme
  `hyprland.lua` is left unchanged; a dangling one is rendered in place without
  creating its target; one ending in `return` parses and loads. A
  `radius = 7.5` token gives 14. The dry run plans `rounding.lua`. Hyprland
  `--verify-config` accepts the two staged files.
- `tests/test-theme-haseen.sh`: the default theme's window radius is 12, and
  `Theme.qml`'s fallbacks equal the rendered `haseen` tokens.
- `tests/test-menu-radius.sh`: the menu `Panel.qml` under Quickshell rounds at
  `frame.radius` 20, then at 5 after `shell.json` is rewritten, with no theme
  set in between (with the `windowRadius` token: 12 both times).
- `tests/test-migrate-defaults.sh`: the migration gives an old render (no
  `rounding.lua`, the theme's own rounding unprefixed) both files; a re-run
  leaves the render byte-identical; no theme writes nothing; a current theme
  that no longer exists warns, keeps the old render and exits 0.

## Open

Not seen on screen: proving the curves coincide needs a running Hyprland
session with the frame enabled, which is the owner's live desktop.

## Execution record

`share/haseen/layers/theme/theme-lib.sh` (`_theme_window_radius`,
`_theme_window_rounding`, `theme_stage`, `theme_render_templates`),
`share/haseen/default/hypr/init.lua` (`haseen.theme_hl`, the `rounding.lua`
include), `bin/haseen-theme-set` (dry-run plan),
`share/haseen/default/hypr/looknfeel.lua`,
`share/haseen/themes/haseen/hyprland.lua`, `share/haseen/shell/Haseen/Theme.qml`,
`share/haseen/shell/plugins/haseen.menu/Panel.qml` (`cornerRadius`),
`share/haseen/themed/shell.json.tpl`, `tests/test-menu-radius.sh`,
`share/haseen/lib/settings.sh`, `docs/architecture.md`,
`share/haseen/agents/skills/haseen/theming.md`, `tests/test-theme.sh`,
`tests/test-theme-haseen.sh`, `share/haseen/migrations/1791466289-theme-rounding.sh`,
`tests/test-migrate-defaults.sh`.

## Follow-up (plan 114)

Reversed on 2026-10-25 by the owner's "Restyle to Omarchy" decision
(`plans/114-windows-like-omarchy.md`). Omarchy runs the radius the other way
round: a theme's own `hyprland.lua` owns `decoration.rounding`
(`themes/solitude/hyprland.lua@v4.5.0-rc1:18-19`; 0 elsewhere,
`default/hypr/looknfeel.lua@v4.5.0-rc1:25`) and the shell mirrors it
(`shell/Commons/Style.qml@v4.5.0-rc1:13-33`). So, since plan 114:

- `haseen theme set` no longer writes `current/theme/rounding.lua` and
  `init.lua` no longer loads it; `_theme_window_radius` and
  `_theme_window_rounding` are gone (`theme-lib.sh`'s `_theme_hyprland_prefix`
  keeps the prefix). A stale `rounding.lua` in an older render is ignored and
  goes at the next `haseen theme set`.
- `haseen.theme_hl` no longer drops the theme's rounding: it drops whatever a
  toggle or hyprmod set (`haseen.held`), so `haseen toggle gaps`,
  `omarchy-hyprland-corners` and hyprmod still win over the theme, and the
  user's own files still win over all three.
- `looknfeel.lua`'s fallback is Omarchy's 0; `solitude` keeps Omarchy's 6, and
  `haseen` has its own 4 back (its `UPSTREAM.md`).
- The migration `1791466289-theme-rounding.sh` now only adds the prefix to a
  render that lacks it.
- The menu and the frame still follow `Config.frameRadius`; making the shell
  read Hyprland's rounding is plan 115's.
