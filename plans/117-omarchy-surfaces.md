# Plan 117: Panels, notifications, OSD, lock and launcher look like Omarchy's

## Status

- **Priority**: P1
- **Effort**: L
- **Risk**: MEDIUM. Every popup surface is touched; the token API is 115's.
- **Depends on**: 115, 116
- **Category**: shell
- **Planned at**: 2026-10-25
- **State**: DONE 2026-10-25 for notifications, OSD, launcher, lock and the
  section headers of four panels. The other panels' rows are plan 121.

## What changed

- **Notifications** (`NotificationCard.qml:32-38`): Omarchy's card is the
  `[notifications]` surface with a 2 px border, 12 px side and 10 px vertical
  padding (`shell/plugins/notifications/components/NotificationCard.qml:64-114`).
  Replaced `Theme.surface`, a 1 px border and `Theme.gap * 1.5` padding.
- **OSD** (`CardWindow.qml:25,40-45`): 67 px above the edge, the `[popups]`
  surface, a 2 px border and 16 px padding around at least `displayLarge`
  (`shell/plugins/osd/Osd.qml:28-35,143-150`). Replaced `Theme.gap * 12`,
  `Theme.surface`, a 1 px border and gap-sized padding.
- **Launcher** (`haseen.launcher/Panel.qml`): Omarchy's menu, not a form.
  - the bordered input box is gone; the query line is a heading-size `Text`
    dimmed to 0.58 while empty (`Menu.qml:1153-1168`);
  - rows are `BorderSurface`s of `max(58, body + caption + 2 * row-padding-x)`
    (`Menu.qml:101-109`) painted with `[launcher]`'s selected fill and
    selected border over a 36 px icon column (`Menu.qml:1223-1225`), a
    heading-weight Medium label and a body-small detail line
    (`Menu.qml:1275-1305`);
  - `Theme.launcher.selectedBorderSpec` is new, Omarchy's
    `Border.surfaceSpec("menu", "selected-border", selectedBorder, 0)`
    (`Menu.qml:96`) with haseen's `[launcher]` group
    (`Theme.qml:404-406`); the row reserves that border's width so a selected
    row never pushes its label sideways.
- **Lock** (`haseen.lock/LockView.qml:24-45,120-200`): Omarchy's field —
  381 x 67 px, a 3 px outline in `[lock]`'s border-active / border /
  border-error colour, the `[lock]` fill, a heading*1.125 label, password dots
  at heading*1.33 with heading*0.19 letter spacing that shrink to fit rather
  than clip, and the failure shown in the field in italic
  (`shell/plugins/lock/LockView.qml:22-40,125-215`). Replaced `Theme.surface`,
  `Theme.gap`-sized padding and a 1 px border.
- **Panel section headers** (`haseen.audio`, `haseen.battery`,
  `haseen.bluetooth`, `haseen.gestures`): the local `SectionLabel` (muted text
  one pixel under body) is now `PanelSectionHeader` — caption size, bold, the
  foreground darkened 1.4 times (`Ui/PanelSectionHeader.qml`). Audio and
  bluetooth also take Omarchy's `PanelSeparator` before each section
  (`panels/audio/Panel.qml:783-800`, `panels/bluetooth/Panel.qml:768-780`).

## Evidence

- `tests/run.sh test-lock.sh test-launcher-providers.sh test-surfaces.sh
  test-shell-tokens.sh test-i18n.sh test-themegen-keys.sh` -> 453/453.
- `tests/run.sh test-audio-panel.sh test-audio.sh test-battery.sh
  test-gestures.sh test-surfaces.sh` -> 360/360.
- `tools/lint.sh` -> OK (qmllint over 346 QML files); `tools/check-docs.sh` ->
  OK.
- `tests/run.sh --affected` -> 10588/10620; every failure is environmental and
  fails on `origin/main` too: `test-menu*` and `test-pager` abort on a
  `mise` config-trust error in this shell, `test-plymouth` and
  `test-nvim-theme` need a short path and 17 nvim specs.

## Live check on IO (2026-10-25)

Deployed with the cherry-picked commit in `~/.cache/haseen-deploy-115`
(`./install.sh --yes`, `systemctl --user daemon-reload`, restart of
`haseen-shell.service`), then read back with `grim`:

- the bar is one strip at Omarchy's 26 px with no inner hairline;
- `haseen shell ipc launcher toggle` shows Omarchy's menu: the dimmed
  heading-size query line, the prefix line, and 58 px rows with icons, a
  Medium heading label, a body-small detail and the `[launcher]` selected
  fill and border on the cursor row;
- `haseen notification send` draws the card with the 2 px `[notifications]`
  border and 12/10 px padding.

The lock's `LockView` is instantiated offscreen by `tests/test-lock.sh`'s
quickshell harness (it finds the fingerprint hint and toggles its
visibility), so its bindings resolve; the lock itself is an owner step —
locking IO over SSH would need the owner's password to unlock.

## Rejected options

- **Adopting Omarchy's panel bodies wholesale** (its audio panel is 1249 lines
  against haseen's 225): haseen's panels bind PipeWire and NetworkManager
  through its own models, and Omarchy's QML would drag Omarchy's services in.
  The card and the row controls are shared; the rollout is plan 121.
- **Omarchy's upper-case section labels** ("OUTPUT"): the text is translated,
  and Arabic has no case to raise. The header's weight and colour is what the
  eye reads.
- **Removing the lock's clock**: Omarchy 4.5's lock is a blurred wallpaper and
  a password field only. haseen's clock and date stay — they are the owner's
  lock screen, and dropping them is a separate decision.
- **A blurred wallpaper on the lock**: Omarchy's `MultiEffect` blur over the
  current background is not ported, because `haseen.lock` has no background
  path to read. Recorded as a gap in plan 121.
