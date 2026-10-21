# haseen architecture

حصين (*haseen*): fortified, hard to breach. A clean, low-resource desktop
layered onto an existing **CachyOS** install (Arch also works; NixOS is not
supported). It runs on Hyprland (Lua config) with its own Quickshell shell, and
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
| 7 | Arch / CachyOS | installer (CachyOS, Arch); NixOS is detected and refused |
| 8 | Secure Boot for Windows dual boot | `layers/secureboot` |
| 9 | CapsLock as a hyper key (opt-in) | `haseen setup keyd on`: keyd from `extra`, `share/haseen/default/keyd/default.conf` → `/etc/keyd/default.conf` (a different one is backed up), hold = `SUPER + SHIFT + ALT + CTRL`, tap = Escape |
| 10 | Brightness (plan 077) | `haseen brightness`: backlights and `*::kbd_backlight` via brightnessctl (logind), DDC/CI monitors via ddcutil (bus map cached in `$XDG_CACHE_HOME/haseen/ddc-displays.tsv`); `haseen setup ddc on` (opt-in) installs ddcutil and loads i2c-dev; the `haseen.display` panel (off) slides each device |
| 11 | optional VAPT workstation environment, no AUR or tool execution | `layers/vapt`, 25 explicit group manifests and owned native environments (plans 007, 087) |

## 2. Filesystem

| Path | What | Owner |
|---|---|---|
| `bin/haseen*` | CLI (router + commands) | repo → `PREFIX/bin` |
| `share/haseen/omarchy/` | haseen's answer to every Omarchy command but the Apple ones (§5.4, plan 093): `commands.tsv`, `dispatch`, `lib.sh`, `bin/omarchy*` | repo → `PREFIX/share/haseen`; `bin/*` linked into `PREFIX/bin` |
| `share/haseen/` | everything else; `$HASEEN_PATH` at runtime | repo → `PREFIX/share/haseen` |
| `share/haseen/lib/*.sh` | `common.sh` (dry-run contract), `preflight.sh`, `packages.sh`, `layers.sh` | core |
| `share/haseen/layers/<name>/` | one directory per layer (§3) | one per slice |
| `share/haseen/default/` | defaults never edited by users (`hypr/`, `shell.json`, `ai.json`, …) | per slice |
| `share/haseen/themes/<name>/` | stock themes (Omarchy `colors.toml` format) | theme |
| `share/haseen/themed/*.tpl` | theme templates | theme |
| `share/haseen/shell/` | Quickshell config root (§5) | shell |
| `share/haseen/systemd/user/*` | user units → `PREFIX/lib/systemd/user` | per slice |
| `share/haseen/seeds/NN-<name>.sh` | one user-config seed each: defines `seed_main`, declares `# haseen:seed <path>\|<description>`; `bin/haseen-seed-user` runs them in name order | per slice |
| `share/haseen/default/applications/mimeapps.list` | vendor default handlers → `PREFIX/share/applications/mimeapps.list` (lowest XDG precedence, so the user always wins) | desktop |
| `share/haseen/default/xdg-terminal-exec/` | terminal preference → `PREFIX/share/xdg-terminal-exec/` | desktop |
| `share/haseen/branding/` | haseen's marks (§11): `<mark>/{mark,symbolic,symbolic-24,wordmark}.svg` and `logo-<mark>.txt` | shell |
| `share/haseen/sidecar/` | compiled helpers built into the tree by `tools/build-sidecar.sh`, never tracked: `haseen-sidecar` and `haseen-palette` (Go, `core/`), `wootingd` (Rust, `core/wootingd/`, plan 099) | build |
| `share/haseen/default/applications/*.desktop` | desktop entries (the `dms://` link handler, `haseen plugin url`) → `PREFIX/share/applications` | shell |
| `share/haseen/agents/skills/haseen/` | end-user agent skill | AI |
| `/var/lib/haseen/layers/<name>` | applied-layer marker | core |
| `/etc/pacman.d/hooks/50-haseen-omarchy.hook` | the Omarchy package guard (§5.4, plan 101), from `share/haseen/default/omarchy-guard/`; fires only when `omarchy` or `omarchy-settings` is installed or upgraded | base |
| `PREFIX/lib/systemd/user/omarchy-migrate-notify.service.d/haseen.conf` | silences Omarchy's own pending-migration notice (plan 101) | repo → installed with the user units |
| `~/.config/haseen/` | user config: `shell.json`, `ai.json`, `plugins/`, `themes/`, `hooks/` | user |
| `~/.local/state/haseen/` | `current/theme/` (rendered), `active-shell`, `dotfiles-backup/<timestamp>/` (files `haseen setup dotfiles` replaced), `rc-include` (the rcs `haseen seed user` added its include line to, one path per line) | runtime |
| `~/.local/share/haseen/extensions/cairn/<version>/` | Cairn's release `.crx`, downloaded and checked; Helium installs it from `~/.config/net.imput.helium/External Extensions/<id>.json` (plan 073) | shell |

`PREFIX` is `/usr/local` for the installer. When the PKGBUILD phase lands it
becomes `/usr`. Code never hard-codes either one: resolve `$HASEEN_PATH`, or use
`bin/../share/haseen`.

## 3. Layers

The contract is the header of `share/haseen/lib/layers.sh`. In short:
`layer.sh` sets `LAYER_SUMMARY`, `LAYER_REQUIRES`, `LAYER_CONFLICTS` and
`LAYER_DISTROS`, and defines `layer_status`, `layer_apply` and optionally
`layer_remove`. A layer that needs its own arguments sets `LAYER_PICKABLE=false`
so the install picker never offers it (`vapt`: its groups come from
`./install.sh --vapt-groups`). An optional `packages.txt` installs first.
Preflight globals are already set when the layer runs.

| Layer | Requires | Summary |
|---|---|---|
| `base` | — | essentials, firewall, snapper sanity, pacman hygiene on CachyOS, the Omarchy package guard hook (§5.4) |
| `chaotic` | base | Chaotic-AUR (pinned key `EF925EA6…87B78AEB`), so `aur:` entries install prebuilt |
| `omarchy-repo` | base | Omarchy's signed repo, appended last in pacman.conf: leaf packages (ttfx) prebuilt, and the only source of `omarchy:` entries (herdr, xdg-terminal-exec); `omarchy`/`omarchy-settings` refused (ADR 0001) |
| `desktop` | base chaotic | Hyprland (Lua), uwsm, greetd + tuigreet, portals, audio, fonts, GPU session env |
| `theme` | base | theme pipeline, the 22 Omarchy stock themes plus haseen's own `haseen` (the default), pinned background fetch, `haseen-background.service` (swaybg) |
| `shell` | desktop theme | the haseen Quickshell shell as `haseen-shell.service`; Helium (`aur:helium-browser-bin`) with the Cairn extension, its release `.crx` fetched at a pinned SHA-256 and handed over as a per-user external extension (`lib/cairn.sh`, `haseen setup cairn`, plan 073) |
| `flatpak` | desktop | Flathub remote in the per-user installation; `haseen install` is Flatpak-first for apps (catalogue `share/haseen/default/catalog.json`) |
| `secureboot` | base | sbctl own keys + Microsoft + firmware keys, signing hooks, Limine config enrollment |
| `ai` | base | Ollama (or llama.cpp) on 127.0.0.1, GPU-matched backend |
| `dms` | desktop | DankMaterialShell, installed so it can be switched in for the haseen shell |
| `gaming` | desktop | Steam, gamemode, MangoHud, Proton (CachyOS gaming packages) |
| `vapt` | — | explicit owner tool groups (plus the oniomarchy-category groups of plan 087), checked binary/native sources (the private oniomarchy source only per operation, last), passive PATH and the optional shared COAE Python environment; dependency-only packages are never roots; no assessment execution or service activation (plans 007, 087) |
| `mobile` | desktop | phones: KDE Connect (with its ufw ports), scrcpy, adb, MTP, and the iOS stack (usbmuxd, libimobiledevice, gvfs-afc/gphoto2); `ifuse` refused while the repos ship the data-corrupting 1.2.0 (plan 040) |

Rules every layer follows:

