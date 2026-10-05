# Plan 035: Plugin registry and lockfile

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MEDIUM (installs third-party QML from the internet)
- **Depends on**: 005 011
- **Category**: shell
- **Planned at**: 2026-10-05, owner request
- **State**: DONE 2026-10-05

## Problem

haseen could create, validate and enable a plugin, but not **get** one. There
was no way to find a plugin someone else wrote, no record of where an installed
one came from, and no way to reproduce a plugin set on a second machine.

## Decision

Port DankMaterialShell's distribution half (`core/internal/{registries,plugins}`)
as bash plus git and jq, which is what it is: a registry is a git repository
whose `plugins/` directory holds one JSON file per plugin, and an install is a
clone at a commit.

- **Sources.** `haseen plugin registry list|add|remove|sync`. The built-in
  source is the official DMS registry — its plugins are DMS-format, which
  haseen already loads through the compat adapter (architecture 5.4), so the
  ecosystem haseen can use exists on day one. `HASEEN_REGISTRY_DEFAULT`
  replaces or removes it; the tests set it empty and never touch the network.
- **Index and search.** `haseen plugin search [query]` over the cloned indexes,
  marking what is already installed.
- **Install.** `haseen plugin install <id|url> [--path SUBDIR] [--commit SHA]
  [--enable]`. Plugins from one repository share a checkout under
  `~/.config/haseen/plugins/.repos/<hash>`, and the plugin directory is a
  symlink into it, which is how a monorepo entry's `path` works.
- **Lockfile.** `~/.config/haseen/plugins.lock.json` pins `{repo, path, commit}`
  per plugin plus one commit per repository. `haseen plugin lock [--write]`
  snapshots what is installed; `haseen plugin restore [--prune]` reproduces it.
  Upstream's invariants are kept and tested: a supported version, a plugin id
  that is one safe path component, a path that cannot climb out, a full 40-hex
  commit, and no credentials in a repository URL.
- **What haseen adds.** Upstream verifies **nothing** before third-party QML is
  loadable (no schema check, no signature, no checksum — `manager.go`). Here
  every install, update and restore runs the plugin through
  `haseen plugin validate`, and a plugin that fails is removed again; an update
  that fails validation is rolled back to the commit the lockfile still holds.
  This is the one idea taken from Noctalia, whose plugin platform lints before
  it enables (`src/scripting/plugin_lint.cpp`).
- Local paths count as repository URLs, so a plugin you are writing installs
  the same way a published one does.

A registry id is a directory name; the id the **shell** loads a plugin under is
the one in its manifest, which for a DMS plugin is the adapted `dms.<name>`.
Install prints both, because `haseen plugin enable` wants the second.

## Verification

- `tests/test-registry.sh` (48), entirely against local git repositories:
  sources and their URL rules; search by description; install from a registry,
  from a monorepo subdirectory and from a path; one shared checkout for two
  plugins; the pin and its fields; a plugin that fails the schema being refused
  and leaving nothing behind; update bumping the pin and being a no-op the
  second time; **a second machine restoring the same commits from the lockfile
  alone**, including the pinned (older) version rather than the newest; a
  lockfile whose id does not match what the repository declares being refused;
  `--prune`; every lockfile invariant; and uninstall dropping both the files and
  the pin.
- Live against the real DMS registry: `haseen plugin registry sync` indexed it,
  `haseen plugin search clock` listed seven plugins,
  `haseen plugin install worldClock` cloned `rochacbruno/WorldClock` at
  `92dafcd81244`, wrote the lock, and `haseen plugin list` shows it as
  `dms.world-clock  user:dms  available  bar-widget`. A second scratch home with
  only that lockfile restored the identical commit.

## Execution record

`share/haseen/shell/lib/registry.sh`,
`bin/haseen-plugin-{registry,search,install,update,restore,uninstall,lock}`, and
`tests/test-registry.sh`.
