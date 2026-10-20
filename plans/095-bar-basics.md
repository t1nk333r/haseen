# Plan 095: bar basics, four of the owner's plugins adopted

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: LOW (four plugins, all off by default; one guarded hook in `Bar.qml`; a migration that only rewrites the user's `shell.json` atomically and only when it names an old id)
- **Depends on**: 005 021 060 074 076 091
- **Category**: shell, plugins
- **Planned at**: 2026-10-20, owner decision below
- **State**: DONE 2026-10-20 (`tests/test-bar-basics.sh` 138/138; lint; full gate, see Evidence)

## Decision (owner, 2026-10-20)

Asked to "list the … plugins so i can choose which to adopt into haseen as a
1st party plugin", the owner chose 13; plans 095–098 port them. This plan
takes four. Following the owner's rule recorded on luna (a plugin we change
takes a `haseen.*` id) they are renamed:

| old id | new id | source copy ported |
|---|---|---|
| `t1nk33r.active-window` | `haseen.active-window` | luna `~/.config/omarchy/plugins/t1nk33r.active-window` |
| `t1nk33r.power` | `haseen.power` | IO `~/.config/omarchy/plugins/t1nk33r.power` (the only copy) |
| `t1nk33r.updates` | `haseen.updates` | IO `~/.config/haseen/plugins/t1nk33r.updates` |
| `t1nk33r.nook` | `haseen.nook` | IO `~/.config/haseen/plugins/t1nk33r.nook` |

Per CLAUDE.md a new built-in ships off until the owner adds it to the default
list, so adoption is not default-on: each is `"enabled": false` in
`share/haseen/default/shell.json` and in no bar section or service. This
decision overrides "third-party plugins are never bundled" for these plugins
only. CLAUDE.md records one line per plugin.

### Which copy

All copies were taken read-only on 2026-10-20 (`rsync` from IO, `cp` on
luna) and compared with `diff -rq`:

- active-window: IO's `~/.config/omarchy/plugins/` copy and luna's are
  identical; IO's haseen plugin directory has none (IO runs it through the
  Omarchy compat adapter).
- nook and updates: IO's haseen copy, IO's Omarchy copy and luna's are
  identical apart from build output (`tests/__pycache__`, the built `vptr`
  and its generated protocol sources). luna's yadm history:
  `.config/omarchy/plugins/t1nk33r.nook` last changed in 88c47f7 (2026-10-20,
  the Qt 6.12 `Commons.Color` fix), before that 4fd1be3, 1e3ff51, eb9c3d4,
  ec79ac7; `t1nk33r.updates` in 88c47f7 and 08baa17 (yadm commits, not
  commits of this repository).
- power exists only on IO (`~/.config/omarchy/plugins/t1nk33r.power`,
  disabled there: `plugins."t1nk33r.power".enabled` is false in IO's
  `shell.json`).

The Qt 6.12 fix in every copy (`import qs.Commons as Commons`) is moot: the
ports use `qs.Haseen` `Theme` tokens.

IO's `shell.json` (read, never copied into the repo) uses
`t1nk33r.active-window` in `bar.left` with `maxChars` 25, `t1nk33r.updates`
in `bar.center` with no settings, and `t1nk33r.nook` both in `bar.right`
and in `bar.overflow` (a drawer inside haseen's drawer), with nine widgets in
its `items`, `trigger: "click"` and a `widgetOrigins` map.

## Change

### haseen.active-window

`share/haseen/shell/plugins/haseen.active-window/` (`Widget.qml`, `Title.js`).
The focused toplevel from Quickshell's `ToplevelManager` (an event), the
title or else the app id, cut by `Title.label` to `maxChars` characters (50)
with a middle ellipsis, counting characters, not UTF-16 units, so an emoji is
never split: the fork's `charCut`/`tailCut`. `maxWidth` (0) is the optional
pixel clamp, through `BarButton.maxTextWidth`. Takes no room without a
window or in a vertical bar. Left click focuses, middle and right click
close, as in the fork. `toplevel` is writable so the test hands in a
stand-in.

Dropped: the 180 ms `Behavior on implicitWidth` (fork `ActiveWindow.qml:65`),
because every frame of it would refit the bar's overflow (`Bar.qml`
`onFitSpecChanged`); the hover tooltip with the full title
(`ActiveWindow.qml:107`), because haseen's bar has no generic tooltip and
the middle ellipsis keeps both ends.

### haseen.updates

`share/haseen/shell/plugins/haseen.updates/` (`Widget.qml`, `Panel.qml`,
`Model.js`) and `bin/haseen-update-check`.

- `haseen update check [--force] [--dry-run]` is the owner's `updates.sh` as a
  haseen command: `checkupdates` on a private database under
  `$XDG_RUNTIME_DIR/haseen/updates-db`, the AUR helper's `-Qua` (haseen's
  `aur_helper`, paru before yay), one flock, a 60 s cache of clean results
  only, the same JSON shape. Read-only apart from that cache;
  `--dry-run` prints the two checks.
