# Plan 102: Answer Omarchy 4.5's commands

## Status

- **Priority**: P1
- **Effort**: L
- **Risk**: MEDIUM (94 more command names in `/usr/local/bin` shadow an
  installed Omarchy's `/usr/bin` ones, and Omarchy's own code reaches them:
  every initramfs build asks `omarchy-hw-platform`, every `claude`, `codex`
  and `grok` run goes through `omarchy-agent-account-exec`. Those answer
  exactly as Omarchy's do; each new answer has a test)
- **Depends on**: 093 (the command model it extends), 100 (affected tests)
- **Category**: compat, CLI
- **Planned at**: 2026-10-21, owner request: "Check omarchy 4.5 and what
  worth adopting"
- **State**: DONE 2026-10-22 (pull request; the live install on IO and luna is
  an owner step). The `boot_hooks_known` guard for `omarchy-plymouth-set` waits
  for plan 101 (#57), see Not done.

## Decision (owner)

Asked "Check omarchy 4.5 and what worth adopting", the owner read the survey
and chose:

- Fixes: "4.5 compatibility (Recommended)", "Security & bug fixes
  (Recommended)", "Neutralise Omarchy's migrations (Recommended)". Not chosen:
  "Override the package's tweaks" — so kyber, `KillMode=mixed`, BBR/ARP, the
  locale NOPASSWD rule and the mise wrappers that the 4.5 package installs
  stay as Omarchy ships them.
- Small features: "Quake console", "Captive-portal sign-in", "Faster boot &
  logout", "Starship theme & per-theme wallpaper".
- Bigger features: "Per-monitor workspaces", "Omasnap instead of Tensaku",
  "Arabic interface". Not chosen: "World clock (Elsewhen)".
- Also: "Floating layout step", "Multiple Claude/Codex accounts", "1-second
  boot menu", "New binds".

Earlier standing decisions: adopt all Omarchy commands except Apple-hardware
ones (plan 093); a new built-in plugin or optional behaviour is off by default
unless the owner approved it on; no dock, titlebars, video wallpapers, theme
intros or blur.

This plan is "4.5 compatibility (Recommended)" and the command half of
"Security & bug fixes (Recommended)". The migrations, the accounts feature
(plan 108), the Arabic interface (plan 109) and the other features are other
plans of the same batch.

## Problem

Omarchy's `bin/` went from 449 scripts at `v4.0.6` to 536 at `v4.5.0-rc1`:
93 added, 6 removed, 194 changed (`git ls-tree` of `bin/` at both tags; the
survey's A.1). haseen's `commands.tsv` held 446 rows, the commands the 4.0.6
package ships (plan 093). So:

1. **93 new names had no answer.** Each one's `/usr/bin` copy runs when it is
   called. Four kinds of them are reached by Omarchy's own code, so a wrong
   answer breaks something outside haseen (verified at `v4.5.0-rc1`):
   - `etc/mkinitcpio.conf.d/00-omarchy-hooks.conf:10-13` runs
     `command -v omarchy-hw-platform` on every initramfs build and
     `return 1`s when it fails: a refusal in `/usr/local/bin`, which comes
     before `/usr/bin` on sudo's and pacman's `PATH`, would stop every
     mkinitcpio run;
   - the `omarchy-hw-*` predicates and `omarchy-sleep-disabled` are guards
     (`omarchy-hw-aarch64-n1x || exit 0` in
     `bin/omarchy-apply-n1x-gpu-memory:27`): an inert row exits 0, which reads
     as "yes, this hardware";
   - `etc/mise/conf.d/omarchy-agent-accounts.toml:3-13` (Omarchy f9646299b,
     #14233) wraps every `claude`, `codex` and `grok` run with
     `omarchy-agent-account-exec`;
   - about 95 scripts call `omarchy-i18n` for their messages
     (`git grep omarchy-i18n v4.5.0-rc1 -- bin`), and `omarchy-launch-about:35`
     sources `omarchy-branding-about-animation` by name.
2. **`omarchy-kernel`** arrived on Omarchy's `quattro` branch after the tag
   (690526508, #15966): it rewrites `BOOT_ORDER` in `/etc/default/limine`
   drop-ins (`bin/omarchy-kernel@quattro:17-31`).
3. **Three answers broke a 4.5 caller** (survey A.1.2, verified):
   - SUPER + RETURN runs `omarchy-launch-terminal --pid=<pid>`
     (`default/hypr/helpers.lua@v4.5.0-rc1:174-180`, Omarchy f81463955,
     #13521); haseen's port took `--pid=N` for the command to run;
   - SUPER + ALT + L runs `omarchy-hyprland-workspace-layout-toggle back`
     (`default/hypr/bindings/tiling.lua@v4.5.0-rc1:15`); haseen's shim called
     `haseen-toggle-workspace-layout toggle back`, a usage error;
   - `default/input-methods/typing_setup.py@v4.5.0-rc1:57-62` calls
     `omarchy-menu-select … -- --multiple --width 620 --maxheight 650
     --on-change JSON --change-key K --selected V`; haseen's shim made every
     unknown flag an option row, so nothing applied and nothing failed.
4. **Three security fixes in Omarchy had not reached haseen's copies**:
   - Omarchy fa3f60770 keeps the Windows VM password off the RDP client's
     argument list (`bin/omarchy-windows-vm@v4.5.0-rc1:1489-1493`, through
     `/args-from:stdin`); haseen's port still passed `/p:$WIN_PASS` on argv,
     readable in `/proc/<pid>/cmdline`;
   - Omarchy dc2b18098 stopped giving a received Taildrop file to the
     notification server as its image (the `--image "$path"` of
     `bin/omarchy-tailscale-receive@v4.0.6:66` is gone at `v4.5.0-rc1`);
     haseen's port still passed `-i "$path"`, so any tailnet peer could send
     an image straight to the notification daemon's decoder;
   - Omarchy names its grants by UID now and keeps a permanent one beside the
     timed one (`bin/omarchy-sudo-passwordless@v4.5.0-rc1:100-107`
     `rule_file`, timers `omarchy-nopasswd-expire-<uid>-<token>` at `:387`);
     haseen's `omarchy-sudo-passwordless --disable` and
     `haseen setup passwordless-sudo --off` removed only the 4.0.6 name
     (`99-omarchy-nopasswd-<user>`), so a 4.5 grant kept sudo passwordless
     after "off".

## Evidence

- Omarchy, cloned read-only to a scratch directory and deleted afterwards:
  `v4.0.6` = 237f1b407, `v4.5.0-rc1` = 03ff1eff3, `quattro` at 82662dd26
  (`git describe`: `v4.5.0-rc1-25-g82662dd26`). Every port and translation
  names its upstream file (`bin/<name>@v4.5.0-rc1`) in its header and was
  written from that file, not from the survey.
- The fixtures: `tests/fixtures/omarchy-4.5/bin.txt` (533 names) is
  `git ls-tree --name-only v4.5.0-rc1 bin/` (536) without `omarchy-debug`,
  `omarchy-debug-idle` and `omarchy-upload-log`, which plan 093 found the
  package does not ship (`plans/093-adopt-omarchy-commands.md`, Problem);
  `tests/fixtures/omarchy-4.5/after-rc1.txt` holds `omarchy-kernel`.
  `comm -13` of the 4.0.6 and 4.5 lists gives the 93 added names, `comm -23`
  the 6 removed ones; `tests/test-omarchy-commands.sh` asserts all three.
- Verified in Omarchy's code: the four PATH-shadowing callers above, the three
  breaks, the three security fixes, `omarchy-kernel`, every new script ported
  or translated (its header cites it), Omarchy's `default/i18n/` catalog
  layout and `plural.jq`, the input-method presets
  (`default/input-methods/presets.json`) that `omarchy-setup-input` maps to
  fcitx5 engines, and the `omarchy-ascii` font's missing licence.
- Taken from the survey without re-deriving: the 194-changed tally and its
  A.1.4/A.1.5 split (the 52 argument drifts are not this plan's), and the
  reach notes (which of haseen's binds load Omarchy's Lua helpers).

## Design

### Inventory

`commands.tsv` now has a row for each of 540 names: the 539-name union of
Omarchy 4.0.6's 446 and 4.5's 93 additions, plus `omarchy-kernel`. The six
names 4.5 removed (`omarchy-system-{logout,reboot,shutdown}`,
`omarchy-voxtype-{install,remove,status}`) keep their rows: haseen's own
ports call `omarchy-system-reboot`, and older Omarchy plugins call the
Voxtype names.

| Kind | 4.0.6 (plan 093) | Added here | Changed here | Now |
|---|---|---|---|---|
| shim | 79 | 2 | −2 | 79 |
| translate | 81 | 23 | +2 | 106 |
| port | 236 | 52 | | 288 |
| refuse | 44 | 10 | | 54 |
| inert | 4 | 5 | | 9 |
| apple | 2 | 2 | | 4 |
| total | 446 | 94 | | 540 |

`share/haseen/omarchy/bin/` holds 536 entries (every row but the four Apple
ones): links to `../dispatch` for the 16 new shim, refuse and inert rows,
scripts for the rest. The table's per-command list is under Inventory below.

### Faithful answers where Omarchy's own code asks

- `omarchy-hw-platform` is ported unchanged in what it reads and answers
  (x86, aarch64, aarch64-apple, -qualcomm, -n1x, -gb10; the image-build
  manifest; refusal of contradictory identities). Like Omarchy's it stands
  alone (`#!/bin/bash -p`, sourcing nothing of haseen's): mkinitcpio runs from
  a pacman hook as root, often without `HOME`. A launch without `-p` exits
  126, as Omarchy's guard does; root re-executes in an empty environment with
  a fixed `PATH`. An unprivileged caller's fixture root is `HASEEN_SYSROOT`,
  in place of Omarchy's three `OMARCHY_*_ROOT` variables.
- The predicates that run it (`omarchy-hw-aarch64-gb10`, `-n1x`, `-qualcomm`,
  `omarchy-hw-n1x`) stand alone too and run the detector beside themselves.
  The other predicates (`omarchy-hw-aarch64`, `-x86`, `-vm`,
  `-match-device-tree`, `-dell-xps13-sidecar-amps`, `-elgato-camlink-4k`,
  `omarchy-sleep-disabled`) source `lib.sh` and read through `sysroot_path`.
  None is inert or a refusal.
- `share/haseen/omarchy/lib.sh` sets `HOME` from the passwd entry when it is
  unset: Omarchy's root units without `User=` call these names, and
  `common.sh`'s per-user paths under `set -u` would stop a command before it
  answered.
- `omarchy-i18n` prints Omarchy's strings from its installed catalogs
  (`$OMARCHY_PATH/default/i18n`, read only), in Omarchy's chosen language
  (`~/.config/omarchy/language`, read only), with Omarchy's `plural.jq`; with
  no catalogs it prints the key, Omarchy's own last fallback. haseen's
  messages do not go through it.
- `omarchy-branding-about-animation` and `omarchy-security-functions` are
  scripts of their own, safe to source (plan 093's rule for sourced names):
  the first defines Omarchy's sheen helpers and nothing of haseen's; the
  second refuses and `return 1`s, so its callers stop.
- `omarchy-agent-account-exec` always runs the agent: an explicit
  `CLAUDE_CONFIG_DIR`/`CODEX_HOME`/`GROK_HOME` wins, then a session's pinned
  home, then `omarchy-agent-account-home`. A CLI that is not installed is
  installed through mise only when Omarchy's system mise config declares it;
  otherwise it fails with how to install it. Omarchy's `mise use -g` would
  edit the user's global mise config unasked.

### The families

| Family | Answer |
|---|---|
| Hardware detection and its non-Apple ARM steps (`hw-*`, `apply-n1x-gpu-memory`, `n1x-probe`, `install-camera`, `install-video-decode`, `system-lid-inhibit`, `chromium-add-feature`) | ported faithfully (plan 093's treatment of hardware scripts); each step does nothing off its hardware, as Omarchy's. The N1x GPU-memory write goes through `run_root` (`chattr -i`, one `dd`, `chattr +i`); the probe logs to `/var/log/haseen-n1x-probe.log`; the lid inhibitor is `haseen-lid-inhibit.service` |
| Shared plumbing (`i18n`, `capture-screenrecording-process`, `network-wifi-connected`, `webapp-window-class`, `mise-default-tools`, `crash-mute`, `windows-key`, `boot-direct`, `dev-notification-demo`, `theme-set-hunk`, `theme-set-fcitx5`, `hyprland-corners`, `hyprland-workspace-layout-current`) | ported; state moves to haseen's store (`toggles/crash-ignore`, `toggles/hypr`), and `bin/haseen-crash-watch` skips a muted program |
| Installers and removers (`install-service-microsoft`, `remove-service-*`, `remove-ai-*`, `install-chromium-claude`, `install-ai-claude`, `install-t3code-app`) | through haseen's helpers: `haseen webapp install/remove`, `haseen install` (the repository order), `haseen remove`, `remove-lib.sh`'s `ask` for user data (kept under `--yes`, deleted with `--purge`); the Chromium extension file through `write_root_file` |
| Agent usage (`agent-usage-grok`, `agent-usage-kimi`) | ported collectors (Python, run isolated with `-I`), caches in haseen's `~/.cache/haseen/agent-usage`; `omarchy-agent-usage-update` lists them |
| Agent accounts (`agent-account-*`, owner: multiple accounts, plan 108) | `exec` and `home` ported (above); `add`, `list`, `mode`, `remove`, `rename`, `state`, `use` run Omarchy's installed copy (`omarchy_passthrough`, `lib.sh`), so the state stays in Omarchy's `~/.local/state/omarchy/agents/accounts` until plan 108, and refuse where Omarchy is not installed; `copy` and `transfer` are refused: they send agent logins to another machine over SSH |
| Dictation (`dictation`, `dictation-use`, `dictation-voxtype`, `default-dictation`, `install-`/`remove-dictation-voxtype`) | ported onto the Voxtype rows plan 093 already had; the backend is in `$HASEEN_USER_STATE/dictation-backend`. Superwhisper's three are refused: a proprietary cloud service whose setup writes into `~/.config/omarchy/plugins` |
| Language and input (`language`, `locale-generate`, `input-method`, `setup-input`, `setup-keyboard`, `font-cjk`) | reads are Omarchy's own (registry, choice, fontconfig); `locale-generate` uncomments and generates a registry locale as root through `run_root`; input goes to fcitx5 (`fcitx5-remote`, `fcitx5-configtool`, engines through `haseen install package`). Setting Omarchy's language, its fcitx5 rewrite (`input-method configure`) and its CJK font choice are refused: they write the user's uwsm environment and fcitx5 and fontconfig files, and haseen's language is plan 109's |
| Session and update (`system`, `update-pacman`) | `omarchy-system <verb>` goes to the `omarchy-system-<verb>` rows, dropping Omarchy's internal `--execute`/`--inhibited`; `update-pacman` runs upgrades only (`-Su`-style), as root in a `systemd-run --scope`, and refuses `-S <pkg>`, removals and `--overwrite` |
| Desktop settings (`hyprland-window-transparency`, `hyprland-workspace-layout-default`, `toggle-fullscreen-desktop`, `theme-bg-intro`, `toggle-animations`, `setup-security-ssh-agent`) | onto haseen's toggles: opaque only (glassy needs blur); the default layout is Hyprland's and stays, per-workspace layouts go through `haseen toggle workspace-layout`; full screen is `omarchy-toggle-bar` plus `haseen toggle gaps`; theme intros are off and stay off; two shims |
| Theme sync to herdr machines (`theme-set-herdr-machines`, `toggle-theme-sync`) | ported, off by default (the flag in haseen's toggle store); only a theme name travels over SSH |
| `ascii` | runs Omarchy's installed copy: its FIGlet font comes with no licence, so haseen ships none |
| Refused outright | `dock` (no dock), `pkg-defaults` (`haseen layer list`), `provision-hardware` (`haseen hw apply`), `kernel` (`haseen boot list`; haseen never edits Limine's config) |
| Inert | `lifecycle-dispatch`, `update-boot` (platform boot packages, no-ops on x86), `theme-set-glass` (no blur), `theme-bg-boot-intro` (no intro videos), `hyprland-window-minimize` (no dock) |
| Apple | `hw-aarch64-apple`, `hw-apple-silicon`: recorded, not provided |

Neither IO nor luna is ARM, a Dell XPS 13 DX13260, or has a Cam Link: the
N1x, GB10, Snapdragon and those two devices' steps run only against fixture
trees (`tests/test-omarchy-45.sh`).

### The three breaks

- `omarchy-launch-terminal` takes `--pid=N` (digits only) and passes N to
  `omarchy-cmd-terminal-cwd`, which now takes `[terminal-pid]` and reads that
  terminal's newest child from `/proc/<pid>/task/*/children` through
  `sysroot_path`, as Omarchy's does (`bin/omarchy-cmd-terminal-cwd@v4.5.0-rc1:15-20`).
- `omarchy-hyprland-workspace-layout-toggle` is a translation now: `back` is
  the same step, because haseen cycles between two layouts. It calls
  `haseen-toggle-workspace-layout toggle`, unchanged (plan 105 owns that
  command).
- `omarchy-menu-select` is a translation now: `--width`, `--height` and
  `--maxheight` pass through to `haseen menu select`; `--multiple`,
  `--selected`, `--on-change`, `--change-key` and any other flag after `--`
  exit 2 with a message. `typing_setup.py:64-67` takes a non-1 status as
  "the selection menu could not open" and reports it, instead of applying
  nothing silently. haseen answers its three callers itself (setup-input,
  setup-keyboard, language), so the path is reached only by Omarchy's
  absolute `/usr/bin` copies.

### The three security fixes

- `omarchy-windows-vm` builds the RDP arguments in an array and pipes them to
  `xfreerdp3 /args-from:stdin`; a dry run prints `<password>` in place of the
  password.
- `omarchy-tailscale-receive` announces a received file by name only; the
  notification never carries it as an image.
- `omarchy-sudo-passwordless` handles 4.5's names: `--disable` removes
  `99-omarchy-nopasswd-<user>`, `-<uid>` and `99-omarchy-permanent-nopasswd-<uid>`
  and stops `omarchy-nopasswd-expire-<user>.timer` and
  `omarchy-nopasswd-expire-<uid>-*.timer`; a timed grant replaces any of them
  with haseen's; `--active` asks sudo itself (`sudo -n -l -l`) whether a
  NOPASSWD rule applies; `permanent` is refused, pointing at
  `haseen setup passwordless-sudo`. `haseen setup passwordless-sudo --off`
  removes the same five files and three timer patterns.

### The router

`omarchy up` is `omarchy update`, as in 4.5's router. The longest-prefix
match stops at a group that has longer members: `omarchy agent account`
lists the `omarchy-agent-account-*` commands rather than running
`omarchy-agent` with `account` as its argument.

## Rejected options

- **Inert predicates or a refused detector.** An inert predicate says "yes"
  and a refused detector stops mkinitcpio (Problem 1).
- **Sourcing `lib.sh` from the detector.** `common.sh` needs `HOME` and
  reads the caller's environment; mkinitcpio runs as root without one. The
  detector and the predicates that run it stand alone, as Omarchy's.
- **Refusing the account commands until plan 108.** Omarchy 4.5 users who
  already added accounts would lose them under haseen; passing through keeps
  Omarchy's registry working and keeps the rows easy to change for plan 108.
- **Porting `agent-account-copy`/`-transfer`.** They send Claude, Codex and
  Grok login files to another host over SSH. haseen never ships agent
  credentials between machines.
- **Porting `omarchy-language` set, `input-method configure` and
  `font-cjk` set.** They write `~/.config/uwsm/env.d`, fcitx5's config and
  fontconfig drop-ins, files haseen seeds and must not edit afterwards; the
  locale needs Omarchy's passwordless rule; haseen's language is plan 109.
- **Shipping the `omarchy-ascii` font.** Delta Corps Priest 1 carries no
  licence (`bin/omarchy-ascii@v4.5.0-rc1`, its embedded header).
- **Editing `bin/haseen-menu-select` or `bin/haseen-toggle-workspace-layout`
  for the 4.5 flags.** The first is the menu's own interface, the second plan
  105's; translating in `share/haseen/omarchy/` fixes the callers without
  either.
- **Implementing `--multiple` in haseen's menu.** It needs a multi-select UI
  and live `--on-change` callbacks for one caller haseen answers anyway.
- **Porting Superwhisper.** A proprietary cloud service whose installer links
  an Omarchy plugin into `~/.config/omarchy/plugins`.
- **`omarchy-kernel` as a read-only translation.** Its `get`/`list` read
  `BOOT_ORDER` patterns haseen's Limine setup does not use; `haseen boot list`
  is the haseen way.
- **Adding the Grok and Kimi variables to `tests/lib.sh`'s sandbox.** Only
  `tests/test-omarchy-45.sh` runs those collectors; `tests/lib.sh` is global
  in plan 100, so the edit would run the whole suite on every pull request
  for one file's hygiene. The test clears them itself.

## Inventory

The 94 rows added (`share/haseen/omarchy/commands.tsv`):

| Command | Kind | haseen | What it does here |
|---|---|---|---|
| `omarchy-agent-account-add` | translate | own script | runs Omarchy's own account sign-in when Omarchy is installed (haseen has no agent accounts yet) |
| `omarchy-agent-account-copy` | refuse | none: sign in on the other machine with the agent's own CLI | It sends your Claude, Codex and Grok logins to another machine over SSH; haseen never ships agent credentials to another host. |
| `omarchy-agent-account-exec` | port | own script | runs claude, codex or grok with the selected account's config home; never refuses |
| `omarchy-agent-account-home` | port | own script | prints the active account's config home from Omarchy's registry, nothing for the primary one |
| `omarchy-agent-account-list` | translate | own script | runs Omarchy's own account list when Omarchy is installed (haseen has no agent accounts yet) |
| `omarchy-agent-account-mode` | translate | own script | runs Omarchy's own account switching mode when Omarchy is installed (haseen has no agent accounts yet) |
| `omarchy-agent-account-remove` | translate | own script | runs Omarchy's own account removal when Omarchy is installed (haseen has no agent accounts yet) |
| `omarchy-agent-account-rename` | translate | own script | runs Omarchy's own account rename when Omarchy is installed (haseen has no agent accounts yet) |
| `omarchy-agent-account-state` | translate | own script | runs Omarchy's own account registry when Omarchy is installed (haseen has no agent accounts yet) |
| `omarchy-agent-account-transfer` | refuse | none: sign in on the other machine with the agent's own CLI | It exports and imports agent login credentials for account copy; haseen never ships agent credentials to another host. |
| `omarchy-agent-account-use` | translate | own script | runs Omarchy's own account choice when Omarchy is installed (haseen has no agent accounts yet) |
| `omarchy-agent-usage-grok` | port | own script | prints the Grok usage record as JSON for an agents panel |
| `omarchy-agent-usage-kimi` | port | own script | prints the Kimi usage record as JSON for an agents panel |
| `omarchy-apply-n1x-gpu-memory` | port | own script | on an NVIDIA N1x, shrinks the firmware's GPU memory reservation to 4 GiB; elsewhere nothing |
| `omarchy-ascii` | translate | own script | runs Omarchy's own omarchy-ascii when installed: haseen does not ship its unlicensed logo font |
| `omarchy-boot-direct` | port | own script | exit 0 when an active haseen or Omarchy direct-boot UEFI entry is set; --number lists them |
| `omarchy-branding-about-animation` | port | own script | the About sheen's frame helpers, sourced by Omarchy's About |
| `omarchy-capture-screenrecording-process` | port | own script | checks or signals this user's screen recorders |
| `omarchy-chromium-add-feature` | port | own script | adds a feature to --enable-features in an existing chromium-flags.conf |
| `omarchy-crash-mute` | port | own script | silences one program's crash notifications, or lists the silenced ones |
| `omarchy-default-dictation` | port | own script | prints the dictation backend, or runs its installer |
| `omarchy-dev-notification-demo` | port | own script | plays a realistic run of notifications to look at the notification cards |
| `omarchy-dictation` | port | own script | starts, stops or toggles dictation with the configured backend |
| `omarchy-dictation-superwhisper` | refuse | `omarchy-dictation (Voxtype, local)` | haseen does not install Superwhisper, a proprietary cloud dictation service, so there is no Superwhisper backend. |
| `omarchy-dictation-use` | port | own script | stops the previous dictation backend and saves the new one |
| `omarchy-dictation-voxtype` | port | own script | Voxtype's dictation adapter: voxtype record start, stop or toggle |
| `omarchy-dock` | refuse | none: haseen has no dock; the launcher and the bar hold the apps | It configures Omarchy's dock, a shell element haseen does not have. |
| `omarchy-font-cjk` | translate | own script | prints the CJK glyph forms in use; choosing them is refused |
| `omarchy-hw-aarch64` | port | own script | exit 0 when the CPU is aarch64 |
| `omarchy-hw-aarch64-apple` | apple | — | true only on an Apple Silicon Mac (hw-platform aarch64-apple) |
| `omarchy-hw-aarch64-gb10` | port | own script | exit 0 on an NVIDIA GB10 desktop |
| `omarchy-hw-aarch64-n1x` | port | own script | exit 0 on an NVIDIA N1x laptop |
| `omarchy-hw-aarch64-qualcomm` | port | own script | exit 0 on a Qualcomm Snapdragon machine |
| `omarchy-hw-apple-silicon` | apple | — | old name of omarchy-hw-aarch64-apple |
| `omarchy-hw-dell-xps13-sidecar-amps` | port | own script | exit 0 on the Dell XPS 13 DX13260 with SKU 0E53 |
| `omarchy-hw-elgato-camlink-4k` | port | own script | exit 0 while an Elgato Cam Link 4K is plugged in |
| `omarchy-hw-match-device-tree` | port | own script | exit 0 when the device tree's root lists one of the compatible strings |
| `omarchy-hw-n1x` | port | own script | old name of omarchy-hw-aarch64-n1x |
| `omarchy-hw-platform` | port | own script | prints x86, aarch64 or the ARM family, exactly as Omarchy's detector (every initramfs build asks it) |
| `omarchy-hw-vm` | port | own script | exit 0 inside a virtual machine |
| `omarchy-hw-x86` | port | own script | exit 0 when the CPU is x86_64 |
| `omarchy-hyprland-corners` | port | own script | shows or sets window corners: the theme's, sharp or rounded |
| `omarchy-hyprland-window-minimize` | inert | — | it minimizes a window to the dock of a floating workspace, and haseen has neither |
| `omarchy-hyprland-window-transparency` | translate | own script | prints opaque, haseen's only window look; transparent and glassy are refused |
| `omarchy-hyprland-workspace-layout-current` | port | own script | prints a workspace's layout, dwindle or scrolling |
| `omarchy-hyprland-workspace-layout-default` | translate | own script | prints the default workspace layout; another default is refused (haseen sets layouts per workspace) |
| `omarchy-i18n` | port | own script | prints one of Omarchy's CLI strings from its installed catalogs; never refuses |
| `omarchy-input-method` | translate | own script | cycle switches fcitx5 between English and Arabic; status prints the input method |
| `omarchy-install-ai-claude` | translate | `haseen-install` | installs claude-desktop (repositories first, the AUR last) and opens it |
| `omarchy-install-camera` | port | own script | on a Snapdragon, turns on Chromium's PipeWire camera capture; elsewhere nothing |
| `omarchy-install-chromium-claude` | port | own script | seeds the Claude extension into Chromium's, Chrome's and Edge's extension directories |
| `omarchy-install-dictation-superwhisper` | refuse | `omarchy-install-dictation-voxtype (local dictation)` | Superwhisper is a proprietary cloud dictation service whose setup links an Omarchy plugin into ~/.config/omarchy/plugins, which haseen never writes. |
| `omarchy-install-dictation-voxtype` | translate | own script | installs Voxtype (omarchy-voxtype-install) and makes it the dictation backend |
| `omarchy-install-service-microsoft` | port | `haseen-webapp-install` | adds Microsoft Outlook, Word, Excel, PowerPoint, Teams and OneDrive as web apps |
| `omarchy-install-t3code-app` | translate | `haseen-install app t3-code` | stable installs T3 Code from haseen's catalogue; the nightly AppImage is refused |
| `omarchy-install-video-decode` | port | own script | on a Snapdragon, sets mpv and Chromium up for its video decoder; elsewhere nothing |
| `omarchy-kernel` | refuse | `haseen boot list (Limine's entries)` | It rewrites BOOT_ORDER in /etc/default/limine and rebuilds the boot entries; haseen never edits Limine's configuration. |
| `omarchy-language` | translate | own script | prints Omarchy's language, its list or a locale; setting it is refused |
| `omarchy-lifecycle-dispatch` | inert | — | it runs a platform boot package's lifecycle hooks, and on x86 every operation is a no-op |
| `omarchy-locale-generate` | port | own script | generates the system locale of one of Omarchy's languages, as root |
| `omarchy-mise-default-tools` | port | own script | lists Omarchy's default mise tools, or opts you out of them or back in |
| `omarchy-n1x-probe` | port | own script | records N1x hardware and boot evidence to /var/log/haseen-n1x-probe.log |
| `omarchy-network-wifi-connected` | port | own script | exit 0 when the default route runs over connected Wi-Fi |
| `omarchy-pkg-defaults` | refuse | `haseen layer list` | It prints Omarchy's install package lists for a platform; haseen's packages come from its layers. |
| `omarchy-provision-hardware` | refuse | `haseen hw apply` | It finishes the hardware steps an Omarchy image build deferred to first boot; haseen sets hardware up on the running machine. |
| `omarchy-remove-ai-chatgpt` | port | own script | removes the ChatGPT desktop app; asks before deleting its settings and caches |
| `omarchy-remove-ai-claude` | port | own script | removes the Claude desktop app; asks before deleting its settings and caches |
| `omarchy-remove-ai-grok-bot` | port | own script | removes Grok Bot; asks before deleting its settings and data |
| `omarchy-remove-ai-lm-studio` | port | own script | removes LM Studio; asks before deleting its settings and models |
| `omarchy-remove-ai-ollama` | port | own script | removes Ollama and its service; asks before deleting the pulled models |
| `omarchy-remove-dictation-superwhisper` | refuse | `haseen remove package superwhisper-bin` | Its cleanup takes a plugin out of ~/.config/omarchy/plugins, which haseen never changes. |
| `omarchy-remove-dictation-voxtype` | translate | own script | removes Voxtype (omarchy-voxtype-remove) and forgets it as the dictation backend |
| `omarchy-remove-service-microsoft` | port | own script | removes the Microsoft web apps that are installed |
| `omarchy-remove-service-ssh-agent` | port | own script | turns gcr-ssh-agent off and drops haseen's and Omarchy's SSH_AUTH_SOCK export |
| `omarchy-security-functions` | refuse | `haseen update` | It hardens sudo for Omarchy's own update and release commands, which haseen does not run. |
| `omarchy-setup-input` | translate | own script | installs a CJK input method's fcitx5 engine and opens fcitx5-configtool |
| `omarchy-setup-keyboard` | translate | own script | opens fcitx5-configtool to choose the keyboard layouts |
| `omarchy-setup-security-ssh-agent` | shim | `haseen-setup-ssh-agent` | turns on the gcr-ssh-agent SSH agent for this user |
| `omarchy-sleep-disabled` | port | own script | exit 0 when Omarchy turned system sleep off on this machine |
| `omarchy-system` | translate | own script | logs out, reboots or shuts down through haseen system |
| `omarchy-system-lid-inhibit` | port | own script | holds logind's lid inhibitor while a USB-C or unknown-connector display is in use |
| `omarchy-theme-bg-boot-intro` | inert | — | it plays a background's intro video, and haseen's shell plays none |
| `omarchy-theme-bg-intro` | translate | own script | background intros are always off: status exits 1, disable succeeds, enable is refused |
| `omarchy-theme-set-fcitx5` | port | own script | publishes the theme to fcitx5's candidate window |
| `omarchy-theme-set-glass` | inert | — | it writes see-through backgrounds for glassy windows, which haseen never turns on (no blur) |
| `omarchy-theme-set-herdr-machines` | port | own script | with theme sync on, sets your theme on your herdr machines over SSH |
| `omarchy-theme-set-hunk` | port | own script | nudges running hunk sessions to repaint in the new colours |
| `omarchy-toggle-animations` | shim | `haseen-toggle-animations` | turns Hyprland animations on or off |
| `omarchy-toggle-fullscreen-desktop` | translate | own script | hides the bar and removes the gaps together, or brings both back |
| `omarchy-toggle-theme-sync` | port | own script | flips theme sync to your herdr machines (off by default) |
| `omarchy-update-boot` | inert | — | it verifies a platform boot package's boot chain after an update, a no-op on x86 |
| `omarchy-update-pacman` | translate | own script | runs pacman system upgrades as root in a scope that survives the session; installs are refused |
| `omarchy-webapp-window-class` | port | own script | prints the window class Chromium gives a web app opened at a URL |
| `omarchy-windows-key` | port | own script | prints the OEM Windows product key the firmware stores |

The two rows changed:

| Command | Was | Now |
|---|---|---|
| `omarchy-hyprland-workspace-layout-toggle` | shim `haseen-toggle-workspace-layout toggle` | translate: `back` is the same step |
| `omarchy-menu-select` | shim `haseen-menu-select` | translate: one pick through `haseen menu select`; multiple selection exits 2 |

## Tests

Run with the hermetic wrapper of the batch rules, on 2026-10-22, base
`origin/main` at 56d0cd8:

| Run | Result |
|---|---|
| `tests/run.sh --affected origin/main` (36 of 155 test files) | 5122/5122 |
| `tests/test-omarchy-45.sh` (new) | 256/256 |
| `tests/test-omarchy-commands.sh` | 179/179 |
| `tests/test-omarchy-restart.sh` | 277/277 |
| `tests/test-omarchy-update.sh` | 177/177 |
| `tests/test-menu.sh` | 309/309 |
| `tests/test-crashwatch.sh` | 14/14 |
| `tools/affected-tests.sh --check` | 2568 files, 155 tests, 1812 covers globs: every file covered |
| `tools/lint.sh` (shellcheck 0.11) | lint OK |
| `tools/check-docs.sh` | check-docs OK |

- `tests/test-omarchy-commands.sh` pins the 540-name union to the three
  fixture lists, the 533 and 93 counts, the six removed rows, the four Apple
  rows, the sourced and standalone scripts, and that this plan's inventory
  lists every new name with its kind.
- `tests/test-omarchy-45.sh` runs each new answer against fixture roots and
  recorders of haseen's commands: the detector on x86, Snapdragon, Apple,
  N1x (ACPI and PCI), GB10, contradictory identities and image manifests, a
  launch without `-p` (126) and a launch as mkinitcpio does it (`env -i`, no
  `HOME`); each predicate; the N1x EFI write, the probe, the camera and
  video-decode steps on a Snapdragon fixture and their no-op on x86; the lid
  inhibitor; `omarchy-i18n` and `omarchy-language` over fixture catalogs;
  the sourced scripts; the plumbing, theme, installer, remover, dictation and
  agent commands, the copy/transfer refusals never reaching SSH; the three
  caller fixes; `omarchy-system`, `omarchy-update-pacman` and the router.
- The first affected run failed one check (5121/5122): test-core's static
  rule caught a refusal note in `commands.tsv` that said "unlinks" next to
  `~/.config/omarchy/plugins`. Only the wording was wrong (the row refuses);
  it was reworded and the second run passed.

## Owner steps

1. After merging, install haseen on IO and luna as usual (`./install.sh`
   relinks `/usr/local/bin`). A new link appears only where no other file
   already holds the name.
2. On a machine with Omarchy 4.5, check that `sudo mkinitcpio -P` still
   builds (it runs haseen's `omarchy-hw-platform`, which must print `x86`):
   `sudo env -i PATH=/usr/local/bin:/usr/bin omarchy-hw-platform`.
3. If you used Omarchy 4.5's passwordless sudo, run
   `haseen setup passwordless-sudo --off` once; it now removes the UID-named
   and permanent grants too.

## Not done

- The `boot_hooks_known` guard in `share/haseen/omarchy/bin/omarchy-plymouth-set`
  (from the review of plan 101, #57): it belongs after #57 adds
  `boot_hooks_known` to `share/haseen/lib/boot.sh`. #57 had not merged when
  this plan finished, so it is a follow-up.
- The 52 argument and behaviour drifts in older ports (survey A.1.4): a later
  re-sync.
- haseen's own agent accounts (plan 108) and language (plan 109): the
  pass-through and refused rows above change with them.
- `haseen theme set` does not run the herdr mirror yet; only
  `omarchy-theme-set-herdr-machines` does.
- Claude desktop has no catalogue entry, so the app menu does not list it;
  `omarchy-install-ai-claude` installs it through `haseen install aur`.