- **Idempotent.** A re-apply converges and never duplicates anything.
- **Dry-run pure.** Every mutation goes through `run`, `run_root`, `run_polkit` (pkexec, for a command started from the desktop with no terminal for sudo), `write_root_file`, `append_root_file`, `install_root_file`, `write_user_file`, `replace_user_file` (atomic, for a file an application reads while it runs) or `seed_user_file`.
- **User files are seeded once** (`seed_user_file`). After that they belong to the user, and haseen-owned behaviour lives in `share/haseen/default/` and is included from the user file. Nothing appends to or edits a user file after seeding, with one exception (owner, 2026-10-08, plan 038): `haseen seed user` appends one line sourcing `share/haseen/default/shell/init.sh` to `~/.bashrc`, and to `~/.zshrc` if it exists, once per rc. `~/.local/state/haseen/rc-include` records it, so a line the user deletes is never added back; the seed never changes or removes a line. The optional VAPT layer seeds only its owned link `~/.config/haseen/vapt/shell.sh` and never edits `~/.bashrc`/`~/.zshrc`. When no rc sources the link, it prints the line the user may add (plan 087).
- **Never clobber system files.** Use drop-ins (`/etc/*.d/`, `pacman.d/hooks`, `limine-entry-tool.d`). These exceptions are necessary:
  - `ENABLE_ENROLL_LIMINE_CONFIG=yes` has to be appended to `/etc/default/limine`, because limine-entry-tool resets that key after it reads the drop-ins (`limine-common-functions:143-144`, plan 002).
  - The `chaotic` and `omarchy-repo` layers append their repository stanzas to `/etc/pacman.conf`, because pacman has no repository drop-ins (plans 023 and 024). The optional VAPT layer appends a reviewed BlackArch stanza the same way, and only after its reviewed upgrade commits (plan 007).
