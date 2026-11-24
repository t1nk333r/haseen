# Plan 201: the docs say what is true, and the gates check what they claim

## Status

- **Priority**: P3
- **Effort**: S
- **Risk**: LOW. Documentation, the docs and lint gates, and the test
  selector. The selector change is in a global path, so this plan's own pull
  request runs the whole suite. A new file that only a whole-tree sweep
  reaches now fails `--check` until a test covers it.
- **Depends on**: 100 (affected tests), 115 (no frame by default), 176
  (affected tests on `main`)
- **Category**: docs, CI
- **Planned at**: 2026-11-24, from the owner ("fix them", after the
  35-auditor audit)
- **State**: DONE 2026-11-24 (`tests/test-affected.sh` 90/90,
  `tests/test-notice.sh` 4/4; the affected selection is `all` because
  `tools/affected-tests.sh` is global; the metadata half of finding 8 waits
  for the owner, see below)

## Findings

The audit read plan 182's branch before pull request #140 merged. Each
finding was checked again on 9a9e82ab
(`main` with plans 182 to 184), and each one still held. Findings 3 and 4
are the same defect, reported by two auditors.

### 1. handoff.md gave 091 as the next free plan number

`handoff.md:118` was headed "State and queue (2026-10-14)", and `:129` said
"The next free plan number is 091". `plans/091-shell-production-polish.md`
exists, and the last row of `plans/README.md` was 184. CLAUDE.md tells
agents to read `handoff.md` first. The rest of that section described pull
requests #39 to #42.

**Fix.** The section is now "State and queue (2026-11-24)". It says the
record on `main` runs to plan 184, that this audit's fixes are plans 185 to
201, that the next free number is the one after the last row of
`plans/README.md`, and that `main`'s copy should be checked again before a
merge. The header date is 2026-11-24.

**Test.** `tools/check-docs.sh` has a fourth check: AGENTS.md and handoff.md
may not name a "next free plan number" that already has a plan file. On the
old `handoff.md` it prints `a doc names 091 as the next free plan number,
but plans/091-*.md exists`, and on the new one it passes.

**Rejected.** Writing 202 in the file. It goes stale with the next plan,
and a parallel pull request can take it first, which is how plan 182 was
renumbered.

### 2. README said `main` runs the full suite and the bar flows into a frame

`README.md:100` said "`main` runs the full `tests/run.sh` after each merge".
Since plan 176, `.github/workflows/ci.yml:3-7` runs `tests/run.sh
--affected` on a push to `main` for that push's changes only, and runs the
full suite only from a manual run or when a global path changes.
`README.md:11` said the bar "flows into a slim frame around the screen", but
`jq .frame share/haseen/default/shell.json` gives `{"enabled":false,"thickness":6}`,
and `docs/architecture.md:297-299` says the frame has been off by default
since plan 115.

**Fix.** README now says that CI runs the affected selection on pull
requests and on every push to `main`, and that the full suite runs only from
a manual `ci` run or when a change touches a global path. It also says the
frame is off by default and that `frame.enabled` in `shell.json` turns it
on.

**Test.** None. No gate can tell a true prose claim from a false one. The
check in finding 6 covers the paths that README's neighbours cite.

### 3 and 4. Omarchy- and DMS-adapted files with no NOTICE.md row

These headers say the code is adapted from Omarchy's MIT code:
- `share/haseen/shell/plugins/haseen.imagepicker/Images.js:3-6`;
- `share/haseen/shell/plugins/haseen.imagepicker/Panel.qml:13-18`;
- `share/haseen/default/hypr/init.lua:37-39`;
- `share/haseen/default/hypr/input.lua:4-6`.

`grep -n 'imagepicker\|init.lua\|input.lua\|helpers.lua' NOTICE.md` found
nothing. Row 107 lists the carousel files, haseen.background and
haseen.themepicker, but not haseen.imagepicker. CLAUDE.md requires a row as
well as the header notice.

