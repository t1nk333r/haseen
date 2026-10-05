# Shell plugins

The haseen shell is Quickshell (QML). Everything on screen, the bar widgets
included, is a plugin: a directory with a `manifest.json` and one QML file per
kind. User plugins live in `~/.config/haseen/plugins/<id>/`; built-ins in
`$HASEEN_PATH/shell/plugins/` (read-only; read them as examples).

| Kind | What it is | Entry root | Shown when |
|---|---|---|---|
| `bar-widget` | an item in a bar section | `BarButton` or any `Item` | its id is in `shell.json` `bar.left/center/right` |
| `panel` | a popup card under the bar | any `Item` with an implicit size | `haseen shell ipc panel toggle <id>` (bind a key) |
| `service` | a non-visual object created at startup | `Scope` / `QtObject` | its id is in `shell.json` `services` |
| `launcher-provider` | search results for the launcher | `QtObject` with `prefix` and `query(text)` | the launcher asks it |
| `overlay` | a full-screen layer surface it owns (OSD, lock) | `Scope` with a `PanelWindow` | the plugin decides; keep it hidden at idle |

A plugin may have several kinds (one entry file each).

## Create a plugin, step by step

Use exactly these steps. `<id>` is `<user>.<name>`: lowercase letters, digits
and dashes, at least one dot, e.g. `alice.load`. `haseen.*` is reserved.

1. **Look first.** `haseen plugin list` shows what exists;
   `haseen plugin info haseen.clock` and `$HASEEN_PATH/shell/plugins/*/` are
   working examples.
