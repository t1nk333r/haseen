# Plan 182: `haseen update` in one step, and one notification when updates wait

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MEDIUM. `haseen update` with no argument now installs haseen as
  well as the packages, and a new user timer reaches GitHub and the package
  databases every four hours. Each step is one that already existed
  (`haseen update haseen`, `haseen update system`, `haseen migrate`); the new
  parts are where haseen comes from, the order, one sudo prompt and the
  notice.
- **Depends on**: 017 (update), 095 (`haseen update check`), 103 and 111 (the
  cold AUR phase, pacman's scope), 134 (`haseen update haseen`), 142 (units
  read again), 147 (the build version)
- **Category**: commands, install
- **Planned at**: 2026-11-21, from the owner
- **State**: DONE 2026-11-21 (`tests/test-update-all.sh` 72/72,
  `tests/test-update-haseen.sh` 102/102 after a Sonnet review, every finding
  taken; luna and IO are the owner's check)

## Why

The owner, 2026-11-21: "i need an easier way to make reciving an update
sommther like omarchy "omarchy update"".

Getting an update meant two commands and a checkout to look after:

- `haseen update` (the default, `system`) upgraded only the packages
  (`bin/haseen-update` on b6d3a35, `what="${REST[0]:-system}"`).
- `haseen update haseen` installed haseen from the checkout named in
  `~/.config/haseen/source`, a developer's checkout. On luna that checkout was
  on `plans/lucid-adoptions` at 5230619 while main was at b6d3a35, so
  `haseen update haseen --check` offered to install a tree four merges older
  than the installed one ("the checkout is current; the installed tree is
  not … --force to install it"). IO's checkout has uncommitted changes, which
  the command refuses, so IO was updated by hand from a throwaway clone
  (memory: IO deploy and restart).
- Nothing said that an update was waiting. The `haseen.updates` pill counts
  packages only and is off by default.

`omarchy update` (`/usr/share/omarchy/bin/omarchy-update`, Omarchy 4.5) is one
command: it confirms, asks for sudo once and keeps it fresh, pulls Omarchy,
upgrades the packages, runs migrations, restarts what changed, then builds AUR
packages.

Asked, the owner chose "Managed clone of main" for where haseen comes from
and "One notification" for how to learn about updates. That option read: "A
background check (every few hours) sends one notification when new haseen
commits or packages arrive, with an Update button. Nothing is added to the
bar." Running it on existing machines (the migration) follows from that
answer.

## Decision

- **`haseen update` (`all`, the new default).**
  1. Shows what is new: haseen's commits since the installed one (subjects,
     up to eight) and the package counts (`haseen update check --force`).
  2. Asks `Update now? [Y/n]` on a terminal (Enter is yes; `--yes` skips
     it).
  3. Asks for sudo once (`sudo_keep_warm`, `lib/common.sh`). A loop keeps
     the timestamp fresh every 60 s while the update runs.
  4. Installs haseen: `haseen update haseen --tree-only --no-reload`.
  5. Then `exec`s the prefix's `haseen update all`
     (`HASEEN_UPDATE_STAGE=rest`), so everything after runs the tree just
     installed. That holds also when the first half ran from a checkout:
     `HASEEN_PATH` is unset for the prefix's router. An exec keeps the PID, so
     the sudo loop carries over.
  6. The rest: pacman, then `haseen migrate` (migrations may be written
     against the new packages, as in Omarchy), then Flatpak, then the
     post-update hooks.
  7. The sudo loop stops, then the AUR builds run, still cold (plan 103).
  8. Hyprland is reloaded and the shell restarted, only when haseen's tree
     changed. A replaced kernel gets a reboot hint (`reboot_hint`, also in
     `system`).
  9. If haseen could not be installed (offline), the packages are updated
     all the same and the run exits non-zero, naming what is left.

  `haseen update system`, `firmware` and `haseen` still run one part each.
- **Where haseen comes from** (`lib/self-update.sh`).
  - haseen's own blobless clone in `~/.local/share/haseen/checkout`, of
    `HASEEN_UPDATE_REMOTE` (default `https://github.com/t1nk333r/haseen.git`)
    and branch `HASEEN_UPDATE_BRANCH` (default `main`).
  - It is moved to the branch tip with `checkout --detach`. Changes made in it
    by hand are refused, not overwritten.
  - `--source DIR` and `$HASEEN_SOURCE` still install a checkout of your
    own. `~/.config/haseen/source` is no longer read by updates; `haseen bar
    edit` still uses it.
- **Never backwards** (`self_update_relation`).
  - An installed commit newer than main (`ahead`) is left alone.
  - So is a commit the copy does not have, or one not on main, when it was
    installed after main's last commit (`local`, by the stamp's date). That
    is luna running a pull request before it merges: it stays until main
    moves on, then main replaces it.
  - Commits are compared as commits, not as text. A stamp from another clone
    may abbreviate the same commit to twelve characters.
  - `--force` overrides all of these.
