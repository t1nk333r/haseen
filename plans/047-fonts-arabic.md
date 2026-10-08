# Plan 047: Fonts, Arabic rendering, Qt theming and the seed registry

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: LOW (user-level configuration only; no root, no package beyond what the base layer already installs)
- **Depends on**: 004 033
- **Category**: desktop
- **Planned at**: 2026-10-05, owner request ("arabic support in hyprland and all other")
- **State**: DONE 2026-10-05

## Problem

haseen shipped **no fontconfig at all** (`grep -rn fontconfig share bin` → nothing
before this plan), while shipping the parts that need it: `haseen.prayers`, the
fcitx5 Arabic↔English seed and Arabic punctuation in XCompose. The consequences
on a real machine:

- The Latin faces haseen installs (Inter, JetBrainsMono Nerd Font) carry no
  Arabic glyphs, so every Arabic run falls through to whatever fontconfig ranks
  next. Unpatched that is **Noto Nastaliq Urdu** — the sloping calligraphic
  style used for Urdu and Persian — so Modern Standard Arabic renders as if it
  were Farsi. Standard Arabic wants Naskh.
- `haseen font set NAME` reached the shell and the four terminal configs and
  nothing else: GTK, Qt, Electron and every web view kept their own idea of
  `monospace`.
- Qt applications followed no theme at all: `QT_QPA_PLATFORMTHEME` was unset.

A fourth problem was structural: every new user-config seed meant editing
`bin/haseen-seed-user`, which serialises unrelated work on one file.

## Decision

- **Two files, in a fixed order.** `share/haseen/themed/fonts.conf.tpl` renders
  with the rest of the theme into `~/.local/state/haseen/current/theme/fonts.conf`
  and *assigns* the generic families from the theme's `font_family` / `font_mono`
  (so `haseen font set` now reaches every toolkit). Because fontconfig's
  `mode="assign"` replaces the whole family list, each list carries its own
  fallbacks: a Latin Noto face, `Noto Sans Arabic`, `Noto Naskh Arabic`,
  `Noto Color Emoji`. `share/haseen/default/fontconfig/arabic.conf` then adds the
  script rules, which test `lang` rather than `family` and therefore still fire
  after the assign: Naskh appended for `ar`, Nastaliq prepended for `ur` (where
  it is correct), and Nastaliq demoted for `ar` by zeroing its `fontversion` for
  that language only.
- **The seeded user file is an includes file**, generated like XCompose because
  it carries absolute paths: theme render first, `arabic.conf` second. Both
  `ignore_missing`, so a home with no theme applied still has valid fontconfig.
- **Omarchy's system file is defeated, not deleted.** A machine migrated from
  Omarchy keeps `/etc/fonts/conf.d/50-omarchy.conf` (package `omarchy-settings`,
  which haseen refuses to install, ADR 0001). fontconfig reads `/etc/fonts/conf.d`
  **before** the user config, and that file *assigns* the generic names away —
  `sans-serif` → `Liberation Sans`, `monospace` → `JetBrainsMono Nerd Font` — so
  haseen's generic rules would never match. The template therefore re-maps what
  Omarchy substituted. This is a user-level, reversible fix; deleting a
  package-owned system file is not an option (pacman restores it, and
  `docs/architecture.md` §3 forbids clobbering system files).
- **Qt follows GTK, not a second theming stack.** `QT_QPA_PLATFORMTHEME=gtk3` in
  the desktop layer's session env. The plugin is `libqgtk3.so` from `qt6-base`
  (`pacman -Qo /usr/lib/qt6/plugins/platformthemes/libqgtk3.so` →
  `qt6-base 6.11.2-3`), so it costs no package, and it reuses the GTK colours
  `themed/gtk.css.tpl` already renders. Omarchy reached the same conclusion from
  the other direction and removed Kvantum in its migration `1785351479`.
- **Seeds became modules.** `share/haseen/seeds/NN-<name>.sh` each define
  `seed_main` and declare `# haseen:seed <path>|<description>` lines;
  `bin/haseen-seed-user` sources and runs them in name order and builds `--help`
  from the declarations. Adding a seed is now adding a file.
- **Seeds reach every user** (landing review, 2026-10-08). Nothing called
  `haseen seed user`, so the seeded defaults of this plan and of 037, 038, 041
  and 044 reached only a user who knew to run it. `install.sh` now runs it
  after the layers and migrations on every run, fresh or upgrade (not
  `--tree-only`), and migration `1791466288-seed-user.sh` runs it once for a
  HOME upgraded another way. Each `seed_main` runs in its own errexit
  subshell; a failed seed is named at the end and the others still land. The
  migration and the installer warn on a failed seed rather than failing, so
  a read-only rc does not hold back later migrations.
