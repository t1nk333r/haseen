# Plan 057: debrand — no Omarchy surface or name under haseen

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: LOW (new shims sit only on the shell's `PATH`; text changes)
- **Depends on**: 052 (the command-shim mechanism)
- **Category**: shell, compat, CLI
- **Planned at**: 2026-10-07, owner report on io: "updater still has omarchy
  branding; remove omarchy branding everywhere and prompt haseen"
- **State**: DONE 2026-10-07 (the live click on the update widget is an owner check)

## Problem and decision

io runs haseen on top of an installed Omarchy 4.0.4 (`/usr/share/omarchy`,
`/usr/bin/omarchy-*`). The owner's Omarchy plugins (`~/.config/omarchy/plugins`,
and the copies in `~/.config/haseen/plugins`) call `omarchy-*` commands, and
those show Omarchy's UI: the update widget (`t1nk33r.updates`, `BarWidget.qml:27`)
runs `omarchy-launch-floating-terminal-with-presentation omarchy-update`, which
opens a terminal titled "Omarchy" that prints Omarchy's logo and runs Omarchy's
updater.

Decision: extend the plan 052 command shims (`share/haseen/shell/Compat/bin/`,
first on the shell's `PATH` through `haseen shell run`). Every Omarchy command
a plugin runs from the shell that has a haseen equivalent now reaches it.
Commands without one are listed below and left alone; a shim that pretends
would be worse than Omarchy's command. haseen's own user-visible text loses the
word Omarchy where it described haseen features. MIT notices in source headers,
comments and NOTICE.md stay: they are attribution, not branding.

Rejected: rewriting the owner's plugin files (read-only, and every plugin
update would undo it); a global `PATH` change for the session (Hyprland binds
and systemd units would then lose Omarchy commands that have no substitute).

## Changes

- New shims, each a single `exec` of the haseen command or a translation of
  its arguments (tests: `tests/test-shell.sh`, "debrand shims"):
  - `omarchy-update` → `haseen update` (Omarchy's `-y` is haseen's `-y`);
  - `omarchy-launch-floating-terminal-with-presentation CMD…` →
    `haseen config terminal -- bash -c "CMD…"`;
  - `omarchy-notification-send` → `haseen notification send` (argument order
    kept, `low` default urgency, `--image` as the icon, the glyph dropped);
  - `omarchy-menu [toggle|summon] [route]` → `haseen menu [route]`;
  - `omarchy-toggle-idle` → `haseen toggle idle` (Omarchy's verbs, its
    `enabled`/`disabled` lines and its `status` JSON kept);
  - `omarchy-powerprofiles-list`, `omarchy-powerprofiles-set` →
    `haseen powerprofile list`, `haseen powerprofile set`;
  - `omarchy-capture-screenrecording` → `haseen capture screenrecord`
    (flags translated; `--webcam-size`/`--resolution` dropped).
- `haseen update` opens on haseen's name: the haseen wordmark
  (`share/haseen/default/screensaver/screensaver.txt`) when stdout is a
  terminal, then `[*] haseen update: <target>` always. It never printed
  Omarchy's logo; now it shows haseen's.
- About panel: Omarchy writes `NAME="Omarchy"` over `/etc/os-release`, so the
  OS line read "Omarchy 4.0.4". `haseen about` now names the distribution
  underneath from `/usr/lib/os-release` (package `filesystem`: "Arch Linux" on
  io), or "Linux" without one.
- Text: `haseen screensaver` and `haseen screensaver style` help and summary,
  and the descriptions of `haseen.indicators`, `haseen.network`,
  `haseen.screensaver`, `haseen.tray`, `haseen.weather` and
  `haseen.workspaces`, no longer call those features Omarchy's.
- `docs/architecture.md` §5.4 lists the debrand shims; NOTICE.md has a row
  for the Omarchy command interfaces the shims accept.

## Audit

### (a) `omarchy-*` commands the plugins call

`grep -rhoE 'omarchy-[a-z0-9-]+'` over both plugin directories, kept when the
name is an installed command (`/usr/share/omarchy/bin`), then each call site
read. "On" = enabled in `~/.config/haseen/shell.json` on io. "Shell" = run by a
process the shell starts (sees the shims); "Hyprland" = written into a bind or
dispatched through `hyprctl`, which runs with the compositor's `PATH` and does
not see them.

