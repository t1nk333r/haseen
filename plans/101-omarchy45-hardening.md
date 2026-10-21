# Plan 101: Make Omarchy 4.5's package and migrations safe under haseen

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MEDIUM (a pacman hook that runs as root after Omarchy's
  package transactions and writes into user ledgers through `runuser`; a
  migration that may ask for sudo; `boot_hooks` now sources the machine's
  mkinitcpio configuration instead of reading it. Each step is idempotent,
  dry-run aware and covered by fixture tests; nothing touches
  `~/.config/omarchy/plugins/`)
- **Depends on**: 028 033 036 048 093
- **Category**: compat, boot, migrations, importer
- **Planned at**: 2026-10-21, owner decision (below)
- **State**: DONE 2026-10-21 (`tests/test-omarchy-guard.sh` 93/93; the
  changed suites in Evidence; IO and luna steps in Owner steps)

## Decision (owner, 2026-10-21)

Asked "Check omarchy 4.5 and what worth adopting", the owner read the survey
(`~/.cache/haseen-wt/omarchy-45-survey.md`, not in this repository) and chose,
among others:

- Fixes: **"4.5 compatibility (Recommended)"**, **"Security & bug fixes
  (Recommended)"**, **"Neutralise Omarchy's migrations (Recommended)"**.
- Not chosen: **"Override the package's tweaks"**, so kyber,
  `KillMode=mixed`, BBR/ARP, the locale NOPASSWD rule and the mise wrappers
  that the 4.5 package installs stay as Omarchy ships them.

