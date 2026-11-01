# Plan 150: haseen.capture, a capture toolbar of haseen's own

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: LOW. A new plugin, off by default, that starts nothing until it
  is enabled. The two shared changes are small: `haseen capture screenrecord`
  writes its start time into the flag it already wrote and gains `--window`,
  and `Flags` reads one more flag file. A shell restart cannot cut a
  recording, because recordings run in their own scope.
- **Depends on**: 018 (the capture commands and the `recording` flag), 041 and
  107 (`haseen capture screenshot` and Omasnap), 052 and 054 (the DMS toolbar
  the owner installed, which haseen could not ship), 109 (English and Arabic),
  115 (Omarchy's controls and Theme)
- **Category**: shell, plugins
- **Planned at**: 2026-11-01, owner: "Bring the plugin into proper haseen
  support with theme support and naming". The owner chose a plugin written
  from scratch rather than a port, with screenshots, screen recording with a
  timer pill, sound-only recording and the game controller.
- **State**: DONE 2026-11-01 (`tests/test-capture-toolbar.sh` 55/55; the
  affected run is in Verification; the live toolbar is an owner step)

## Problem

The owner uses JDKamalakar/DMS-ScreenCapture_Toolbar, a DankMaterialShell
plugin, through haseen's DMS compat host. The plugin has no license file
(plan 052:58-59, plan 054:55-58), so haseen ships none of it and may adapt
none of it. Through compat it runs as a foreign plugin:

- compat maps the Material colour names it reads onto haseen's tokens
  (`share/haseen/shell/Compat/Dms/Common/Theme.qml:7-14`), but its controls, layout and type are
  DMS's own, not the Omarchy controls haseen's panels use (plan 115);
- its strings are its own, outside haseen's English and Arabic catalogs
  (plan 109);
- it captures through its own pipeline, not `haseen capture`.

haseen had no capture toolbar of its own. It had the commands: `haseen capture
screenshot` (region, window, output, screen, `--edit`) and `haseen capture
screenrecord` (region or full screen, desktop audio, microphone). It had no
way to record sound alone and no clock for a running recording: the
`recording` flag was an empty file.

## What changed

- **`share/haseen/shell/plugins/haseen.capture/`**, a new first-party plugin
  (kinds `service` and `panel`, role `capture`), off in
  `share/haseen/default/shell.json`. It is written for haseen and shares no
  code with the DMS plugin.
  - `Model.js` is pure JavaScript: the modes, targets, delays and formats; the
    toolbar state and the command each choice runs; the delay; the elapsed
    text (`1:15`, `1:02:05`); one cursor for the keyboard and the controller
    (`rows`, `move`, `activate`); and the controller's button map
    (`padAction`, `padLine`).
  - `Service.qml` holds what must outlive the toolbar, which is freed when it
    closes:
    - the choices;
    - the pending delay;
    - the recording's clock;
    - the pill's loader;
    - the controller listener.
    It runs the commands through `Apps.launch`, so each capture gets its own
    scope. The recording flags (`Flags.recording`, `Flags.audioRecording`) say
    what runs, however it was started.
  - `Panel.qml` is the toolbar. While nothing records:
    - a mode row (screenshot, video, sound);
    - the target (region, window, output, screen);
    - desktop audio and microphone, for video and sound;
    - the delay (none, 3, 5, 10 s), or the sound's format (MP3, Opus, FLAC,
      WAV, M4A, OGG);
    - Capture/Record and Edit.
    While a recording runs, the toolbar is the elapsed time and Stop. Keys:
    arrows, Tab and Shift+Tab, Enter, and Space (Ctrl+Space edits a
    screenshot); Left and Right follow a right-to-left screen.
  - `PillWindow.qml` is the recording pill: a layer surface beside the bar on
    the screen that was focused at the start. It shows a red dot, the mode's
    glyph, the elapsed time and Stop. It exists only while a recording runs
    (`settings.pill`, on by default), takes no keyboard, and mirrors for
    Arabic.
  - `gamepad.py` is the controller listener (stdlib only). It finds
    controllers by the `BTN_SOUTH` bit in sysfs and reads their evdev nodes
    without grabbing them, so games still see every press. It maps buttons,
    hats and the left stick (with hysteresis) to names. It reads analogue
    triggers only on pads that have no digital ones. It sleeps in `select()`
    with an inotify watch on `/dev/input`, and prints `connected N`,
    `press <button>` and `error <text>`. It runs only when `settings.controller`
    is on and the toolbar is open or a recording runs.
  - The controller's buttons:
    - the D-pad moves;
    - A presses;
    - B closes;
    - LT/RT change the mode, LB/RB the target;
    - Start captures or stops;
    - Guide stops a recording, even with the toolbar closed.