| Command | Plugins (o = omarchy/, h = haseen/; on = enabled) | How it is reached | Verdict |
|---|---|---|---|
| `omarchy-update` | h:t1nk33r.updates (on) | shell, inside the presentation terminal | **shim** → `haseen update` |
| `omarchy-launch-floating-terminal-with-presentation` | h:t1nk33r.updates (on), h:t1nk33r.vpn (on), h:t1nk33r.typist (on), o:t1nk33r.nearby-share (on), o:omaconnect | shell | **shim** → `haseen config terminal` |
| `omarchy-notification-send` | o:t1nk33r.nearby-share (on), o:t1nk33r.omaprayers (on), o:t1nk33r.agents (on, by absolute `/usr/bin` path), o:io.github.ilyazar.syncthing, h:t1nk33r.typist (on), h:t1nk33r.screen-search (on), h:t1nk33r.omarr (on), h:io.github.linuxg33k76.hey-im-gaming-here (on), h:t1nk33r.nothing-glass (on, comments) | shell; also inside Omarchy scripts the shell runs (`omarchy-display-text-size`, `omarchy-tailscale-send`, `omarchy-launch-config-editor`) | **shim** → `haseen notification send`. The agents call by absolute path is not reached |
| `omarchy-menu` | h:t1nk33r.wooting (on), h:t1nk33r.screen-search (on), o:io.github.heroesofcode.omagesture (Hyprland bind) | shell; Hyprland for omagesture | **shim** → `haseen menu`. Omarchy's needs Omarchy's shell, which is not running, so the "Plugin settings" buttons did nothing |
| `omarchy-toggle-idle` | h:io.github.linuxg33k76.hey-im-gaming-here (on) | shell | **shim** → `haseen toggle idle`. Omarchy's marker file is ignored by haseen's idle, so the plugin's stay-awake did nothing |
| `omarchy-powerprofiles-list`, `-set` | o:t1nk33r.power (on) | shell | **shim** → `haseen powerprofile list`/`set` (same interface; haseen's remembered profile is the one restored on AC changes) |
| `omarchy-capture-screenrecording` | o:t1nk33r.privacy (on, stop button) | shell | **shim** → `haseen capture screenrecord --stop` |
| `omarchy-restart-shell` | ten plugins | shell | shim since plan 052 |
| `omarchy-hyprland-monitor-internal-mirror` | o:io.github.juliusmork-sys.monitor-settings-extender (on) | shell | shim since plan 052 |
| `omarchy-shell` | most plugins (`shell toggle/summon/ping/rescanPlugins/listPlugins`, `<plugin> <fn>`, `lock status`) | shell | **not shimmed**: haseen's `shell` IPC target has `reload`/`plugins` only. Plugin targets would work through `haseen shell ipc`, Omarchy's `shell …` verbs need a translator. Should exist (own plan); today these calls fail quietly ("omarchy-shell is not running") |
| `omarchy-menu-select`, `omarchy-menu-input` | h:t1nk33r.typist (on), o:omaconnect | shell | **not shimmed**: open a picker/prompt in Omarchy's shell menu. haseen has no CLI picker or prompt; one should exist (`haseen menu select/input` over the menu IPC) |
| `omarchy-file-select` | o:t1nk33r.nearby-share (on) | shell | not shimmed: GTK file chooser, no Omarchy branding; no haseen equivalent needed |
| `omarchy-launch-browser` | h:t1nk33r.screen-search (on), h:t1nk33r.browser-picker (comments) | shell | not shimmed: opens the default browser, no branding; no haseen equivalent needed |
| `omarchy-launch-webapp` | h:t1nk33r.omarr (on) | shell | not shimmed: no branding; haseen has `webapp install/remove` but no launcher. A `haseen webapp launch` should exist if the Omarchy package is ever removed |
| `omarchy-launch-tui`, `omarchy-launch-or-focus-tui` | o:t1nk33r.vigil (on, `--app-id=org.omarchy.vigil`), o:crmne.omastats | shell | not shimmed: no haseen equivalent (haseen's floating terminal waits for Enter, Omarchy's tiles). Window class `org.omarchy.*`, see (d) |
| `omarchy-launch-config-editor` | o:t1nk33r.agents (on) | absolute `/usr/bin` path | not reachable by a shim; `haseen config edit` is the equivalent. Its own toast goes through the notification shim |
| `omarchy-default-agent` | o:t1nk33r.vigil (on) | shell | **not shimmed** on purpose: `haseen setup default agent` exists, but the owner's choice (`opencode`) is only in `~/.config/omarchy/defaults/agent`; a shim would lose it. Shim after `haseen setup default agent opencode` or an import of Omarchy defaults |
| `omarchy-brightness-display`, `omarchy-brightness-keyboard` | o:io.github.juliusmork-sys.monitor-settings-extender (on, `--no-osd`), o:t1nk33r.lock | shell | not shimmed: haseen has no brightness command (binds call `brightnessctl`). Its OSD path (`omarchy-osd` → Omarchy's shell) shows nothing under haseen |
| `omarchy-hyprland-monitor-scaling`, `omarchy-monitor-state`, `omarchy-display-text-size` | o:io.github.juliusmork-sys.monitor-settings-extender (on) | shell | not shimmed: no haseen equivalent. `display-text-size` also rewrites Omarchy's shell font size, which haseen ignores |
| `omarchy-battery-status`, `omarchy-system-stats` | o:t1nk33r.power (on) | shell | not shimmed: read-only text, no branding, no haseen equivalent needed |
| `omarchy-cmd-present` | h:t1nk33r.vpn (on) | shell | not shimmed: `command -v`, no branding |
| `omarchy-tailscale-send` | o:t1nk33r.tailscale (on) | shell | not shimmed: no haseen Taildrop sender (haseen shares with LocalSend); its toasts go through the notification shim |
| `omarchy-agent-usage-update` | o:t1nk33r.agents (on) | `$OMARCHY_PATH/bin` path | not reachable; no haseen equivalent |
| `omarchy-plugin-validate` | o:t1nk33r.vigil, o:omaconnect | shell | not shimmed: `haseen plugin validate` checks haseen manifests, not Omarchy's |
| `omarchy-theme-color` | o:io.github.ilyazar.syncthing (off) | shell | not shimmed: no haseen equivalent |
| `omarchy-hyprland-session-locked`, `omarchy-system-wake`, `omarchy-launch-shell` | o:t1nk33r.lock (off) | shell; `omarchy-launch-shell` through `hyprctl dispatch exec_cmd` | not shimmed. `omarchy-launch-shell` would start Omarchy's whole shell; the plugin is off (haseen has its own lock), keep it off |
| `omarchy-capture-screenshot` | o:io.github.heroesofcode.omagesture (off) | Hyprland bind | not reachable; `haseen.gestures` replaces the plugin |
| `omarchy-capture-text`, `omarchy-osd`, `omarchy-hook`, `omarchy-theme-set`, `omarchy-font-set`, `omarchy-refresh-shell`, `omarchy-plugin-remove`, `omarchy-plugin-update`, `omarchy-update-available`, `omarchy-weather-location`, `omarchy-agent-usage-claude`, `omarchy-agent-usage-codex`, `omarchy-theme-refresh`, `omarchy-tailscale-receive` | comments, READMEs, tests or file names only | — | nothing runs |

Names the grep also returns that are not commands (plugin ids such as
`omarchy-nearby`, `omarchy-vpn`, `omarchy-weather`) are left out.

### (b) haseen's own user-visible text

| Where | Was | Now |
|---|---|---|
| About panel OS line (`bin/haseen-about`) | "Omarchy 4.0.4" (Omarchy's `/etc/os-release`) | "Arch Linux" (`/usr/lib/os-release`) |
| `haseen update` | no haseen mark; started from the widget, Omarchy's logo and updater | haseen wordmark + `[*] haseen update: system` |
| `haseen screensaver` summary and `--help`, `haseen screensaver style --help` | "Omarchy's ttfx terminals", "Omarchy's screensaver" | "ttfx text effects" |
| manifests: `haseen.indicators`, `haseen.network`, `haseen.screensaver` (and its `style` setting), `haseen.tray`, `haseen.weather`, `haseen.workspaces` | "port of Omarchy's", "Omarchy's network panel", "Omarchy's weather", "Omarchy port" | the feature only |
| menu labels (`share/haseen/default/menu.jsonc`), QML `text:`, notifications, greeter, Plymouth theme, default screensaver text | — | no Omarchy text found (only header comments) |

Kept on purpose, because they name Omarchy as the thing the user deals with:
`haseen import omarchy`, the `omarchy-repo` layer, `haseen theme fetch`
("an Omarchy stock theme"), the Omarchy plugin directories in
`haseen config plugin`/`plugin uninstall` help, and `haseen.gestures`' warning
about the Omarchy plugin it replaces.

### (c) Omarchy surfaces outside the shell on io

Nothing here was changed: they are files under `/usr`, `/boot`, `/etc` or the
owner's home. Each row gives the command that hides or removes it.

| Item | What the owner sees | Fix (owner/integrator runs it) | haseen way |
|---|---|---|---|
| Limine boot menu: `interface_branding: Omarchy Bootloader` (from Omarchy's `default/limine/limine.conf`) and the entry `/+Omarchy` (`limine-entry-tool` names it from `/etc/os-release` `PRETTY_NAME`) in `/boot/limine.conf` | "Omarchy Bootloader" and "Omarchy" at every boot | `sudo sed -i 's/^interface_branding: .*/interface_branding: haseen/' /boot/limine.conf`; for the entry, a drop-in `/etc/limine-entry-tool.d/haseen-name.conf` with `TARGET_OS_NAME="haseen"` [INFERENCE: the variable name is read from the compiled `limine-entry-tool`, not tested], then `sudo limine-update`. With Secure Boot on, `sudo haseen secureboot sign` afterwards (the config hash changes) | a `haseen setup boot-branding` step: `lib/boot.sh` already writes `/etc/limine-entry-tool.d/haseen-*.conf` drop-ins |
| `/etc/os-release` `NAME="Omarchy"` (unowned; Omarchy installs it from `/usr/share/omarchy/etc-overrides/os-release`) | `fastfetch`, `hostnamectl`, other tools; About fixed in haseen | none lasting: Omarchy would put its copy back; leave it while the omarchy package stays | About already reads `/usr/lib/os-release` |
| `omarchy-tailscale-receive.service` (user, enabled, running) | Taildrop toasts sent with `omarchy-notification-send` outside the shell, so named `omarchy-action` | no haseen receiver exists; keep, or `systemctl --user disable --now omarchy-tailscale-receive.service` if Taildrop is unused | a `haseen share` Taildrop receiver would replace it |
| `omarchy-fcitx5.service` (user, enabled, running) | no branding (fcitx5 itself); also autostarted by `org.fcitx.Fcitx5.desktop` in `/etc/xdg/autostart` and `~/.config/autostart` | `systemctl --user disable --now omarchy-fcitx5.service` once the autostart copy is the one wanted | `haseen seed user` could own the fcitx5 start |
| `omarchy-crash-watch`, `omarchy-migrate-notify` (+ alias `omarchy-update-user-notify`), `omarchy-sleep-lock`, `omarchy-recover-internal-monitor` (user units) | nothing: all disabled; haseen runs its own crash watch and sleep lock | `systemctl --user mask omarchy-migrate-notify.service` keeps a future Omarchy update from re-enabling its notification | `haseen import omarchy` could mask Omarchy units it replaces |
| `EDITOR=omarchy-launch-editor --inline` (Omarchy's `default/uwsm/env.d/10-omarchy`) | no branding; reads `~/.local/state/omarchy/defaults/editor` | `haseen setup default editor nvim` (writes `~/.config/uwsm/env.d/60-haseen-defaults`, sourced later) | exists |
| `~/.local/share/applications/` web apps from Omarchy (Discord, Tailscale, … with `Exec=omarchy-launch-webapp`, HEY with `omarchy-webapp-handler-hey`, Docker with `omarchy-launch-docker-tui`, icon `omarchy-discord`) | names are the apps', no Omarchy name; they run Omarchy commands | `haseen webapp remove NAME` then `haseen webapp install NAME URL ICON` | exists |
| Desktop entries named Omarchy under `/usr/share/applications`, walker, elephant, mako, swayosd, hypridle | — | none installed or running on io | — |
| Plymouth | `Theme=haseen` already | — | `haseen plymouth set` |
| Greeter | `/usr/local/bin/haseen-greeter` already | — | — |

### (d) Hyprland window classes and titles

| Window | Before | After / note |
|---|---|---|
| Presentation terminal (`omarchy-launch-floating-terminal-with-presentation`) | class `org.omarchy.terminal`, title "Omarchy" (shown by `t1nk33r.active-window`); haseen has no rule for that class, so it tiled | class `haseen.floating`, title "haseen": floats and centres under `haseen_floating_terminal`, and gets the `terminal` tag |
| Vigil reviews (`omarchy-launch-tui --app-id=org.omarchy.vigil`), omastats `btop` (`org.omarchy.btop`) | class `org.omarchy.*`, no haseen rule, not tagged `terminal` (universal copy/paste treat it as an app) | unchanged: no haseen equivalent of `omarchy-launch-tui`; the plugin chooses the class. A `haseen launch tui` could give `haseen.tui.<cmd>` and the terminal tag |
| haseen's own rules (`share/haseen/default/hypr/windowrules.lua`) | no `org.omarchy.*` match | — |

## Verification

- `QT_QPA_PLATFORM=offscreen tests/run.sh tests/test-shell.sh tests/test-menu.sh tests/test-catalog.sh`:
  the shims are driven as children of `haseen shell run` against recording
  stubs of each haseen target (argv checked) with the installed Omarchy
  commands stubbed to fail; `omarchy-toggle-idle` runs the real
  `haseen toggle idle` and the test reads its state back. `haseen update`
  names itself; `haseen about --facts` under an Omarchy os-release says "Arch
  Linux" (or "Linux"), never Omarchy.
- Gates: `tools/lint.sh`, `tools/check-docs.sh`.

## Not done

- The real click on the update widget after the live install (owner check).
- Everything in (c) and the `omarchy-shell`, `omarchy-menu-select`/`-input`
  and `omarchy-launch-tui` gaps in (a): they need either owner action or a
  haseen feature of their own.