- **The notice.** `haseen-update-notify.timer`:
  - It runs 15 minutes after it starts, then every four hours.
  - Each run (`haseen update notify`) fetches the copy and counts haseen's new
    commits and the pending packages.
  - It sends one notification ("Updates are ready", "haseen: 3 new changes ·
    12 packages to upgrade") with an Update button. The button starts
    `haseen update` as a transient unit in `app-graphical.slice`
    (`systemd-run --user`), not inside the notice's idle-priority unit; with
    no terminal there, it opens a floating one.
  - What it was about is kept in `~/.local/state/haseen/update-notified`. A
    run notifies only for something not on that list, so a dismissed notice
    comes back with the next commit or package, not every four hours.
  - With nothing pending the list is removed. Without a notification daemon,
    nothing is remembered.
  - The shell layer enables the timer (status reports it). Migration
    `1795289723-update-notify-timer.sh` enables and starts it where the shell
    layer was applied before. Without a user manager (su, ssh without
    `XDG_RUNTIME_DIR`) the migration says how to turn it on and succeeds,
    rather than stopping every later migration.
  - Both write `~/.local/state/haseen/update-notify-enabled` when they turn
    it on. A timer disabled after that is the user's choice: status reports
    it as "off (your choice)" and a re-apply leaves it off.
  - It is a new default, approved by the owner (AGENTS.md).
- **Strings.** Five notification strings with Arabic. The menu's Update
  submenu gains "Everything" (`haseen update`), and the haseen entry no
  longer says it pulls a checkout.
- `share/haseen/migrations/README.md` says that `haseen update` applies no
  layers, so a new default package or unit for existing machines needs a
  migration.

## Rejected

- **The developer's checkout, made safer** (always install `origin/main`
  from it) and **release tags only**: the owner chose the managed clone. A
  developer's checkout is also where uncommitted work lives (IO).
- **A bar pill on by default**, or both pill and notice: the owner chose one
  notification, and AGENTS.md asks for no new always-visible element without
  a reason.
- **One authorization for the AUR too**, as Omarchy does
  (`omarchy-update-aur-pkgs` shares it): plan 103 decided that PKGBUILDs
  never inherit sudo's timestamp, and that stands.
- **The whole `install.sh --yes` (layers) on every update**: layers install
  packages and seed files; the tree, migrations and pacman are what an update
  needs. `haseen update haseen` without `--tree-only` still does the whole
  install.
- **A notice for every check, or for any change in the set**: four-hourly
  repeats of a dismissed notice.
- **Comparing short commit strings**: a stamp from another clone abbreviates
  differently and would reinstall the same tree.

## Limitations

- The first `haseen update` clones the repository (blobless; the history and
  the current files only). The install then builds or fetches the sidecars,
  as any install does.
- A pull request's tree installed on a machine stays until main gets a new
  commit, merged or not. `haseen update haseen --force` installs main at once.
- The timer counts on `checkupdates` and the AUR helper for packages; a check
  that fails counts as nothing pending, and the next run tries again.
- A package's new version is a new update, so on a rolling release the
  notice comes about once a day while updates are left waiting.
- `haseen update` applies no layers: what a change needs on existing machines
  comes through a migration (README above).

## Review

A Sonnet subagent reviewed `38216ca`: REQUEST_CHANGES, one major finding.
Every finding was taken:

1. **Major:** the Update button `exec`ed the update inside the notice's
   unit, so pacman and the builds ran at `Nice=10` and idle I/O, and the unit
   stayed active until the terminal closed. It is now a transient unit in
   `app-graphical.slice`, checked by the test.
2. The migration failed without a user bus, which would stop every later
   migration and the update's second half. It now warns and succeeds.
3. A stamp of `unknown` (a tree without git) with a recent date read as
   `local` and was never updated. `unknown` is now always updated.
4. Run from a checkout, the second half ran the checkout's code. It now
   runs the prefix's router with its own tree.
5. Disabling the timer showed as a degraded layer, and a re-apply turned it
   on again. There is now the opt-out marker above.
6. The menu still described the old `haseen update haseen` and had no entry
   for the one-step update.
7. The `--tree-only` choice was not written down where migrations are
   written. It now is.
8. Escaped mutations: the keepalive stop removed, and the remote reset
   removed. The keepalive is now tested through the hand-over: it refreshes
   every second (`HASEEN_SUDO_WARM_INTERVAL`), and none after the AUR starts;
   removing the stop fails that check. Also tested: a changed remote, sudo
   refused, and the second stage reaching the prefix's router.
9. A stopped keepalive left its `sleep` running. The sleep is now waited on
   and killed with the loop.
10. Without a terminal the update does not ask. The usage now says so.
11. The notice called `haseen` through `PATH`. It now uses its own tree's
    router.
12. The plan now quotes the option the owner chose, and the noise on a
    rolling release is a limitation above.

## Verification

- `tests/test-update-all.sh` (72 checks):
  - the dry-run plan;
  - a real run against a bare repository and stubs: the preview, the order
    (sudo once, install, pacman, Flatpak, the cold AUR, reload);
  - no reload without a new tree;
  - declining at the prompt;
  - an unreachable haseen (packages still upgraded, exit 128);
  - the notice: once per new set, again for a new package, quiet and cleared
    with nothing pending, nothing remembered without a daemon, Update running
    the update;
  - the units, the shell layer line and the migration.
- `tests/test-update-haseen.sh` (102 checks): the managed copy cloned by
  `--check`, installed, a longer stamp abbreviation, a new commit, a newer
  installed tree left (and `--force`), the pull-request case by date, a copy
  changed by hand refused, and an unreachable remote.
- `tests/test-shell.sh`: the layer enables the timer and status names it.
