# Plan 022: Starter widgets B: clipboard history, weather, Bluetooth and Wi-Fi panels

## Status

- **Priority**: P1
- **Effort**: L
- **Risk**: MEDIUM
- **Depends on**: 005 010 011
- **Category**: shell
- **Planned at**: 2026-10-04, owner request (second feature round)
- **State**: DONE 2026-10-04. Clipboard, weather (from a fixture), and the Bluetooth and Wi-Fi panels were verified live. No real connections or radio changes were made.

## Why this matters

These are the starter plugins the owner chose.

## Execution record

### What changed

- **`haseen.clipboard`** (new; kinds service, panel and launcher-provider; provides `clipboard`):
  - `Service.qml` runs two watchers, `wl-paste --type text|image --watch cliphist -max-items N store`, which is the setup cliphist's README recommends. A missing tool exits 127 before wl-paste starts, and the plugin logs one line.
  - Sensitive copies are left to cliphist: wl-paste ≥ 2.2 sets `CLIPBOARD_STATE=sensitive` for `x-kde-passwordManagerHint` and `cliphist store` skips the copy. haseen filters no MIME types itself.
  - Each watcher runs under `setpriv --pdeathsig TERM` (util-linux), so it dies with the shell. Without it, a SIGTERMed qs left both watchers orphaned and still recording; this was observed and fixed in the smoke.
  - `History.qml`, shared by the panel and the provider:
    - lists with `cliphist list`;
    - copies back with `printf line | cliphist decode | wl-copy`;
    - deletes with `printf line | cliphist delete`.
  - `Cliphist.js` holds the pure parsing and filtering.
  - `Panel.qml`:
    - search box (every word must match, case-insensitive);
    - arrows to move, Enter or a click to copy and close;
    - Delete or the trash button to remove an entry.
  - Image entries show a thumbnail. It is decoded only for visible ListView rows into `$XDG_RUNTIME_DIR/haseen-clipboard/`, and the directory is removed when the panel closes.
  - `Provider.qml` serves the `>` prefix in the launcher.
  - Debug hook `haseen.clipboard`: `search`, `select`, `copy`, `remove`, `refresh`, `state`.
- **`haseen.weather`** (new; kinds service, bar-widget and panel; provides `weather`):
  - The service runs `curl -fsS --max-time 15 https://wttr.in/<location>?format=j1` from a Process. A `// haseen:sample` Timer refetches every 30 min. Location and units changes also trigger a fetch or a re-parse.
  - Offline or a bad answer keeps the last good data and logs nothing.
  - It is a service, so one fetch serves every screen's bar.
  - The service exists only while the plugin is enabled. "Off by default" is shell.json `plugins.haseen.weather.enabled: false`, which is an integration request below.
  - `Weather.js` is the pure parser (current conditions plus 3 days) and the day/night glyph table, adapted from Omarchy's `bin/omarchy-weather-icon` (MIT).
  - The bar widget shows the glyph and the temperature, and takes no room until data exists. The panel shows current conditions and a 3-day forecast.
  - Debug hook `haseen.weather`: `loadFixture(path)`, `refresh`, `state`. With `debugIpc` on, automatic fetching stops, so a smoke never contacts wttr.in.
- **`haseen.bluetooth`** (new; bar-widget and panel; `Quickshell.Bluetooth`, which exists in 0.3.1: `/usr/lib/qt6/qml/Quickshell/Bluetooth/quickshell-bluetooth.qmltypes`):
  - The bar glyph is off, on or connected, with `implicitWidth: 0` when there is no adapter. Right click toggles power, after the owner's `t1nk33r.tailscale` convention.
  - The panel has:
    - a power toggle;
    - paired devices (connect/disconnect, battery when `batteryAvailable`);
    - nearby named devices with Pair or Cancel (trusted first).
  - Discovery starts when the panel opens (or the adapter turns on) and stops in `Component.onDestruction`.
  - The debug hook is read-only (`state`).
- **`haseen.network`** (extended):
  - The widget colour is `Theme.barForeground` and a click opens the new panel.
  - `Panel.qml` shows:
    - wired devices (connected with link speed, cable unplugged, or disconnected);
    - a Wi-Fi on/off switch (shows "Blocked" under rfkill);
    - the strongest N networks (default 8), connected and saved first.
  - Clicking a network acts as follows:
    - connected: disconnect;
    - saved or open: connect;
    - secured and new: one password field below the list, which submits with `connectWithPsk`. It sits outside the rows because scans rebuild the sorted rows and would drop typed text.
  - `connectionFailed` shows the reason, and NoSecrets or an auth timeout re-prompts for the password.
  - The scanner runs only while the panel is open, stopped in `Component.onDestruction`.
  - Debug hook: `state` and `prompt(name)` (opens the password field only).
