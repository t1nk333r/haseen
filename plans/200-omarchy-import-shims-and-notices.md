# Plan 200: the Omarchy import, the Omarchy shims' dry runs and four commands' notices

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW. The import maps two more Omarchy widgets and reports one
  more case instead of rewriting a file; four Omarchy ports and
  `haseen keybinds` gain `--dry-run`; one shim reads `DRY_RUN` from the
  environment; reminders get a longer unit name; crash, circle-to-search
  and reminder toasts follow the interface language; `haseen layer apply`
  fires the `layer-applied` hooks it always documented.
- **Depends on**: 048 (the Omarchy import), 070 (haseen.logo), 080
  (haseen.kblayout), 093 and 102 (the Omarchy commands), 101 (Omarchy 4.5
  import), 105 (haseen.rebind), 109 (Arabic notifications)
- **Category**: omarchy
- **Planned at**: 2026-11-24, from the owner ("fix them", after the
  35-auditor audit of a tree identical to main's 59207f25; the findings
  re-checked on main 9a9e82ab)
- **State**: DONE 2026-11-24 (`tests/run.sh --affected 9a9e82ab`, see
  Gates)

## Problem

The audit raised twelve findings in this group; two (10 and 11) are the same
defect seen by two auditors. Every one still held on 9a9e82ab: of the files
below only `docs/architecture.md` changed between 59207f25 and 9a9e82ab
(two lines elsewhere, which moved the hooks line from 767 to 769).

### 0. The import drops Omarchy's menu button and keyboard layout

`share/haseen/lib/omarchy-import.sh:27-38` (`builtin_map`) was written in
plan 048, before haseen.logo (plan 070, "the mark that opens the menu") and
haseen.kblayout (plan 080) existed, and was never updated. `omarchy.menu`
and `omarchy.keyboard-layout` fell through to `builtin()` (:120-121) and
were dropped as "Omarchy built-in with no haseen equivalent". The imported
`bar.left` replaces the default `["haseen.logo", "haseen.workspaces"]`
(`share/haseen/default/shell.json:6`), and migration 1791365994-bar-logo.sh
does not run again on an installed or sealed machine, so an imported bar
lost the logo for good. `tests/test-omarchy-import.sh` asserted the drop.

### 1. `haseen import omarchy --help` says haseen.bind

`bin/haseen-import-omarchy:61-63` said bindings.lua comes over "with o.bind
turned into haseen.bind". The translator writes `haseen.rebind`
(`omarchy-import.sh:377`), which unbinds the key first
(`share/haseen/default/hypr/init.lua:166-169`), on purpose (plan 105): an
imported bind replaces haseen's on the same key.

### 2. The splice drops every line after a block whose closing marker changed

`omarchy_lua_splice` (`omarchy-import.sh:459-471`) skipped from the opening
marker to a line equal to the closing marker byte for byte. A trailing
space, a CR, or a deleted closing line made it skip to the end of the file,
and `hypr_write` (`bin/haseen-import-omarchy:440-443`) wrote the shortened
file. The user's lines after the block survived only in the backup.

### 3. Omarchy commands called by path were not recognised

`OMARCHY_CMD_ERE` (`omarchy-import.sh:19`) refuses a `/` before
`omarchy-`, to skip `~/.config/omarchy/...`. That also skipped
`/usr/bin/omarchy-restart-waybar` and `$OMARCHY_PATH/bin/omarchy-x`, which
run Omarchy's own copies past haseen's answers (architecture 5.4). A hook
calling one was imported as plain (`bin/haseen-import-omarchy:311`), and a
bind running `/usr/bin/omarchy-menu` was carried into bindings.lua. The
awk copy of the rule (:386, :392) had the same gap.

### 4. `omarchy-sudo-docker --configured` took docker-users for docker

`share/haseen/omarchy/bin/omarchy-sudo-docker:32` ran `grep -qw docker` on
`id -nG`. `-` is not a word character, so `docker-users` or `ci-docker`
matched, and `omarchy-setup-security-sudoless-docker:37-40` said sudoless
Docker was already on without adding the user.