2. **Scaffold.**
   ```bash
   haseen plugin new alice.load --kind bar-widget
   ```
   This writes `~/.config/haseen/plugins/alice.load/manifest.json` and
   `Widget.qml` from `$HASEEN_PATH/shell/templates/`. (Kinds: `bar-widget`
   → `Widget.qml`, `panel` → `Panel.qml`, `service` → `Service.qml`,
   `launcher-provider` → `Provider.qml`, `overlay` → `Overlay.qml`; the
   manifest's `entry` names the file, so trust it over this list.)
3. **Edit** the QML (and the manifest's `description`, `settings`,
   `permissions`). Rules: below. Example: a load-average widget.
   ```qml
   import QtQuick
   import Quickshell.Io
   import qs.Haseen
   import qs.Haseen.Widgets

   // 1-minute load average, re-read every 10 s while the bar is visible.
   BarButton {
       id: root

       property string pluginId
       property var settings: ({})
       property var screen: null

       glyph: "\uf0e4"
       text: load.text().split(" ")[0]
       color: Theme.barForeground

       FileView {
           id: load
           path: "/proc/loadavg"
       }

       // haseen:sample
       Timer {
           interval: 10000
           running: root.visible
           repeat: true
           onTriggered: load.reload()
       }
   }
   ```
4. **Validate.**
   ```bash
   haseen plugin validate alice.load      # must print "ok: alice.load (user: …)"
   ```
   Fix every `error:` line it prints. It checks the manifest against
   `$HASEEN_PATH/shell/plugin.schema.json`, the id (must equal the directory
   name) and that each entry file exists. It does not run the QML.
5. **Enable.**
   ```bash
   haseen plugin enable alice.load
   ```
   A bar widget not yet in any section is appended to `bar.right` in
   `~/.config/haseen/shell.json`; a service is appended to `services`. To
   place it elsewhere, edit the section arrays in `shell.json` (below).
6. **Reload the shell** so it loads the new directory and QML:
   ```bash
   haseen shell ipc shell reload
   ```
7. **Verify.**
   ```bash
   haseen shell ipc shell plugins | jq '.plugins[] | select(.id == "alice.load")'
   # want: "valid": true, "enabled": true, "listed": true, "errors": []
   haseen shell ipc shell plugins | jq '.errors'      # want: []
   ```
   Then check the shell log for QML errors naming the file
   (`journalctl --user -u haseen-shell -n 50`, or
   `qs log -p "$HASEEN_PATH/shell" -t 50`), and take a screenshot
   (`grim /tmp/bar.png`) to see it render. A QML error hides only that
   plugin, never the bar.

After editing the QML of an existing plugin, run step 6 again. Edits to
`shell.json` apply live without a reload.

## The manifest

```json
{
  "schemaVersion": 1,
  "id": "alice.load",
  "name": "Load",
  "version": "1.0.0",
  "description": "1-minute load average",
  "kinds": ["bar-widget"],
  "entry": { "bar-widget": "Widget.qml" },
  "settings": {
    "label": { "type": "string", "default": "", "description": "Text before the value" }
  },
  "permissions": ["files:read"]
}
```

| Field | Rule |
|---|---|
| `schemaVersion` | `1` |
| `id` | `^[a-z0-9-]+(\.[a-z0-9-]+)+$`, equal to the directory name |
| `name`, `version`, `description` | strings |
| `kinds` | from `bar-widget panel service launcher-provider overlay` |
| `entry` | one `.qml` file per kind, relative to the plugin directory |
| `settings` | `{ name: { type, default, description } }`; type is `string number integer boolean array object` |
| `permissions` | any of `exec network network:local files:read files:write notifications` |
| `provides` | optional roles the plugin answers: `launcher`, `lock`, `notifications` |

No other top-level fields are allowed. `permissions` is review metadata
(QML cannot be sandboxed): declare honestly what the code does. `network`
(beyond localhost) makes `validate` warn; tell the user why it is needed.

## Writing the QML

- **Contract.** Every entry root declares and receives:
  `property string pluginId`, `property var settings: ({})`,
  `property var screen: null`. `settings` = the manifest defaults merged with
  `shell.json` → `plugins.<id>.settings`, and it updates live.
- **Imports.** `import qs.Haseen` (singletons `Theme`, `Config`, `Paths`,
  `Plugins`) and `import qs.Haseen.Widgets` (`BarButton`, `Glyph`,
  `PanelSurface`). Quickshell modules (`Quickshell`, `Quickshell.Io`,
  `Quickshell.Hyprland`, `Quickshell.Services.*`) are fine. Never import
  `qs.Compat.*`; that is only for adapted third-party plugins.
- **BarButton** is the bar cell: `glyph` (a Nerd Font codepoint such as
  `"\uf0e4"`), `text`, `color`, `highlighted`, signals `clicked(button)` and
  `scrolled(steps)`. Set `implicitWidth: 0` to hide the widget and give its
  slot back (the battery widget does this without a battery).
- **Theme tokens only**, never colour literals like `"#ff0000"`:
  `Theme.background surface surfaceAlt foreground muted accent accentFg urgent
  warning success border selection` (colours), `Theme.fontFamily fontMono`
  (fonts), `Theme.fontSize radius gap borderWidth` (numbers), `Theme.mode`
  (`"dark"`/`"light"`). They follow `haseen theme set` live.
- **Panels** size themselves: give the root `implicitWidth`/`implicitHeight`.
  The host draws the card, closes it on Escape or an outside click, and
  destroys the panel when it closes, so state that must survive goes in a file
  (`FileView` under `Paths.userState`).
- **Running commands**: `Process` from `Quickshell.Io` (declare `exec`), or
  `Quickshell.execDetached([...])` for fire-and-forget. Pass arguments as a
  list, never by building a shell string from user input.
- **Opening a panel from a widget**:
  `Quickshell.execDetached(["haseen", "shell", "ipc", "panel", "toggle", "alice.notes"])`.
- **A key for a panel**: in `~/.config/hypr/bindings.lua`,
  `haseen.bind("SUPER + N", "Notes", haseen.ipc("panel", "toggle", "alice.notes"))`
  (see `hyprland.md`).
- **Roles.** A service with `"provides": ["launcher"]` and a `toggle()`
  function answers `haseen shell ipc launcher toggle` (likewise `lock` →
  `lock()`, `notifications` → `clear()`, `toggleDnd()`). A panel that
  provides `launcher` is toggled by `launcher toggle`.

## Resource rules (the shell idles under 200 MiB RSS)

- No `Timer` with an interval under 2000 ms. Run timers only while visible
  (`running: root.visible`) or when the service's job needs it.
- Prefer events to polling: `Quickshell.Hyprland` (workspaces, focus),
  `Quickshell.Services.Pipewire`, `UPower`, `Quickshell.Networking`,
  `FileView { watchChanges: true }`, `SystemClock`.
- No blur, no shaders, no wallpaper-derived colours, no Python.
- Heavy things belong in a panel (created on open, freed on close), not in
  the bar.
- Check with `haseen doctor` (shell RSS) before and after; mention anything
  over ~10 MiB.

## Bar layout (`~/.config/haseen/shell.json`)

```json
{
  "bar": { "position": "top", "height": 28,
           "left": ["haseen.workspaces"], "center": ["haseen.clock"],
           "right": ["haseen.tray", "alice.load", "haseen.audio", "haseen.network", "haseen.battery"] },
  "plugins": { "alice.load": { "settings": { "label": "load" } } }
}
```

It is deep-merged over `$HASEEN_PATH/default/shell.json`: objects merge, but
**arrays replace**, so a section you set must list every widget you want in
it. Start from the effective layout in `$HASEEN_PATH/default/shell.json` plus
the user's file. `"enabled": false` under `plugins.<id>` hides a plugin
(`haseen plugin disable <id>` writes that).

## Change a built-in plugin

Copy it, keep the id, and edit the copy; the user directory wins:

```bash
cp -r "$HASEEN_PATH/shell/plugins/haseen.clock" ~/.config/haseen/plugins/
haseen shell ipc shell reload
```

`haseen shell ipc shell plugins` then shows `"origin": "user", "overrides": true`.
Delete the copy to go back to the built-in.

## Existing Omarchy plugins

Their original directory is read-only. Do not move, rewrite or remove anything
under `~/.config/omarchy/plugins/`; no Omarchy settings file is updated by haseen.
Inspect before enabling: QML plugins can start helpers or modify device state.
Native haseen plugins remain the default; imported plugins are opt-in.

```sh
haseen plugin list
haseen plugin info t1nk33r.tailscale
haseen plugin validate t1nk33r.tailscale
haseen plugin enable t1nk33r.tailscale --dry-run
```

Bar widgets, services, panels and overlays are supported. Listed legacy
widgets start their companion service/overlay once per plugin, not per screen.
`haseen shell ipc panel toggle <id>` also opens a legacy widget's nested panel.
Single-segment upstream ids are namespaced in the list (`omaconnect` becomes
`omarchy.omaconnect`), without renaming its source folder.

Compilation and an empty error list do not prove a hardware/network action
works. External prerequisites and original hard-coded config/scripts still
need attention; whole-bar replacement plugins require their original host.
Legacy inline Item bodies can be eager, so enable only the widgets you use.
Always check the source before live activation and use a protected offline
namespace when testing unknown startup behavior.

Scoped settings use `haseen plugin settings <id>` with JSON on stdin. They
preserve unrelated haseen settings and never write back to the original source.


## Remove a plugin

```bash
haseen plugin disable alice.load
rm -r ~/.config/haseen/plugins/alice.load    # ask the user first
```

Then drop its id from the `shell.json` sections and run
`haseen shell ipc shell reload`.
