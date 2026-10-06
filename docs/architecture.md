# haseen architecture

حصين (*haseen*): fortified, hard to breach. A clean, low-resource desktop
layered onto an existing **CachyOS** install (Arch also works; NixOS goes through
the flake). It runs on Hyprland (Lua config) with its own Quickshell shell, and
it can load DankMaterialShell and Omarchy add-ons without depending on either
project.

This file is the **contract** between the parts. When an interface changes, this
file changes in the same commit.

## 1. Requirements → where they live

| # | Requirement | Owner |
|---|---|---|
| 1 | clean | layers are opt-in; `base chaotic omarchy-repo desktop theme shell` is the whole default |
| 2 | extendable with AI | plugin manifest + JSON schema + `haseen plugin new/validate`, agent skill in `share/haseen/agents/skills/haseen/` |
| 3 | no visual clutter | shell defaults: one thin bar, no blur, no dock, no desktop widgets; everything else is a panel opened on demand |
| 4 | DMS and Omarchy add-ons | `layers/dms` (run DMS in place of the haseen shell), the compat adapters in `shell/Compat/`, and the Omarchy `colors.toml` theme format |
| 5 | not a resource hog | §6 resource rules |
| 6 | local AI | `layers/ai` (Ollama/llama.cpp bound to loopback only) + the `haseen.ai` panel plugin |
| 7 | Arch / CachyOS / NixOS | installer (CachyOS, Arch) + `flake.nix` (NixOS) |
| 8 | Secure Boot for Windows dual boot | `layers/secureboot` |

## 2. Filesystem

| Path | What | Owner |
|---|---|---|
| `bin/haseen*` | CLI (router + commands) | repo → `PREFIX/bin` |
| `share/haseen/` | everything else; `$HASEEN_PATH` at runtime | repo → `PREFIX/share/haseen` |
| `share/haseen/lib/*.sh` | `common.sh` (dry-run contract), `preflight.sh`, `packages.sh`, `layers.sh` | core |
| `share/haseen/layers/<name>/` | one directory per layer (§3) | one per slice |
| `share/haseen/default/` | defaults never edited by users (`hypr/`, `shell.json`, `ai.json`, …) | per slice |
| `share/haseen/themes/<name>/` | stock themes (Omarchy `colors.toml` format) | theme |
| `share/haseen/themed/*.tpl` | theme templates | theme |
| `share/haseen/shell/` | Quickshell config root (§5) | shell |
| `share/haseen/systemd/user/*` | user units → `PREFIX/lib/systemd/user` | per slice |
| `share/haseen/agents/skills/haseen/` | end-user agent skill | AI |
| `/var/lib/haseen/layers/<name>` | applied-layer marker | core |
| `~/.config/haseen/` | user config: `shell.json`, `ai.json`, `plugins/`, `themes/`, `hooks/` | user |
| `~/.local/state/haseen/` | `current/theme/` (rendered), `active-shell` | runtime |

`PREFIX` is `/usr/local` for the installer. When the PKGBUILD phase lands it
becomes `/usr`. Code never hard-codes either one: resolve `$HASEEN_PATH`, or use
`bin/../share/haseen`.

## 3. Layers

The contract is the header of `share/haseen/lib/layers.sh`. In short:
`layer.sh` sets `LAYER_SUMMARY`, `LAYER_REQUIRES`, `LAYER_CONFLICTS` and
`LAYER_DISTROS`, and defines `layer_status`, `layer_apply` and optionally
`layer_remove`. An optional `packages.txt` installs first. Preflight globals are
already set when the layer runs.