- **A theme installed from a git repo may not ship `fonts.conf`**
  (`THEME_INSTALLED_DENIED`): fontconfig's `<include>` reads any path, so a
  stranger's theme could pull a file of its choosing into every application's
  font configuration. It is denied, not merely reviewed as colour data.

## Rejected

- **qt6ct / Kvantum** for Qt theming: a second palette to keep in sync with the
  GTK one, two more packages, and Omarchy's own migration notes say it never
  tracked the theme.
- **Installing `noto-fonts-extra`** for Nastaliq: 100+ MB for a face that the
  Arabic rules exist to *demote*. The Urdu rules are no-ops without it, which is
  the correct behaviour on a machine with no Urdu.
- **Copying waydots' file verbatim**: it pins `0xProto Nerd Font` and carries a
  `prgname=quickshell` override for Omarchy's hard-coded `monospace`. haseen's
  font is a theme token, so the family belongs in the template, not in a static
  file.
- **A `fc-cache` run after `haseen theme set`**: fontconfig re-reads its
  configuration per process; the cache is for font *files*, which do not change.
  Running apps pick the new mapping up when they restart, which the plan says.

## Verification

- `tests/test-seeds.sh`: the two includes are present and in the right order,
  the dry run plans the write without touching `$HOME`, and `fc-pattern -c`
  against the seeded file (no installed font needed) shows what fontconfig
  does with it: Arabic keeps the theme face and gains Noto Naskh Arabic, Urdu
  puts Noto Nastaliq Urdu first, Latin is untouched, and the Arabic rules apply
  with no theme render. The `target="font"` rules (the Nastaliq demotion,
  hinting) need real fonts and are covered only by the live table below.
- `tests/test-theme.sh`: `fonts.conf` is in `THEME_OUTPUTS` (every stock theme
  renders it) and in the installed-theme denylist classification test.
- `tests/test-desktop.sh` (+1): the session env exports `QT_QPA_PLATFORMTHEME=gtk3`.
- **Live `fc-match` on the reference machine**, against a scratch home seeded and
  themed by the real commands, with `/etc/fonts/conf.d/50-omarchy.conf` present:

  | pattern | before | after |
  |---|---|---|
  | `monospace` | JetBrainsMono Nerd Font | JetBrainsMono Nerd Font |
  | `sans-serif` | Liberation Sans (Omarchy's assign) | Noto Sans (theme family; Inter is not installed on this box) |
  | `Liberation Sans` | Liberation Sans | Noto Sans — proof the Omarchy override is defeated |
  | `monospace:lang=ar` | Noto Naskh Arabic | Noto Naskh Arabic |
  | `sans-serif:lang=ar` | Noto Naskh Arabic | Noto Naskh Arabic |
  | `sans-serif:lang=ur` | — | Noto Nastaliq Urdu |

- `haseen seed user --help` lists every seeded path with its description,
  generated from the modules.
- `tests/test-migrate-defaults.sh`: `install.sh --dry-run` plans the seeds on
  a fresh and an upgraded HOME and not under `--tree-only`; the migration
  seeds, leaves a user's own file alone, changes nothing on a re-run, and
  exits 0 with the failed seed named when `~/.bashrc` is read-only.
  `tests/test-seeds.sh`: one failing seed does not stop the others.

## Open

- `Inter` is not installed on the reference machine (the desktop layer installs
  it; that layer has not been applied there), so the `sans-serif` row above
  resolves to the next family in the list. That is the fallback working, not a
  substitute for testing on a machine with the font present.
- Arabic *shaping* is HarfBuzz's and was not re-verified here; what this plan
  changes is which face is selected.

## Execution record

`share/haseen/themed/fonts.conf.tpl`,
`share/haseen/default/fontconfig/arabic.conf`,
`share/haseen/seeds/{10-btop,20-fcitx5,30-fontconfig,40-xcompose}.sh`,
`bin/haseen-seed-user` (rewritten as a module runner),
`share/haseen/layers/theme/theme-lib.sh` (`THEME_INSTALLED_DENIED`),
`share/haseen/layers/desktop/layer.sh` (`QT_QPA_PLATFORMTHEME`),
`tests/test-seeds.sh`, `tests/test-theme.sh`, `tests/test-desktop.sh`;
landing review: `install.sh` (seed user on every run),
`share/haseen/migrations/1791466288-seed-user.sh`, `tests/test-migrate-defaults.sh`,
`tests/test-paths.sh` (one more installer phase).