This plan implements "Neutralise Omarchy's migrations" and the part of "4.5
compatibility" that is about the package, the boot configuration and the bar
(survey Part A, A.6 items 1, 2, 5, 6 and 7). Plan 102 takes the commands (A.6
#3, #4), plan 103 the security and bug fixes outside them.

## Problem

IO and luna run haseen as the desktop with Omarchy's `omarchy` and
`omarchy-settings` 4.0.6 packages still installed (`pacman -Q` on luna:
`omarchy 4.0.6-1`, `omarchy-settings 4.0.6-1`). Omarchy 4.5 (tag
v4.5.0-rc1, commit 03ff1eff3) reaches them through `haseen update`. Five
things go wrong:

1. **Omarchy's migrations.** `omarchy-migrate` runs every
   `${OMARCHY_PATH:-/usr/share/omarchy}/migrations/*.sh` without a regular file
   of the same name in `${OMARCHY_MIGRATION_STATE:-$HOME/.local/state/omarchy/migrations}`
   (`bin/omarchy-migrate@v4.5.0-rc1:31-33,35-56,87-96`; unchanged since
   v4.0.6: `git diff v4.0.6 v4.5.0-rc1 -- bin/omarchy-migrate` is empty).
   haseen answers the name (`share/haseen/omarchy/commands.tsv`, plan 093), but
   `/usr/bin/omarchy-migrate`, and Omarchy's own `/usr/bin/omarchy-update`,
   which puts Omarchy first on PATH (`:32`) and runs it right after its
   pacman step (`:127-129`), still run Omarchy's scripts. 4.5 adds 84 and
   changes 4 (`git diff --name-status v4.0.6 v4.5.0-rc1 -- migrations/`:
   84 A, 4 M; 120 files at v4.0.6, 204 at v4.5.0-rc1). The ones that would
   hurt (each read at v4.5.0-rc1):
   - **1791898365** (3b4c5d0da, #15301, "Boot in 1 second"): `sudo sed` on
     `limine.conf` on the ESP named by `/etc/default/limine` (`:11-30`), with
     no Secure Boot re-enrolment: it changes the file whose hash haseen
     enrols (`docs/architecture.md` §8), and haseen never lets Omarchy edit
     Limine (plan 093's `omarchy-refresh-limine` refusal).
   - **1790528634** (e7218e36f, #13429): `rm` of
     `~/.config/omarchy/plugins/omacom.elsewhen` when it is a link (`:23-25`):
     a delete in the owner's read-only plugin directory (AGENTS.md).
   - **1791367434** (0b9dace01, #14433): `omarchy-input-method configure
     --defaults` (`:4`) runs `without_ctrl_space`
     (`default/input-methods/configure.py@v4.5.0-rc1:75-99`), which removes
     `Control+space` from fcitx5's trigger keys: haseen's English↔Arabic
     switch (`share/haseen/default/fcitx5/config:14`).
   - **1788129995** (c0ba99670): `omarchy-pkg-drop satty tensaku` (`:18`):
     haseen's capture editor (`share/haseen/layers/desktop/packages.txt:48`).
   - **1789764927** (b423f4993): installs OWE and enables `owed.service`
     (`:3-16`), a second wallpaper daemon beside `haseen-background.service`.
2. **Omarchy's login notice.** `omarchy-migrate-notify.service` runs
   `/usr/bin/omarchy-migrate-notify` by absolute path
   (`default/systemd/user/omarchy-migrate-notify.service@v4.5.0-rc1`,
   `ExecStart=`), so haseen's answer to that name never replaces it; its inner
   `omarchy-migrate --pending` reaches haseen's ledger, so it shows a second,
   Omarchy-branded notice beside `haseen-migrate-notify.service`. Omarchy's
   first run enables it, and `bt-agent` and `owed` with it
   (`install/user/first-run/enable-user-units.sh@v4.5.0-rc1:21-32`).
3. **mkinitcpio HOOKS.** 4.5 moves the baseline from a column-0
   `HOOKS=(…)` (`etc/mkinitcpio.conf.d/omarchy_hooks.conf@v4.0.6:1`) into an
   indented `HOOKS=` inside a `case` on the result of `omarchy-hw-platform`
   (`etc/mkinitcpio.conf.d/00-omarchy-hooks.conf@v4.5.0-rc1`), which `return 1`s
   when the detector fails. haseen's `boot_hooks()` read only lines starting
   `HOOKS=`/`HOOKS+=` (origin/main `share/haseen/lib/boot.sh:68-81`). Run on
   the fixtures below, it returned the stock systemd list on 4.5
   (`base systemd autodetect … fsck`) where mkinitcpio builds Omarchy's
   busybox list with `plymouth`, so `haseen plymouth set` would add a second
   `plymouth` and `haseen hibernation setup` would skip the `resume` hook.
   It also read haseen's own plymouth drop-in, a `sed` over `${HOOKS[@]}`, as
   the words `$echo ${HOOKS[@]} | sed -E s/\bbase udev|systemd\b/& plymouth/`.
4. **Omarchy's splash.** `omarchy-settings`' install scriptlet runs
   `cp -f /usr/share/omarchy/etc-overrides/plymouth-plymouthd.conf
   /etc/plymouth/plymouthd.conf` on every install and upgrade
   (`/var/lib/pacman/local/omarchy-settings-4.0.6-1/install` on luna,
   `_etc_overrides_apply`; the same line in omacom/omarchy-pkgs
   `pkgbuilds/omarchy-settings/omarchy-settings.install:114` at cce40bdd7 and
   in its `-dev` variant), and that file is `[Daemon] Theme=omarchy`
   (`/usr/share/omarchy/etc-overrides/plymouth-plymouthd.conf` on luna,
   `etc/plymouth/plymouthd.conf@v4.5.0-rc1`). Plymouth's mkinitcpio hook reads
   the theme from it when it builds (`/usr/lib/initcpio/install/plymouth:5,38`,
   plymouth 26.134.222-3). The survey marked this INFERRED; it is verified:
   the next initramfs after any `omarchy-settings` upgrade embeds Omarchy's
   splash over haseen's.
5. **The bar.** 4.5's `shell.json` has six sections, `left`, `centerBegin`,
   `center`, `centerEnd`, `right` and `tray` (the tray's drawer)
   (`shell/Commons/Util.qml@v4.5.0-rc1:179`;
   `default/agents/skills/omarchy/plugins.md@v4.5.0-rc1:81-86`), and
   `bar.background` (`opaque`, `glassy`, `none`) replaces `transparent`
   (`bin/omarchy-bar@v4.5.0-rc1:222-250`; migrations 1791968925 and 1791969355
   move existing files). `haseen import omarchy` read only `left`, `center`,
   `right` (origin/main `share/haseen/lib/omarchy-import.sh:156`) and called
   `background` unknown; the settings mirror into Omarchy's file searched the
   same three (origin/main `bin/haseen-plugin-settings:123`), so a widget
   placed in a new section was silently lost or its entry went stale.

## What was built

### 1. Seal Omarchy's migrations

`share/haseen/lib/omarchy-guard.sh` holds Omarchy's ledger rule
(`omarchy_migrations_dir:39`, `omarchy_ledger_dir:43`,
`omarchy_migrations_unsealed:56`) and `omarchy_seal_migrations:68`, which
writes a marker (content `sealed by haseen <version> on <date>: never run
here`; Omarchy reads only that it is a regular file) for every unsealed
script through `write_user_file`, leaves Omarchy's own markers alone, and
refuses a marker path that is not a regular file. Three callers:

- `bin/haseen-migrate-omarchy` (`haseen migrate omarchy [--pending]
  [--dry-run]`): this user, now. Refuses root.
- `share/haseen/migrations/1792605416-seal-omarchy-migrations.sh`: once for
  every haseen user, at their next `haseen migrate`.
- `share/haseen/default/omarchy-guard/50-haseen-omarchy.hook`, installed by
  `haseen layer apply base` (`base_omarchy_guard`,
  `share/haseen/layers/base/layer.sh:99`, Exec rendered from the installed
  tree like the secureboot hook): after every transaction that installs or
  upgrades `omarchy` or `omarchy-settings` it runs `haseen omarchy guard
  --hook` as root (`bin/haseen-omarchy-guard`). For every login account
  (uid ≥ 1000, not 65534, a real shell) with `~/.local/state/haseen`
  (`haseen_users:71`) it runs `haseen-migrate-omarchy` **as that user**
  through `runuser -u USER -- env -i HOME=… PATH=… HASEEN_PATH=…` (`:97`), so
  root never writes in a home. Under `--hook` a failed step is reported and
  the exit status is 0 (`:112`). Because `omarchy-update` calls
  `omarchy-migrate` only after its pacman transaction has returned
  (`bin/omarchy-update@v4.5.0-rc1:127-129`), 4.5's 84 migrations are sealed
  before Omarchy's own updater could run them.
- `base`'s `layer_status` reports the hook: `ok`, `warn` when it differs,
  `missing` (status 1) only where an Omarchy package is installed.

#### Mechanism chosen, and the ones rejected

- **Chosen: the pacman hook (plus the migration, plus doctor).** It is the
  only point that runs in every path that brings new migrations, including
  Omarchy's own `omarchy-update`, `paru -Syu` with the guard variable, or a
  hand-typed `pacman -S omarchy`, and it runs before `omarchy-migrate` can.
  The migration covers what is already installed, at once; doctor shows what
  is left.
- Rejected, **a step in `haseen update`**: misses every other path, above
  all Omarchy's own updater, which runs `omarchy-migrate` in the same run;
  and `bin/haseen-update` belongs to plan 103.
- Rejected, **the migrate-notify path (seal at login)**: runs after the
  window that matters (`omarchy-update` migrates in the same process as its
  pacman step), and only in a graphical login.
- Rejected, **installing the hook from `install.sh`'s tree install**: a
  system file outside PREFIX; `tests/test-omarchy-commands.sh` runs a real
  tree install with a `sudo` that runs its argv, which would then write
  `/etc/pacman.d/hooks` on the test machine. The tree install keeps writing
  only PREFIX.
- Rejected, **root writing the markers directly**: following a user's links
  as root could create files anywhere; `runuser` keeps every write the
  user's own.
- Rejected, **redirecting Omarchy (`OMARCHY_PATH`, `OMARCHY_MIGRATION_STATE`
  in the session) or replacing `/usr/bin/omarchy-migrate`**: environment
  does not reach a hand-typed absolute call or `omarchy-update`, which resets
  PATH (`:32`) and sources Omarchy's env bootstrap; the binary is pacman's.

#### What the seal skips, and what haseen does instead

Every 4.5 migration was read by the survey (annex `migrations-findings.md`
§2); these are the machine fixes among them, re-read at v4.5.0-rc1:

| Omarchy migration | What it fixes | Under haseen |
|---|---|---|
| 1788256455 (21e797535, 60c73865e, d95c68f9f) | `/etc/pam.d/polkit-1` written by Omarchy's old fingerprint/FIDO2 setup lists `pam_unix` directly, so polkit prompts have no `pam_faillock` lockout | carried: `share/haseen/migrations/1792605417-polkit-faillock.sh`, the same exact-stack match, in-place `sed`, backup and verification through `run_root`. haseen's own setup only prepends to an existing file (`bin/haseen-setup-fingerprint`, `pam_prepend`), so it never writes the stack |
| 1789294350, 1791147791 | `sudo sysctl -p` of `99-omarchy-sysctl.conf` (BBR) and `90-omarchy-arp.conf` now instead of at boot | nothing: both files arrive with the package and apply at the next boot; the owner kept the package's tweaks |
| 1788163635 | removes Omarchy's legacy `99-omarchy-nopasswd-*` grants | plan 102 (UID-named grants); Omarchy's `05-omarchy-passwordless-revoke` pacman hook still runs |
| 1791125650 | fprintd resume hook, only with `/etc/pam.d/omarchy-lock-fingerprint` | not applicable: haseen's lock uses `haseen-lock-fingerprint` |
| 1788261467 | Secret portal configuration | plan 103 |

The seal makes Omarchy's runner skip all of them; it never runs them, so
nothing of `~/.config/omarchy/plugins/` is touched (`tests/test-omarchy-guard.sh`
checks the directory's tree, including the `omacom.elsewhen` link
1790528634 deletes).

### 2. Omarchy's login notice

`share/haseen/default/omarchy-guard/omarchy-migrate-notify.conf` is installed
by the tree install (`install.sh:184`, removed at `:188`) as
`PREFIX/lib/systemd/user/omarchy-migrate-notify.service.d/haseen.conf`, the
way the dms layer places its drop-in: `ExecStart=` reset to `/usr/bin/true`
and a description that names haseen's notice. It takes effect at the next
user-manager reload or login. A condition that is always false was rejected
because it reads as a mistake in `systemctl status`.

`haseen doctor` (`bin/haseen-doctor:65`, `omarchy_guard_doctor`) now prints,
where Omarchy is installed: the seal (`omarchy migrations=sealed (N)` or
`M of N not sealed`), the hook, Omarchy's splash over haseen's, and every
enabled Omarchy user unit, read from the `.wants/` links of the user and of
`/etc/systemd/user` (`omarchy-*`, `bt-agent`, `owed`, `owe-*`), with what to
do for `owed` and the notice. Unsealed migrations, a missing hook and the
splash fail doctor; enabled units are listed.

### 3. `boot_hooks()` as mkinitcpio

`share/haseen/lib/boot.sh:81` now does what mkinitcpio 42.2 does
(`/usr/bin/mkinitcpio:1124-1143`, `arrayize_config` in
`/usr/lib/initcpio/functions:521-529`): `mkinitcpio.conf`, then every
`*.conf` in `mkinitcpio.conf.d` that is a regular file or a link to one, names
`sort -V`, concatenated and sourced once in a subshell (`set +eu`, output
discarded, nothing leaks), a HOOKS string split into words. A source that
fails (Omarchy's detector `return 1`) is a warning and status 1; mkinitcpio
would refuse to build too. `boot_hooks_known` (`:113`) stops
`haseen plymouth set` (`bin/haseen-plymouth-set:56`) and
`haseen hibernation setup` (`bin/haseen-hibernation-setup:58`) before they
mistake that for "missing". The brief said "each drop-in"; mkinitcpio
concatenates them into one script, which differs only for a `return`, so this
follows mkinitcpio.

Fixtures: `tests/fixtures/mkinitcpio-omarchy-4.0.6/` and
`tests/fixtures/mkinitcpio-omarchy-4.5/`, Omarchy's drop-ins copied unchanged
under a notice header (NOTICE.md). Results, old parser → new:

| Layout | origin/main `boot_hooks` | now |
|---|---|---|
| 4.0.6 | `base udev plymouth keyboard … fsck btrfs-overlayfs` | the same |
| 4.5 (x86 detector) | `base systemd autodetect … fsck` (the stock list) | `base udev plymouth keyboard … fsck btrfs-overlayfs` |
| haseen's sed drop-in | `$echo ${HOOKS[@]} \| sed -E …` | `base udev plymouth autodetect …` |

One finding, not changed here: under 4.0.6, `haseen-resume.conf` sorts before
`omarchy_hooks.conf`, which replaces HOOKS, so mkinitcpio drops haseen's
`HOOKS+=(resume)`; the new reader reports that truthfully ("absent"). Under
4.5 the baseline sorts first and the append takes effect
(`tests/test-hibernation.sh`).

### 4. The splash guard

The risk is real (Problem 4), so `plymouth_reset_by_omarchy`
(`share/haseen/lib/plymouth.sh:53`) is true when haseen's theme is installed
(`haseen.plymouth`) and `plymouthd.conf` names `omarchy`, the value the
scriptlet writes; any other theme is the owner's choice and stays. The same
pacman hook (it triggers on `omarchy-settings` too) runs
`plymouth-set-default-theme haseen` through the guard (`:108`), without a
rebuild: the hook sorts as `50-`, before `80-limine-efi-deploy` and
`90-mkinitcpio-install`, so an initramfs built in the same transaction
embeds haseen's splash, and a later one does anyway. `haseen plymouth status`
names the cause; doctor fails on it.

### 5. The six bar sections

`OMARCHY_IMPORT_JQ` (`share/haseen/lib/omarchy-import.sh:182-195`) maps
Omarchy's sections onto haseen's bar (left, center, right, overflow,
pinned):

| Omarchy 4.5 | haseen | Report |
|---|---|---|
| `left` | `bar.left` | — |
| `centerBegin`, `center`, `centerEnd` | `bar.center`, in that order (haseen centres its centre section as a group) | one line per non-empty flank |
| `right` | `bar.right` | — |
| `tray` (the tray's drawer) | the end of `bar.right` and `bar.overflow` (the panel behind the chevron; an overflow id must also sit in a section) | one line; `haseen.tray` itself stays in the bar, reported |
| `bar.background` | `none` → `transparent: true`, `opaque` → `false`, `glassy` → `false` (haseen draws no blur, §6), read after the legacy `transparent` as Omarchy does | `glassy` and unknown values reported |

A widget in any section is placed or reported, never dropped without a line
(a test walks every entry). `omarchy_import_merge` adds an imported overflow
id to a `bar.overflow` the user set only when the user's sections do not
already hold it, and the command lists it ("bar.overflow: added …").
`bin/haseen-plugin-settings:125` mirrors an entry found in any of the six
sections.

## Evidence

Omarchy facts were re-read in a fresh clone (`github.com/basecamp/omarchy`
→ omacom/omarchy; tags v4.0.6 = 237f1b407, v4.5.0-rc1 = 03ff1eff3, `quattro`
at 82662dd26, 25 commits after the tag, none touching `bin/omarchy-migrate`,
`migrations/`, `etc/`, `default/libalpm/` or `default/systemd/`), and the
packaging in a clone of omacom/omarchy-pkgs at cce40bdd7. Taken from the
survey without re-reading: the classification of the 84 migrations other
than those named above.

Tests (the hermetic wrapper of the batch brief; plan 100's `--affected` was
not on this base, so the changed files' own suites and the suites covering
the touched files ran):

| Suite | Checks |
|---|---|
| `tests/test-omarchy-guard.sh` (new) | 93/93, the root-mode checks included (user namespaces on luna; skipped with a note where unavailable) |
| `tests/test-plymouth.sh` | 72/72 |
| `tests/test-hibernation.sh` | 37/37 |
| `tests/test-omarchy-import.sh` | 156/156 |
| `tests/test-compat-mirror.sh` | 23/23 |
| `tests/test-core.sh` | 91/91 |
| those six plus `test-desktop`, `test-handlers`, `test-omarchy-commands`, `test-migrate`, `test-dms-url`, `test-paths`, `test-install-picker`, `test-migrate-defaults`, `test-theme-haseen`, `test-dms`, `test-omarchy-launch`, `test-shelltools`, `test-wooting`, `test-vapt`, `test-compat`, `test-compat-host`, `test-settings`, `test-dotfiles`, in one run | 2785/2785 |

The first run of the covering suites had one failure: `test-core.sh`'s
"omarchy-repo: never Omarchy itself" matched the word `omarchy-settings`
anywhere in the plan, which now includes the base layer's printed hook. It
now checks package commands and the omarchy-repo layer's own steps, as it
meant.

`tools/lint.sh` (shellcheck 0.11 at `/usr/bin/shellcheck`): lint OK (801
shell, 33 Lua, 198 JSON, 334 QML, 41 Go files). `tools/check-docs.sh`: OK.
gitleaks 8.30.1 over the branch range and the privacy patterns: clean.

## Rejected

- Seal only the five harmful migrations: the next release adds others, and
  a partial ledger still runs the rest.
- Override 4.5's `/etc` tweaks: the owner did not choose it.
- Rename `haseen-resume.conf` so it sorts after Omarchy's 4.0.6 list: 4.5
  fixes the order, and a rename moves a file existing machines have.
- Skip `backgrounds/intros/` in the importer (survey A.4): outside this
  brief.

## Owner steps

On **IO** and on **luna**, from a haseen checkout at this PR's merge:

```sh
./install.sh --tree-only --yes      # the tree, the new commands, the notice drop-in
systemctl --user daemon-reload      # picks up the drop-in now
haseen layer apply base             # sudo: installs /etc/pacman.d/hooks/50-haseen-omarchy.hook
haseen migrate                      # runs 1792605416 (seal) and 1792605417 (polkit; sudo only if the old stack is there)
haseen doctor                       # expect: omarchy migrations=sealed, omarchy pacman hook=installed
haseen plymouth status              # if it says Omarchy put its splash back: sudo haseen omarchy guard
```

After the next `haseen update` that brings Omarchy 4.5, run
`haseen migrate omarchy --pending` (exit 1, nothing listed, means sealed) and
`haseen plymouth status`. luna reads `Theme=omarchy` today because
`haseen plymouth set` never ran there; that is the owner's choice, not a
reset, and the guard leaves it.

## Not verified

- The hook in a real pacman transaction (no package was installed): its
  syntax and order are tested, the guard it runs is tested as root in a user
  namespace.
- `systemctl --user` loading the drop-in (no user manager in tests).