Scanning every file, as the new test does, found three more files of the
same kind:
- `share/haseen/lib/greeter.sh:4` is DankMaterialShell's Greetd shape, and
  the DMS greeter row names only `bin/haseen-greeter` and
  `share/haseen/shell/greeter/`;
- `share/haseen/seeds/20-fcitx5.sh:8` and `share/haseen/seeds/40-xcompose.sh:6`
  are Omarchy's config seeds, and the seeds row names `share/haseen/default/…`
  and `bin/haseen-seed-*`.

`git log --diff-filter=A` dates them: haseen.imagepicker 33950d36,
init.lua and input.lua 51d4770c (plan 003), greeter.sh 19c25fd5, the seeds
9b6ec60d.

**Fix.** NOTICE.md gains two Omarchy rows, one for the image picker (plan
033) and one for the Hyprland Lua defaults (plan 003). The DMS greeter row
gains `share/haseen/lib/greeter.sh`, and the config-seeds row gains
`share/haseen/seeds/{20-fcitx5,40-xcompose}.sh`.

**Test.** `tests/test-notice.sh` (new) reads the first 60 lines of every file
under `bin/` and `share/`, and `install.sh`. It strips comment markers so a
sentence split across lines still reads as one. It collects each file that
says it was adapted, ported, copied, taken or derived from Omarchy or
DankMaterialShell, and fails on any that no path in NOTICE.md's Where column
matches. A Where path may use `{a,b}`, `*`, or a trailing `/` for a whole
directory. The test runs the same checker on a small tree first, so it
cannot pass by finding nothing, and it requires more than 100 adapted files
in the repository. Against the old NOTICE.md it lists exactly the seven
files above (3/4 checks pass); against the new one, 4/4 pass.

**Rejected.** Adding haseen.imagepicker to row 107. That row is plan 152's
carousel, a different piece of Omarchy code adapted at a different time.

### 5. Four tests read fixtures their covers did not name

`tools/affected-tests.sh` selects tests only through their covers
(rule 4). These four tests read a fixture tree that their covers did not
name:
- `tests/test-omarchy45-boot.sh:571` runs against
  `$FIXTURES/sb-sdboot-enabled`;
- `tests/test-omarchy-guard.sh:472,479` runs `install.sh` against
  `cachyos-grub-plain`;
- `tests/test-omasnap.sh:413` sets `HASEEN_SYSROOT` to `seeds-plain`;
- `tests/test-vapt.sh:57` copies `omarchy-limine-host/etc/os-release`.

An edit to one of those fixtures selected other tests and skipped these
four.

**Fix.** Each of the four tests now covers its fixture: `/**` where the
fixture is a whole sysroot, and the single file for `test-vapt.sh`. To stop
this happening again, `tools/affected-tests.sh --check` now fails when a
test names a fixture (`$FIXTURES/NAME` or `tests/fixtures/NAME`) and its
covers match none of that fixture's files. One covered file is enough, so
the deliberate single-file covers in `test-vapt-discovery.sh` and
`test-vapt-inventory.sh` still pass. A strict rule, every file of the
fixture, would have flagged those two as well. Names built at run time
(`$FIXTURES/$fx`) are not seen. Before this fix, `--check` on 9a9e82ab with
the new rule listed exactly the four tests.

**Test.** `tests/test-affected.sh` adds a scratch fixture that test-alpha
covers and test-gamma reads. `--check` fails and names test-gamma, but not
test-alpha. Once test-gamma covers one file of the fixture, `--check`
passes, and an edit to the fixture selects both tests. Against the old
selector the two failure assertions fail.

### 6. check-docs.sh promised to check docs/architecture.md and never read it

`tools/check-docs.sh:7-8` said check 3 covers AGENTS.md, handoff.md and
`docs/architecture.md`, but `:42` read only the first two. It had done so
since b9156ebf. A plain repo-root check of the contract would fail on about
70 strings. Most of them are paths written from `share/haseen/` or
`share/haseen/shell/`. The rest are runtime paths (`current/theme/`,
`PREFIX/bin`, `flags/context`), upstream paths, and words such as
`linux/amd64`.