- The widget shows the count (`12`, or `12+3` with `splitAur`), takes no
  room while nothing is pending, and stays visible in the urgent colour when
  a check failed. A left click runs `haseen update` through `Apps.launch`
  (it opens its own floating terminal, plan 060), never Omarchy's updater; a
  right click opens the panel.
- The panel replaces the fork's tooltip: the summary, any errors, at most
  `listLines` package lines (was `tooltipLines`), Check now (`--force`) and
  Update.
- Checks: one at start, then every `interval` minutes (30, at least 2). The
  shell allows only literal sample intervals (`tests/test-shell.sh`), so a
  one-minute `// haseen:sample` tick counts the minutes. The tick also
  re-reads the command's cache (`FileView`, no process), so a check made by
  the panel, another monitor's bar or the CLI reaches every bar within a
  minute; the cache is adopted only when its text changed since the
  previous read, so an old clean result never hides this widget's own failed
  check.

Dropped: the `onClick` setting (fork `BarWidget.qml:27`, default
`omarchy-launch-floating-terminal-with-presentation omarchy-update`): the
brief requires haseen's updater, and a free shell command in a setting is no
longer needed. The fork's IPC target `t1nk33r.updates` (`refresh`, `status`):
every bar instance would register it, and `haseen update check` answers the
same question from a terminal.

Rejected: a systemd user timer writing a state file
(`docs/reference-shell-gaps.md` item 11). It would run with the widget off;
the widget's own tick costs nothing while the plugin is not loaded. Flatpak
updates are not counted (item 11 suggests them); `flatpak remote-ls
--updates` is another network fetch, left for a later plan.

### haseen.power

`share/haseen/shell/plugins/haseen.power/` (`Widget.qml`, `Model.js`).

Overlap: the fork's panel (battery, time, draw, cycles, charge limit
presets, power profiles) is what plan 076 already rebuilt natively as
haseen.battery's panel; `docs/reference-shell-gaps.md` item 4 says that panel
"replaces the owner's compat t1nk33r.power". Porting it again would make two
power panels. So haseen.power keeps only what the fork has and haseen.battery
does not, the bar button:

- the fork's glyph rule: the level glyph while the charge limit holds a
  plugged-in battery (UPower pending charge, full below 99 %, or a trickle of
  at most 0.2 W or eight hours to full: the fork's `chargeThresholdActive`),
  the charging set otherwise, a full glyph when full; the fork's exact
  codepoints;
- the percentage beside it, on by default as in the fork, where only an
  explicit `false` (or the string `"false"`) hides it;
- a right click toggles the percentage at once (`Config.setRuntime`) and
  saves it with `haseen plugin settings haseen.power` (one write at a time,
  the latest value);
- a left click opens haseen.battery's panel (`panel toggle haseen.battery`).

It is an alternative to the haseen.battery widget, not a companion; that is
why it ships off. UPower signals only, no timer.

Dropped, from the fork's `Panel.qml` read on IO: the whole panel (above);
`omarchy-system-stats`, which it ran but never displayed (`systemInfo` is
never read; haseen.sysusage shows system figures); the rotating "Pumping
power" phrases on a 2.8 s timer; the 5 s refresh while open and 30 s battery
read while closed; `charge-limit.sh` with its own `pkexec` (`haseen battery
limit`, plan 060, owns the limit); `omarchy-powerprofiles-set`
(`haseen powerprofile`, used by the battery panel).

### haseen.nook

`share/haseen/shell/plugins/haseen.nook/Widget.qml` and a hook in
`share/haseen/shell/Bar.qml`.

Overlap: the fork is a second bar drawer, 2,801 lines (`BarWidget.qml`
1,281, `Service.qml` 412, `LayoutModel.js` 251, `bin/nook-offload` 857, a
Python writer for Omarchy's `shell.json`), plus its own widget registry
plumbing for Omarchy 4.0.3 (`Service.qml:19-34`). haseen's bar already has
that drawer (architecture 5.3 Overflow): a panel under the bar holding
widgets live, arrange mode with drag in and out, `haseen bar overflow
add|remove|pin|unpin`. Under haseen the fork could only host Omarchy-compat
widgets (`Compat/Runtime.qml` `rebuildCatalogue` skips native and DMS
ones), and on IO it sat inside the overflow panel itself.

So haseen.nook is not a second drawer. What the overflow panel lacks is the
nook's placement: its opener sits where the user puts it in a section, not
at the bar's end. haseen.nook is that opener:

- In a bar section (and enabled), it opens the overflow panel under itself
  (`Bar.toggleOverflowFrom`, `Bar.qml:228`; the panel's centre,
  `Bar.qml:500`), with the bar's own chevron glyph, highlighted while open.
  A right click arranges.
- The end chevron then shows only in arrange mode, as a drop target
  (`Bar.qml:435`), and its length leaves the fit (`Bar.qml:59`).
- The nook never moves into the panel it opens: `never: [nookId]`
  (`Bar.qml:60`), which also ignores it in `bar.overflow`.
- It takes no room while the panel would be empty, as the chevron does.
- A double click on it is not the bar's transparency toggle (as for the
  chevron).
- It finds its bar through `QsWindow.window` and duck typing, the pattern
  haseen.clipboard's panel already uses; in any other window it is inert.

Dropped: hover-to-open (`trigger`) and `duration`: the overflow panel takes
an exclusive keyboard grab when it appears (`BarOverflowPanel.qml`), so
opening it on hover would take the keyboard from the focused window; the
owner's IO setting is `"click"` anyway, and the panel's own animation
applies. `absorb`/`eject`/`reorder`/`restore` and `bin/nook-offload`: `haseen
bar overflow` and `haseen bar move` do it. The drag test harness and the
virtual pointer under `tests/`: haseen has `tools/vptr`.

Rejected: porting the drawer natively (a second implementation of
BarOverflowPanel); a nook setting that names its own item list (two lists of
"what is in the drawer").

### Migration

`share/haseen/migrations/1791560000-adopt-bar-basics.sh`, for a user
`shell.json` that still names an old id:

- bar sections, `bar.overflow`, `bar.pinned`: the old id becomes the new one
  in place, or is dropped where the new one is already listed; an id stays
  once across the sections, where it comes first;
- `services`: the old ids are dropped (none of the new plugins has a service
  kind; the nook's service only served Omarchy's host);
- `plugins.<old>` moves to `plugins.<new>`: `enabled` kept, and set true when
  the old id was in a bar section without one (the new plugins ship off);
  settings mapped (active-window `maxChars`, `maxWidth`; power
  `showPercentage` as a boolean; updates `interval`, `alwaysShow`,
  `splitAur`, `tooltipLines` → `listLines`, `onClick` dropped and said);
  values already under `plugins.<new>` win;
- the nook's `items` move into `bar.overflow` in its order: each into the
  section `widgetOrigins` recorded, else the nook's, else `right`, right
  after the nook; an item's own keys fill in `plugins.<id>.settings`
  (existing keys win); ids already in a section stay. A nook inside
  `bar.overflow` is removed, its widgets taking its place there. A nook that
  was not shown (in no section and not in overflow, or disabled) moves no
  widgets.

Idempotent (no old id left, nothing to do), `--dry-run` aware through
`shell_config_write`, under the `shell.json` lock, written atomically. The
old plugin directories are never read or touched. On a scratch copy of IO's
`shell.json` it renamed active-window and updates in place, removed the
nested nook, put its nine widgets into `bar.overflow` where the nook was and
into `bar.right` (one, by its recorded origin, into `bar.left`), kept every
other key unchanged, and a second run changed nothing.

## Evidence

- `tests/test-bar-basics.sh` (138 checks): manifests validate and are off by
  default; the code uses no Omarchy command or module, no hex colour, no
  privilege escalation, no blur; 58 JS units under the Qt JS engine
  (`Title.js`, both `Model.js`, `Overflow.fit` with `never`); `haseen update
  check` against stub `checkupdates`/`paru` (counts, colour stripping, private
  database, cache, `--force`, failures not cached, dry run, not Arch, no
  checkupdates); active-window, updates widget and panel, and the nook against
  a stand-in bar window in the real Quickshell engine (the update click
  reaching `systemd-run … -- bin/haseen-update`); haseen.power on
  `tools/fake-upower.py` (glyph on battery, held, charging; the right click
  saved to `shell.json`; the left click opening haseen.battery's panel); the
  migration on fixture HOMEs (`tests/fixtures/bar-basics/`), including
  re-run, dry run, old and new together, an invalid `shell.json` refused, the
  old plugin directories unchanged.
- `tools/lint.sh`: OK (qmllint caught a `state` property shadowing
  `Item.state` in the updates widget and panel; renamed `result`).

- CI (PR #45, head 494d66d) failed the three haseen.power checks: glyph
  `null`, text empty. CI's `ARCH_PACKAGES` had no `python-dbus` or
  `python-gobject`, so `tools/fake-upower.py` never started and the widget saw
  no battery; test-battery.sh and test-media.sh had been skipping their own
  fake-bus scenarios in CI for the same reason ("skip: qs, dbus-daemon or
  python3-dbus missing"). Reproduced in `archlinux:latest` with CI's packages
  (135/138); with the two packages added, test-bar-basics, test-battery and
  test-media passed 233/233 there. `.github/workflows/ci.yml` installs them,
  and the power scenario now checks its prerequisites first: it fails as a
  named prerequisite under `HASEEN_REQUIRE_ENGINE=1` (CI) and says skip
  elsewhere.

## Not verified

- No nested Hyprland run: the nook opening the real overflow panel under
  itself, and the four widgets on a real bar, are covered by the engine
  harness and the stand-in bar window, not by a screenshot.
- `haseen update check` against a real `checkupdates` and AUR helper (the
  tests stub both; the logic is the owner's script that plan 060 saw report 2
  repo updates on IO).
- Live migration on IO: an integrator step, with IO's own `haseen migrate`.