### 5. `omarchy-update-pacman` reset `DRY_RUN=true` to false

`omarchy-update-pacman:19-24` started from `dry=false` and set
`DRY_RUN=$dry`, overwriting what `common.sh:19` read from the environment.
`env DRY_RUN=true omarchy-update-pacman -Syu --noconfirm` ran the upgrade
as root.

### 6. Four Omarchy ports refused or ignored `--dry-run`

- `omarchy-dictation-voxtype:13-14` ran `exec voxtype record "$1"`: `start
  --dry-run` started a recording.
- `omarchy-dictation:15` exited 1 on a second argument.
- `omarchy-input-method:19` exited 1 on `cycle --dry-run`.
- `omarchy-capture-screenrecording:26-30` exited 2 on `--dry-run`, though
  `haseen-capture-screenrecord` takes it.

### 7. `haseen keybinds --reload` had no dry run

`bin/haseen-keybinds:47-60` sent `--dry-run` to usage (exit 2), and :63 ran
`hyprctl reload` directly, while every other reload goes through `run` or
prints a DRYRUN line (`haseen-toggle-gaps:51`, `haseen-refresh:81`).

### 8. Two reminders in one second shared a unit name

`bin/haseen-reminder-set:36` named the unit `haseen-reminder-<N>m-<epoch>`.
A second reminder of the same length in the same second wrote its message
file over the first one's (:42-44), then systemd-run refused the duplicate
unit and the command failed, and `haseen reminder show` listed the first
reminder with the second message (`bin/haseen-reminder-show:47`).

### 9. Crash, circle-to-search and reminder toasts stayed English

Plan 109 ("Bash: notifications yes") routes bash notifications through
`i18n`. `bin/haseen-crash-watch:47-50` (title, body, the Diagnose button),
`bin/haseen-search-screen:259,269,273,297,333` and the default reminder
body (`bin/haseen-reminder-set:34`, `bin/haseen-reminder-show:46`) sent
literal English; `tools/i18n.py check` cannot see a string that is not in an
`i18n` call.

### 10 and 11. `layer-applied` was never fired

`bin/haseen-hook:14-16` lists `layer-applied` among "the events haseen
fires", and `docs/architecture.md:769`, the skill's `theming.md:98-99` and
`omarchy-hook-install:7` say the same, but nothing ran `haseen hook run
layer-applied`: `git log -S'layer-applied' -- bin/haseen-layer-apply
share/haseen/lib/layers.sh install.sh` is empty. A hook installed for it
installed fine and never ran.

## Decision

- **0.** `builtin_map` maps `omarchy.menu` to `haseen.logo` and
  `omarchy.keyboard-layout` to `haseen.kblayout`. haseen.kblayout ships off
  (`default/shell.json:31`); like the weather widget, being in the Omarchy
  bar is the opt-in, so the import turns it on. The test expects the logo
  first in `bar.left`, the layout in the centre (and, from Omarchy 4.5's
  tray drawer, in the overflow panel), both reported as mapped.
- **1.** The help says `o.bind` becomes `haseen.rebind`, "an imported bind
  replaces haseen's bind on the same key", and that the menu button becomes
  haseen.logo. A test reads `--help`.
