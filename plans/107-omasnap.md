# Plan 107: Omasnap instead of Tensaku

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: LOW–MEDIUM. PRINT and the capture menu now start a different
  program, and existing machines get a package from a migration. Everything
  scripted (`--geometry`, `--upload`, `--stdout`, `window`, `output`, `dms
  screenshot`, circle to search) keeps haseen's own slurp/grim capture and its
  printed path; without Omasnap (no `[omarchy]` repo, or
  `HASEEN_SCREENSHOT_TOOL=grim`) every command behaves as before this plan.
  Tensaku is never removed.
- **Depends on**: 041 (the capture, upload and Arabic OCR this keeps), 093 and
  102 (the `omarchy-capture-*` answers), 100 (affected tests), 101 (Omarchy's
  migration 1788129995 stays sealed)
- **Category**: capture, desktop
- **Planned at**: 2026-10-21, owner decision (below)
- **State**: DONE 2026-10-22 (pull request; the steps on IO and luna are owner
  steps)

## Decision (owner, 2026-10-21)

Asked "Check omarchy 4.5 and what worth adopting", the owner read the survey
(`~/.cache/haseen-wt/omarchy-45-survey.md`, not in this repository) and chose:

- Fixes: "4.5 compatibility (Recommended)", "Security & bug fixes
  (Recommended)", "Neutralise Omarchy's migrations (Recommended)". Not chosen:
  "Override the package's tweaks", so kyber, `KillMode=mixed`, BBR/ARP, the
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

This plan is **"Omasnap instead of Tensaku"** (survey B.2 #26). It replaces
the owner's 2026-10-14 decision ("Tensaku replaced `satty`, as in Omarchy",
plan 041); `AGENTS.md`'s "Installed with the desktop layer" line now says
Omasnap replaced Tensaku (owner, 2026-10-21, plan 107). Off by default does
not apply: this swaps a default tool by the owner's decision. Removing Tensaku
from a machine is a state change the brief did not ask for, so nothing removes
it (Owner steps say how).

## Problem

