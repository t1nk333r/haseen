# Plan 078: media panel

## Status

- **Priority**: P2
- **Effort**: S–M
- **Risk**: LOW (lazy panel on Quickshell's MPRIS service; remote art opt-in)
- **Depends on**: 010 021
- **Category**: shell, media
- **Planned at**: 2026-10-07, gap 3 of `docs/reference-shell-gaps.md`
- **State**: DONE 2026-10-07 (`tests/test-media.sh` incl. real-engine scenarios on fake players; nested screenshots)

## Change

- `haseen.media` gains a `panel` kind (`Panel.qml`, manifest 1.1.0). A left click on the bar label still
  toggles play/pause; a right or middle click opens the panel (`Widget.qml:36-43`), and so does
  `haseen shell ipc panel toggle haseen.media`. The host loads it lazily and frees it on close.
- Contents, all `Quickshell.Services.Mpris` property bindings (D-Bus signals):
  - a switcher, one shared `Pill` per player, shown with two or more (`Panel.qml:156`). The picked player is held by
    D-Bus name while the panel is open; with no pick, or when the picked one leaves, the panel shows the
    bar's pick: playing, else paused, else the first (`Media.js:40` `selectIndex`, `playerLabels` `:128`);
  - cover art, title, artist, album. Art that cannot show leaves a themed placeholder (a note glyph on
    `Theme.surfaceAlt`); the image is decoded at most at twice its cell (`Panel.qml:209`);
  - a seek bar with elapsed and total time (`formatTime` `:52`, `fraction` `:62`). A drag moves only the
    knob and sends one `SetPosition` on release (the shared `TrackBar`, `live: false`);
  - shuffle, previous, play/pause, next, repeat (None → Playlist → Track, `nextLoop` `:109`);
  - the player's own volume (`Volume`), a bar like the audio panel's.
- A control the player does not offer is hidden, not greyed (`Media.js:90` `controls`): previous, next and
  play/pause follow `CanGoPrevious`/`CanGoNext`/`CanPlay|CanPause`; the time row needs `Position` and a
  length; dragging needs `CanSeek`; shuffle, repeat and volume need `CanControl` and the property itself.
- Theme tokens only. The switcher pills and the seek and volume bars are the shared `qs.Haseen.Widgets`
  `Pill` and `TrackBar` (`share/haseen/shell/Haseen/Widgets/`, also used by the battery and display
  panels); only `Control` (a `BarButton`) stays inline. Play/pause is an accent pill.
- `tools/fake-mpris.py`: a fake MPRIS player for tests and nests (capabilities, metadata, `omit=` for
  properties a player lacks; every call and write is logged). It refuses the login session's bus.
- `tools/vptr`: `rd`/`ru` and `md`/`mu` press and release the right and middle buttons.

### Cover art: plan 010's remote-image rule

Plan 010 turned notification markup off because `StyledText` would fetch `<img>` sources: a remote image
tells its server who looked and when. The panel applies the same rule (`Media.js:75` `artSource`):

- local art always shows: `file://` URLs and paths (Firefox, Chromium, mpv write their art to disk) and
  inline `data:image/` URIs (no fetch);
- `https://` art (Spotify, web players) shows only with the new `remoteArt` setting, **off by default**. The
  fetch would tell the art server what is playing, when, and from which IP. The manifest therefore
  declares `network`, so `haseen plugin validate` warns, as for the pager's opt-in favicons;
- plain `http://` never (anyone on the path sees the track), nor any other scheme.

Turn it on: `~/.config/haseen/shell.json` → `"plugins": {"haseen.media": {"settings": {"remoteArt": true}}}`.

### The seek clock (§6)

MPRIS sends no position updates while playing; Quickshell extrapolates `position` from the last value but
re-reads it only when `positionChanged()` is emitted. Without a clock the bar would stand still. The panel
has one Timer (`Panel.qml:92`), `// haseen:ui-timeout`, single-shot, 1000 ms, re-armed from `onTriggered`
while `ticking` holds: a player is playing a track with a length. It exists only while the panel is
open (the host destroys the panel on close), stops when playback pauses, and each tick only emits the
signal: no D-Bus call, no process. A seek bar that moves every 2 s (the §6 sampler floor the gap report
quoted) would jump two seconds at a time; the owner-approved slice asked for ≤ 1 s while visible. The
bar label still has no Timer.

## Evidence

- `tests/test-media.sh` (30 checks; the 30 model units count as one):
  - manifest and defaults: panel kind, `remoteArt` false, `network` declared, default `shell.json`
    untouched;
  - 30 model units under the real Qt JS engine: player selection (pick, fallback, none), time formatting
    (m:ss, h:mm:ss, junk), the art policy (file, path, data, https off/on, http, other schemes), the
    capability → controls table, repeat cycle and glyphs, volume glyphs, switcher labels;
  - the panel in the real Quickshell engine against two `tools/fake-mpris.py` players on a private bus:
    the playing one is shown with its local art and every control; the seek clock advances 61 s → 63–66 s
    in 2.5 s (it stays at 61 with the Timer off); shuffle, repeat, volume, seek, next and play/pause reach
    the player (`set Shuffle=true`, `set LoopStatus=Playlist`, `set Volume=0.3`,
    `SetPosition … 100000000`, `Next`, `Pause`) and the panel follows the player back; the switcher
    shows the limited player (no `CanSeek`, no length, no `Shuffle`/`LoopStatus`/`Volume`, https art),
    which hides shuffle, repeat, volume and the seek bar, keeps the placeholder, and receives nothing it
    does not offer.
- `tests/test-widgets-a.sh`: the only network warning among those widgets is media's; the only Timer is
  the panel's seek clock; the bar label still has none.

## Nested proof

`tools/nest-launch.sh` nest, the worktree shell on a private session bus with two `tools/fake-mpris.py`
players (Spotify: playing, local 512 px cover, shuffle on, repeat playlist, volume 65 %; Radio: paused, no
seek/length/shuffle/repeat/volume, https art). Pointer input through `tools/vptr`. Screenshots in
`~/.cache/haseen-wt/scratch-media/shots/`:

- `panel-rightclick.png`: a right click on the bar label opened the panel under it: switcher, cover,
  title/artist/album, seek at 1:39 / 4:34, shuffle, previous, pause, next, repeat, volume 65 %.
- `panel-tick.png`: two seconds later the bar reads 1:53 (the fake started at 1:23).
- `panel-radio.png`: a click on Radio: placeholder art (https off), title, previous/play/next only.
- A click on next logged `call Next`; a middle click closed the panel, a left click on the bar label logged
  `call Pause` and the label turned to the play glyph; a middle click reopened the panel
  (`panel-middle.png`, paused, 2:15 standing).

## Not verified

- `remoteArt` on with a real https URL: no network fetch was made from a test or the nest.
- Real players (Spotify, Firefox, mpv with mpv-mpris); only the fake was on the bus.
- Dragging the seek and volume bars with the pointer (the engine test calls the same functions).

## Final shape (2026-10-08)

The review round moved the plugin-local `TrackBar.qml` and the inline `Choice` to the shared `Pill` and
`TrackBar`, made the secondary text readable (`Theme.subtle`) and drew play/pause as an accent pill.
`~/.cache/haseen-wt/scratch-design/shots/4a-media-panel.png` (two fake players, Spotify picked: cover,
title/artist/album, seek 4:18 / 4:34, shuffle, previous, pause, next, repeat, volume 65 %) and
`4b-media-radio.png` (Radio picked) are the final panel in a nest; `tests/test-media.sh` drives it in the
real engine.

## Rejected

- **A chevron in the bar** (the slice allowed one): it adds a cell to a thin bar for what right and middle
  click already do.
- **Fetching https art through `curl` into a cache**, as the pager's favicons do: same disclosure, more
  code; Qt's image loader fetches on demand and only with the setting on.
- **A repeating Timer or `FrameAnimation`** for the seek bar: §6 allows no repeating timer under 2 s, and a
  frame-rate animation redraws far more than once a second.
- **Remembering the switcher's pick across opens**: the panel is freed on close; reopened, it shows what the
  bar shows.
