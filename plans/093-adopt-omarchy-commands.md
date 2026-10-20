# Plan 093: Adopt Omarchy's commands

## Status

- **Priority**: P1
- **Effort**: L
- **Risk**: MEDIUM (a few hundred command names in `/usr/local/bin` now
  shadow an installed Omarchy's `/usr/bin` ones on every `PATH`; each one is
  a table row or a script with a test, refusals fail loudly, and
  `--uninstall-tree` removes exactly haseen's links)
- **Depends on**: 052 057 061 074
- **Category**: compat, CLI, installer
- **Planned at**: 2026-10-20, owner request: "adopt all omarchy scripts and no
  apple hardware scripts."
- **State**: IN PROGRESS

## Problem

On IO (Omarchy 4.0.6 installed, haseen the desktop) the owner ran
`omarchy-update`, and Omarchy's own shell started beside haseen's: two bars.
The path, in Omarchy 4.0.6 (`/usr/share/omarchy/bin` on IO):

1. `omarchy-update:63` runs `omarchy-update-restart`;
2. `omarchy-update-restart:51` runs `omarchy-restart-shell || true`;
3. `omarchy-restart-shell:69` kills Omarchy's shell instance (none ran) and
   `:83` runs `hyprctl dispatch 'hl.dsp.exec_cmd("omarchy-launch-shell")'`;
4. `omarchy-launch-shell:19` starts `quickshell -n -p "$OMARCHY_PATH/shell"`.

Line numbers here and in the inventory are Omarchy's `v4.0.6` tag
(github.com/basecamp/omarchy), whose `bin/` holds the same 446 commands as
`ls /usr/share/omarchy/bin` on IO, plus `omarchy-debug`, `omarchy-debug-idle`
and `omarchy-upload-log`, which the 4.0.6-1 package does not ship.

haseen answered 11 Omarchy names (`share/haseen/shell/Compat/bin/omarchy-*`,
plans 052, 057, 060), and only on the shell's own `PATH` (`bin/haseen-shell-run`):
a terminal, a Hyprland bind or `hyprctl dispatch exec_cmd` still found
Omarchy's `/usr/bin` copies. Plan 057 had left the rest alone because "a
shim that pretends would be worse than Omarchy's command".

## Decision

The owner's request reads as: every `omarchy-*` command Omarchy 4.0.6 ships,
and the `omarchy` router, exists under haseen and does the haseen-correct
thing; none exists for Apple-only hardware. "Haseen-correct" is one of five
things, recorded per command in `share/haseen/omarchy/commands.tsv`:

| Kind | What the command does |
|---|---|
| `shim` | `exec` the haseen command that does the same job, the caller's arguments after any fixed ones |
| `translate` | a script of its own: Omarchy's arguments, verbs or output mapped onto a haseen command |
| `port` | a script of its own: Omarchy's script adapted under MIT (upstream notice kept, NOTICE.md row), with Omarchy's paths, state, branding and calls to other `omarchy-*` commands replaced by haseen's |
| `refuse` | doing what Omarchy's does would break a haseen rule (ADR 0001: `pacman.conf`, mirrorlist, HOOKS, Limine, SDDM; `PKG_DENY`; the AUR order) or only makes sense for Omarchy's own install, release or development machinery. It prints `<name>: not available under haseen.`, the reason as a sentence and `The haseen way: <command>` (`No haseen equivalent: <what to do>` when there is none), and exits 1: never a silent success |
| `inert` | nothing to do under haseen (an Omarchy-only cache or UI state haseen does not have): one line on stderr saying so, exit 0 |

The sixth kind, `apple`, is recorded so the inventory stays complete; no
command of that name exists.

## Design

### One table, one dispatcher, scripts where needed

- `share/haseen/omarchy/commands.tsv`: `name<TAB>kind<TAB>target<TAB>note`,
  one row for each of Omarchy 4.0.6's 446 commands. `target` is the haseen
  argv (`haseen-toggle-nightlight toggle`) for a shim, the haseen way for a
  refusal.
- `share/haseen/omarchy/bin/<name>`: a relative link to `../dispatch` for a
  `shim`, `refuse` or `inert` row, a script for `translate` and `port`, and
  nothing for `apple`. `share/haseen/omarchy/dispatch` reads the row named by
  `$0`.
- `share/haseen/omarchy/lib.sh`: every script sources it. It finds haseen
  from the script's own location (`readlink -f "$0"`), because these
  commands run from `/usr/local/bin` with no `HASEEN_PATH` in the
  environment; `HASEEN_PATH` still wins when set, as everywhere else.
  It sources `lib/common.sh`, so every state change goes through `run`,
  `run_root` or `write_user_file` and honours `--dry-run` and `DRY_RUN`.
- Omarchy's scripts `source` three of its commands (`omarchy-restart-gum`,
  `omarchy-shell-config`, `omarchy-sudo-keepalive`). A link to the dispatcher
  would read the sourcing script's `$0`, so these three are scripts of their
  own whatever their kind, safe to source: `omarchy-restart-gum` returns
  quietly, `omarchy-shell-config` refuses and stops the sourcing script
  before it edits Omarchy's `shell.json`, and `omarchy-sudo-keepalive` asks
  for the password through `run_root` in subshells, so nothing of haseen's
  leaks into the caller but Omarchy's `SUDO_KEEPALIVE_PID` and its EXIT trap.