- **Package sources, in order** (owner decision 2026-10-04, `lib/packages.sh`):
  1. official and CachyOS repositories;
  2. Chaotic-AUR;
  3. Omarchy's `[omarchy]` repo;
  4. the AUR, only as the last resort, with a warning.

  Every `aur:` manifest entry, catalogue `"source": "aur"` app and `haseen install aur` goes through `pkg_install_aur`, which applies this order.
  An `omarchy:` manifest entry (desktop's herdr and xdg-terminal-exec, owner 2026-10-08), and the catalogue's `"source": "omarchy"` herdr, comes from `[omarchy]` alone; `pkg_install_omarchy` skips it with a warning when that repo is not enabled or does not list it, and never builds it (plan 024 amendment).
  `PKG_DENY` (`omarchy`, `omarchy-settings`) is refused as a target, and `pkg_guard_closure` asks before any install whose `pacman -Sp` closure brings either in; `--yes` accepts that only for the catalogue's `flea` (plan 037).
  VAPT keeps its own order as an explicit exception (owner decision,
  2026-10-13): explicit repository pins, BlackArch, pinned native adapters,
  already-enabled Chaotic-AUR, CachyOS, then Arch. It differs because it
  reproduces the source policy of the owner's waydots security inventory,
  which consults BlackArch before the general repositories (`docs/vapt.md`),
  and it has no Omarchy or AUR tier at all. Each tier matches only the
  tool's name or a reviewed alias, checked against any canonical upstream
  identity; a Provides line counts only through such a reviewed identity,
  and only after every tier's name. Its dedicated transaction path
  excludes AUR/Omarchy dependencies, reports unavailable items, and never runs
  the tools it installs. oniomarchy's repository is an opt-in, per-operation,
  x86_64-only last tier (`--with-oniomarchy`, `haseen vapt repo-*`) whose
  stanza stays in haseen's root state and VAPT's own configuration, never
  `/etc/pacman.conf`; it keeps `Required DatabaseRequired`, admits only 52
  reviewed names, is never a base vendor, and its key import into the shared
  pacman keyring is global (plan 087). See `docs/vapt.md` for its trust, environment, and
  limited owned-link removal contracts. It does not require the desktop or
  default layers.
  Plan 088 adds a separate read-only installed workflow: `workflow.py` reuses
  plan 087's metadata for provenance/native state and discovers actual owned files,
  not guessed commands. `vapt tool-list`, JSON status/doctor and `vapt menu`
  execute no listed tool. Explicit `tool-help` needs owned documentation or a
  reviewed help-only argv; `tool-run` shows that usage then opens an ordinary
  shell, never the selected tool. The optional Security surface requires literal
  merged `enabled: true`, without bar/service insertion. Feature workflow
  defaults are seeded once on explicit provisioning, never by observation.
  Explicit service actions select only reviewed package/unit bindings and
  separately require unique package provenance, owned non-template units and current
  `FragmentPath`, rechecking at the root gateway; no enable/preset/init path.
  Local helpers use reviewed owned adapters and loopback defaults; a server or
  non-loopback listener needs consent at an interactive terminal (`--yes`
  cannot give it). HTTP pins descriptors, serves bytes only and answers 421 to
  a request whose Host is not local; the file helper serves one owned file. CA
  trust requires a typed fingerprint, immutable public bytes, an owned updater
  and a journal that records the certificate. Failed or interrupted updates
  expose `anchor.transaction` and `unknown` state; retry or removal revalidates
  under the root lock, foreign or modified anchors remain refusals, and only
  updater success completes recovery (plan 090). Observation never changes
  trust or launches a proxy/browser.
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

Recovery (plan 061): one crash restarts the shell (`RestartMode=direct`).
Four failures within 60 s reach the start limit, and the unit's
`OnFailure=` starts `haseen-shell-recover.service`, which runs
`haseen shell recover present` (`bin/haseen-shell-recover`). It matches
the tail of the shell's journal against every plugin's directory and id. A
plugin that is not built in beats a built-in, and a later mention beats an
earlier one. It records the failure and the suspect in
`~/.local/state/haseen/recovery/last-failure.json`. Then a floating terminal
offers four choices: disable the suspect, safe mode, restore the last good
`shell.json`, or start the shell as it is. Each fix starts the failed unit
again. A second Quickshell config was rejected for the offer: whatever
stopped the shell may stop it too. `haseen-crash-watch.service` asks
`haseen shell recover snapshot` every 5 minutes. That copies `shell.json`
to `recovery/last-good.json` once the shell has been active for 10 minutes
(`HASEEN_SHELL_HEALTHY_MINUTES`) and the file has not changed for as long,
but never while safe mode is on.

Spawning (plan 074): whatever qs starts lands in `haseen-shell.service`'s
cgroup, and the unit's `KillMode=control-group` kills it on every restart.
An app that moves itself into its own scope (Chromium, Helium) leaves the
`cat` readers of its stdout/stderr behind, and the restart breaks its pipes.
So every user-facing app, terminal or menu action goes through `Apps.launch`
(`qs.Haseen`), which execs it in its own scope as `haseen.launch` does in
Hyprland: `uwsm-app --` in a uwsm session, else
`systemd-run --user --scope --slice=app-graphical.slice` as
`app-haseen-<id>-<random>.scope`, else the bare argv. `Apps.launchEntry`
runs a desktop entry's `command` without field codes, in `$TERMINAL -e`
for `Terminal=true`. `Quickshell.execDetached` and `Process` remain for the
shell's own helpers: `qs ipc`, `wl-copy`, `haseen` CLI writes, probes.

### 5.1 QML modules

- `qs.Haseen` (`shell/Haseen/`) — singletons:
  - `Theme`: tokens from `~/.local/state/haseen/current/theme/shell.json`, watched (§7).
  - `Config`: `default/shell.json` deep-merged with `~/.config/haseen/shell.json`, watched.
  - `Paths`: path constants.
  - `Plugins`: plugin registry.
  - `Branding`: the selected mark and its file paths (§11).
  - `Sidecar`: the connection to haseen-sidecar (§5.6).
  - `BorderWipe`: holds the `borderwipe` subscription while the theme asks for a wipe (§5.6, §7).
  - `Apps`: starts user apps outside the shell's cgroup (§5, plan 074).
  - `Keyboard`: the keyboard layout from one `hyprctl -j devices` read plus Hyprland's `activelayout` event, and the lock-key reader (plans 079, 080).
  - `ClockDayName`: pure date-format handling shared by the `haseen.clock` widget and calendar panel.
  - `SecurityRoute`: the one-shot page/item hand-off from the menu's Security rows to the optional `haseen.security` panel (plan 088); `shell/Haseen/SecurityEvidence.js` validates the VAPT CLI's JSON for both, so neither plugin imports the other's files.
- `qs.Haseen.Widgets` — shared primitives (`BarButton`, `Glyph`, `PanelSurface`, `BrandImage`, …).
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
  "settings": {
    "format": { "type": "string", "default": "HH:mm", "description": "Qt date format" },
    "showDayName": { "type": "boolean", "description": "Unset follows the date format" }
  },
  "permissions": []
}
```

- `id`: `^[a-z0-9-]+(\.[a-z0-9-]+)+$`. Built-in plugins use `haseen.*`; user plugins use `<user>.*`.
- `kinds` (each kind needs an `entry`):
  - `bar-widget`: an `Item` placed in a bar section.
  - `panel`: an `Item` the host shows in a popup surface. Toggle it with `panel toggle <id>`. A toggle within 1.5 s of a press on a bar widget opens the popup centred under (or beside) that widget on its screen, clamped to the bar; any other toggle centres it on the bar edge of the focused screen (`share/haseen/shell/PanelPlacement.js`).
  - `service`: a non-visual object created once at startup.
  - `launcher-provider`: a `QtObject` with `prefix: string` and `function query(text): [{title, subtitle, icon, exec(): void}]`.
    Prefixes in use: `>` clipboard history (haseen.clipboard), `=` calculator (haseen.calculator); off by default (plan 081): `@` windows (haseen.windows, `hyprctl dispatch` focus), `:` emoji (haseen.emojisearch, haseen.emoji's list, wl-copy), `/` menu commands (haseen.commands, MenuModel.js leaves; a `when`/`disabled` row only once its guard answered, from the menu's cache or one batch per open) and `?` web search (haseen.websearch, http(s) `url` template, `xdg-open` through `Apps.launch`, no request from the shell). The empty launcher lists the enabled prefixes.
  - `overlay`: a full-screen layer surface the plugin owns, such as OSD or lock.
- `permissions`: declarative. Values: `exec`, `network`, `network:local`, `files:read`, `files:write`, `notifications`. `haseen plugin validate` and `haseen plugin info` show them, and `network` triggers a warning. QML cannot sandbox, so this field is review metadata, not enforcement. The docs say so.
- `requires` (plan 064): `{ "bins": ["cmd"], "tools": ["cmd-or-package"], "layers": ["gaming"], "haseen": "0.2.0" }`, all optional. Unlike `permissions` it is enforced: while a `bins` command is not on PATH, a `tools` name is neither a command nor an installed package (or provider, `pacman -T`), a layer is not applied (`/var/lib/haseen/layers/<name>`) or haseen's `VERSION` is older (major.minor.patch only, so `0.1.0-dev` satisfies `0.1.0`), the plugin is not valid and nothing loads it. Other plugins are unaffected. A `tools` name that no repository knows (`pacman -Si` fails, e.g. Debian's `pulseaudio-utils`) cannot be checked and counts as met. `haseen plugin validate`/`list`/`info` show a refused plugin as `unmet` with the reason (`share/haseen/shell/lib/plugin.sh` `plugin_unmet`); the shell (`Haseen/Plugins.qml` with `Haseen/Requires.js`) probes the facts in one `bash` run per new set, puts the same messages in its plugin errors and sends one notification when a host asks for a refused plugin. The facts are probed again when a plugin directory appears or goes, and on `haseen shell ipc shell reload`. DMS `dependencies` (and its deprecated `requires`) map to `tools`, dropping entries that are not plain names; Omarchy manifests have no requirement field, so an Omarchy plugin may carry haseen's `requires` object as is (an array is read as `tools`).
- Search order: `~/.config/haseen/plugins/<id>/`, then `$HASEEN_PATH/shell/plugins/<id>/`. The first match wins, so a user copy overrides the built-in one.
- Every entry component gets these properties:
  - `pluginId: string`
  - `settings: var` (manifest defaults merged with `shell.json` → `plugins.<id>.settings`)
  - `screen: var` (the `ShellScreen` for bar widgets and panels)
- Credentials (plan 097): a plugin never keeps a token, API key or password
  in `shell.json`, which is configuration and may be shared. `haseen.todoist`
  and `haseen.omarr` keep theirs in a 0600 file in a 0700 directory under
  `$XDG_STATE_HOME/haseen/<name>/` (or upstream's legacy directory, used in
  place so stored secrets are never copied), and hand them to curl through a
  pipe or a 0600 header file, never an argv.
- `haseen.security` (plan 088) is explicitly off in shipped `shell.json`,
  panel-only and lazy. Its read-only `Read.qml` processes consume the CLI's
  versioned evidence; `Haseen/SecurityEvidence.js` validates their schemas and
  `Model.js` builds fixed verb/argv shapes, not a second ownership or
  privilege policy. `haseen.menu` keeps its static
  provider map: Security rows use fixed enable/package guards and one exact
  panel-toggle action. Internal typed page/item roles transfer one consumed
  in-memory selection through `SecurityRoute`, never shell source or a
  dynamic contribution registry.
  Every action goes through `Apps.launch`; previews use Process argv only.
  Service argv includes the displayed unit/FragmentPath expectations; the CLI
  checks them before terminal consent and revalidates again before the root
  gateway. Detached launch has no completion contract: Refresh/reopen only,
  no polling, optimistic success, persisted addresses/drafts or settings writer.
  Identical menu guard expressions share one result per finite batch. The
  menu answers the enablement guard `haseen vapt menu --enabled` from the
  shell's own plugin flag without running it; the CLI itself reads
  configuration without loading provisioning or local-action modules.
  Disabled Security providers still read no inventory.
- Safe mode (plan 061): while `~/.local/state/haseen/safe-mode` exists (JSON `{reason, since}`; `haseen shell recover safe-mode on|off`), `Plugins.held(id)` is true for every plugin whose origin is not `builtin` (user, user:omarchy, user:dms, omarchy, dms). A held plugin has no `entryUrl` and `Config.isEnabled` is false for it, so the running shell unloads it without a restart. A user copy of a built-in id gives way to the built-in. `shell plugins` over IPC reports `held` per plugin and a `safeMode` object. `haseen shell run` creates the state directory, because a `FileView` watch needs its parent to exist.

### 5.3 `shell.json`

```json
{
  "bar": { "position": "top|bottom|left|right", "height": 28, "transparent": false,
           "left": ["haseen.workspaces"], "center": ["haseen.clock", "haseen.media"], "right": ["haseen.tray", "…"],
           "overflow": [], "pinned": [] },
  "frame": { "enabled": true, "thickness": 6 },
  "branding": { "mark": "kufic|shield|gate" },
  "plugins": { "haseen.clock": { "enabled": true, "settings": { "format": "HH:mm" } },
               "haseen.tray": { "settings": { "pinned": false } } },
  "services": ["haseen.notifications", "haseen.osd", "haseen.polkit", "haseen.idle", "haseen.lock", "…"]
}
```

`share/haseen/default/shell.json` holds the full default. `frame.radius` defaults
to `Theme.radius * 2`. Windows and the menu round to the same radius (plan 046).
The menu binds `Config.frameRadius`, the frame's own rule, so it follows a
`frame.radius` edit at once. `haseen theme set` resolves the same rule and
writes it as Hyprland's `decoration.rounding` in `current/theme/rounding.lua`,
which `init.lua` loads with the defaults: toggles, hyprmod and the user's files
still override it, and the theme's own `rounding` is dropped. A change to
`frame.radius` reaches the windows at the next `haseen theme set`. Double-clicking the bar toggles `bar.transparent`: on
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

**Nook** (plan 095). `haseen.nook` (off by default), placed in a bar section,
is the panel's opener instead of the chevron: the panel opens under it
(`Bar.toggleOverflowFrom`), the chevron shows only in arrange mode, the nook's
length replaces the chevron's in the fit, and `Overflow.fit`'s `never` keeps
it out of the panel, `bar.overflow` included. It takes no room while the panel
would be empty.

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
add|remove|pin|unpin <id>`, `list`, and `haseen bar move`. A widget that is
in no section yet goes in with `haseen bar add <id> <left|center|right>
[--before <id>]`, which turns the plugin on when it was off and refuses a
widget already in the bar.

Shared state flags live in `~/.local/state/haseen/flags/<name>`; the file
existing means on. The names are `dnd`, `idle-off`, `screensaver-off`,
`nightlight`, `recording` and `gestures`. Commands write them, and QML reads
them only through the `qs.Haseen.Flags` singleton. `gestures` is written by the
`gestures` hardware quirk on a machine with a touchpad; the `haseen.gestures`
widget is listed in the default `bar.right` and takes no room without it, so
enabling it never rewrites the user's `shell.json`.

