# Plan 190: shipped defaults from the 2026-11-24 audit (fcitx5's switch key, portrait snaps, keyd's CapsLock, weather on)

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW. New installs get a different English↔Arabic key; existing
  fcitx5 configs are the user's and keep theirs. The keyd migration only
  replaces the exact file haseen wrote before. Weather turns on for everyone
  without their own `"enabled": false`, which the owner asked for.
- **Depends on**: 022 (haseen.weather), 043 (the snap layer), 044 (herdr and
  tmux on Ctrl+Space), 056 (keyd), 101 (the sealed Omarchy migration)
- **Category**: defaults
- **Planned at**: 2026-11-24, from the 35-auditor audit (owner, 2026-11-24,
  "fix them")
- **State**: DONE 2026-11-24 (`tests/test-keybinds.sh` 168/168,
  `tests/test-keyd.sh` 45/45, `tests/test-mux.sh` 100/100,
  `tests/test-seeds.sh` 98/98, `tests/test-weather.sh` 116/116; each fix's
  new checks fail on main 9a9e82ab; the keys on a live session are an owner
  check)

## Problem

The audit ran at 2f7f472a; each finding below was checked again on main
9a9e82ab (plans 182–184 merged since) and still held. Two findings are the
same defect seen by two auditors (4 and 5).

## 1. fcitx5's Control+space switch takes the herdr and tmux prefix

**Evidence (main 9a9e82ab).** `share/haseen/default/fcitx5/config:14` bound
`[Hotkey/TriggerKeys] 0=Control+space`; its comment (`:4-6`) checked only
`hypr/binds.lua`. The shipped multiplexers use the same key as their prefix:
`share/haseen/default/herdr/config.toml:38` `prefix = "ctrl+space"` (its only
prefix) and `share/haseen/default/tmux/tmux.conf:18` `set -g prefix C-Space`
(C-b at `:19` is the fallback). fcitx5 is installed by the desktop layer and
seeded by `share/haseen/seeds/20-fcitx5.sh`; while a text-input client such as
foot has focus, fcitx5's keyboard grab sees the key before the client, so
Ctrl+Space switched to Arabic and herdr never saw its prefix. Omarchy hit the
same clash and dropped the key
(`/usr/share/omarchy/default/input-methods/configure.py:75-78`,
`without_ctrl_space`: "Ctrl+Space belongs to tmux and Herdr"); plan 101 had
recorded that migration only as a threat to haseen's switch.

**Owner decision (2026-11-24).** Ctrl+Space stays the herdr/tmux prefix;
fcitx5's switch moves. The owner named Super+Space, which is haseen's menu
(`share/haseen/default/hypr/binds.lua:27`), so another free key was needed.

**Fix.** The trigger is `Super+i`, the key Omarchy 4.5 gives "Switch input
language" (`/usr/share/omarchy/default/hypr/bindings/input-method.lua:19`,
`SUPER + I`), so an Omarchy user's hands already know it. It is free in every
place that could take it first:

- `share/haseen/default/hypr/binds.lua`: no `SUPER + I` (only
  `SUPER + CTRL + I`, Stay awake, `:54`); Hyprland would otherwise consume it
  before fcitx5;
- herdr (`config.toml`) and tmux (`tmux.conf`) bind no Super keys;
- foot's seeded `foot.ini` binds no Super keys;
- keyd's shipped file only maps CapsLock; Hyprland's `kb_options` is empty
  or `grp:alts_toggle` (`share/haseen/default/hypr/input.lua:32,44`).

The comments in `fcitx5/config` and `fcitx5/profile`, the seed summary
(`seeds/20-fcitx5.sh:4`), `omarchy-input-method`'s header and
`omarchy-setup-input`'s message name the new key; plan 101's claim about the
sealed migration now says why Omarchy dropped the key. No keybind sheet,
help text or doc named Control+space for fcitx5 (`grep -rniI
'control\+space|ctrl\+space'` outside plans finds only the multiplexers and
haseen.capture's own in-panel Ctrl+Space, which only applies while that
panel has the keyboard).