- **`bin/haseen-capture-audiorecord`** is new: a sound-only recording through
  ffmpeg's PulseAudio input (PipeWire answers it). It records the microphone
  (the default), desktop audio, or both mixed with `amix`, into
  `$(xdg-user-dir MUSIC)/audiorecording-<date>.<format>` in six formats. It
  toggles, writes an `audio-recording` flag that holds its start, and
  finalises on SIGINT. It follows `screenrecord`'s supervisor and its
  stale-flag recovery, and takes `--dry-run`.
- **`bin/haseen-capture-screenrecord`** writes `date +%s` into its flag, where
  it used to write an empty file, and gains `--window`: the focused window's
  rectangle, from `hyprctl activewindow -j`.
- **`share/haseen/shell/Haseen/Flags.qml`** gains `audioRecording`,
  `recordingStart` and `audioRecordingStart`. A flag from an older recorder
  reads `""`; the clock then starts when the shell first sees the recording.
- **i18n**: 22 shell strings (one a six-form Arabic plural, "%1 controllers")
  and 6 notification strings, in English and Arabic.
- **`docs/architecture.md` §6** names the toolbar's clock as the second
  re-armed `haseen:ui-timeout`, and the controller listener as the Python that
  runs only on demand and wakes only on a press or a plug.

## Verification

- `tests/test-capture-toolbar.sh` 55/55. It covers:
  - `haseen plugin validate` and the manifest;
  - 41 `Model.js` cases under `qml`;
  - `gamepad.py` against a FIFO and a fake sysfs: presses in order, hotplug,
    a digital trigger winning over the analogue axis, unplug, and the
    permission error;
  - `audiorecord`'s dry runs, formats and sources;
  - `audiorecord`'s lifecycle with a fake ffmpeg and a stale flag;
  - an engine probe of the toolbar and its service. It walks the cursor,
    switches modes with the controller, starts a delayed capture and cancels
    it, makes a recording flag appear, and stops it with the Guide button
    through the real CLI.
- `tests/test-trigger.sh`: the flag now holds the start, and the new
  `screenrecord --window` dry run.
- `tools/lint.sh` lint OK (qmllint, the coverage check). `tools/check-docs.sh`
  OK. `tools/i18n.py check`: "catalogs fresh and complete for en, ar".
- `tests/run.sh --affected`: 97 files, 10969/10972 passed. The change touches
  `Flags.qml` and the i18n catalogs, which many suites cover. The three
  failures are `tests/test-install-picker.sh`'s build-version cases. They
  have failed on `main` since `VERSION` became the release 0.2.5 in #105
  (`20117/20120 passed` on da49e26), and #109 fixes them.
- Rendered offscreen with the owner's theme in all three modes; the controls
  are `PanelButton`s in the Theme's colours and fonts.

## Rejected options

- **Port the DMS plugin.** It has no license, so neither haseen nor the owner
  can grant the right to ship or adapt it (ADR 0002, plan 052).
- **Keep it in the compat host.** The owner asked for haseen's theme and
  naming, which a foreign plugin cannot get without its code being changed.
- **A default keybind.** The owner approves binds (plan 043). The toolbar opens
  with `haseen shell ipc panel toggle haseen.capture`, which any bind can call.
- **A bar widget for the running recording.** The bar already has the privacy
  dot. A pill that exists only while recording adds nothing to the bar the
  rest of the time.
- **The controller in the Go sidecar.** The sidecar runs for every user. A
  listener that most machines never need belongs to the plugin that uses it,
  and it is started only when its setting is on.
- **Poll `/dev/input` for hotplug.** inotify wakes the listener on a plug; a
  poll would break §6.
- **A repeating 1 s sampler for the clock.** §6 allows a repeating sampler only
  at 2 s or more. A single-shot timeout re-armed while the clock is on screen
  is the media seek bar's pattern (plan 078).
- **Pause and resume.** gpu-screen-recorder pauses on a signal, but ffmpeg has
  no pause command, so a screen recording could pause and a sound recording
  could not. Left out.
- **Record sound with `pw-record`.** It encodes through libsndfile, which has
  no AAC for M4A, and it reads one source, so desktop audio with the
  microphone would need a second process and a mix. ffmpeg gives all six
  formats and mixes two sources in one pass.