Settings live in **six** stores, and `share/haseen/lib/settings.sh` is the map
over all of them (`haseen settings list`, `haseen settings set <key> [value]`,
plan 045). The split is deliberate and the index does not change it:
`shell.json` is the user's hand-edited document (a plugin's settings fall back
to its manifest's defaults); other one-value files under `~/.config/haseen`
(the mono font) are each owned by one command; `flags/` is session state a
command must be able to flip several times an hour without rewriting a config
file; `~/.local/state/haseen/toggles/hypr/*.lua` is Lua because Hyprland reads
Lua; other `~/.local/state/haseen` files hold the theme name, the active shell
and the remembered power profile; `~/.config/uwsm/env.d/60-haseen-defaults` is
read by uwsm before anything could read `shell.json`. `haseen settings set`
owns no state: it `exec`s the command that already owns the key. Each row says
what that command takes, so on/off always mean the setting as listed (`gaps
off` runs `haseen toggle gaps on`, the no-gaps mode), and a key an editor owns
takes no value.

Runtime contexts (plan 062): `haseen context normal|focus|game|present`
switches several of those flags as one. Entering from normal records them in
`~/.local/state/haseen/context/saved`; leaving sets every one back to that
record, and a second context replaces the first against the same record. The
flag `context` holds the active name (absent = normal) and is read through
`Flags.context`; only the command writes it. Game also writes
`toggles/hypr/context-game.lua` and applies it live, and restores the
animations, blur and shadow values it read with `hyprctl getoption`. The
optional game watcher is the `haseen.indicators` service, listed only by
`haseen context auto-game on|set`.

Idle (`haseen.idle`, plans 019, 082) runs one ext-idle-notify monitor per
non-zero timeout: `screensaverAfter`, `lockAfter`, `dpmsAfter` and
`suspendAfter` (0 = never, the default), which runs `haseen system suspend`.
`onBattery` holds any of those four and wins while UPower's `onBattery` is
true; a plug event recreates only the monitors whose timeout changed, and a
monitor replaced while idle keeps its idle state (displays stay off). Every
timeout is held at 2147483 s: Quickshell's IdleMonitor turns a longer one
into 0 ms. The
`idle-off` flag (Stay Awake, the game and present contexts) removes every
monitor, and the suspend monitor always honours Wayland idle inhibitors.
Hyprland counts only inhibitors on windows, not on layer-shell surfaces.
`haseen setup idle` (Setup › Idle and Suspend) prints and sets the timeouts.
`haseen screen off|on` (plan 084) is the manual DPMS switch, from the menu
(System) and the battery panel too: off waits `--delay` (1000 ms) so the
releasing click or key cannot wake the displays. haseen.idle sends `dpms.on`
only for an off it made itself (`_dpmsOff`), so it never undoes a manual off;
its lock and dpms monitors keep counting from the last input.

A plugin is enabled when it appears in a bar section or in `services`, and
`plugins.<id>.enabled` is not `false`. Unknown ids are skipped with one log line.
Nothing appears on screen for them.

### 5.4 Compat adapters (`shell/Compat/`)