| Layer | Requires | Summary |
|---|---|---|
| `base` | — | essentials, firewall, snapper sanity, pacman hygiene on CachyOS |
| `chaotic` | base | Chaotic-AUR (pinned key `EF925EA6…87B78AEB`), so `aur:` entries install prebuilt |
| `omarchy-repo` | base | Omarchy's signed repo, appended last in pacman.conf: leaf packages (ttfx) prebuilt; `omarchy`/`omarchy-settings` refused (ADR 0001) |
| `desktop` | base chaotic | Hyprland (Lua), uwsm, greetd + tuigreet, portals, audio, fonts, GPU session env |
| `theme` | base | theme pipeline, the 22 Omarchy stock themes, pinned background fetch, `haseen-background.service` (swaybg) |
| `shell` | desktop theme | the haseen Quickshell shell as `haseen-shell.service` |
| `flatpak` | desktop | Flathub remote in the per-user installation; `haseen install` is Flatpak-first for apps (catalogue `share/haseen/default/catalog.json`) |
| `secureboot` | base | sbctl own keys + Microsoft + firmware keys, signing hooks, Limine config enrollment |
| `ai` | base | Ollama (or llama.cpp) on 127.0.0.1, GPU-matched backend |
| `dms` | desktop | DankMaterialShell, installed so it can be switched in for the haseen shell |
| `gaming` | desktop | Steam, gamemode, MangoHud, Proton (CachyOS gaming packages) |

Rules every layer follows:

- **Idempotent.** A re-apply converges and never duplicates anything.
- **Dry-run pure.** Every mutation goes through `run`, `run_root`, `write_root_file`, `append_root_file`, `install_root_file`, `write_user_file` or `seed_user_file`.
- **User files are seeded once** (`seed_user_file`). After that they belong to the user, and haseen-owned behaviour lives in `share/haseen/default/` and is included from the user file.
- **Never clobber system files.** Use drop-ins (`/etc/*.d/`, `pacman.d/hooks`, `limine-entry-tool.d`). There are two exceptions:
  - `ENABLE_ENROLL_LIMINE_CONFIG=yes` has to be appended to `/etc/default/limine`, because limine-entry-tool resets that key after it reads the drop-ins (`limine-common-functions:143-144`, plan 002).
  - The `chaotic` and `omarchy-repo` layers append their repository stanzas to `/etc/pacman.conf`, because pacman has no repository drop-ins (plans 023 and 024).
- **Package sources, in order** (owner decision 2026-10-04, `lib/packages.sh`):
  1. official and CachyOS repositories;
  2. Chaotic-AUR;
  3. Omarchy's `[omarchy]` repo;
  4. the AUR, only as the last resort, with a warning.

  Every `aur:` manifest entry, catalogue `"source": "aur"` app and `haseen install aur` goes through `pkg_install_aur`, which applies this order.
- **Commands are `haseen <layer> <verb>`** (`bin/haseen-<layer>-<verb>`) with the `# haseen:summary` header.

## 4. CLI conventions

- `bin/haseen-<group>-<verb>`, bash, `set -Eeuo pipefail`. Source `lib/common.sh` via `${HASEEN_PATH:-$(dirname "$(readlink -f "$0")")/../share/haseen}`.
- Metadata goes in header comments: `# haseen:summary …` and `# haseen:args …`.
- Every command takes `--help`. Mutating commands also take `--dry-run` and `--yes`.
- Exit codes: 0 ok, 1 failure, 2 usage error.

## 5. The shell (Quickshell)

`share/haseen/shell/shell.qml` runs as `qs -p $HASEEN_PATH/shell`, started by
`bin/haseen-shell-run` from `haseen-shell.service`. That unit is
`PartOf=graphical-session.target`, `Conflicts=dms.service`.

### 5.1 QML modules

- `qs.Haseen` (`shell/Haseen/`) — singletons:
  - `Theme`: tokens from `~/.local/state/haseen/current/theme/shell.json`, watched (§7).
  - `Config`: `default/shell.json` deep-merged with `~/.config/haseen/shell.json`, watched.
  - `Paths`: path constants.
  - `Plugins`: plugin registry.
- `qs.Haseen.Widgets` — shared primitives (`BarButton`, `Glyph`, `PanelSurface`, …).
- Compat modules: the code lives in `shell/Compat/{Omarchy,Dms}/`. Quickshell 0.3.1 resolves `import qs.X.Y` only to `<shell dir>/X/Y` (`qsintercept.cpp`), so six relative symlinks at the shell root expose the foreign module names: `Commons`, `Ui` (Omarchy) and `Common`, `Services`, `Widgets`, `Modules` (DMS). They are **only** for adapted plugins (§5.4). Native code never imports them, and a test enforces this.