1. **haseen's screenshot UI was its own, and its editor Tensaku.** PRINT ran
   `haseen capture screenshot` (`share/haseen/default/hypr/binds.lua:103` before
   this plan), which picked a rectangle with slurp and saved it with grim
   (`bin/haseen-capture-screenshot@origin/main:60` default `region`); `--edit`
   opened Tensaku, else swappy (`:186-191`, `:225-226`). Omarchy 4.5 hands the
   whole flow to Omasnap: `bin/omarchy-capture-screenshot@v4.5.0-rc1:9-23` is
   `exec omasnap` with `copy`/`save` mapped to `--copy`/`--save` (Omarchy
   e265934bb "Use Omasnap for screenshots", merged as ee8ebf615, #9446).
2. **The desktop layer installed Tensaku** (`aur:tensaku`,
   `share/haseen/layers/desktop/packages.txt@origin/main:48`), seeded its
   config and a link to a themed CSS (`share/haseen/seeds/80-capture.sh@origin/main:6-7,18-26`,
   `share/haseen/default/tensaku/config.toml`, `share/haseen/themed/tensaku.css.tpl`).
   Omarchy 4.5 ships `omasnap` instead (`install/omarchy-base.packages@v4.5.0-rc1:104`;
   `tensaku` was line 114 at v4.0.6) and its migration 1788129995 installs
   Omasnap and runs `omarchy-pkg-drop satty tensaku` (Omarchy c0ba99670).
3. **Omarchy's answers lagged 4.5.** haseen's `omarchy-capture-screenshot`
   took the mode and processing words by position and had no `scroll`
   (`share/haseen/omarchy/bin/omarchy-capture-screenshot@origin/main:33-34`,
   survey `changed-1` row "omarchy-capture-screenshot ... DRIFT");
   `omarchy-clipboard-open` opened images in `tensaku-edit` (`:48,54`), where
   4.5 opens them in Omasnap (`bin/omarchy-clipboard-open@v4.5.0-rc1:30-34`).
4. **Existing machines (IO, luna) have Tensaku and no Omasnap**, and haseen's
   update never applies layers (`bin/haseen-update` runs pacman, the AUR
   helper and Flatpak only), so a manifest change alone would never reach them.

## Evidence

Verified, not taken from the survey:

- **Omarchy**, cloned read-only to a scratch directory and deleted afterwards:
  `v4.5.0-rc1` = 03ff1eff3, `v4.0.6` = 237f1b407, `quattro` at a17a001b7
  (`git describe --tags`: `v4.5.0-rc1-27-ga17a001b7`). On `quattro` only
  `default/hypr/bindings/utilities.lua` differs from the tag among the files
  this plan reads (`git diff --stat v4.5.0-rc1 quattro -- ...`): 0a7beb7d6
  moves the extra screenshot chord to Super + Ctrl + Alt + C, which is plan
  105's. Files read: `bin/omarchy-capture-screenshot`, `bin/omarchy-clipboard-open`,
  `migrations/1788129995.sh`, `default/hypr/apps/screenshot-selection.lua:4-5`
  (the `^omasnap$` layer rule, with `no_screen_share = true`),
  `default/hypr/bindings/utilities.lua:38-39` (PRINT and Super + Shift + S run
  `omarchy-capture-screenshot` bare), `default/omarchy/omarchy-menu.jsonc:120`
  (one Screenshot row, no scroll row), `install/omarchy-base.packages`,
  `test/shell.d/omasnap-test.sh` (the argument cases `tests/test-omasnap.sh`
  repeats).
- **Omasnap**, cloned read-only (omacom/omasnap), tag `v1.21.0` = 3ee643c, the
  version `[omarchy]` packages:
  - licence: `LICENSE` is MIT, Copyright (c) 2026 Tobi Lütke; the fonts in
    `assets/` are OFL-1.1 (`assets/OFL.txt`, `assets/Inter-OFL.txt`,
    `assets/JetBrainsMono-OFL.txt`);
  - command line (`src/main.cpp@v1.21.0`): positional `smart|region|windows|fullscreen|scroll`
    or an image path (`:234-257`), `--copy`/`--save` quick output (`:193-199`),
    `--editor window|overlay` (`:183-188`), quick output refused with an image
    input (`:271-275`), a fresh capture copies and previews by default (`:276-279`),
    a single-instance lock that a second capture press dismisses and an image
    edit takes over (`:291-305`);
  - where a save goes: `OMASNAP_SCREENSHOT_DIR`, then `[output] directory` in
    `~/.config/omasnap/omasnap.conf`, then `~/Pictures/Screenshots`, with its
    own `screenshot-{date}_{time}-{app}` name (`src/capture.cpp@v1.21.0:357-385`,
    `src/output-config.cpp@v1.21.0:9-25`); the editor saves through the same
    path (`src/editor.cpp@v1.21.0:3964`) and announces it
    (`:4013-4019`) through `omarchy-notification-send` found on `PATH`
    (`src/capture.cpp@v1.21.0:2501-2525`);
  - OCR: `tesseract -l "$OMASNAP_OCR_LANGS"`, else `$OMARCHY_OCR_LANGS`, else
    `eng`, with `--oem 1 --psm 6 --dpi 300` (`src/capture.cpp@v1.21.0:2468-2499`);
  - editor keys (`README.md@v1.21.0:439-443`): Ctrl+C copies, Ctrl+S saves,
    Enter copies and saves, Esc dismisses;
  - theme: v1.21.0 reads no theme file (`git grep -i theme v1.21.0 -- src`
    finds only Qt's platform theme, which `src/main.cpp:150-159` bypasses).
    Following Omarchy's theme came later and is in no release yet (d52b49a,
    reading `~/.local/state/omarchy/current/theme/{colors,shell}.toml`), so
    there is nothing for haseen's theme pipeline to render;
  - the layer rule: the v1.21.0 README recommends `no_screen_share = true`
    (`README.md@v1.21.0:123-128`); 282b338 (after the tag, "docs: fix
    scrolling capture setup guidance", Fixes #128) removes it because Hyprland
    then blacks out the whole overlay in output capture and a scrolling
    capture stitches nothing.
- **The package** (`pacman -Si omasnap`, luna, 2026-10-22): `Repository:
  omarchy`, `Version: 1.21.0-2`, `Licenses: MIT OFL-1.1`, `Depends On:
  hyprland layer-shell-qt qt6-base tesseract tesseract-data-eng wayland
  wl-clipboard`. Its install closure on luna (`pacman -Sp --print-format
  '%r/%n %v' omasnap`): `extra/layer-shell-qt 6.8.0-1`, `omarchy/omasnap
  1.21.0-2`: neither `omarchy` nor `omarchy-settings` (`PKG_DENY`), so
  `pkg_guard_closure` (`share/haseen/lib/packages.sh:145`) has nothing to ask.
  Not in the AUR (`aur.archlinux.org/rpc/v5/info?arg[]=omasnap&arg[]=omasnap-git`
  returned only `tensaku`) nor in Chaotic-AUR (`pacman -Sl chaotic-aur`), so
  `[omarchy]` is its only source: an `omarchy:` entry, like herdr's.
  `tesseract-data-ara 2:4.1.0-5` stays: Omasnap's OCR reads Arabic only with it.
- **Tensaku** (`pacman -Si omarchy/tensaku`): 0.29.0-2, MPL-2.0, installed on
  luna (`pacman -Q tensaku`); its `tensaku-edit` is the package's own script
  (`pacman -Ql tensaku`).

## What was built

- **`share/haseen/lib/omasnap.sh`** (new): how haseen starts Omasnap.
  - `omasnap_use` (`:35`): Omasnap is used when installed, unless
    `HASEEN_SCREENSHOT_TOOL=grim` (never) or `=omasnap` (required, else a
    clear error). The switch exists so a test, or a user, can have the old
    behaviour on a machine that has Omasnap.
  - `omasnap_env` (`:89`): `OMASNAP_SCREENSHOT_DIR` is haseen's folder
    (`$HASEEN_SCREENSHOT_DIR`, else `xdg-user-dir PICTURES`, `screenshot_dir`
    `:24`, moved here from the screenshot command) unless the user set
    `OMASNAP_SCREENSHOT_DIR` or Omasnap's own `[output] directory`
    (`omasnap_conf` `:51` reads the INI as QSettings does: exact names,
    quotes removed); an explicit `HASEEN_SCREENSHOT_DIR` still wins over
    the INI. `OMASNAP_OCR_LANGS` is `$HASEEN_OCR_LANGS`, else `ara+eng`
    (`haseen capture text`'s default), unless the user set it or
    `OMARCHY_OCR_LANGS`, which Omasnap reads next.
  - `omasnap_exec` (`:107`) execs it (so the same key dismisses it again) or
    prints `DRYRUN: env … omasnap …`.
- **`bin/haseen-capture-screenshot`**:
  - modes `smart` (the new default) and `scroll`; `smart`, `region` and
    `scroll` go to Omasnap (`:155-161`) when no option of haseen's own
    capture is given (`own`: `--geometry`, `--output`, `--file`, `--format`,
    `--quality`, `--cursor`, `--upload*`, `--stdout`, `--no-notify`);
    `--no-save` is `--copy`, `--no-copy` is `--save`, `--edit` is `--editor`
    in the user's `[editor] mode` (overlay unless `window`). `--edit` with
    `--no-save` or `--no-copy` stays haseen's: Omasnap's editor decides the
    output itself.
  - without Omasnap, `smart` is slurp's rectangle, as `region` was (`:166`);
    `scroll` fails and says why.
  - `window`, `output` and `screen` stay one-key grim captures.
  - the editor is Omasnap, then Tensaku, then swappy (`:218-228`). Omasnap
    edits the grabbed file (`--file`) and saves under a name of its own, so
    it is given a private folder and what appears there is what it saved
    (`:258-290`); its own notification, which would name that private file,
    goes to a silent `omarchy-notification-send` first on its `PATH`
    (`:322-326`), and haseen announces the kept file. The folder is made in
    `$XDG_RUNTIME_DIR` (`:278`), because a pin made in the editor inherits it
    and may save there later, after this run removed it. haseen's `--edit`
    contract holds: Enter (or Ctrl+S) saves, Escape, a pin or a copy-only
    keep nothing, `--edit --upload` uploads the edit.
- **`share/haseen/omarchy/bin/omarchy-capture-screenshot`**: with Omasnap, 4.5's
  mapping (`:40-54`): `copy`/`save` anywhere become `--copy`/`--save`, `slurp`
  is dropped, everything else goes to omasnap as it is, `OMARCHY_SCREENSHOT_DIR`
  becomes `OMASNAP_SCREENSHOT_DIR`, plus haseen's folder and OCR languages.
  Without it, plan 093's flow, now taking the words in any order and
  `--editor=X` as `--edit` (`:56-67`); `scroll` fails.
- **`share/haseen/omarchy/bin/omarchy-clipboard-open`**: an image opens in
  Omasnap as in 4.5 (`:51-63`), `tensaku-edit` without it.
- **Desktop layer**: `omarchy:omasnap` (`share/haseen/layers/desktop/packages.txt:35`)
  in place of `aur:tensaku`; without the omarchy-repo layer it is skipped with
  the warning herdr and xdg-terminal-exec get. `tesseract-data-ara` stays.
- **Migration** `share/haseen/migrations/1792634179-omasnap.sh`: where the
  desktop layer is applied (`layer_is_applied desktop`), `pkg_install_omarchy
  omasnap`, which installs from `[omarchy]` only (after `pkg_guard_closure`)
  or warns; nothing else, so Tensaku stays. A fresh install seals it
  (`install.sh` seals every shipped migration) and gets Omasnap from the layer.
- **Binds and rules**: PRINT is "Screenshot" (Omasnap's smart pick) and
  SHIFT/CTRL + PRINT stay the focused window and monitor at once
  (`share/haseen/default/hypr/binds.lua:103-109`); Omasnap's overlay has no
  layer animation (`share/haseen/default/hypr/windowrules.lua:93-104`),
  without `no_screen_share` (above).
- **Tensaku support files**: the seed no longer writes Tensaku's config or its
  CSS link (`share/haseen/seeds/80-capture.sh:1-12`), and
  `share/haseen/default/tensaku/config.toml` and
  `share/haseen/themed/tensaku.css.tpl` are gone (with `tensaku.css` from
  `THEME_COLOUR_ONLY`, `share/haseen/layers/theme/theme-lib.sh:66`). Files
  already seeded stay the user's: the link dangles once a theme is set again,
  which Tensaku 0.29.0 treats as no overrides (plan 041).
- Docs: `AGENTS.md` (the one line), `handoff.md` (map rows), `NOTICE.md` (two
  rows), `docs/reference-shell-gaps.md:125`, `commands.tsv:63`'s note.

Every capture entry point now agrees: PRINT and the capture menu's
Screenshot row (`haseen capture screenshot`), the gestures' three-finger
click (`haseen capture screenshot region`, `share/haseen/lib/gestures.sh:278`),
`omarchy screenshot` and Omarchy's menus and plugins
(`omarchy-capture-screenshot`), and clipboard images. haseen's own bar has no
screenshot widget (`grep -rni screenshot share/haseen/shell --include=*.qml`);
an Omarchy bar widget reaches the same answer.

## Outside the brief's owned paths

- `share/haseen/default/hypr/binds.lua:103`: only the PRINT line and a
  comment above it. Plan 103 owns the terminal copy/paste lines (`:98-100`),
  three lines above; the two changes do not overlap.
- `share/haseen/default/hypr/windowrules.lua`: one layer rule.
- `share/haseen/layers/theme/theme-lib.sh:66` (`tensaku.css` out of
  `THEME_COLOUR_ONLY`) and `tests/test-theme.sh:16`, with the template.
- `tests/test-desktop.sh` (the omarchy: warning and install lines name
  omasnap), `tests/test-omarchy-system.sh` and `tests/test-capture-upload.sh`
  (`HASEEN_SCREENSHOT_TOOL=grim` where they test the pre-Omasnap paths; the
  Tensaku seed checks removed), `tests/test-mux.sh:3` and
  `tests/test-shelltools.sh:3` (a covers glob for the removed directory).
- `handoff.md`, `NOTICE.md`, `docs/reference-shell-gaps.md`.

## Rejected options

| Option | Why not |
|---|---|
| `haseen capture screenshot` = `exec omasnap`, as Omarchy 4.5 | breaks every scripted caller: `--geometry`, `--upload`, `--stdout`, `--file`, the printed path (`dms screenshot`, `haseen search screen`, plan 041's upload) |
| `window`/`output` through `omasnap windows`/`fullscreen` | those are Omasnap's picker modes (a window to pick, a monitor to confirm), not one-key captures; Omarchy's answer keeps them for Omarchy's callers |
| `aur:omasnap` | not in the AUR: on a machine without `[omarchy]` the layer would fail on it instead of skipping |
| Omasnap's default folder (`~/Pictures/Screenshots`) | grim's captures would land in `~/Pictures` and Omasnap's beside it; haseen passes its own folder unless the user named one for Omasnap |
| Forcing `OMASNAP_SCREENSHOT_DIR` always | would override the user's `[output] directory` in `omasnap.conf`, which the variable beats |
| Omasnap as editor with its own toast and save | the toast names a private file haseen moves at once, and haseen's file name, `--file`, `--no-save` and `--upload` would be lost |
| A "Scrolling screenshot" menu row, or a new bind | no visual clutter: S in the overlay and `haseen capture screenshot scroll` reach it; Omarchy's menu has no such row; new binds are plan 105's |
| `no_screen_share = true` on the overlay, as Omarchy 4.5 | blacks out the overlay in output capture, so scrolling capture stitches nothing (Omasnap 282b338, #128) |
| A theme template for Omasnap | v1.21.0 reads no theme; the unreleased version reads Omarchy's state directory, which haseen does not write (Not done) |
| Keeping Tensaku's seed and template | haseen no longer installs Tensaku; it stays only as an editor fallback where already installed |
| Uninstalling Tensaku in the migration | the brief: a package the user has stays; removal is an owner step |
| `OMASNAP_OCR_LANGS` in a seeded `environment.d` file | a new seed reaches existing machines only through another migration, and Omasnap's own processes (pins, its notification's edit action) already inherit it from haseen's launch |

## Tests

New `tests/test-omasnap.sh` (160 checks), with `# haseen:covers` in its header:
the hand-over and its arguments, folder and OCR rules (13 cases), every
option that keeps haseen's own capture, `HASEEN_SCREENSHOT_TOOL`, Omasnap as
the editor (Enter keeps, uploads and copies the edit under haseen's name with
Omasnap's toast silenced; Escape keeps nothing; no private folder is left,
with and without a runtime dir), the Tensaku and swappy fallbacks, Omarchy's
`omarchy-capture-screenshot` cases from its own `test/shell.d/omasnap-test.sh`,
clipboard images, the manifest, the migration on fixture sysroots (installs
from `[omarchy]` only, skips with the layer hint, leaves an installed Omasnap
and a machine without the desktop layer alone, never removes Tensaku), the
binds, the overlay rule and the seed. Omasnap is a recording stub; no window
opens.

- `tools/affected-tests.sh --check`: 2596 files, 158 tests, 1845 covers
  globs, every file covered.
- `./tests/run.sh --affected origin/main` (51 files, from the change's 26
  paths): 8163/8163, run from a short bind mount of the checkout. From the
  T3 worktree's own long path, test-nvim-theme ("one line per spec") and
  test-themegen-keys (its Quickshell IPC socket path passes the 108-byte
  limit) fail; both pass from a short path, with this change and on
  `origin/main` alike (190/190 for the two files each way).
- `tools/lint.sh` (shellcheck 0.11.0): lint OK, 889 shell files.
- `tools/check-docs.sh`: OK. gitleaks on the branch range: no leaks; the
  privacy pattern over `git log -p`: no match.
- On luna Tensaku is installed, so the swappy fallback check skips there; CI
  has neither and runs it.

## Owner steps

On IO and luna, after the merge and the usual deploy:

1. `haseen migrate` (or `haseen layer apply desktop`): installs Omasnap with
   `sudo pacman -S --needed omarchy/omasnap` (on luna it adds
   `layer-shell-qt`). If it warns that `[omarchy]` is not enabled, run
   `haseen layer apply omarchy-repo desktop`.
2. `hyprctl reload` (or log out and in) for the PRINT description and the
   overlay rule.
3. Press PRINT: drag a region, click a window or open space, S first for a
   scrolling region; PRINT again dismisses. Screenshots go to `~/Pictures`
   as before; to use another folder for both haseen's and Omasnap's captures,
   set `HASEEN_SCREENSHOT_DIR`.
4. To remove Tensaku (optional, the owner's call): `sudo pacman -Rns
   tensaku`, then `rm -r ~/.config/tensaku` (the seeded config and the
   `overrides.css` link are yours; haseen never touches them). If
   `~/.config/imv/config` binds `tensaku-edit` (an Omarchy-era file, not
   haseen's), change that line to `omasnap "$imv_current_file"` by hand.
5. To go back to the old picker without removing Omasnap:
   `HASEEN_SCREENSHOT_TOOL=grim` in the session environment.

## Not done

- Omasnap's theme: when `[omarchy]` ships a release that follows the theme
  (Omasnap d52b49a), it reads `~/.local/state/omarchy/current/theme/`, which
  haseen does not populate; theming it then means a link or a render there
  (a follow-up plan).
- Omasnap's OCR keeps its own `--dpi 300`, which plan 041 found merges
  Arabic words; `haseen capture text` (and `haseen search screen text`) stays
  the Arabic-tuned OCR.
- Super + Ctrl + Alt + C (Omarchy 0a7beb7d6) is plan 105's; it will run
  `haseen capture screenshot` and so reach Omasnap.
