# Plan 096: Adopt the owner's tool forks (typist, settings, browser picker, VPN)

## Status

- **Priority**: P2
- **Effort**: L
- **Risk**: MEDIUM (four new built-ins and a migration that rewrites `shell.json`; all ship off, the migration only touches ids that are in use and never the old plugin directories)
- **Depends on**: 027 035 037 042 073
- **Category**: shell, plugins
- **Planned at**: 2026-10-20, owner decision of the same day
- **State**: DONE 2026-10-20 (PR open, not merged)

## Decision

The owner chose thirteen of their plugins to adopt into haseen (2026-10-20).
This plan carries four of them, the tools:

| old id (owner's fork) | new id | upstream |
|---|---|---|
| `t1nk33r.typist` | `haseen.typist` | [sanjuanjor/typist](https://github.com/sanjuanjor/typist) |
| `t1nk33r.settings` | `haseen.settings` | [AyushKr2003/shell-settings](https://github.com/AyushKr2003/shell-settings) |
| `t1nk33r.browser-picker` | `haseen.browser-picker` | [K53N0/omarchy-browser-picker](https://github.com/K53N0/omarchy-browser-picker) |
| `t1nk33r.vpn` | `haseen.vpn` | [jkoestinger/omarchy-vpn](https://github.com/jkoestinger/omarchy-vpn) and [guiestrela/omarchy-norvpn-plugin](https://github.com/guiestrela/omarchy-norvpn-plugin) |

The owner's rules for the adoption, recorded in `CLAUDE.md` (plugin section,
one line per plugin, commit ca2ff63):

- adopted plugins take `haseen.*` ids and become first-party built-ins;
- they ship **off**: none is in `share/haseen/default/shell.json`'s bar or
  `services` (checked by `tests/test-adopted-tools.sh`);
- for these four only this overrides "third-party plugins are never bundled";
- every upstream is MIT: its `LICENSE` stays in the plugin directory
  unchanged, each adapted file names its upstream in its header, and
  `NOTICE.md` gains a row per upstream (ca2ff63). Files written for the port
  say so in their header (`haseen.settings/PluginRow.qml`,
  `haseen.settings/SettingField.qml`, `haseen.browser-picker/SettingRow.qml`).

## Sources

The owner's forks were read, never written, on IO
(`~/.config/haseen/plugins/<id>` and `~/.config/omarchy/plugins/<id>`) and on
luna (`~/.config/omarchy/plugins/<id>`, the owner's yadm dotfiles at their commit 88c47f7, outside this repository, for all four).
The copies were byte-identical across the three places (sha256 of the main
files, prefix: typist `typist` 0ec69718ba6c, `typist_worker.py` 0cc2adfb7cf5,
`Picker.js` e7dd2c901385; browser picker `Model.js` d349e9a97c05,
`Picker.qml` 95137aa1b257, `bin/browser-picker` 2323a6af3c2f; VPN
`VpnController.qml` 18a056ea85e0, `Shared.js` 10e06af188ae; settings
`SettingsPanel.qml` e69546cf4a60, `DynamicSettingsForm.qml` bf20cdd2bc97).
Each plugin's `UPSTREAM.md` lists what was kept, changed and dropped.

How IO uses them (read only to shape the migration; no value from IO's
`shell.json` is in this repository): `t1nk33r.settings` in `bar.right`,
`bar.overflow` and `services`; the other three in `services` only; all four
`enabled: true` under `plugins`. That shape is the migration test's fixture
(`tests/test-adopted-tools.sh`, "the migration").

## What was built

### haseen.typist (d45901c)

Types the clipboard, a snippet or a recent clipboard entry as key presses,
for fields that refuse a paste.

- `bin/haseen-typist`: `start | stop | toggle | status | type snippet INDEX MD5
  | type recent ID | snippets edit`. The worker runs in a transient user unit
  (`systemd-run --user --unit=haseen-typist`); settings come from
  `shell.json` over the manifest defaults, a bad value falls back to its
  default. A snippet is named by index **and** the md5 of its text, so a list
  edited behind the picker's back is refused (`bin/haseen-typist:137`); a
  recent entry is named by cliphist id and decoded inside the unit, images
  refused. Without a Hyprland session nothing starts
  (`bin/haseen-typist:86`).
- Keys go through haseen's `ydotool` compat shim
  (`share/haseen/shell/Compat/bin/ydotool`, `bin/haseen-typist:24`), which
  sends key states to Hyprland; no ydotoold, no uinput group.
- `typist-worker.py`: the fork's layout tables and timing, but only Shift as
  a modifier: the shim has no AltGr mod name, so a character that needs AltGr
  is skipped and counted, and the run reports it
  (`typist-worker.py:231`, `:340`). The text never reaches the key
  command's argv, only key codes (test "the text never reaches the key
  command").
- Panel: Clipboard, Snippets, Recent. Recent reads haseen.clipboard's
  cliphist store (`Panel.qml:5`) instead of the fork's own history file; a
  pin decodes the whole entry rather than cliphist's truncated preview.
- Bar widget: glyph, left click opens the panel (or stops a run), middle
  starts, right opens the snippets file in the editor.

### haseen.browser-picker (430fd86)

Asks which browser (and profile) opens a link, with per-site rules.

- `bin/haseen-browser-picker` is the default-browser shim; `bin/haseen-browser-scan`
  lists browsers and profiles from desktop entries. The shim asks the shell
  through `haseen shell ipc haseen.browser-picker pick REQUEST` and waits on a
  FIFO the service releases, the menu-select handshake. A shell that does not
  answer still opens the link: fzf in `$TERMINAL`, else the first browser
  found.
- The service answers a matching rule without showing anything, otherwise
  opens the card (`Overlay.qml`); Ctrl+Enter learns a rule; rankings live in
  `~/.local/state/haseen/browser-picker.json`, rules in
  `~/.config/haseen/browser-picker.json`, settings in `shell.json`.
- Overlap with `haseen setup default`: the picker is one more choice there,
  `haseen setup default browser browser-picker`
  (`bin/haseen-setup-default:21`, `:181`), through the vendor entry
  `share/haseen/default/applications/haseen-browser-picker.desktop`
  (hidden from launchers). Helium stays haseen's default browser
  (`share/haseen/default/applications/mimeapps.list:92`); enabling the plugin
  does not change the default.

### haseen.vpn (f9880d4)

One panel over NetworkManager VPN profiles (WireGuard, OpenVPN, OpenConnect),
Mullvad, ProtonVPN, Windscribe and NordVPN.

- All five backends kept, each found by `command -v`; the fork's models and
  their 113 tests unchanged (`tests/run.js`).
- `VpnController.qml` became `Service.qml` (a `vpn` role): IPC target
  `haseen.vpn` (`Service.qml:440`), exit address from
  `checkip.amazonaws.com` (the manifest's only `network` permission), and
  sampling timers at 2 s or slower (`Service.qml:163`, `:339`), the fork's
  1.5 s settle raised to the floor.
- `omarchy-openconnect-auth` is `bin/haseen-vpn-openconnect`; an auth prompt
  opens through `haseen config terminal`.
- Panel: native, keys j/k, Enter, Tab, Space, `/`, r, Esc; the providers gear
  hides backends through the `hiddenBackends` setting (`Panel.qml:104`).

### haseen.settings (710314d)

The fork was a whole settings app; most of it already exists in haseen.
Kept: the plugin manager.

- Lists the shell's plugin registry with filters (all, enabled, built-in,
  installed, read-only, configurable) and search; switches a plugin on or off
  through `haseen plugin enable/disable`.
- A settings form for any plugin whose manifest declares settings, typed per
  the manifest schema and saved in one `haseen plugin settings ID` request;
  reset drops a key back to its default.
- Delete only for a directory directly under `~/.config/haseen/plugins`
  (`Model.js:20`), two presses, through `haseen plugin uninstall`
  (`Panel.qml:136`). Omarchy's and DMS's plugin directories are listed and
  never deletable; the engine test checks the Omarchy fixture byte for byte.
- Dropped, with where haseen already does it (`UPSTREAM.md`): the bar
  arranger (`haseen bar arrange`, `haseen bar move`), idle settings (`haseen
  setup idle`), the installer (`haseen plugin install`, menu Setup ›
  Plugins, `share/haseen/default/menu.jsonc:218`), the overflow drawer.

### Migration (c3bb14e)

`share/haseen/migrations/1791560100-adopt-tools-forks.sh`, in this plan's
range. For a `shell.json` that names an old id:

- bar sections (left, center, right, overflow, pinned): the old id becomes the
  new one in place, duplicates dropped;
- `services`: kept for browser picker and VPN (they have a service), dropped
  for typist and settings (they have none);
- `plugins.<old>` → `plugins.<new>`: `enabled` and only the settings the new
  manifest declares; an entry already under the new id wins key by key;
- the forks' data is **copied**, never moved, where nothing is yet:
  `~/.config/omarchy/t1nk33r.typist.json` → `~/.config/haseen/typist.json`;
  the browser picker's rules → `~/.config/haseen/browser-picker.json`, its four
  settings into `shell.json` where unset; its rankings →
  `~/.local/state/haseen/browser-picker.json`.

It never reads, changes or removes `~/.config/omarchy/plugins` or
`~/.config/haseen/plugins`, does not change the default browser, writes
atomically under the shell config lock, honours `DRY_RUN`, and a second run
changes nothing.

## Tests (1a635a2)

`tests/test-adopted-tools.sh`, 236 checks, all passing with
`HASEEN_REQUIRE_ENGINE=1`:

- manifests validate; off by default; licences, `UPSTREAM.md`, `NOTICE.md`
  and `CLAUDE.md` rows; no compat module, omarchy command or Omarchy path;
  no privilege escalation; no rich text from outside;
- the forks' own suites: browser picker model (41) and scanner (27), VPN
  models (113);
- typist worker with a logging key command (us, de with an AltGr skip, size
  limit, empty input, a failing key command) and `haseen typist` dry runs and
  refusals;
- the browser-picker shim with a stub shell (answer, cancel, no answer),
  `--default --dry-run`; the OpenConnect helper's dialog override;
- `Picker.js` and the settings `Model.js` in the Qt JS engine;
- each plugin in the real engine, offscreen: the typist panel (rows, first
  Enter, pin, typing commands, delete), the browser-picker service (rule,
  card, pick, Ctrl+Enter, files), the VPN service on a PATH holding only
  `nmcli`/`wg`/`curl` stubs (luna has mullvad and nordvpn installed), the
  settings panel against the real CLI;
- the migration on an IO-shaped fixture: dry-run purity, results, old
  directories and data untouched, idempotence, no `shell.json`, odd shapes,
  an unreadable `shell.json` refused.

## Rejected options

- **Keep the forks as installed third-party plugins.** The owner decided to
  adopt them (2026-10-20); kept as Omarchy plugins they would run through the
  compat layer and depend on Omarchy commands (`omarchy-openconnect-auth`,
  `omarchy-shell`).
- **Port shell-settings whole.** Its bar arranger, idle page, installer and
  drawer duplicate `haseen bar arrange`, `haseen setup idle`, `haseen plugin install`
  and the overflow panel; two editors for the same `shell.json` keys would
  disagree.
- **Typist through real ydotool.** It needs ydotoold and uinput access; the
  compat shim is already shipped and needs neither. The cost is AltGr,
  recorded below.
- **Typist's own clipboard history.** haseen.clipboard already keeps one in
  cliphist; a second store would diverge.
- **Make the browser picker the default when enabled.** The default browser is
  the owner's choice (Helium, plan 073); `haseen setup default browser
  browser-picker` makes it explicit and reversible.
- **Drop the VPN backends that cannot be tested live** (Mullvad, Proton,
  Windscribe, NordVPN). Their models carry the fork's tests and the owner
  chose the plugin as is.
- **Move the forks' data files.** A copy leaves the forks working if the
  owner switches back.

## Limitations

- The typist bar highlight notices a run started outside the widget (a
  hotkey) only on its next sample.
- AltGr characters are skipped (the shim has no AltGr mod).
- An empty clipboard is refused; the fork typed a space.
- The browser picker's `promptAfter` is edited only through the
  haseen.settings form or `haseen plugin settings`.
- `haseen webapp install` uses the default browser's Exec; with the picker as
  default, web apps go through the picker.
- The VPN panel's keyboard model is smaller than the fork's.
- The browser-picker card and the panels were checked in the offscreen engine,
  not in a nested Hyprland; no screenshots were taken.
- No menu row opens haseen.settings yet; `qs ipc call panel toggle
  haseen.settings` or the bar widget does.