**Fix.** Check 3 now also reads `docs/architecture.md`. It resolves a path
against the repository root, `share/haseen/`, `share/haseen/shell/` and
`share/haseen/omarchy/`. It checks a path only when the path's first
directory exists under one of those four, which skips the runtime paths.
Four strings were left over after that:
- `Ui/KeyboardPanel` was a real file written without its extension; the
  contract now says `Ui/KeyboardPanel.qml`;
- `share/haseen/sidecar/` and `share/haseen/sidecar/wootingd` are
  `tools/build-sidecar.sh`'s untracked output;
- `default/themed/shell.toml.tpl` is Omarchy's file.

The last three are listed in `plans/.known-absent-paths` with their
reasons. The header now describes exactly what the check does.

**Test.** With `share/haseen/shell/Compat/DmsStartupGate.qml` renamed (only
the contract cites it), the new check-docs fails with "path in
docs/architecture.md does not exist … Compat/DmsStartupGate.qml". The old
one printed "check-docs OK". With every file in place, the new check passes.

**Rejected.**
- Correcting the header only. That would keep the gap the finding
  describes.
- One allowlist entry per non-path string, about 35 lines. The
  first-directory rule says the same thing in one test.

### 7. lint.sh skipped shipped shell scripts

`tools/lint.sh:24-34` chose its candidates by name and place: `*.sh` files,
`*/bin/*` files, and a fixed list. These shell scripts were never linted:
- `share/haseen/systemd/system-sleep/haseen-charge-limit` (`#!/bin/sh`,
  which runs as root on every resume);
- `share/haseen/libexec/agent-usage-cpa`;
- `share/haseen/layers/dms/ipc-translate`;
- `tools/vptr/build.sh`;
- `share/haseen/audio/tunings/dell-xps-2026/tuning.conf`, which carries a
  `# shellcheck shell=bash` directive.

**Fix.** The candidates are now `install.sh`, `tests/*.sh` and every regular
file under `bin/`, `share/haseen/` and `tools/` whose first line is a shell
shebang or a shellcheck directive, or whose name ends in `.sh`. One awk pass
reads the first lines, and symbolic links are skipped as before. The
candidate list grew from 940 to 945 files, exactly the five above, and lost
none (compared with the old list on the same tree). All five pass
shellcheck 0.11.0 at `--severity=warning` today.

**Test.** The lint run's `shell: 945 files` line, and the list comparison
above. No test file runs `tools/lint.sh`, which is exempt from the selector.

### 8. secrets.sh does not scan commit metadata, and promised a LAN pattern

`tools/secrets.sh:4-5` promised "lab LAN addresses", and `:25-27` described
an RFC 1918 allowance, but the four patterns (`:28-33`) have no LAN entry.
Commit messages and author and committer identities are scanned neither by
the pattern pass (`:36` keeps only added `+` lines of `git log -p`) nor by
gitleaks.

**Fixed: the header.** It now lists the patterns the script really has. It
says that neither pass reads commit messages or identities, and that no
pattern matches RFC 1918 ranges.

**Rejected: a LAN pattern.** `git grep` finds 12 legitimate RFC 1918
addresses in the tree: the Sunshine firewall CIDRs in
`share/haseen/omarchy/bin/omarchy-{install,remove}-service-sunshine`, URL
fixtures in `tests/test-ai.sh`, and haseen.pager's URL security tests. The
history pass would match more, and published history cannot be rewritten.

**Deferred to the owner: a metadata scan.** The owner's own git identity is
the personal address the pattern matches. `git config user.email` in this
checkout is a gmail address. GitHub's squash merges author as the noreply
address but add a `Co-authored-by: t1nk33r <…@gmail.com>` trailer for each
locally authored commit: 58 of the last 60 commits on `main` carry it, and
141 bodies on `main` match the pattern. A metadata scan would fail the
secrets job on history that cannot change, and on every new branch pushed
from this laptop. The decision needed is whether the owner's address
counts as private. If it does, the owner switches `user.email` for this
repository to `35288751+t1nk333r@users.noreply.github.com`, and the scan
then covers commits after a baseline commit, so the history stays as it
is.

