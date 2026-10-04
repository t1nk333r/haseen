# Plan 018: Trigger: capture, screen recording, emoji, reminders, toggles, hardware, share, tests

## Status

- **Priority**: P1
- **Effort**: L
- **Risk**: MEDIUM
- **Depends on**: 005 010 011
- **Category**: shell
- **Planned at**: 2026-10-04, owner request (second feature round)
- **State**: PLANNED (executor: Trigger)

## Why this matters

These are the Trigger groups the owner chose. Screen recording also drives the red privacy dot.

## Execution record

**What changed** (Omarchy MIT adaptations are credited in each file header):

- **Capture.**
  - `bin/haseen-capture-screenshot`: modes region, window, output and screen. `--geometry "X,Y WxH"` skips slurp. Also takes `--edit` (satty, else swappy), `--no-save` and `--no-copy`. Files go to `$(xdg-user-dir PICTURES)`.
  - `bin/haseen-capture-screenrecord`: the same command starts and stops.
    - A detached supervisor (`setsid -f "$0" --supervise`) runs gpu-screen-recorder. It writes `flags/recording` and keeps an EXIT trap that removes the flag however the recorder ends.
    - The supervisor uses `set -m`. Without job control, bash starts background jobs with SIGINT ignored, and the stub recorder never saw the stop signal.
    - Stopping sends SIGINT to the recorder (finalises the file), then waits 5 s before KILL.
    - When a start or `--stop` finds a flag or pid file whose supervisor is dead, it removes them ("Cleared a stale recording flag").
    - Options: `--desktop-audio`/`--microphone` (one merged track), `--webcam` (mpv overlay, app-id `haseen-webcam`), `--fullscreen` and `--geometry`.
    - The region is passed as `-w WxH+X+Y`. The `-region` flag is deprecated in gsr 6.1.0, and the live run warned about it.
  - `bin/haseen-capture-text` (tesseract), `bin/haseen-capture-qr` (zbarimg with QR symbology only; `wl-copy --sensitive`; never shown in a notification) and `bin/haseen-capture-color` (hyprpicker -f).
  - text and qr also accept `--image FILE`.
- **Reminders.** `bin/haseen-reminder-{set,show,clear}`. Each reminder is a `systemd-run --user --collect --on-active=Nm` unit named `haseen-reminder-*`. The message goes in as an argument and is stored in `$XDG_RUNTIME_DIR/haseen-reminders`. `show --json` lists them for the menu.
- **Toggles.** `bin/haseen-toggle-{gaps,animations,one-window-ratio,workspace-layout}`.
  - Each writes Lua to `~/.local/state/haseen/toggles/hypr/<name>.lua` and applies it live with `hyprctl eval`. Turning one off deletes the file and runs `hyprctl reload`.
  - `toggle-bar` calls `haseen shell ipc bar toggle`.
- **Hardware.** `bin/haseen-hardware-{touchpad,touchscreen}` use `hl.device`. `laptop-display` (`hl.monitor disabled`) refuses to turn off the only active display. `mirror-display` uses `hl.monitor mirror`. All of them persist in the same directory.
  - Names are checked against a strict charset before they go into Lua.
  - `hybrid-gpu` covers status, integrated, hybrid and toggle via `supergfxctl -m`. It asks for confirmation and runs in a floating terminal. It does not install supergfxctl and does not rewrite `/etc/supergfxd.conf`.
- **Share.** `bin/haseen-share-{clipboard,file,folder,receive}` run LocalSend (the `localsend` package, else the flatpak) in a transient user unit, using `--headless send` as Omarchy does. When no path is given, a zenity chooser opens.
- **Tests.**
  - `bin/haseen-test-network` uses librespeed-cli, then speedtest-go, then speedtest-cli.
  - `bin/haseen-test-disk` uses fio, or dd with direct I/O on a mktemp file that a trap removes.
  - Both run in the floating terminal (`lib/terminal.sh`).
- `bin/haseen-transcode`: takes arguments (input, format, resolution) with defaults, or opens a zenity chooser. The output's file URI goes on the clipboard.
- `shell/plugins/haseen.emoji`: a lazy panel with a search field and a GridView. Arrow keys and Tab move the selection, Enter or a click runs `wl-copy` and closes the panel. `emojis.json` (1870 entries) and `EmojiSearch.js` come from Omarchy. The data is read by FileView only while the panel is open, and `settings.debugIpc` adds the hooks `setQuery`/`right`/`accept`/`state`.

**Evidence.**

- Lint and tests:
  - `bash -n` and shellcheck `--severity=warning -x` are clean on all shell files and the test.
  - `jq empty` passes on the JSON.
  - qmllint with the lint.sh flags reports 0 errors.
  - `tests/run.sh tests/test-trigger.sh` → 179/179. It covers:
    - dry-run plans for every command, with purity: the HOME tree is unchanged and the fakes record no calls;
    - `--help` and the summary header on every command;
    - the recording lifecycle with a stub recorder: start → flag, second call → SIGINT-finalised file and no flag;
    - a recorder SIGKILL → the trap removes the flag;
    - a supervisor SIGKILL → the flag is stale, a dry run only plans the cleanup, a real run clears it;
    - reminders with fake systemd;
    - toggle and hardware files and the eval/reload calls against a fake hyprctl, plus the guards;
    - a real qrencode → zbarimg decode, with the secret absent from stdout and notifications;
    - a real 16 MB dd disk test that leaves no files behind.
- Live smoke:
  - `capture screenshot --geometry "0,0 400x250" --no-copy` gave a correct 400x250 PNG. I viewed it and deleted it.
  - A real 2 s gsr region recording into /tmp with scratch `HASEEN_USER_STATE`: the flag existed while recording and was gone after `--stop`, and ffprobe measured 1.4 s. The file was deleted.
  - A scratch qs instance with its own `XDG_CONFIG_HOME`/`STATE`/`RUNTIME` dirs, `dbus-run-session`, idle and lock disabled, and a stub `wl-copy`:
    - `panel toggle haseen.emoji` → `loaded 1870`;
    - `setQuery heart` → 35 results;
    - `right` → current 1;
    - screenshot (viewed): a 9-column grid with the second tile highlighted;
    - `accept` → the stub received 😍 and the panel closed;
    - `.errors` → `[]`.
    The instance was killed afterwards.
- RSS: 189,028 KiB before opening, 188,628 KiB with the panel open, 188,356 KiB after closing. The panel is lazy, so it adds no idle cost.

**Rejected.**

- `wtype` emoji insertion: haseen never injects keys, so the emoji is only copied.
- `localsend-cli`: it is an interactive TUI.
- Omarchy's curl/fast.com network meter: haseen uses a real speed-test CLI instead.
- Omarchy's toggles directory, which needs a placeholder file: haseen uses a Lua include of a directory that may be missing.

**Unverified.**

- `localsend --headless send` against a real peer.
- The webcam overlay, satty/swappy, OCR on a live region, and hybrid-gpu on real hardware.
- Persistence across a reload needs the hypr include requested from Main.