### 5.2 Plugin manifest (`manifest.json`, schema `share/haseen/shell/plugin.schema.json`)

```json
{
  "schemaVersion": 1,
  "id": "haseen.clock",
  "name": "Clock",
  "version": "1.0.0",
  "description": "Time and date in the bar",
  "kinds": ["bar-widget"],
  "entry": { "bar-widget": "Widget.qml" },
  "settings": { "format": { "type": "string", "default": "HH:mm", "description": "Qt date format" } },
  "permissions": []
}
```

- `id`: `^[a-z0-9-]+(\.[a-z0-9-]+)+$`. Built-in plugins use `haseen.*`; user plugins use `<user>.*`.
- `kinds` (each kind needs an `entry`):
  - `bar-widget`: an `Item` placed in a bar section.
  - `panel`: an `Item` the host shows in a popup surface. Toggle it with `panel toggle <id>`. A toggle within 1.5 s of a press on a bar widget opens the popup centred under (or beside) that widget on its screen, clamped to the bar; any other toggle centres it on the bar edge of the focused screen (`share/haseen/shell/PanelPlacement.js`).
  - `service`: a non-visual object created once at startup.
  - `launcher-provider`: a `QtObject` with `prefix: string` and `function query(text): [{title, subtitle, icon, exec(): void}]`.
    Prefixes in use: `>` clipboard history (haseen.clipboard), `=` calculator (haseen.calculator).
  - `overlay`: a full-screen layer surface the plugin owns, such as OSD or lock.
- `permissions`: declarative. Values: `exec`, `network`, `network:local`, `files:read`, `files:write`, `notifications`. `haseen plugin validate` and `haseen plugin info` show them, and `network` triggers a warning. QML cannot sandbox, so this field is review metadata, not enforcement. The docs say so.
- Search order: `~/.config/haseen/plugins/<id>/`, then `$HASEEN_PATH/shell/plugins/<id>/`. The first match wins, so a user copy overrides the built-in one.
- Every entry component gets these properties:
  - `pluginId: string`
  - `settings: var` (manifest defaults merged with `shell.json` → `plugins.<id>.settings`)
  - `screen: var` (the `ShellScreen` for bar widgets and panels)

### 5.3 `shell.json`

```json
{
  "bar": { "position": "top|bottom|left|right", "height": 28, "transparent": false,
           "left": ["haseen.workspaces"], "center": ["haseen.clock", "haseen.media"], "right": ["haseen.tray", "…"],
           "overflow": [], "pinned": [] },
  "frame": { "enabled": true, "thickness": 6 },
  "plugins": { "haseen.clock": { "enabled": true, "settings": { "format": "HH:mm" } },
               "haseen.tray": { "settings": { "pinned": false } } },
  "services": ["haseen.notifications", "haseen.osd", "haseen.polkit", "haseen.idle", "haseen.lock", "…"]
}
```

`share/haseen/default/shell.json` holds the full default. `frame.radius` defaults
to `Theme.radius * 2`. Double-clicking the bar toggles `bar.transparent`: on
empty space and, as in Omarchy's bar, on a widget too (a passive `PointHandler`
over the bar, so the widget still gets both clicks), but not on the overflow
chevron or in arrange mode. The text colour then comes from
`Theme.barForeground`, which is set at runtime from the wallpaper under the
bar (`bin/haseen-bar-text-color`) and is not a theme key. Every bar widget's
normal-state text uses `Theme.barForeground`.

A bar widget that is invisible (`visible: false`, also inside an Omarchy or
DMS host) or reports `implicitWidth` 0 gets a zero-size slot: no room, no
spacing, no hover highlight and no press area.

**Tray anchor.** `haseen.tray` anchors the right section: when listed in
`bar.right` it is always drawn first there, whatever its index, and nothing is
placed before it (`Overflow.sections`). An id listed in two sections is shown
once, where it comes first (left, centre, right).

**Overflow.** When the sections do not fit the bar's length, widgets move into
a panel behind a chevron at the end of the bar (the right end, or the bottom of
a vertical bar), shown only while something is in it or the panel is open.
"Does not fit" means a side section comes within `Theme.gap` of the centred
centre section (or, with no centre, of the other side section).
`share/haseen/shell/Overflow.js` decides, and `tests/test-bar-overflow.sh`
tests it:

- `bar.overflow` ids are always in the panel, first, in their order, from any
  section. The tray never is.
- Then, automatically, the right section gives up widgets from its innermost
  end (the first after the tray) outwards; if the left section still reaches
  the centre, it gives up its innermost (last) widgets. The centre section never
  overflows on its own. `bar.pinned` ids, the tray and zero-width widgets are
  never moved automatically; `bar.overflow` wins over `bar.pinned`.
- The chevron's own length counts. A widget that left comes back only once it
  fits with `2 × Theme.gap` to spare, so a width that wobbles does not flip it.
- Each screen's bar computes its own, again whenever a widget's size, the bar's
  length or these settings change (bindings and a deferred call, no timer).

The panel (`BarOverflowPanel.qml`, lazy) slides out under the chevron, placed
by `PanelPlacement.offset`, and holds the widgets live: each one's bar slot is
moved into the panel's cell while it is open and back to a zero-size, clipped
cell in the bar when it closes, never rebuilt or hidden, so widgets keep their
state, IPC targets stay single, and a click opens their own popup as in the bar.
Its window spans the bar edge from the popups' origin, transparent and without
input outside the card, so native panels open under the widget and Omarchy
popups (`Ui/KeyboardPanel`) below the panel; the panel stays open under such a
popup and closes with it. Escape or a click outside closes it.

**Arrange mode** opens the panel (even with nothing in it) from its footer's
**Arrange**, a right click on the chevron or on empty bar space,
`haseen bar arrange` or Style › Bar › Arrange widgets in the menu. Widgets
then show an outline and take the pointer instead of the widget under it:

- a click moves a widget between the bar and the panel: `haseen bar overflow
  add` from the bar, `pin` ("keep in bar") from the panel;
- a drag moves it where it is dropped, marked by an accent line: within its
  section, to another section, onto the chevron or the panel (into
  `bar.overflow`, in front of the cell under the pointer), or out of the panel
  into the bar (out of `bar.overflow` and into `bar.pinned`). The drop is
  saved with `haseen bar move <id> <left|center|right|overflow> [--before
  <id>] [--pin]`; `Overflow.move` and `Overflow.dropTarget` hold the rule,
  and nothing ever lands in front of the tray. A drag that starts in one
  window (bar or panel) keeps the pointer until the release, so the bar maps
  the panel's coordinates onto its own;
- four edge buttons in the footer move the bar to another screen edge
  (`haseen bar position`), live, with the panel following.

Dragging works only in arrange mode: outside it every press belongs to the
widget (sliders, drags, its own popups), and a hold-to-drag gesture would have
to cancel the widget's press after the fact. A modifier gesture cannot do it
either, because Wayland only tells the client with keyboard focus about Shift,
and a bar never has it. The same edits from a terminal: `haseen bar overflow
add|remove|pin|unpin <id>`, `list`, and `haseen bar move`.

Shared state flags live in `~/.local/state/haseen/flags/<name>`; the file
existing means on. The names are `dnd`, `idle-off`, `screensaver-off`,
`nightlight`, `recording` and `gestures`. Commands write them, and QML reads
them only through the `qs.Haseen.Flags` singleton. `gestures` is written by the
`gestures` hardware quirk on a machine with a touchpad; the `haseen.gestures`
widget is listed in the default `bar.right` and takes no room without it, so
enabling it never rewrites the user's `shell.json`.

A plugin is enabled when it appears in a bar section or in `services`, and
`plugins.<id>.enabled` is not `false`. Unknown ids are skipped with one log line.
Nothing appears on screen for them.

### 5.4 Compat adapters (`shell/Compat/`)