- `omarchy` is Omarchy's router (`bin/omarchy`, MIT) over this directory:
  `omarchy a b` runs the longest matching `omarchy-a-b`, Omarchy's aliases
  (`screenshot`, `screenrecord`, `logout`, `reboot`, `shutdown`,
  `background`) are kept, `omarchy commands [--all]` lists the table, a
  group prints its commands, and an unknown command exits 127 as Omarchy's
  does (`omarchy:1062-1068`).
- The 11 earlier shims moved from `shell/Compat/bin/` into
  `share/haseen/omarchy/bin/` (5 became table rows); `dms` and `ydotool`
  stay in `Compat/bin`.

### Where they are installed, so that they win

`install.sh` links every `share/haseen/omarchy/bin/<name>` into `PREFIX/bin`
(`/usr/local/bin`) with one `ln -sf -t`, the link target
`../share/haseen/omarchy/bin/<name>`. On IO `/usr/local/bin` precedes
`/usr/bin` everywhere a name is looked up:

- the systemd user manager (`systemctl --user show-environment`):
  `PATH=…:/usr/local/sbin:/usr/local/bin:/usr/bin:…`;
- Hyprland's own environment (`/proc/<Hyprland pid>/environ`), which
  `exec_cmd`, binds and `uwsm app` inherit: the same order;
- login shells: Arch's `/etc/profile:15-17` appends `/usr/local/sbin`,
  `/usr/local/bin`, then `/usr/bin`.

Omarchy's own scripts call each other by name, so even Omarchy's copy of
`omarchy-restart-shell`, run by absolute path, ends in haseen's
`omarchy-launch-shell` (step 3 above). `haseen shell run` also puts
`share/haseen/omarchy/bin` on the shell's `PATH`, so a checkout's shell has
them without an install. An existing `PREFIX/bin/omarchy*` that is not
haseen's link is never replaced (a warning names it); a link to a command a
later haseen drops is removed; `--uninstall-tree` removes haseen's links and
nothing else. `haseen doctor` says whose `omarchy-launch-shell` comes first
on `PATH` and whether an Omarchy shell is running.

### The restart chain

- `omarchy-launch-shell` (port): stops any Quickshell instance whose config
  is under `$OMARCHY_PATH/shell/` (`qs list -a -j`, then `qs kill --pid`),
  then makes sure the desktop shell haseen uses runs: `dms.service` after
  `haseen shell use dms`; else `haseen-shell.service` (nothing to do when it
  is active, and nothing yet while `graphical-session.target` is down:
  the target starts the unit, and a start before the session's Wayland
  environment exists fails and counts toward plan 061's recovery offer);
  else, without a unit, a running `qs -p $HASEEN_PATH/shell`
  counts, and otherwise `haseen shell run` runs in the foreground, as
  Omarchy's launcher keeps its own shell.
- `omarchy-restart-shell` (translate): the same stop, then `haseen shell
  restart` (or `systemctl --user restart dms.service`).
- `omarchy-update` (shim): `haseen update`.
- `omarchy-update-restart` (port): Omarchy's reboot offers (a replaced kernel
  or Hyprland binary), asked only at a terminal, then haseen's
  `omarchy-restart-shell`. Omarchy's `restart-*-required` markers are written
  by Omarchy's migrations, which haseen does not run, so they are not read.

## Rejected options

- **Shims on the shell's `PATH` only** (plan 057's scope): the IO incident
  ran from a terminal and through `hyprctl dispatch exec_cmd`, neither of
  which sees `bin/haseen-shell-run`'s `PATH`.
- **Prepending a haseen directory through `~/.config/uwsm/env.d`**: it is a
  user file (seeded once, CLAUDE.md), reaches neither SSH/TTY logins nor
  root, and is not needed: `/usr/local/bin` already comes first in all three
  environments above.
- **Pointing `OMARCHY_PATH` at a haseen tree**, so `$OMARCHY_PATH/bin/…` calls
  reach haseen too: Omarchy's still-installed scripts and the owner's Omarchy
  plugins read `$OMARCHY_PATH/default`, `/shell` and `/themes`
  (e.g. `omarchy-restart-shell:8-11` takes the shell config from it), and
  `/usr/bin/omarchy-*` absolute calls would stay Omarchy's anyway.
- **Replacing or diverting Omarchy's `/usr/bin/omarchy-*`**: pacman owns
  them (`omarchy` 4.0.6-1 on IO) and the next update restores them; ADR 0001
  and the "never clobber system files" rule.