**No migration.** `fcitx5/config` is seeded once and then belongs to fcitx5
and the user (`fcitx5/config:1`, "fcitx5 owns the file afterwards";
fcitx5-configtool rewrites it), and haseen never edits a user file after
seeding it (CLAUDE.md). Only the default changes: new installs and fresh
seeds get Super+i; an existing machine keeps Control+space until the user
changes it in fcitx5-configtool.

**Tests.** `tests/test-seeds.sh`: the seeded trigger is `Super+i` and not
`Control+space`. `tests/test-mux.sh`: every fcitx5 trigger key, normalised
with herdr's prefix and tmux's `prefix`/`prefix2`, is none of them.
`tests/test-keybinds.sh`: every fcitx5 trigger key, written as Hyprland's
combo, is not a shipped bind. On main the seeds and mux checks fail, and so
does the keybinds check that reads the key (Control+space is no Hyprland
bind either).

**Rejected keys.**
- Super+Space (the owner's pick): haseen's menu (`binds.lua:27`).
- Super+Shift/Alt/Ctrl+Space and their mixes: launcher, toggle bar, theme
  and background pickers, next background (`binds.lua:28,35,49-51`).
- Control+space: the multiplexers' prefix, the defect itself.
- Alt+Shift (a common layout switch): herdr's `alt+shift+enter` and tmux's
  `M-S-Enter` start with it, and fcitx5 would fire on the bare modifiers.
- Shift+space: types a space in every app for someone typing with Shift
  held.
- Zenkaku_Hankaku / Hangul (Omarchy's other triggers): absent from US and
  Arabic keyboards.

**Rejected options.** Changing the herdr/tmux prefix (the owner kept it). A
Hyprland `SUPER + I` bind running `fcitx5-remote -t`, as Omarchy does: it
adds a compositor bind for what fcitx5 already does, and a user who changes
the key in fcitx5-configtool would find Super+I still taken. A migration
that rewrites existing fcitx5 configs: a user file.

## 2. The HYPER snap layer ignores monitor rotation

**Evidence (main 9a9e82ab).** `usable_area()` in
`share/haseen/default/hypr/binds.lua:329-340` returned `mon.width / scale`
and `mon.height / scale` and never read `mon.transform`. Hyprland reports the
panel's unrotated pixels; `share/haseen/default/hypr/qconsole.lua:108-114`
and `workspace-modes.lua:96-98` swap them on `transform % 2 == 1`. On a
2560x1440 panel at transform 1 (1440x2560 on screen), HYPER+H sized the
window 1280x1440, HYPER+L moved it to x 1280 (mostly past the 1440-wide
screen), and HYPER+F made it 2560x1440.

**Fix.** `usable_area()` swaps width and height for the odd transforms
before dividing by the scale, as qconsole's `fit()` does.

**Test.** `tests/test-keybinds.sh` presses HYPER+H, HYPER+L and HYPER+F on a
2560x1440 monitor at transform 1 with a 24 px top reservation and expects
720x2536 at x 0, 720x2536 at x 720, and 1440x2536 at x 0. All three fail on
main.

**Rejected.** Reading Hyprland's logical size from another field: the Lua
monitor object the other two files use is the same one, and they swap.

## 3. keyd's `rightalt+capslock = capslock` is a 50 ms chord

**Evidence (main 9a9e82ab).** `share/haseen/default/keyd/default.conf:9` put
`rightalt+capslock = capslock` in `[main]`. `man keyd` (2.6.0), "Chording":
a `+` left-hand side is a chord, "activated if all keys are struck within the
chording interval (chord_timeout)", default 50 ms. Holding RightAlt and then
tapping CapsLock, as `default.conf:3`, `bin/haseen-setup-keyd:22,79`, the
skill (`share/haseen/agents/skills/haseen/hyprland.md:66`) and the keybind
sheet described, sent AltGr+Escape. The sheet's test asserted hold semantics
(`tests/test-keybinds.sh:663`).

**Fix.** The shipped file puts CapsLock in RightAlt's layer: keyd binds
`rightalt = layer(altgr)` by default, and `man keyd` recommends overriding a
modifier in its pre-defined layer (`[control] j = down`). So `[altgr]
capslock = capslock`, and no chord line. The help, the info line, the skill
and `docs/architecture.md` §1 row 9 say "hold RightAlt and press CapsLock".
`haseen keybinds` reads a CapsLock line in a modifier's layer
(`[control]`, `[shift]`, `[alt]`, `[meta]`, `[altgr]`) as that modifier key
plus CapsLock, and labels a real `[main]` chord "Press together for …" so a
user's own chord reads as what it is.

**Existing machines.** `/etc/keyd/default.conf` is written by `haseen setup
keyd on`, not a user file. Migration
`share/haseen/migrations/1795510882-keyd-capslock-layer.sh` replaces it only
when its sha256 is exactly that of the one earlier version haseen shipped
(90a8afd2), through `write_root_file`, and runs `keyd reload` when keyd is
active. Any other file is left alone.

**Tests.** `tests/test-keyd.sh`: the shipped file has the `[altgr]` line and
no chord; the migration rewrites the old file (and shows the new one under
`DRY_RUN`), and leaves an edited, a current and a missing file alone.
`tests/test-keybinds.sh`: the shipped sheet row is still `RIGHT ALT +
CAPSLOCK`, "Press for CAPSLOCK"; a `[main]` chord reads "Press together";
`[control] capslock = esc` reads `CTRL + CAPSLOCK`. These fail on main.

**Rejected.** Only rewording the docs to "press both within 50 ms": a Caps
Lock that needs a 50 ms strike is not dependable. Raising `chord_timeout`:
it would slow every chord a user adds.

## 4. The default shell.json disables haseen.weather

**Evidence (main 9a9e82ab).** `share/haseen/default/shell.json:28`
`"haseen.weather": { "enabled": false, "settings": { "location": "" } }`,
while `:15` (bar.right) and `:53` (services) list it.
`share/haseen/shell/Haseen/Config.qml` `isEnabled` returns
`enabled !== false && !Plugins.held(id)`, so a fresh install had neither the
widget nor the service. The flag dates from plan 022 (ccf11aee).

**Owner decision (2026-11-24).** haseen.weather is approved on by default.

**Fix.** The default drops `"enabled": false` and keeps the empty location:
with no location the service asks GeoClue, then wttr.in's IP lookup (the
"no location" cases in `tests/test-weather.sh`). The config is a deep merge
of the default and `~/.config/haseen/shell.json` (`Config.qml:7-8`), so
every machine whose own file does not switch weather off gets it after the
update; no migration. The manifest's description, README's feature list,
`docs/reference-shell-gaps.md` and `omarchy-import.sh`'s comment (which
said haseen ships it off) now say it is on. The Omarchy import still turns
it on explicitly, for a user file that had it off.

**Test.** `tests/test-weather.sh`: the shipped `shell.json` never sets
`enabled` for weather, lists it in bar.right and services, and carries no
location. The first check fails on main.

**Rejected.** Taking weather out of CLAUDE.md's approved list (the other
reading of the finding): the owner chose on.

## 5. The agent guide lists weather as on while the default had it off

**Evidence.** CLAUDE.md lists weather under "Approved on by default"; the
default had it off (finding 4).

**Fix.** The same change as finding 4: the default now matches the guide,
which needs no edit.

## Gates

Run through the hermetic wrapper from the worktree on 2026-11-24:

- `tools/lint.sh`: lint OK.
- `tests/run.sh --affected 9a9e82ab…`: 107 files, 12254/12275. The 21
  failures are not this change: test-idle (1), test-pager (2),
  test-vapt-panel-conformance (12) and test-vapt-security-ui (5) fail the
  same way on an untouched checkout of main 9a9e82ab (123/143 for those
  five files there; their Qt runners abort with "Failed to initialize
  graphics backend for OpenGL" on this host), and test-menu-back's two are
  the long worktree path's IPC socket limit: it passes 34/34 from a short
  bind mount.
- `tools/check-docs.sh`: check-docs OK.