- **2.** A marker line matches after trailing spaces, tabs and a CR are
  dropped. An opening marker with no closing one makes the splice fail
  (status 3, nothing printed); `hypr_carry` then reports
  "`hypr/<name>: <dest> has the line '…' without its closing '…'; left as
  is`" and leaves that block alone, while the other files' blocks still
  land. Tests: an edited closing marker (trailing space and CR) is
  replaced with the user's lines after it kept; a deleted one is reported
  and nothing after it is lost.
- **3.** `OMARCHY_CMD_ERE` also matches `bin/omarchy-<letter>` after a
  character that is not a word character, `.` or `-` (so `/usr/bin/`,
  `$OMARCHY_PATH/bin/`, `"$OMARCHY_PATH"/bin/`), and the Lua translator
  takes the same ERE through `awk -v cmd_ere`, so the two can no longer
  drift. `~/.config/omarchy/...`, `hypr.omarchy-*` and `omarchy_scale`
  still do not match. Test: hooks calling `/usr/bin/omarchy-*` and
  `"$OMARCHY_PATH"/bin/omarchy-*` are reported and not copied, one reading
  `~/.config/omarchy` is copied, a bind running `/usr/bin/omarchy-menu` is
  skipped and reported beside a plain bind that is carried. The gap after
  the `omarchy` router is `[[:blank:]]+` (space or tab in both grep and
  awk), since the awk copy matches whole multi-line chunks, where
  `[[:space:]]` would span a newline (see Review).
- **4.** `id -nG | tr -s '[:space:]' '\n' | grep -qx docker`: the whole
  name. Test: `wheel docker-users ci-docker` still needs sudo.
- **5.** `dry=$DRY_RUN`; the `--dry-run` word only adds to it. Test:
  `env DRY_RUN=true omarchy-update-pacman -Syu --noconfirm` prints the
  DRYRUN line and calls nothing.
- **6.** Each port strips `--dry-run` (as `omarchy-crash-mute` does).
  The voxtype adapter runs its voxtype calls through `run`;
  `omarchy-dictation` takes no lock under a dry run and passes `--dry-run`
  to the adapter; `omarchy-input-method` already ran `fcitx5-remote -t`
  through `run`; `omarchy-capture-screenrecording` passes `--dry-run` on to
  `haseen-capture-screenrecord`. Usage lines name the flag. Tests in
  `tests/test-omarchy-45.sh`.
- **7.** `haseen keybinds` takes `--dry-run`; with `--reload` it prints
  `DRYRUN: hyprctl reload` on stderr (stdout is the sheet or its JSON) and
  reloads nothing. The help says a reload drops runtime `hyprctl keyword`
  changes. Test: a recording `hyprctl` stub sees no reload under
  `--dry-run` and one without it.
- **8.** The unit is `haseen-reminder-<N>m-<epoch>-<pid>`; two processes alive
  at once never share a PID, and `reminder show`'s and `omarchy-reminder`'s
  `${unit%%m-*}` parse is unchanged. Test: with `date +%s` stubbed to one
  value, two reminders of 5 minutes are two units with their own messages.
- **9.** The strings go through `i18n` (`i18n_n` for the minutes, "Your %1
  minute is up" / "Your %1 minutes are up"), with Arabic in
  `share/haseen/i18n/ar/notify.json`. The reminder's default stays English
  in the terminal and in `show --json` (`omarchy-reminder` reads the English
  default back as "no message"); `show --notify` uses a `notice` field,
  deleted from the JSON, and "in %1m". Tests: Arabic crash toast
  (`tests/test-crashwatch.sh`), Arabic circle-to-search toasts
  (`tests/test-capture-upload.sh`), Arabic reminder toast and `--notify`
  list with an English terminal line and JSON (`tests/test-trigger.sh`).
  The new Arabic is machine-made like the rest of the catalog
  (`ar/provenance.json` lists only reviewed keys, so it is unchanged).
- **10, 11.** `haseen layer apply` runs `haseen-hook run layer-applied
  <layer>` through `run`, after each layer it applies, so a dry run prints
  it and a skipped layer fires nothing. architecture 7 and `theming.md` say
  who fires each event. Tests in `tests/test-core.sh`: the dry run plans the
  hook for each applied layer after its marker, a refused layer plans none,
  and every event in `HOOK_EVENTS` has a `run <event>` caller in `bin/` or
  `share/`.

Every new assertion fails on 9a9e82ab with the new tests copied over (a
detached worktree of 9a9e82ab, removed after): 43 in
test-omarchy-45/restart/keybinds/trigger/crashwatch/omarchy-import
(1114/1157), 7 in test-core and test-capture-upload (489/496).

## Rejected

- **0: leaving the menu button dropped and letting the logo migration add
  it.** The migration has run (or was sealed) on every installed machine.
- **0: importing haseen.kblayout without enabling it.** It would sit in the
  bar doing nothing, while the weather widget sets the precedent that an
  Omarchy bar entry is the user's opt-in.
- **2: refusing the whole import on an unclosed block.** shell.json and the
  other files have been written by then; reporting the one block keeps the
  run useful, and a re-run after the fix finishes it.
- **2: keeping the lines after an unclosed marker and appending a new
  block.** The old, unclosed block would then be duplicated on every run.
- **3: matching any `/omarchy-`.** That catches `~/.config/omarchy-backup/`
  and similar paths; a command lives in a `bin` directory.
- **6: passing `--dry-run` through `omarchy_passthrough`-style parsing.**
  These ports run haseen's own code, not Omarchy's copies; the strip loop
  is what `omarchy-crash-mute` already does.
- **7: printing the DRYRUN line on stdout.** `--json` consumers would get a
  line that is not JSON.
- **8: `date +%s%N`.** Unique in practice but not by construction, and a
  test cannot pin it; writing the message after systemd-run alone still
  lets two reminders collide on the unit.
- **9: a `tools/i18n.py check` rule against literal English in
  `notify-send`/`haseen-notification-send` arguments.** It would flag the
  Omarchy ports' toasts (about twenty, e.g. `omarchy-tailscale-send`,
  `omarchy-chromium-ytdlp-host`), which plan 109 never routed, and
  `haseen-upload:534` and `haseen-typist:71`; that sweep is wider than these
  findings and is left for a plan of its own.
- **10, 11: removing `layer-applied` instead.** It is documented in four
  places, `haseen hook install` accepts it, and firing it is one line.
- **10, 11: firing from `layer_run_apply` in `share/haseen/lib/layers.sh`.**
  It would also cover `haseen vapt install`, but it widens the change to
  shared infrastructure (every VAPT suite); `install.sh` applies the vapt
  layer through `haseen layer apply` anyway.

## Review

An independent Sonnet reviewer read the first commit of this plan's branch
and returned APPROVE with two nits, both taken:

1. `haseen keybinds --reload --dry-run` prints its DRYRUN line with a plain
   `echo` to stderr instead of common.sh's `run`. That is deliberate (`run`
   prints to stdout and would break `--json`, as Rejected records); the
   comment above the line in `bin/haseen-keybinds` now says it is the one
   place the command skips `run` on purpose.
2. Before this plan the Lua translator's awk copy of the rule used
   `[ \t]+` after `omarchy`; sharing `OMARCHY_CMD_ERE` gave it
   `[[:space:]]+`, which matches a newline inside a multi-line chunk, so
   a Lua name `omarchy` ending one line (`local omarchy`) read as the
   `omarchy foo` router with the next line's first word, and the chunk was
   skipped. The ERE now uses `[[:blank:]]+`, which means space or tab in
   both grep and awk (`[ \t]` would be a literal backslash and `t` in grep's
   bracket). Test: a multi-line `hl.bind` holding `local omarchy` is carried
   and not reported; it failed before the change (178/180) and passes after.

## Gates

- `tests/run.sh --affected 9a9e82ab` selected 35 files (the changes touch
  `bin/` and `share/haseen/omarchy/`, which several suites cover whole):
  6040/6041. The one failure, test-vapt's "nothing from the Omarchy
  repository", is the worktree's own path: the assertion refuses
  `omarchy/` anywhere in the output, and the checkout lived in a directory
  named `g16-omarchy`. The same tree copied to a path without it passed
  `tests/test-vapt.sh` 364/364; CI's checkout path has no such name.
  After the review round the same selection (35 files) gave 6042/6043,
  the same single failure for the same reason; test-vapt.sh from a copy at
  a neutral path passed 364/364 again.
- `tools/lint.sh`: lint OK.
- `tools/check-docs.sh`: check-docs OK.
