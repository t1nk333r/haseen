# Plan 046: Window corners follow the shell's screen frame

## Status

- **Priority**: P3
- **Effort**: S
- **Risk**: LOW (one rendered Hyprland value and one shell token)
- **Depends on**: 004 015 068
- **Category**: shell
- **Planned at**: 2026-10-05, owner request ("corners of the windows match the radius of the frame"); reworked 2026-10-08 (owner decision: one shared radius rule for the menu and the windows that also works on the default theme)
- **State**: DONE 2026-10-08

## Problem

Three radii, set independently. The shell's screen frame draws its inner
corners at `Config.frameRadius`: `shell.json`'s `frame.radius`, or twice the
theme's `radius` token, 12 px by default (`share/haseen/shell/Haseen/Config.qml`).
Hyprland rounded windows at the theme's own `rounding` (`haseen` ships 4), else
`looknfeel.lua`'s 4. Plan 068's menu took `windowRadius` from that Hyprland
value. A window tucked into a frame corner cut across the frame's curve.

The first version (2026-10-05) rendered `rounding = {{ frame_radius }}` from
`themed/hyprland.lua.tpl`. It changed nothing on the default theme: a theme
that ships its own `hyprland.lua` is never overwritten by a template, and
`haseen` and `solitude` ship one. It also left the menu on the old value.

## Decision

One rule, resolved once per theme render, used by all three. The radius is the
frame's inner radius, by `Config.qml`'s rule: `frame.radius` from the user's
`shell.json` over the shipped default, when it is a number from 0 to 64
(rounded); otherwise twice the theme's `radius` token.

- `_theme_window_radius` in `share/haseen/layers/theme/theme-lib.sh` resolves
  it into `THEME_COLORS[window_radius]`. The rendered `shell.json` carries it as
  `windowRadius`, so the menu (`Theme.windowRadius`) rounds like the windows.
- `_theme_window_rounding` ends the staged `current/theme/hyprland.lua`,
  rendered or the theme's own, with
  `hl.config({ decoration = { rounding = <radius> } })`. It is the last word of
  the theme file, so a theme's `rounding` no longer splits the windows from the
  frame. The user's `monitors/bindings/local.lua` load after it and still win.
  The staged file is rewritten, never appended through, because a user theme
  may link its `hyprland.lua` to a file elsewhere.
- The `haseen` theme's own `rounding = 4` is removed (dead under the rule).
  `solitude` keeps upstream's file as it is; its `rounding = 6` is overridden.
- The unrendered fallbacks follow the same rule at the default radius:
  `looknfeel.lua` `rounding = 12` and `Theme.qml` `windowRadius: 12`.

A `frame.radius` edit reaches the frame at once and the windows and menu at
the next `haseen theme set`. The settings index notes it.

## Rejected

- **Reading `shell.json` from Lua at Hyprland config time.** Hyprland's Lua VM
  would need a JSON parser and the file is not guaranteed to exist.
- **Adding an include after the theme in `~/.config/hypr/hyprland.lua`.** That
  file is seeded once and never rewritten, so existing users would not get it.
- **Pushing `hyprctl keyword decoration:rounding` from the shell** when the
  frame radius changes. A second writer of Hyprland state, racing config
  reloads.
- **Making the frame follow Hyprland instead.** The frame is the shell's own
  surface and the theme owns `radius`; a compositor value would decide a theme
  token.

## Verification

- `tests/test-theme.sh`: every stock theme renders `windowRadius` = 2 × its
  `radius`, and its rendered `hyprland.lua`, run under Lua with a recording
  `hl`, leaves `decoration.rounding` at the same value, including `haseen` and
  `solitude`, which ship their own. Under a user `shell.json`: `frame.radius`
  20 gives 20; 7.6 gives 8; 0 gives 0; 65, `"20"` and an unreadable file fall
  back to 12, and the theme still sets. A user theme whose `hyprland.lua` is a
  symlink leaves the link target unchanged. Hyprland `--verify-config` accepts
  the rendered file.
- `tests/test-theme-haseen.sh`: the default theme's menu radius is 12, and
  `Theme.qml`'s fallbacks equal the rendered `haseen` tokens.

## Open

Not seen on screen: proving the curves coincide needs a running Hyprland
session with the frame enabled, which is the owner's live desktop.

## Execution record

`share/haseen/layers/theme/theme-lib.sh` (`_theme_window_radius`,
`_theme_window_rounding`, `theme_stage`), `share/haseen/default/hypr/looknfeel.lua`,
`share/haseen/themes/haseen/hyprland.lua`, `share/haseen/shell/Haseen/Theme.qml`,
`share/haseen/lib/settings.sh`, `docs/architecture.md`,
`share/haseen/agents/skills/haseen/theming.md`, `tests/test-theme.sh`,
`tests/test-theme-haseen.sh`.