### 9. test-core.sh claimed every file under bin/ and share/

`tests/test-core.sh:2` declared `# haseen:covers bin/** share/**`, which
matched all 1,857 product files. So `--check` could never report a product
file as uncovered, and rule 6 (an unclaimed path runs every test) never
fired there. The glob is still needed: `tests/test-core.sh:104-110` greps
all of `bin/`, `share/` and `install.sh` for destructive operations on the
owner's plugin dirs, and any change there can break that check.

**Fix.** Covers lines may now sit beside `# haseen:scans GLOB…` lines. A scans
glob selects its test like a covers glob does (under rules 2 to 6), but it
claims nothing:
- `--check` still needs a covers glob, or a GLOBAL, EXEMPT or NOWIDEN entry,
  for each file;
- rule 6 still runs every test for a changed path that no covers glob
  claims;
- a scans glob that matches no file is reported as stale.

test-core's line is now a scans line. `tests/test-notice.sh`'s whole-tree
sweep is declared the same way. With test-core's globs turned into scans,
`--check` still passes on this tree, so every product file has a covering
test besides test-core. The selection does not change either: test-core
still runs for every change under `bin/` and `share/`.

**Test.** `tests/test-affected.sh` adds a test that covers `src/beta.sh` and
scans `src/**`. It checks four things:
- the scan passes `--check`;
- a change to `src/alpha/a.txt` selects both test-alpha and the sweep, and
  the report says "scanned by";
- a path that only the scan reaches selects `all` and fails `--check` as
  uncovered;
- a stale scans glob fails `--check`.

Against the old selector, the selection and stale-glob assertions fail
(84/90).

**Rejected.**
- Narrowing test-core's covers. That drops a real dependency (the
  owner-plugin grep).
- Moving the owner-plugin grep into `tools/lint.sh`. CLAUDE.md names
  `tests/test-core.sh` as the check.

**Left as it is.** Other whole-tree covers remain:
- `tests/test-i18n.sh` covers `bin/**` and `share/haseen/shell/**`;
- `tests/test-shell.sh` and `tests/test-surfaces.sh` cover
  `share/haseen/shell/**`.

Turning all of them into scans would leave three files uncovered (measured
with a selector variant):
- `share/haseen/shell/plugins/haseen.session/Panel.qml` and
  `haseen.polkit/Service.qml`, which test-surfaces really exercises;
- `haseen.keybinds/Overlay.qml`, which no test loads.

Those tests are outside this audit's findings. Each can move to scans once
its files have a covering test.

## Verification

- `tests/run.sh tests/test-affected.sh`: 90/90 (84/90 with the 9a9e82ab
  selector).
- `tests/run.sh tests/test-notice.sh`: 4/4 (3/4 with the 9a9e82ab
  NOTICE.md).
- `tools/affected-tests.sh --check`: every file covered, global or exempt.
- `tools/check-docs.sh`: OK.
- `tools/lint.sh`: lint OK, with `shell: 945 files`.
- `tests/run.sh --affected 9a9e82ab…`: `all`, because
  `tools/affected-tests.sh` is global. 178 files, 20,820/20,843 passed. The
  23 failures fail the same way on a copy of the 9a9e82ab tree, and this
  plan changes nothing under `bin/` or `share/`:
  - `test-agent-accounts.sh`, 1 check: the message names mise shims
    because mise is installed on this laptop;
  - 22 checks in `test-idle.sh`, `test-pager.sh`,
    `test-vapt-panel-conformance.sh`, `test-vapt-security-ui.sh` and
    `test-vapt-ui-adversarial.sh`: this laptop's qmltestrunner aborts with
    SIGABRT (Qt 6.12.0). The five files gave 89/111 on both trees.
