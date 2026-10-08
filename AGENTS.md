# haseen — agent guide

Read `handoff.md` first, then `docs/architecture.md`, which is the contract
between parts. The engineering record is `plans/`, indexed by
`plans/README.md`.

## Ground rules

- **Dry-run contract.** Every state change goes through the helpers in
  `share/haseen/lib/common.sh`, and every mutating command takes `--dry-run`.
  `sudo` appears nowhere else. Check with
  `grep -rn 'sudo ' bin share | grep -v common.sh`.
- **Read system state through `sysroot_path`.** Tests run against fixture trees
  in `tests/fixtures/`, never against the live machine.
- **Never edit the user's files after seeding them.** Behaviour that haseen owns
  lives in `share/haseen/default/`, and user files include it.
- **Never remove the owner's plugins.** `~/.config/omarchy/plugins/` and
  `~/.config/DankMaterialShell/plugins/` are read-only sources. No command,
  layer, migration or cleanup may delete, move or rewrite anything in them.
  haseen writes plugins only under `~/.config/haseen/plugins/`, and
  `tests/test-core.sh` checks this. A full copy of the owner's set from the
  machine luna is kept at `~/Backups/luna/omarchy-plugins-20261004/`.
- **The AUR is the last resort.** Package sources are tried in this order:
  official/CachyOS repos, then Chaotic-AUR, then Omarchy's `[omarchy]` repo,
  then the AUR. Never call paru/yay directly to install anything: use
  `pkg_install` for repo packages and `pkg_install_aur` for everything else,
  which applies the order. Prefer a repo, Chaotic-AUR or `[omarchy]` package
  over an AUR one when choosing a dependency. Never add `omarchy` or
  `omarchy-settings` (`PKG_DENY`).
- **License: MIT.** You may adapt Omarchy and DMS code (MIT): keep the upstream
  notice in the file header and add a row to `NOTICE.md`. end-4 and caelestia
  are GPL-3.0 and are reference only. Never paste their code.
- **Resource rules** are in `docs/architecture.md` §6. No polling under 2 s, no
  blur, panels load lazily.
- **No visual clutter.** A new on-screen element needs a reason in its plan.
  Default to a panel opened on demand, not something always visible.
- **Never ship optional plugins by default.** The owner approves the default
  set plugin by plugin; anything else ships off or not at all.
  - Approved on by default (owner, 2026-10-07):
    - bar: logo (owner, 2026-10-07, plan 070), workspaces, clock, tray, audio, network, battery, bluetooth,
      privacy, idle, pager, media, prayers, sysusage, weather, gestures;
    - services: lock, idle, osd, polkit, screensaver, nightlight, clipboard,
      keybinds, battery (low-battery warnings; owner, 2026-10-07, plan 075;
      `criticalAction` stays `none`);
    - also: calculator, indicators, calendar, emoji, ai, agents and the pickers;
    - the desktop itself, never optional: launcher, menu, notifications,
      session, background.
  - Installed with the shell layer (owner, 2026-10-07, plan 073): the Helium
    browser (`helium-browser-bin`) and its Cairn extension, downloaded from
    Cairn's releases (AGPL-3.0, never vendored).
  - A new built-in plugin is off until the owner adds it to this list.
  - Third-party plugins (Omarchy, DMS, any other) are never bundled and never
    added to haseen's defaults. The owner installs them with
    `haseen plugin install`, and installing does not enable them.

## Gates (run both before every commit)

```sh
tools/lint.sh      # bash -n, shellcheck -x --severity=warning, luac -p, jq, qmllint
tests/run.sh       # hermetic; stub PATH; fixtures
tools/check-docs.sh
tools/secrets.sh   # before every push: gitleaks (history) + privacy patterns
```

`main` on GitHub is protected:
- The CI checks `lint`, `test`, `docs` and `secrets` must pass on an up-to-date branch.
- History stays linear: no force pushes and no deletion.
- Admins are included.

Direct pushes to `main` are rejected. Every change lands through a pull request:

```sh
git switch -c <topic> && git push -u origin <topic>
gh pr create --fill && gh pr merge --squash --auto --delete-branch
```

The repository is public. Never commit:
- the owner's location, hostnames' addresses or tailnet IPs;
- tokens, keys or anything under `~/.config` copied from a live machine.

Plugin defaults use public, city-level values only.

shellcheck is not installed on the author's laptop. Use
`SHELLCHECK=/path/to/shellcheck tools/lint.sh` with the static release binary.

## Style

- Bash: `set -Eeuo pipefail`, 4-space indent, functions `snake_case`. Comments
  say *why*.
- Commands: `bin/haseen-<group>-<verb>` with `# haseen:summary` / `# haseen:args`
  headers and `--help`.
- QML: one component per file. Singletons go in `qs.Haseen`. Theme tokens come
  only from `Theme`, never hex literals in widgets.
- Commits: `scope: lowercase imperative` (e.g. `secureboot: refuse enrollment outside setup mode`).
- Plans: `plans/NNN-slug.md` with a Status block. Add a row to `plans/README.md`
  in the same commit. Every claim cites evidence (a file:line, a command output,
  a commit). Record rejected options.

## Extending the desktop (plugins)

`haseen plugin new <id> --kind bar-widget` scaffolds a plugin in
`~/.config/haseen/plugins/<id>/`. `haseen plugin validate <id>` checks it
against `share/haseen/shell/plugin.schema.json`. The end-user skill in
`share/haseen/agents/skills/haseen/` explains the rest.