- **Omarchy plugins** (`manifest.json` with `kinds` and `entryPoints`): bar widgets, services, panels and overlays are adapted to native registry records. The source directories `~/.config/omarchy/plugins/` and `~/.config/haseen/plugins/` are read without modifying them. Whole-bar replacements still require their original Omarchy bar host; they are not treated as slot widgets.
- Omarchy imports `qs.Ui` and `qs.Commons` provide the shared panel, keyboard, popup, control, border and theme contracts. A real scoped facade supplies dependencies, popup ownership and settings. Settings writes go atomically to **haseen's** `shell.json`, which stays the record. An accepted asynchronous mutation is not durable until `Runtime.settingsWritten(id, success)` fires.
- The one exception: Omarchy plugins may read their settings back from Omarchy's own `~/.config/omarchy/shell.json` (t1nk33r.nearby-share keeps its receiver, mode and device name there), so `updateEntryInline` of an Omarchy plugin also mirrors that plugin's own entry into that file with Omarchy's rule (its object entry in `bar.layout`, else its `plugins[]` marker, becomes `{id, ...entry}`). Only an existing file and an existing entry are touched; the write is atomic and the first one keeps `shell.json.haseen-bak`.
- A compat `KeyboardPanel` remembers the input mask the panel asked for and presents an empty one only while it is closed (fade-out). Its own empty region is never adopted as the panel's request: the `mask` binding notifies before `Component.onCompleted`, and adopting it there left every open Omarchy panel without pointer input.
- Omarchy's font family is the fontconfig `monospace` alias, and its plugins draw Nerd Font codepoints as plain text in it. So `Style.font.family` and the bar facade's `fontFamily` are `Theme.fontMono`, never the sans `Theme.fontFamily`.
- Companion services and overlays of listed Omarchy widgets start once per plugin, shared across monitors. Distinct stable `service:<id>` / `overlay:<id>` keys avoid restarting them during unrelated config edits. Initial settings, source metadata and host APIs exist before plugin completion handlers run.
- Legacy single-segment ids receive a namespace in haseen's registry (`omaconnect` → `omarchy.omaconnect`), while dependency lookups retain the original identity. Original directory names never change.
- **DMS plugins** (`plugin.json`): a `widget` surface is a bar widget (`Compat/DmsHost.qml`) and a `daemon` surface a service (`Compat/DmsServiceHost.qml`, started once like any service, with `pluginId` and `pluginService` set as DMS sets them). Other surfaces (launcher, desktop, dash) are listed as `unsupported`, and a `settings` component is not shown: haseen has no plugin settings UI. `qs.Common` / `qs.Services` / `qs.Widgets` / `qs.Modules.Plugins` provide the subset these plugins use, drawn with haseen's theme. `savePluginData` applies at once and is written to haseen's `shell.json` through `haseen plugin settings`, the Omarchy settings writer; `PluginService` global variables last as long as the shell. Layer effects (`MultiEffect` drop shadows) draw nothing in the software renderer and would hide what they wrap, so both hosts turn them off once the plugin is built (`Compat/Layers.js`). The source directory is read-only.
- Adapted records expose `compat`, `upstreamId` and `unsupported`; component errors affect that plugin alone. This is **not a sandbox**. Package prerequisites, device permissions, credentials, direct original IPC handlers and hard-coded Omarchy config/scripts remain the plugin's responsibility. Native equivalents are not assumed identical.
- Omarchy `ShellIpc` helpers negotiate one target owner and hand it to the next enabled instance on teardown. Immutable original direct `IpcHandler` children cannot be universally deduplicated by host injection. Native panels remain lazy; existing legacy inline Item bodies preserve their ids and may be eager.
- Verification compiles every original entry without activating it first. Hazardous original services are exercised only inside a read-only, offline namespace with a private home/run/dev/proc and non-activating D-Bus, never directly on the owner's account.
- **Command shims** (`shell/Compat/bin/`): `haseen shell run` (the unit and `haseen shell restart` both go through it) puts this directory first on the shell's `PATH`, so an Omarchy command a plugin process runs that would act on Omarchy's own shell or config reaches haseen instead. Each shim is one `exec` of the haseen command: `omarchy-restart-shell` → `haseen shell restart`; `omarchy-hyprland-monitor-internal-mirror` → `haseen hardware mirror-display`; `dms` (DMS plugins) → `haseen capture screenshot` for `dms screenshot` (modes and flags translated), `haseen shell ipc` for `dms ipc`, and a desktop notification for its `toast` target. Other Omarchy commands still run as installed.