- **Omarchy plugins** (`manifest.json` with `kinds` and `entryPoints`): bar widgets, services, panels and overlays are adapted to native registry records. The source directories `~/.config/omarchy/plugins/` and `~/.config/haseen/plugins/` are read without modifying them. Whole-bar replacements still require their original Omarchy bar host; they are not treated as slot widgets.
- Omarchy imports `qs.Ui` and `qs.Commons` provide the shared panel, keyboard, popup, control, border and theme contracts. A real scoped facade supplies dependencies, popup ownership and settings. Settings writes go atomically to **haseen's** `shell.json`, which stays the record. An accepted asynchronous mutation is not durable until `Runtime.settingsWritten(id, success)` fires.
- Qt 6.12 added a QtQuick `Color` singleton, and it wins every bare `Color.` whatever the import order, even over a real module imported after QtQuick. So compat files read the palette as `Commons.Color.<role>` (`import qs.Commons as Commons`), as Omarchy 4.0.6 does, and `tests/test-compat.sh` holds it statically and in the engine. A plugin's own bare `Color.` reads QtQuick's singleton (undefined roles) under Qt 6.12. haseen cannot redirect it without editing the plugin, so its author must qualify it (plan 092).
- The one exception: Omarchy plugins may read their settings back from Omarchy's own `~/.config/omarchy/shell.json` (t1nk33r.nearby-share keeps its receiver, mode and device name there), so `updateEntryInline` of an Omarchy plugin also mirrors that plugin's own entry into that file with Omarchy's rule (its object entry in `bar.layout`, in any of Omarchy 4.5's sections `left`, `centerBegin`, `center`, `centerEnd`, `right` and `tray`, else its `plugins[]` marker, becomes `{id, ...entry}`). Only an existing file and an existing entry are touched; the write is atomic and the first one keeps `shell.json.haseen-bak`.
- A compat `KeyboardPanel` remembers the input mask the panel asked for and presents an empty one only while it is closed (fade-out). Its own empty region is never adopted as the panel's request: the `mask` binding notifies before `Component.onCompleted`, and adopting it there left every open Omarchy panel without pointer input.
- Omarchy's font family is the fontconfig `monospace` alias, and its plugins draw Nerd Font codepoints as plain text in it. So `Style.font.family` and the bar facade's `fontFamily` are `Theme.fontMono`, never the sans `Theme.fontFamily`.
- Companion services and overlays of listed Omarchy widgets start once per plugin, shared across monitors. Distinct stable `service:<id>` / `overlay:<id>` keys avoid restarting them during unrelated config edits. Initial settings, source metadata and host APIs exist before plugin completion handlers run.
- Legacy single-segment ids receive a namespace in haseen's registry (`omaconnect` → `omarchy.omaconnect`), while dependency lookups retain the original identity. Original directory names never change.
- **DMS plugins** (`plugin.json`): a `widget` surface is a bar widget (`Compat/DmsHost.qml`) and a `daemon` surface a service (`Compat/DmsServiceHost.qml`, started once like any service, with `pluginId` and `pluginService` set as DMS sets them). A `desktop` surface is an overlay (`Compat/DmsDesktopHost.qml`, below). Other surfaces (launcher, dash) are listed as `unsupported`, and a `settings` component is not shown: haseen has no plugin settings UI. `qs.Common` / `qs.Services` / `qs.Widgets` / `qs.Modules.Plugins` provide the subset these plugins use, drawn with haseen's theme. `savePluginData` applies at once and is written to haseen's `shell.json` through `haseen plugin settings`, the Omarchy settings writer; `PluginService` global variables last as long as the shell. Layer effects (`MultiEffect` drop shadows) draw nothing in the software renderer and would hide what they wrap, so both hosts turn them off once the plugin is built (`Compat/Layers.js`). The source directory is read-only.
- DMS bar widgets beyond the basics: a widget's `popoutContent` opens in `Compat/Dms/Modules/Plugins/PluginPopout.qml`, a popup of the bar window drawn as a haseen panel card, centred on the widget and `Theme.gap` off the bar; its height follows the content, the content exists only while it is open, and `Compat.Runtime.requestPopout` keeps one popout or panel open at a time (a click outside, Escape or the widget again closes it). `PluginService` plugin state (`loadPluginState`/`savePluginState`) is one JSON file per plugin, `~/.local/state/haseen/plugins/<DMS id>_state.json`, written atomically at every change, so the save a plugin makes while the shell tears it down is kept. `Proc.runCommand` runs a plugin's command unchanged: haseen neither rewrites nor blocks a state-changing one (`tlp`, `pkexec`), which is the plugin's to make. `BatteryService` reads UPower and changes nothing. `PopoutService.openSettingsWithTab(page)` opens the haseen panel of the same subject (`network*` → `haseen.network`, audio, theme, wallpaper, notifications) and otherwise logs once.
- DMS desktop widgets, startup checks and services: the surface map is `widget` → bar-widget, `daemon` → service, `desktop` → overlay; `launcher` and `dash` stay unsupported. `Compat/DmsDesktopHost.qml` gives each chosen screen a bottom-layer window (`Compat/DmsDesktopWindow.qml`) holding its own instance of the plugin's component. DMS places widget instances by dragging in an edit mode; haseen has one instance per enabled plugin, placed by `shell.json` `plugins.<id>.settings.desktop` `{ x, y, anchorX, anchorY, width, height, screens }`: x/y are offsets from the anchored edge (`start`, `center`, `end`), without them the widget is centred, without width/height it takes the plugin's `defaultWidth`/`defaultHeight` (`Compat/DesktopGeometry.js`), and `screens` lists output names (absent or `["all"]`: every screen). A manifest `startupCheck` runs through `Compat/DmsStartupGate.qml` before any host of the plugin loads it: once per plugin however many hosts ask, a pass is remembered for the life of the shell, and a refusal (`done("msg")` or `{ title, details }`) keeps the plugin unloaded, is reported through `Plugins.reportError` and a notification, and is checked again on the next request. `qs.Services` adds `DgopService` (system figures from haseen-sidecar's `sysusage` stream, the sampler haseen.sysusage uses), `MprisController`, `CavaService` (cava while a `qs.Common.Ref` holds it), `WeatherService` (the reading of the `weather` role provider; no request of its own) and a read-only `DMSNetworkService` (Quickshell's NetworkManager binding; no control functions).
- Adapted records expose `compat`, `upstreamId` and `unsupported`; component errors affect that plugin alone. This is **not a sandbox**. Package prerequisites, device permissions, credentials, direct original IPC handlers and hard-coded Omarchy config/scripts remain the plugin's responsibility. Native equivalents are not assumed identical.
- Omarchy `ShellIpc` helpers negotiate one target owner and hand it to the next enabled instance on teardown. Immutable original direct `IpcHandler` children cannot be universally deduplicated by host injection. Native panels remain lazy; existing legacy inline Item bodies preserve their ids and may be eager.
- Verification compiles every original entry without activating it first. Hazardous original services are exercised only inside a read-only, offline namespace with a private home/run/dev/proc and non-activating D-Bus, never directly on the owner's account.
- **Command shims** (`shell/Compat/bin/`): `haseen shell run` (the unit and `haseen shell restart` both go through it) puts this directory, then `share/haseen/omarchy/bin`, first on the shell's `PATH`. `dms` (DMS plugins) → `haseen capture screenshot` for `dms screenshot` (modes and flags translated), `haseen shell ipc` for `dms ipc`, and a desktop notification for its `toast` target. `ydotool` (DMS on-screen keyboards) is not an `exec`: `ydotool key CODE:STATE …` becomes Hyprland `send_key_state` dispatches (key code + 8, modifiers held between calls in `$XDG_RUNTIME_DIR/haseen`) aimed at the active window of the shell's own Hyprland instance, because haseen runs no root `ydotoold` and gives nothing `/dev/uinput`; it takes `--dry-run`, and other ydotool commands go to a real ydotool further down `PATH`.
- **Omarchy's commands** (`share/haseen/omarchy/`, plan 093; plans 052, 057 and 060 began it as shell shims): every command Omarchy 4.0.6 ships (`omarchy` and 445 `omarchy-*`) except the Apple-hardware ones has an answer here, so Omarchy plugins, keybinds, habits and Omarchy's own scripts reach haseen. `commands.tsv` records each one as `name<TAB>kind<TAB>target<TAB>note`, kind one of:
  - `shim`: `bin/<name>` links to `dispatch`, which `exec`s the haseen command in `target` (`omarchy-update` → `haseen update`);
  - `translate`: a script mapping Omarchy's arguments, verbs or output onto a haseen command (`omarchy-notification-send`, `omarchy-menu`, `omarchy-toggle-idle`, `omarchy-shell` onto `haseen shell ipc`);
  - `port`: Omarchy's script adapted under MIT, its state, paths and branding haseen's (hardware probes, window helpers, `omarchy-launch-shell`);
  - `refuse`: a link to `dispatch`, which prints `<name>: not available under haseen.`, the note (why) and `The haseen way: <target>` (`No haseen equivalent: …` for a target of `none: …`) and exits 1: Omarchy's behaviour would break a haseen rule (ADR 0001's `pacman.conf`, mirrorlist, HOOKS, Limine and SDDM; `PKG_DENY`; the package order) or belongs to Omarchy's own install, release or development machinery;
  - `inert`: nothing to do under haseen; one line on stderr, exit 0;
  - `apple`: recorded, not provided.

  `lib.sh` finds haseen from the script's own location (they run from `/usr/local/bin` with no `HASEEN_PATH`) and sources `lib/common.sh`, so every change honours `--dry-run`. `bin/omarchy` routes `omarchy a b` to the longest `omarchy-a-b…`, with Omarchy's aliases, and `omarchy commands` lists what each does here. `install.sh` links every `bin/<name>` into `PREFIX/bin` as `../share/haseen/omarchy/bin/<name>`, ahead of an installed Omarchy's `/usr/bin` copies; a file there that is not that link is never replaced, and `--uninstall-tree` removes only the links. An Omarchy-seeded `~/.config/uwsm/env` can prepend `$OMARCHY_PATH/bin` to the session's `PATH`, so the desktop layer's `~/.config/uwsm/env.d/10-haseen` (sourced after it) and the shell init (`default/shell/init.sh`) put `share/haseen/omarchy/bin` first; `haseen doctor` checks the compositor's `PATH` (from Hyprland's `/proc/<pid>/environ`) and the terminal's, and fails when another directory's `omarchy-launch-shell` comes first. Shell restarts never start Omarchy's shell: `omarchy-launch-shell` (where Omarchy's own `omarchy-restart-shell` ends, through `hyprctl dispatch exec_cmd`) and `omarchy-restart-shell` stop any Quickshell instance of `$OMARCHY_PATH/shell` and start or restart the desktop shell haseen uses (`haseen-shell.service`, or `dms.service` after `haseen shell use dms`); `omarchy-update` is `haseen update`. `omarchy-battery-status [--shell]` → `haseen battery status` (plan 060): the charge-limit window comes from `charge_control_*_threshold`, not UPower's fixed 75-80% default. `haseen battery limit set|off|save|restore` writes and records it in `/etc/haseen/charge-limit`; `haseen setup battery-limit on` (opt-in, laptops only) installs `haseen-charge-limit.service` and a system-sleep hook to restore it. Absolute-path calls (`/usr/bin/omarchy-*`, `$OMARCHY_PATH/bin/…`, Omarchy's own units) still run Omarchy's copies; their inner calls by name reach haseen. `haseen doctor` reports whose commands come first on `PATH` and an Omarchy shell running beside haseen's.
- **Omarchy's own packages** (plan 101, `share/haseen/lib/omarchy-guard.sh`). On a machine that keeps `omarchy` and `omarchy-settings`, two absolute paths matter: `/usr/bin/omarchy-migrate` and Omarchy's own `/usr/bin/omarchy-update` (which runs it right after its pacman transaction) run Omarchy's migrations, which edit Limine, the owner's plugin directory, fcitx5 and haseen's packages; and `omarchy-settings`' install scriptlet copies `Theme=omarchy` over `/etc/plymouth/plymouthd.conf`. So:
  - every migration the package ships is recorded as done in Omarchy's own ledger (`~/.local/state/omarchy/migrations/<name>.sh`, or `$OMARCHY_MIGRATION_STATE`): `haseen migrate omarchy` for the user, the migration `1792605416-seal-omarchy-migrations.sh` once, and the base layer's pacman hook `50-haseen-omarchy.hook` after every transaction that installs or upgrades either package, which runs `haseen omarchy guard` as root: the seal for each login account with `~/.local/state/haseen`, through `runuser` as that user, and `plymouth-set-default-theme haseen` when haseen's splash is installed and the file names Omarchy's. The hook sorts before the initramfs and Limine hooks, so an initramfs built in the same transaction embeds haseen's splash;
  - Omarchy's machine fixes the seal skips have haseen equivalents or need none: its polkit-1 repair is the migration `1792605417-polkit-faillock.sh`; the sysctl apply-now migrations only apply files that boot applies anyway;
  - `omarchy-migrate-notify.service` (absolute `ExecStart`, so haseen's answer to that name never ran) runs `/usr/bin/true` through a drop-in installed with the user units;
  - `haseen doctor` reports unsealed migrations, a missing hook, Omarchy's splash over haseen's, and every enabled Omarchy user unit (`omarchy-*`, `bt-agent`, OWE's `owed`), with what to do.

### 5.5 IPC

`haseen shell ipc <target> <fn> [args]` calls `qs -p $HASEEN_PATH/shell ipc call …`.
When `~/.local/state/haseen/active-shell` contains `dms`, it hands the call to
`$HASEEN_PATH/layers/dms/ipc-translate`, so Hyprland binds work with either shell.

| target | functions |
|---|---|
| `shell` | `reload()`, `plugins(): string` |
| `panel` | `toggle(id)`, `close()` |
| `launcher` | `toggle()` |
| `menu` | `toggle(path)`; `haseen menu [path]` wraps it. `select(request): string`: the card as a pick list (plan 071) on a JSON request file `{prompt, options, selectionFile, doneFile, width, height}`; the choice goes to `selectionFile`, then one line to the caller's FIFO `doneFile`, also when nothing was chosen; answers the shell's PID. `haseen menu select` wraps it |
| `lock` | `lock()` |
| `notifications` | `clear()`, `toggleDnd()` (also writes the `dnd` flag) |
| `bar` | `toggle()`, `transparent(mode)`, `position(pos)`, `tray(mode)`, `overflow(verb, id)`, `move(id, to, before, pin)`, `arrange(mode)` (focused screen, session only), `status()` (with each screen's `overflow` panel and `arranging`) |
| `screensaver` | `start(style)` (`ttfx`, `native` or `default`) |
| `nightlight` | `on()`, `off()`, `toggle()`, `refresh()`, `status(): string` |
| `pager` | `count()`, `probe()`, `cards()`, `clear()`, `dnd()`, `expand()`, `snooze(minutes)`, `snoozeAll(minutes)`, `unsnooze(key)`, `snoozes()`, `codes(state)`, `open(deckKey)`, `act(identifier)`, `reply(text)`, `dismissOne()`, `dismissAll()`, `dismissShown()`, `invokeLast()`, `showHistory()`, `forgetHistory()`, `dismiss(summary)`, `recent(action)`, … (plan 025) |
| `haseen.prayers` | `refresh()`, `status()` (plan 026) |
| `osd` | `lockkeys()`: read Caps/Num Lock once and show a change (the default `code:66`/`code:77` release binds call it; plan 079), `state(): string` |

Plugins with `settings.debugIpc` expose test-only targets named after the
plugin, for example `haseen.menu`, `haseen.launcher` and `haseen.themepicker`.
Smoke tests drive the UI through these, never through injected input.

### 5.6 haseen-sidecar

`core/` builds `haseen-sidecar` into `share/haseen/sidecar/` (`tools/build-sidecar.sh`). `qs.Haseen.Sidecar` (`shell/Haseen/Sidecar.qml`) starts it on demand and talks JSON lines over `$XDG_RUNTIME_DIR/haseen/sidecar.sock` (`core/internal/proto`). The daemon greets with its capabilities, runs a stream only while some client subscribes to it, and exits 5 minutes after its last client leaves. `haseen sidecar status` (`bin/haseen-sidecar`) shows the binary, the socket and the border wipe's state.

| stream | what | subscriber |
|---|---|---|
| `sysusage` | CPU, memory, GPU, processes (plan 032) | the haseen.sysusage widget, the DMS `DgopService` |
| `borderwipe` | turns the active border's gradient for a theme that asks (§7, plan 069) | `qs.Haseen.BorderWipe`, while the theme's `colors.toml` has `border_wipe` |

Methods: `subscribe`/`unsubscribe` (with `stream`), `capabilities`, `status` (answers `{"borderwipe": {state, reason, secondsPerTurn, angle, frames}}`), `shutdown`.

The border wipe loop (`core/internal/borderwipe`) is a port of the owner's `hypr-border-wipe` from luna. Each frame is one `eval hl.config(...)` on Hyprland's request socket (connect, send, receive, close), built in a reused buffer, with no process started. Frames run at most 10 a second, a degree each at 36 s a turn. Its states:

- `off`: nobody subscribed, or the theme asks for no wipe.
- `waiting`: Hyprland is not answering. It retries every 2 s and reconnects when the socket returns. A shell started after a Hyprland restart subscribes with the new instance's signature.
- `native`: Hyprland's `borderangle` leaf loops. The loop stands aside, so the two never run together.
- `paused`: the `game` context (`flags/context`), `animations:enabled` false, or no window focused. The first two are read every 2 s; focus and reloads come from Hyprland's event socket.
- `running`.

A reload that hands the border back (a theme without the wipe, or one that `borderangle` turns) after frames went out gets one more `reload`, so that a late frame cannot keep the old gradient.

### 5.7 wootingd (plan 099)

haseen has two compiled languages: Go for `core/` (§5.6) and Rust for
`core/wootingd/`, the daemon the owner wrote for the t1nk33r.wooting plugin,
vendored by owner decision (2026-10-21) with its behaviour unchanged.
`tools/build-sidecar.sh` builds it with `cargo build --release --locked`
in a target directory outside the tree (`$CARGO_TARGET_DIR`, else
`$XDG_CACHE_HOME/haseen/wootingd-target`) and installs the binary as
`share/haseen/sidecar/wootingd`. Without a working cargo, or when the build
fails, it says so and skips it, like the Go part without go: the daemon
serves one off-by-default plugin and never stops an install.
`HASEEN_REQUIRE_CARGO=1` makes that an error. Its
one dependency is `parking_lot`; no Wooting SDK is linked. CI installs
`rust` and runs its 49 unit tests (`tests/test-wootingd.sh`).

- **One owner.** Only one process may hold a Wooting keyboard's vendor
  command interface (HID usage page 0xFF55; 0x1337 on standard firmware).
  wootingd is that process; everything else asks it over
  `$WOOTINGD_SOCKET`, else `$XDG_RUNTIME_DIR/wootingd.sock`, one verb line in
  and one JSON line back (`share/haseen/lib/wooting.sh`). It refuses to start
  beside a live socket.
- **Device-gated.** `haseen setup wooting on` installs
  `/etc/udev/rules.d/70-wootingd.rules` (`share/haseen/default/udev/`) and
  `~/.config/systemd/user/wootingd.service` with `ExecStart` set to the
  installed daemon (`share/haseen/default/systemd/`). The rule tags the
  keyboard (vendor 31e3) `uaccess` and `systemd` and pulls the unit in with
  `SYSTEMD_USER_WANTS`; the unit `BindsTo=` the keyboard's device unit and is
  never enabled. So wootingd runs only while a Wooting is attached, and
  removes its socket on SIGTERM.
- **Resource profile: a recorded exception to §6.** The daemon is vendored
  unchanged (owner, 2026-10-21, plan 099), so §6's 2 s floor does not hold
  inside it. While it runs:
  - one thread reads the active profile every 1.5 s, which is one HID round
    trip, and the profile list every 30 s (`core/wootingd/src/main.rs:50`,
    `:202`, loop at `:917`);
  - a second thread owns the analog interface for the daemon's whole life,
    whether or not anyone subscribed (`main.rs:459`, spawned at `:940`).
    - It blocks in `poll(2)` for at most 250 ms (`ANALOG_READ_TIMEOUT_MS`,
      `main.rs:443`), so an idle keyboard wakes it about 4 times a second.
    - While keys move, every analog report, up to 1 kHz, is decoded and given
      to the Fn-layer learner (`fnmap.observe`, `main.rs:528`). Broadcasts
      are coalesced to at most 60 a second, and the learned map is written
      to disk only on a release that taught it something.
    - While the interface is absent it retries every 1.5 s (`ANALOG_RETRY`,
      `main.rs:445`).

  The shell side never polls. The 250 ms read timeout only bounds how fast
  an unplug is noticed, so the owner could raise it later.
- **Coexistence.** The owner's t1nk33r.wooting plugin installs the same two
  names. haseen keeps them and takes them over: one rule wants one unit name,
  the name resolves to one file, and the user's unit directory outranks the
  system ones, so the keyboard starts one daemon. `on` saves the plugin's
  copies to `~/.local/state/haseen/wooting/replaced-<time>/` first, removes
  its old always-on `default.target.wants` link, and restarts the one unit;
  it refuses a file of either name that is neither haseen's nor the
  plugin's. `off` removes only haseen's copies.
- **The shell side.** `haseen.wooting` (off by default) has no HID code and
  no timer but a bounded 2 s connect retry: it watches the socket file
  through `FileView` (inotify), so with no keyboard it takes no room and does
  nothing. The panel lists the stored profiles; its keyboard drawing opens
  the shell's analog subscription only while it is shown, and receives at
  most 60 frames a second, coalesced by the daemon. The daemon reads the
  analog interface whether or not anyone subscribed (above).
- **Commands.** `haseen wooting` (status, get, list, set, analog, fn) and
  `haseen wooting doctor` use exit codes beyond §4's: 3 daemon not
  reachable, 4 no keyboard, 5 dependency missing.

## 6. Resource rules (enforced in review)

- Every `Timer` is marked on the line above it, and `tests/test-shell.sh` enforces both kinds. Prefer events: Hyprland IPC, PipeWire, UPower and NetworkManager D-Bus, `FileView` watches.
  - `// haseen:ui-timeout`: a single-shot UI timeout. One is re-armed as a clock: the `haseen.media` panel's seek bar emits `positionChanged()` once a second while the panel is open and the player plays (plan 078); the panel is freed on close, and a tick makes no D-Bus call.
  - `// haseen:sample`: a repeating sampler with an interval of 2 s or more and a `running:` binding gated on visibility or enablement.
- No blur, no shaders, no wallpaper-derived colour generation at runtime. No Python for shell startup or polling. The optional Security panel invokes its Python workflow only for finite, explicit reads and actions (§3), never as a background sampler.
- Panels are `LazyLoader`s: nothing is instantiated until first open.
- The border wipe (§7) is the one continuous animation. Its sidecar loop draws at most 10 frames a second, with one socket round trip and no process per frame. While it is paused or off, no frame is drawn. Plan 069 measured it at 36 s a turn: 0.27 % of a core for haseen-sidecar and 1.67 % for Hyprland. Hyprland's native `borderangle` loop at 10 s a turn redraws at the refresh rate and cost 6.9 %. haseen-sidecar holds 12 MiB RSS.
- Measure before claiming. `haseen doctor` matches the shell by canonicalizing absolute `qs -p` paths and resolving relative ones against that process's working directory; equivalent path spellings are recognized. It also prints the running shell's RSS and PSS. The idle budget is **< 200 MiB RSS, ~0 % CPU**. It was revised from an unmeasured 150 MiB after plan 005's measurement on the reference machine (Iris Xe, quickshell 0.3.1):
  - bare `qs` with an empty config: 122 MiB RSS
  - haseen default bar on the software backend: 178 MiB RSS / 126 MiB PSS, 0.01 s CPU per 60 s
  - omarchy-shell beside it: 630 MiB RSS / 554 MiB PSS

  Any change that adds more than 10 MiB idle must say so in its plan.

## 7. Themes

- **Format:** Omarchy `colors.toml` (de-facto community standard), so Omarchy themes install unchanged. The keys are `mode`, `accent`, `selection`, `muted`, `background` (+ `dark_`/`darker_`/`lighter_` variants), `foreground` (+ variants), and the eight ANSI colour names plus their `bright_` variants.
- **Rendering:** `haseen theme set <name>` renders `share/haseen/themed/*.tpl` (plus user templates in `~/.config/haseen/themed/`) into `~/.local/state/haseen/current/theme/`. App configs include those outputs with one line each.
- **Default:** `haseen` (`THEME_DEFAULT` in `theme-lib.sh`) is haseen's own theme, derived from HANCORE's Greek Noir (MIT) with the owner's "akane" border wipe; the theme layer sets it for a user who has none. Renamed stock themes are aliases (`THEME_ALIASES`): `haseen theme set greek-noir-akane` and a `theme.name` of `greek-noir-akane` resolve to `haseen` with a one-line notice, and `haseen` also finds backgrounds in `~/.config/haseen/backgrounds/greek-noir-akane/`. The migration `1791356361-theme-haseen.sh` renames `theme.name` and moves that folder to `backgrounds/haseen/`, only for a user whose current theme is `greek-noir-akane` (plan 066).
- **Border wipe:** a theme may ask for the active border's gradient to turn clockwise with two `colors.toml` keys: `border_wipe` (the stops, `rgba(RRGGBBAA)`, `rgb(RRGGBB)` or `0xAARRGGBB`, space-separated) and `border_wipe_seconds` (one turn). The `haseen` theme declares four orange stops at 36 s, the pace of the owner's loop on luna. Its `hyprland.lua` reads both keys from the `colors.toml` beside it. Up to 10 s a turn it enables Hyprland's `borderangle` animation in `loop` style, at speed = seconds × 10, with the built-in `linear` curve. Hyprland 0.56 refuses a speed above 100. Slower than that, it turns `borderangle` off and haseen-sidecar's `borderwipe` loop does the turning (§5.6). Either way a theme switch carries the wipe along, and the two never run together. Hyprland starts the native loop when a window maps, so windows that were already open before a reload into a ≤ 10 s pace stay still until they are reopened (plan 069).
- **Neovim:** in a LazyVim or haseen.nvim config, `haseen theme set` links `~/.config/nvim/lua/plugins/theme.lua` to `current/theme/neovim.lua` when it is missing or links to an Omarchy or haseen theme (a file of the user's stays), plus `haseen-theme-hotreload.lua` and `haseen-all-themes.lua` from `share/haseen/default/nvim/`. lazy.nvim's change detection sees the new spec and fires `User LazyReload`, and the hot-reload applies its colourscheme in running nvims. While Omarchy's `omarchy-theme-hotreload.lua`/`all-themes.lua` are there, haseen's twins are not added; `haseen import omarchy` moves them to `<file>.bak-<timestamp>` (plan 058).
- **haseen.nvim:** haseen's Neovim config is the owner's plain lazy.nvim config, fetched rather than shipped. `haseen setup nvim` (`bin/haseen-setup-nvim`) clones it at a pinned commit (`NVIM_REPO_URL`, `NVIM_COMMIT`) into `~/.config/nvim` and links `share/haseen/default/nvim/haseen-colorscheme.lua` into its `lua/plugins/`. That bridge disables the theme spec's `LazyVim/LazyVim` entry and applies its colourscheme on `User LazyDone`; its presence is what makes `haseen theme set` link a config that is not LazyVim. A first install runs it with `--if-absent`; an existing config is replaced only with `--replace`, after it moves to `~/.config/nvim.bak-<timestamp>` (plan 065).
- **Shell tokens:** `current/theme/shell.json` uses these keys:
  `mode background surface surfaceAlt foreground muted accent accentFg urgent warning success border selection fontFamily fontMono fontSize radius gap borderWidth`.
  The window corner radius is not a token: it is the frame's inner radius (`frame.radius`, else twice `radius`), which the menu reads from `Config.frameRadius` and `haseen theme set` gives Hyprland as `decoration.rounding`, so the menu rounds like the windows, as Omarchy's does (plans 068, 046).
  `Theme.qml` falls back to built-in values for any key that is missing; they are the `haseen` theme's rendered `shell.json`, so a missing file still looks like the default.
- **Hooks:** `~/.config/haseen/hooks/<event>` and `<event>.d/*`, run by `haseen hook run <event> [args]`. Events: `theme-set`, `post-update`, `post-boot`, `layer-applied`.
- **Generated themes:** two commands turn an image into an ordinary user theme (`~/.config/haseen/themes/<name>/colors.toml` plus the image as its background), on demand only. `haseen theme wallpaper` uses haseen's own extractor (`haseen-palette`, plan 034). `haseen theme generate` runs matugen (Material You, an optional package called as a program with `--json hex --dry-run` and haseen's `share/haseen/layers/theme/matugen.toml`). It maps the Material roles onto `colors.toml` keys and takes the ANSI hues from matugen custom colours. Foreground, accent and selection are held to plan 064's contrast floors, and a theme of the user's own is never overwritten. Its panel `haseen.themegen` (image strip, scheme, dark/light, swatches and a mock desktop, Save/Apply; menu Style › Theme Generator) is off by default (plan 067).
- **Wallhaven** (plan 072): `haseen wallhaven search|get|random` (`share/haseen/lib/wallhaven.sh`) call the Wallhaven API v1 with curl (https only, timeouts, haseen's User-Agent).
  - SFW (purity 100) unless the user keeps an API key in `~/.config/haseen/wallhaven.key` (mode 600); the key travels only in an `X-API-Key` header file, never in an argv, URL or log.
  - A local count keeps to the API's 45 calls a minute.
  - Thumbnails are cached in `~/.cache/haseen/wallhaven/thumbs` (a week unused, 600 files at most).
  - `get` saves `~/.config/haseen/backgrounds/wallhaven/<id>.<ext>` only from wallhaven's image host, announced and sniffed as JPEG/PNG/WebP, at most 50 MiB and the size the API gave.
  - `haseen.themegen` has a source switch (My wallpapers | Wallhaven). Its `WallhavenGrid.qml` searches, pages when scrolled to the end and downloads the pick, which then previews and applies through `haseen theme generate` like a local image.
- **Backgrounds:**
  - Images are never shipped. `haseen theme fetch [NAME|--all]` downloads them from Omarchy at a pinned commit, checked against the hashes in `share/haseen/layers/theme/omarchy-assets.txt`, into `~/.cache/haseen/themes/<name>/`.
  - `haseen theme bg list|set|next` maintains `current/background`, which `haseen-background.service` (swaybg) draws.
  - Pickers on Omarchy's keys: the panels `haseen.themepicker` (SUPER + CTRL + SHIFT + SPACE, menu Style › Theme) and `haseen.background` (SUPER + CTRL + SPACE, menu Style › Background). `bg next` is SUPER + CTRL + ALT + SPACE and Style › Next background.
  - `~/.config/haseen/font` overrides `fontMono`.


## 8. Secure Boot model

- **Keys:** sbctl (version 0.17 or newer, which ships the Microsoft 2023 CAs next to the 2011 ones that expired in June 2026; sbctl commit 6df94e4) creates our own PK/KEK/db and enrolls them **together with the Microsoft keys, always, and the firmware's built-in keys when the firmware has them**, so Windows, Microsoft-signed GPU option ROMs and anti-cheat (which require Secure Boot to be on) keep working. `--firmware-builtin` is passed only when the `dbDefault` and `KEKDefault` efivars exist: sbctl aborts the whole enrollment when either is missing (plan 002, decision 7). Without them, setup warns and runs `sbctl enroll-keys --microsoft`.
- **Limine:** the Limine EFI binary is signed. `limine-enroll-config` embeds the hash of `limine.conf`, and every path in the config carries `#blake2b`. The fallback `EFI/BOOT/BOOTX64.EFI` is a **copy of the enrolled, signed binary**, never a separately signed raw one: Limine treats Secure Boot as inactive when no config hash is enrolled, so a signed raw fallback would boot unhashed kernels. A pacman hook (`zz-haseen-secureboot.hook`, sorted after Limine's and Omarchy's hooks and before `zz-sbctl.hook`) re-signs and re-enrolls whenever Limine, a kernel or the config changes.
- **systemd-boot / GRUB:** UKIs and the loader are signed by the sbctl pacman hook. GRUB needs `--disable-shim-lock` plus its modules embedded, which is documented as the weakest path.
- **Safety:** enrollment needs Setup Mode and a typed confirmation, and refuses if any boot file sbctl tracks is unsigned. When Windows is on the ESP, the layer prints the BitLocker warning before enrolling: changing `db` changes PCR 7, so BitLocker will ask for its recovery key once.

## 9. Login

From the bootloader to the desktop, every step is switchable on its own and the
default is the one that cannot lock you out.

- **Splash:** `haseen plymouth set` installs `share/haseen/default/plymouth/` into `/usr/share/plymouth/themes/haseen`, coloured from the current theme's `colors.toml`, adds the `plymouth` hook, puts `quiet splash` on the kernel command line through `share/haseen/lib/boot.sh`, and rebuilds the initramfs. The theme is a plymouth script that draws its own password prompt; its one image, `logo.png`, is the selected mark (§11) rendered from its SVG in the accent colour at install time, so no images ship here. `haseen plymouth status` says which of the three preconditions is missing. Whether the hook is there is read as mkinitcpio reads it (`boot_hooks` in `share/haseen/lib/boot.sh`): `mkinitcpio.conf` and its version-sorted drop-ins concatenated and sourced in a subshell, so code in a drop-in (Omarchy 4.5's platform `case`, haseen's own `sed` edit) counts; a configuration that does not source stops `haseen plymouth set` and `haseen hibernation setup` instead of reading as "missing" (plan 101). On a machine with Omarchy's `omarchy-settings`, its upgrades put `Theme=omarchy` back; the Omarchy package guard (§5.4) names haseen's splash again.
- **Greeter:** greetd starts either tuigreet (default) or `bin/haseen-greeter`, which runs a throwaway Hyprland whose config only starts `share/haseen/shell/greeter/`. Authentication is `Quickshell.Services.Greetd`; `GreeterSession.qml` holds the logic and the `greeter` IPC target, `GreeterCard.qml` only draws it, and `GreeterPalette.qml` keeps the login screen free of `qs.Haseen` singletons that read a logged-in user's files.
- **Autologin:** `haseen setup greeter autologin <user>` writes greetd's `[initial_session]`, which runs once at boot. With an encrypted root the disk password at the splash is that boot's authentication; without one, the command warns that it means no password at all.
- **Replacing another display manager:** `haseen layer apply desktop` keeps an enabled SDDM/GDM; `haseen setup greeter tuigreet|haseen` is the explicit request to replace it. It asks, installs greetd and tuigreet, disables the old unit before enabling greetd (`display-manager.service` is an alias only one unit holds), starts nothing, and prints the way back.
- **Getting back:** `sudo haseen setup greeter tuigreet && sudo systemctl restart greetd` from a TTY, which is why tuigreet stays the default.

## 10. Dotfiles (yadm)

`haseen setup dotfiles <git-url> [--branch B] [--bootstrap]`
(`bin/haseen-setup-dotfiles`, menu Setup › Dotfiles) puts a yadm repository in
`$HOME`. It is optional and never runs on its own: no layer calls it, and the
installer runs it only when it is ticked in the install picker (plan 063).

- **Plan first.** A throwaway bare clone lists what is new, what is identical and what would be replaced. That clone is the only thing `--dry-run` runs.
- **Backup, then the repo wins.** Every file the repo replaces is copied to `~/.local/state/haseen/dotfiles-backup/<timestamp>/` first. Then `yadm clone --no-bootstrap` runs, followed by `yadm checkout` of those files.
- **haseen's entry point stays.** If the repo's `~/.config/hypr/hyprland.lua` does not load `default/hypr/init.lua` (the desktop layer's seed test), the repo's `.config/hypr` is Omarchy's:
  - haseen's files there are kept, and the seed is restored when it is missing;
  - the repo's Omarchy files are taken back out;
  - the repo's copy goes to `~/.local/state/haseen/dotfiles-omarchy/<timestamp>/` for the import.
- **Plugin sources stay read-only.** Existing files under `~/.config/omarchy/plugins` and `~/.config/DankMaterialShell/plugins` are never replaced; new files are added.
- **Omarchy config.** A repo that carries `~/.config/omarchy` gets `haseen import omarchy --merge`, unless it also tracks `~/.config/haseen/shell.json` (it is set up for haseen already).
- **yadm bootstrap** runs only with `--bootstrap`. If a yadm repo with a different remote already exists, the command refuses. `haseen setup dotfiles status` prints the remote, the branch and the number of changed files.

## 11. Branding

haseen has three original marks (plan 059): `kufic` (the default, a square-Kufic
حصين), `shield` and `gate`. Each lives in `share/haseen/branding/<mark>/` as
`mark.svg`, `symbolic.svg` (16 px grid), `symbolic-24.svg` and `wordmark.svg`,
all filled with `currentColor`, plus a terminal logo `logo-<mark>.txt` (at most
81 columns).

- **One setting.** `branding.mark` in `shell.json`; `haseen branding mark <name>` writes it. `share/haseen/lib/branding.sh` (`branding_mark`, `branding_file`) and `qs.Haseen.Branding` (`mark`, `paths`, `pathsFor()`) read it with one rule: anything but the three names is `kufic`.
- **Colour.** QML draws the SVGs through `qs.Haseen.Widgets.BrandImage`, which writes a `Theme` colour into the SVG text (the software renderer has no shader recolouring). Files outside the shell get a baked colour: the plymouth `logo.png` and the scalable app icon use the theme accent.
- **Where it shows.** The menu header, the About panel (the wordmark, unless `haseen branding about` set a text or image), `haseen about --logo`, the screensaver's default text (both styles), the boot splash, and the app icon `haseen` / `haseen-symbolic` in hicolor (installed by `install.sh` under `PREFIX`, and per user by `haseen branding mark`). The bar widget `haseen.logo`, first in `bar.left` by default (plan 070), opens the menu. The greeter shows no logo.
- **Applying a change.** The shell follows `shell.json` at once; the splash needs `haseen plymouth set` again (it lives under `/usr`).