- Bar widgets open their panel with `qs ipc --pid <Quickshell.processId> call panel toggle <id>`. There is no in-process panel API, and `--pid` keeps the call on this instance.
- `tests/test-widgets-b.sh` and the fixture `tests/fixtures/wttr/j1.json` (a real wttr.in Berlin answer from 2026-10-04, trimmed to the fields used). The test covers:
  - manifests, kinds and roles;
  - no hex literals; bar widgets never use `Theme.foreground`;
  - exactly one Timer, a gated `haseen:sample` at 1800000 ms;
  - scanning only from panels, with a stop on destruction;
  - read-only debug hooks; the watcher command;
  - Weather.js on the fixture (metric, imperial, night, offline HTML, empty answer, glyph table, URL) and Cliphist.js, both under `/usr/lib/qt6/bin/qml`.

### Evidence

- `tests/run.sh tests/test-widgets-b.sh`: 59/59 passed.
- qmllint with the `tools/lint.sh` flags on the 4 plugin dirs: 0 errors.
- `jq empty` on all 4 manifests and the fixture.
- shellcheck 0.11.0 `--severity=warning -x` and `bash -n` on the test: clean.
- `haseen plugin validate` passes all four; only weather warns about `network`.
- Scratch instance with its own XDG_CONFIG/STATE/CACHE/RUNTIME_DIR, symlinked hypr and wayland sockets, `dbus-run-session`, and idle and lock disabled:
  - **Clipboard.** The owner's clipboard was saved first (an empty text/plain) and restored afterwards.
    - Copied two texts and a 64×64 grim PNG with `wl-copy`. `cliphist list` showed ids 1-3.
    - Panel screenshot: the image thumbnail and both texts.
    - IPC `search second` returned one row; `remove` left 2 entries in `cliphist list`.
    - `select 1; copy` made `wl-paste` print `haseen smoke: hello clipboard`, closed the panel, and removed the thumbnail directory.
    - `wl-copy --sensitive` was not recorded.
    - In the launcher, `>hello` returned the entry (screenshot).
    - After `kill <qs pid>` no watcher survived (with setpriv).
  - **Weather.** `loadFixture tests/fixtures/wttr/j1.json` (no network call; `state` showed `updated: 0` before the call). The bar showed the cloud glyph and 19° (screenshot). The panel showed Berlin, 19°C, and the 3 days with rain chances (screenshot).
  - **Bluetooth.** The panel opened over IPC (screenshot: power On, 3 nearby devices; the owner has no paired devices).
    - `Adapter1.Discovering` was false before opening, true while open, and false after `panel close`.
    - With `DBUS_SYSTEM_BUS_ADDRESS` pointing at nothing: "No Bluetooth adapter." and "NetworkManager is not running." (screenshots).
  - **Wi-Fi.** The panel opened over IPC (screenshot: wired "Cable unplugged" plus 12 networks, before the default became 8).
    - `prompt <secured network>` showed the password field; nothing was submitted.
    - NM `LastScan` did not change over 45 s closed, and changed within 45 s open.
    - No connection was made or dropped and no radio was toggled. nmcli shows the same active connection.
- Idle RSS on the same scratch setup, 25 s after load: 161.1 MiB baseline (clock and network only) → 163.7 MiB with the 4 plugins plus both services and weather data loaded, so +2.6 MiB. qs PSS was 102.6 MiB. Each wl-paste watcher is 2.1 MiB RSS.

### Rejected

- **A `Binding` on `discovering`/`scannerEnabled`:** destroying the Binding did not restore the value. The live check showed discovery still on after the panel closed, so start and stop are explicit.
- **Per-screen fetch in the weather widget:** it would make one request per monitor. A service with a role makes one.
- **A password field inside each Wi-Fi row:** scan updates re-sort the rows and recreate them, which loses typed text.
- **Right click toggles Wi-Fi:** an accidental click drops the connection. Bluetooth got the right click only.

### Not verified

- The bar widgets' mouse clicks (no pointer injection allowed). The exact command they run, `qs ipc --pid <pid> call panel toggle haseen.network`, opened the panel.
- The bar's hidden state without an adapter: an owner notification covered that region in the screenshot. The code path is `implicitWidth: adapter ? contentWidth : 0`.
- Pairing, connecting, Wi-Fi password submit and the power toggles (forbidden on the owner's machine).
- A real wttr.in fetch through the service (only the fixture, deliberately). The fixture itself came from one manual curl.
- Vertical bars: the widgets rely on Frame's BarButton `vertical` handling.