### 5.5 IPC

`haseen shell ipc <target> <fn> [args]` calls `qs -p $HASEEN_PATH/shell ipc call …`.
When `~/.local/state/haseen/active-shell` contains `dms`, it hands the call to
`$HASEEN_PATH/layers/dms/ipc-translate`, so Hyprland binds work with either shell.

| target | functions |
|---|---|
| `shell` | `reload()`, `plugins(): string` |
| `panel` | `toggle(id)`, `close()` |
| `launcher` | `toggle()` |
| `menu` | `toggle(path)`; `haseen menu [path]` wraps it |
| `lock` | `lock()` |
| `notifications` | `clear()`, `toggleDnd()` (also writes the `dnd` flag) |
| `bar` | `toggle()`, `transparent(mode)`, `position(pos)`, `tray(mode)`, `overflow(verb, id)`, `move(id, to, before, pin)`, `arrange(mode)` (focused screen, session only), `status()` (with each screen's `overflow` panel and `arranging`) |
| `screensaver` | `start(style)` (`ttfx`, `native` or `default`) |
| `nightlight` | `on()`, `off()`, `toggle()`, `refresh()`, `status(): string` |
| `pager` | `count()`, `probe()`, `cards()`, `clear()`, `dnd()`, `expand()`, `snooze(minutes)`, `snoozeAll(minutes)`, `unsnooze(key)`, `snoozes()`, `codes(state)`, `open(deckKey)`, `act(identifier)`, `reply(text)`, `dismissOne()`, `dismissAll()`, `dismissShown()`, `invokeLast()`, `showHistory()`, `forgetHistory()`, `dismiss(summary)`, `recent(action)`, … (plan 025) |
| `haseen.prayers` | `refresh()`, `status()` (plan 026) |

Plugins with `settings.debugIpc` expose test-only targets named after the
plugin, for example `haseen.menu`, `haseen.launcher` and `haseen.themepicker`.
Smoke tests drive the UI through these, never through injected input.

## 6. Resource rules (enforced in review)

- Every `Timer` is marked on the line above it, and `tests/test-shell.sh` enforces both kinds. Prefer events: Hyprland IPC, PipeWire, UPower and NetworkManager D-Bus, `FileView` watches.
  - `// haseen:ui-timeout`: a single-shot UI timeout.
  - `// haseen:sample`: a repeating sampler with an interval of 2 s or more and a `running:` binding gated on visibility or enablement.
- No blur, no shaders, no wallpaper-derived colour generation at runtime. No Python in the shell path.
- Panels are `LazyLoader`s: nothing is instantiated until first open.
- Measure before claiming. `haseen doctor` prints the running shell's RSS and PSS. The idle budget is **< 200 MiB RSS, ~0 % CPU**. It was revised from an unmeasured 150 MiB after plan 005's measurement on the reference machine (Iris Xe, quickshell 0.3.1):
  - bare `qs` with an empty config: 122 MiB RSS
  - haseen default bar on the software backend: 178 MiB RSS / 126 MiB PSS, 0.01 s CPU per 60 s
  - omarchy-shell beside it: 630 MiB RSS / 554 MiB PSS

  Any change that adds more than 10 MiB idle must say so in its plan.

## 7. Themes

- **Format:** Omarchy `colors.toml` (de-facto community standard), so Omarchy themes install unchanged. The keys are `mode`, `accent`, `selection`, `muted`, `background` (+ `dark_`/`darker_`/`lighter_` variants), `foreground` (+ variants), and the eight ANSI colour names plus their `bright_` variants.
- **Rendering:** `haseen theme set <name>` renders `share/haseen/themed/*.tpl` (plus user templates in `~/.config/haseen/themed/`) into `~/.local/state/haseen/current/theme/`. App configs include those outputs with one line each.
- **Shell tokens:** `current/theme/shell.json` uses these keys:
  `mode background surface surfaceAlt foreground muted accent accentFg urgent warning success border selection fontFamily fontMono fontSize radius gap borderWidth`.
  `Theme.qml` falls back to built-in values for any key that is missing.
- **Hooks:** `~/.config/haseen/hooks/<event>` and `<event>.d/*`, run by `haseen hook run <event> [args]`. Events: `theme-set`, `post-update`, `post-boot`, `layer-applied`.
- **Backgrounds:**
  - Images are never shipped. `haseen theme fetch [NAME|--all]` downloads them from Omarchy at a pinned commit, checked against the hashes in `share/haseen/layers/theme/omarchy-assets.txt`, into `~/.cache/haseen/themes/<name>/`.
  - `haseen theme bg list|set|next` maintains `current/background`, which `haseen-background.service` (swaybg) draws.
  - Pickers on Omarchy's keys: the panels `haseen.themepicker` (SUPER + CTRL + SHIFT + SPACE, menu Style › Theme) and `haseen.background` (SUPER + CTRL + SPACE, menu Style › Background). `bg next` is SUPER + CTRL + ALT + SPACE and Style › Next background.
  - `~/.config/haseen/font` overrides `fontMono`.


## 8. Secure Boot model

- **Keys:** sbctl (version 0.17 or newer, which ships the Microsoft 2023 CAs next to the 2011 ones that expired in June 2026; sbctl commit 6df94e4) creates our own PK/KEK/db and enrolls them **together with the Microsoft and firmware-builtin keys**, so Windows, Microsoft-signed GPU option ROMs and anti-cheat (which require Secure Boot to be on) keep working.
- **Limine:** the Limine EFI binary is signed. `limine-enroll-config` embeds the hash of `limine.conf`, and every path in the config carries `#blake2b`. The fallback `EFI/BOOT/BOOTX64.EFI` is a **copy of the enrolled, signed binary**, never a separately signed raw one: Limine treats Secure Boot as inactive when no config hash is enrolled, so a signed raw fallback would boot unhashed kernels. A pacman hook (`zz-haseen-secureboot.hook`, sorted after Limine's and Omarchy's hooks and before `zz-sbctl.hook`) re-signs and re-enrolls whenever Limine, a kernel or the config changes.
- **systemd-boot / GRUB:** UKIs and the loader are signed by the sbctl pacman hook. GRUB needs `--disable-shim-lock` plus its modules embedded, which is documented as the weakest path.
- **Safety:** enrollment needs Setup Mode and a typed confirmation, and refuses if any boot file sbctl tracks is unsigned. When Windows is on the ESP, the layer prints the BitLocker warning before enrolling: changing `db` changes PCR 7, so BitLocker will ask for its recovery key once.

## 9. Login

From the bootloader to the desktop, every step is switchable on its own and the
default is the one that cannot lock you out.

- **Splash:** `haseen plymouth set` installs `share/haseen/default/plymouth/` into `/usr/share/plymouth/themes/haseen`, coloured from the current theme's `colors.toml`, adds the `plymouth` hook, puts `quiet splash` on the kernel command line through `share/haseen/lib/boot.sh`, and rebuilds the initramfs. The theme is a plymouth script that draws its own password prompt, so no images ship here. `haseen plymouth status` says which of the three preconditions is missing.
- **Greeter:** greetd starts either tuigreet (default) or `bin/haseen-greeter`, which runs a throwaway Hyprland whose config only starts `share/haseen/shell/greeter/`. Authentication is `Quickshell.Services.Greetd`; `GreeterSession.qml` holds the logic and the `greeter` IPC target, `GreeterCard.qml` only draws it, and `GreeterPalette.qml` keeps the login screen free of `qs.Haseen` singletons that read a logged-in user's files.
- **Autologin:** `haseen setup greeter autologin <user>` writes greetd's `[initial_session]`, which runs once at boot. With an encrypted root the disk password at the splash is that boot's authentication; without one, the command warns that it means no password at all.
- **Replacing another display manager:** `haseen layer apply desktop` keeps an enabled SDDM/GDM; `haseen setup greeter tuigreet|haseen` is the explicit request to replace it. It asks, installs greetd and tuigreet, disables the old unit before enabling greetd (`display-manager.service` is an alias only one unit holds), starts nothing, and prints the way back.
- **Getting back:** `sudo haseen setup greeter tuigreet && sudo systemctl restart greetd` from a TTY, which is why tuigreet stays the default.
