# Plan 079: more OSD kinds: microphone, keyboard layout, Caps/Num Lock

## Status

- **Priority**: P2
- **Effort**: S–M
- **Risk**: LOW (event sources only; lock keys opt-in)
- **Depends on**: 010
- **Category**: shell, input
- **Planned at**: 2026-10-07, gap 5 of `docs/reference-shell-gaps.md`
- **State**: DONE 2026-10-07 (`tests/test-keyboard.sh`; nested screenshots of the layout and Caps Lock cards)

## Change

- `haseen.osd` (manifest 1.1.0) gains three kinds, each a setting (`Osd.js` `kinds`):
  - `mic` (on): the default source's volume/mute from `Pipewire.defaultAudioSource` signals. Volume and
    mic share one inline `AudioWatch` (`Service.qml`), whose first reading of a node only seeds the
    baseline, so startup and a device switch flash nothing. The existing XF86AudioMicMute bind now shows it.
  - `layout` (on): Hyprland's socket2 `activelayout` event through the new `qs.Haseen` singleton
    `Keyboard` (`Haseen/Keyboard.qml`, pure functions in `Haseen/Keyboard.js`). The card shows the code
    (AR) and the xkb name (Arabic). Hyprland also sends `activelayout` for every keyboard on a config
    reload and for a new keyboard (`InputManager.cpp` keymap listener and `applyConfigToKeyboard`), so each
    keyboard's layout from one `hyprctl -j devices` read is the baseline and only a real change counts
    (`layoutEvent`).
  - `lockKeys` (**off**): Caps/Num Lock. See below.
- The card window moved to `CardWindow.qml`, loaded by URL (as haseen.lock's preview), so the service
  compiles in the offscreen test engine.
- Mic and layout follow the owner-approved slice: on because `haseen.osd` is a default service.

### Lock keys: the event source

Hyprland 0.56.2 posts no event when a lock modifier changes (`IKeyboard::updateModifiers` only emits the
internal `modifiers` signal; socket2 has `activelayout` only on a group change). The kernel's LED class
does not notify its `brightness` file, and polling is forbidden (§6). So:

- `share/haseen/default/hypr/binds.lua` binds `code:66` (Caps Lock key) and `code:77` (Num Lock key) with
  `non_consuming` (the key still reaches xkb and the app), `release` (the lock state has settled; xkb locks
  on press) and `ignore_mods` (Shift + Caps). Keycodes, not the `Caps_Lock` keysym: Hyprland resolves bind
  keysyms on a modifier-free first-layout state (`KeybindManager.cpp:369`), and haseen's `compose:caps`
  turns the Caps key into Compose, so a keysym bind would never fire.
- The bind runs `haseen shell ipc osd lockkeys`. The OSD's `osd` IPC target (`lockkeys()`, `state()`) reads
  `hyprctl -j devices` once and compares the main keyboard's `capsLock`/`numLock` with the last reading
  (`Keyboard.js` `lockState`, `Osd.js` `lockChanges`). The first read when the kind turns on is only the
  baseline. Under compose:caps the read finds nothing changed and shows nothing.
- With the kind off the call returns at once and starts no process; each Caps/Num key release still runs
  one `haseen shell ipc` (bash + `qs ipc`). Under DMS the call is unmapped (exit 3, one stderr line).

## Evidence

- `tests/test-keyboard.sh` (36 checks; 43 JS units count as one): manifest defaults (mic, layout on,
  lockKeys off); the code mapping incl. every xkb Arabic variant, devices reader, lock reader on fixture
  devices JSON (`tests/fixtures/keyboard/`), layout-event baseline and the OSD kind model under the real Qt
  JS engine; the lock binds' flags under a stub `hl`; and in the real Quickshell engine with a stub
  `hyprctl`: no flash at startup, an `activelayout` switch shows `AR Arabic`, a reload burst does not, Caps
  on and Num off each take one devices read and show their card, lockKeys off reads nothing.

## Nested proof

`tools/nest-launch.sh` nest; `kb_layout = "us,ara"`, the IO monitor and the two lock binds (calling a
scratch wrapper around `haseen shell ipc osd lockkeys`) in the nest's `hyprland.lua`; the worktree shell with
a scratch HOME and `lockKeys` on. Screenshots in `~/.cache/haseen-wt/scratch-keyboard/shots/`:

- `switch-ar.png`: `hyprctl switchxkblayout main next` on the NEST socket: the card `AR Arabic` and the bar
  code AR.
- `caps-on.png` / `caps-on-osd.png`: a Caps Lock press from a scratch zwp_virtual_keyboard client (xkb state
  computed like a real keyboard, `~/.cache/haseen-wt/scratch-keyboard/vkbd/`): the release bind fired, the
  read found `capsLock: true` on the main keyboard, the card reads `Caps Lock on`.

## Not verified

- Num Lock in the nest (the engine test covers it); a real mic mute (no PipeWire source in the nest).
- The owner's machine: his Caps Lock comes from `shift:both_capslock_cancel` (both Shifts) and keyd maps the
  Caps key to hyper, so neither `code:66` nor `code:77` fires there; a user bind on the Shift keycodes
  would cover it at one process per Shift release. Owner decision.

## Rejected

- **A `Caps_Lock` keysym bind**: never fires under `compose:caps` (above).
- **`hl.on("input.keyboard.key")`**: a Lua callback on every keystroke to catch two keys.
- **Watching `/sys/class/leds/*::capslock/brightness`**: no sysfs notify, absent in nests and on many
  keyboards behind keyd/fcitx virtual keyboards.