- **One file per command, no table**: about 300 near-identical three-line
  files, and no single place a test can hold against Omarchy's list.
- **Removing the `omarchy` package from IO**: the owner's call; ADR 0001
  names a fresh CachyOS install as the supported migration.

## Inventory

(Filled from `share/haseen/omarchy/commands.tsv`.)

## Apple hardware

Two commands drive Apple hardware only and have no haseen answer (their
rows are `apple`; `omarchy commands --all` lists them, nothing else does):

- `omarchy-brightness-display-apple`: Apple Studio Display and Pro Display
  XDR brightness through `asdcontrol` (`omarchy-brightness-display-apple:3`);
- `omarchy-hyprland-monitor-focused-apple`: true only when the focused
  monitor is one of those (`.make == "Apple Computer Inc"`,
  `omarchy-hyprland-monitor-focused-apple:11`).

Apple-only branches dropped from commands that are adopted:

- `omarchy-brightness-display:38-40,47-49,79-84`: the Apple-display path
  through the two commands above;
- `omarchy-hw-display:10-14`: the T2 Touch Bar's `appletb_backlight`
  exclusion and `gmux_backlight` as the first candidate;
- `omarchy-setup-direct-boot:23-26`: the refusal on Apple firmware;
- `omarchy-menu-keybindings:427`: the "Apple Display" sort priority (the
  command is haseen's keybind sheet);
- `omarchy-upgrade-to-quattro:684,786-799`: `asdcontrol-git` for Apple
  displays (the command is refused as a whole).

`apple-touch-icon` in `omarchy-webapp-install:90-104` and
`omarchy-install-ai-openclaw:17` is a web icon convention, not hardware,
and stays.

## Findings outside this plan

Found while classifying the commands and left for their own plans:

- `bin/haseen-agent-crash:96` passes `--prompt` to every agent; Omarchy's
  `omarchy-agent` maps each agent's own prompt syntax.
- `bin/haseen-webapp-install:126` takes the first word of the default
  browser's `Exec=`, which is `/usr/bin/flatpak` for a Flathub browser.
- `share/haseen/lib/catalog.sh:304-328` (`catalog_post_install`) has no step
  for the `once` entry (`share/haseen/default/catalog.json:76`); Omarchy's
  `omarchy-install-service-once:11` enables `once-background.service`.
- `bin/haseen-restart:46-49` (`wifi`) unblocks the radio but never runs
  `nmcli networking on`, which Omarchy's `omarchy-restart-wifi:8` does.

## Tests

`tests/test-omarchy-commands.sh`, hermetic (sandbox HOME, stub PATH,
fixtures; nothing reaches the live session):

- the table names exactly Omarchy 4.0.6's 446 commands
  (`tests/fixtures/omarchy-4.0.6/bin.txt`, from `ls /usr/share/omarchy/bin` on
  IO), each once, with one of the six kinds; the two Apple commands are the
  `apple` rows and do not exist; `omarchy/bin` holds every other name and
  nothing else, table rows as links to the dispatcher, the rest as
  executable scripts that source `lib.sh`; every shim names an existing
  haseen command; every port keeps Omarchy's MIT notice;
- every refusal prints why and the haseen way and exits 1; every `inert`
  command says so and exits 0; every command answers `--help` with exit 0;
  none of them runs a stubbed binary;
- the router: longest-prefix routes, Omarchy's aliases, `omarchy commands`
  without and with the Apple rows, group listings, unknown commands;
- the installer: one `ln -sf -t PREFIX/bin` for every name, existing haseen
  links kept, a foreign file or link left alone and named, a retired
  command's link removed; `--uninstall-tree` removes haseen's links only;
- the restart chain: a fake Omarchy `omarchy-restart-shell` (its last step,
  `omarchy-restart-shell:83`) run by absolute path with haseen's directory
  first on `PATH`, as on IO: Omarchy's launcher never runs, the running
  Omarchy shell is stopped, haseen's own instance is left alone and
  `haseen-shell.service` is started; `omarchy-restart-shell` and
  `omarchy-launch-shell` under a running unit, without a unit, and under
  DMS; `omarchy-update-restart` offers a reboot only for a replaced kernel,
  never without a terminal, and restarts haseen's shell;
- per-command behaviour of the translations and ports (below).

## Not done

- Absolute-path calls still reach Omarchy's own copies:
  `/usr/bin/omarchy-*`, `$OMARCHY_PATH/bin/omarchy-*` (plan 057 found
  `t1nk33r.agents` calling `/usr/bin/omarchy-notification-send`), and
  Omarchy's systemd units (`ExecStart=/usr/bin/omarchy-…` on IO). Their
  inner calls by name do reach haseen.
- The PKGBUILD phase (plan 013, `PREFIX=/usr`) cannot put these names in
  `/usr/bin`: they are the `omarchy` package's files there. It will need a
  directory of its own ahead on `PATH`.
- Installing on IO and the live `omarchy-update` there are integrator steps.
