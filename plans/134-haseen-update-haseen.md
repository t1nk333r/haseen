# Plan 134: `haseen update haseen` installs the checkout and reloads the desktop

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: LOW-MEDIUM. It runs the checkout's own `install.sh` — the same
  command the owner runs by hand — only after a clean fast-forward, and it
  refuses a dirty checkout or a directory that is not one. Nothing it does is
  new privilege: `install.sh` already asks for sudo.
- **Depends on**: 093 (the omarchy answers), 100 (affected tests), 127 (the
  sidecar release the install fetches), 133 (the change that was done by hand)
- **Category**: commands, install
- **Planned at**: 2026-10-26
- **State**: DONE 2026-10-26

## Why

Owner, 2026-10-26, after SUPER + O: "i want some thing like this / haseen
update / then bump versions".

Pulling the checkout changes nothing on screen: Hyprland reads
`~/.config/hypr/hyprland.lua`, which `dofile`s the tree under
`$HASEEN_PATH`, and that is the **installed** tree (`/usr/local/share/haseen`),
not the checkout. So every change meant, by hand and in this order:

```sh
cd ~/Projects/cachyos-quickshellarchy
./install.sh --yes          # with sudo
hyprctl reload
haseen shell restart
```

Three steps, one forgot easily, and nothing says which commit is installed.
This turns it into one command, next to `haseen update system` and
`haseen update firmware`.

## What changed

- **`bin/haseen-update-haseen`** — `haseen update haseen`:
  - the checkout is `--source DIR`, `$HASEEN_SOURCE` or one line in
    `~/.config/haseen/source`, the rule `haseen bar edit` already follows; it
    refuses instead of guessing, and refuses a directory that is not a
    checkout (needs `install.sh` and `share/haseen/VERSION`) or not a git
    checkout at all;
  - uncommitted tracked changes are refused before anything is fetched: a
    fast-forward over the owner's work is worse than saying so;
  - `git fetch`, then `merge --ff-only @{u}` — never a rebase, never a reset;
  - `install.sh --yes --prefix <prefix>` from the checkout, or
    `--tree-only` for a fast shell/keybind refresh (no layers, no migrations);
  - then `hyprctl reload` (binds, rules, look) and
    `systemctl --user restart haseen-shell.service`; `--no-reload` stops
    after the install, and a machine running DMS says so instead;
  - `--check` prints the checkout's commit, the installed one and whether an
    update is available, and changes nothing (no terminal opened for it);
  - `--force` installs again when the stamp already names the commit;
  - started without a terminal (the menu) it opens haseen's floating one, so
    sudo's prompt has somewhere to appear.
- **`share/haseen/lib/install-stamp.sh`** — what an install put where:
  `prefix`, `commit`, `version`, `date` in `<prefix>/share/haseen/.installed`,
  written as root and atomically. `install.sh` writes it at the end of
  `install_tree`, so every install (not only this command's) is recorded; a
  tree installed by an older haseen has no stamp and that reads as *unknown*,
  never as *current*.
- **The prefix** is the running tree's own when it is an installed tree, else
  the prefix an existing stamp names, else `install.sh`'s default
  `/usr/local`; `--prefix` overrides. A checkout run by hand has
  `HASEEN_PATH` inside git and is never mistaken for one.
- **`share/haseen/default/menu.jsonc`** — `Update › haseen`, with the Arabic
  catalog.
- **`share/haseen/VERSION`** — `0.1.0-dev` → `0.2.0-dev`: the batch since the
  foundation (127-133) plus this. The sidecar release is cut for it
  (`tools/release-sidecar.sh`, plan 127), because a machine with no Go
  toolchain downloads `sidecar-v0.2.0-dev` instead of building it.

## Evidence

- `tests/test-update-haseen.sh` → 43/43, against a real bare repository:
  `--check` reports and changes nothing; `--dry-run` prints the
  fast-forward, the install and the reload and does neither; the update pulls
  one commit, runs `install.sh --yes --prefix …`, reloads Hyprland and
  restarts the shell; an installed commit is not installed again (`--force`
  installs it); `--tree-only` and `--no-reload` pass through and stay quiet;
  a dirty checkout, a non-checkout and no source are refused with their
  reasons; the stamp round-trips.
- `tools/lint.sh` → lint OK (923 shell, 348 QML, 207 JSON files);
  `tools/check-docs.sh` → OK.
- `tests/run.sh --affected` → 14147/14148. The one failure is
  `test-menu-back.sh`, environmental and older than this plan: its IPC socket
  path is 108 characters under this checkout (the `sun_path` limit), and the
  same test passes from a short worktree.

## Rejected options

- **`install.sh` alone** (`haseen install`). It installs but does not reload,
  and a checkout has to be found and pulled first — that is the command.
- **Always `--tree-only`.** Faster, but it skips migrations and layer seeds:
  a change that adds a package or a seeded file would silently not apply.
  It is a flag, not the default.
- **Trusting `VERSION` instead of a commit stamp.** Several changes (today's
  among them) land without a version bump; a version comparison would say
  "current" while the tree is a week old.
- **`git pull` from wherever the shell runs.** `HASEEN_PATH` is the installed
  tree as root created it, and pulling into a root-owned tree is not
  something a user command should do.
- **Answering Omarchy's `omarchy-update` with this.** Omarchy's update means
  packages (`haseen update system`); this is haseen's own tree.

## Owner steps

```sh
haseen update haseen --check     # what the checkout and the install are
haseen update haseen             # pull, install, reload — sudo asks in a terminal
```

The first run after this lands installs (no stamp yet); after that a second
run over the same commit says so and does nothing.
