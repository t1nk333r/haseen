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

## dms:// links from the DMS gallery (io round 7)

The owner could not install anything from https://danklinux.com/plugins: its
Install button is a `dms://` link and nothing on haseen handled the scheme.

What DMS does (AvengeMedia/DankMaterialShell at 5eb78f1, MIT):
- `assets/dms-open.desktop` claims `x-scheme-handler/dms` and runs `dms open %u`,
  which hands the URL to the running shell (`core/cmd/dms/commands_open.go:82,121`).
- `quickshell/DMSShell.qml:892-907` knows two forms, `dms://theme/install/<id>`
  and `dms://plugin/install/<id>`, keeps the id up to the first `?` or `#`, asks
  "Install plugin '<id>' from the DMS registry?" and installs that registry id
  (`core/internal/plugins/registry.go` `Get`: exact `id`, then `name`).
- The gallery page (bundle `72f5456f.03f2f6df.js`) builds
  `dms://plugin/install/${e.id}` from `https://api.danklinux.com/plugins`, whose
  369 entries are the files of `dms-plugin-registry/plugins/` (same count, same
  ids). Theme links carry `?flavor=&accent=` or `?variant=`. No link names a
  repository: the registry entry's `repo` (and `path`) does.

What haseen does:
- `share/haseen/default/applications/haseen-dms-url.desktop` (MimeType
  `x-scheme-handler/dms`) runs `bin/haseen-plugin-url %u`. install.sh installs it
  to `PREFIX/share/applications`; the Nix package to `$out/share/applications`.
- `haseen plugin url` refuses anything but `dms://plugin/install/<id>` with a
  plugin-id-shaped id (themes, other actions, `..`, `%`-encoding, shell
  characters), looks the id up with `haseen plugin search --json` (the same
  clones `haseen plugin install` reads), refuses an entry whose repository is
  not `https://host/...` without credentials (git@, local paths and http are
  fine for a hand-typed install, not for a web link) or whose path climbs out,
  prints name, author, repository, directory and description, asks, and then
  runs `haseen plugin install <id> --no-sync`. `--no-sync` (new) makes install
  resolve against the clones just shown, so what is installed is what was
  confirmed. Started by a browser it has no TTY, so it reopens itself in the
  `haseen.floating` terminal (lib/terminal.sh, as `haseen password` does); a
  refusal there is a notification, since nobody reads a scheme handler's stderr.
- When DMS is the active shell (`haseen shell use dms`) the link goes to
  `dms open` unchanged, so taking over DMS's handler loses nothing.
- The shell layer sets `xdg-mime default haseen-dms-url.desktop
  x-scheme-handler/dms` when `~/.config/mimeapps.list` names no default or DMS's
  `dms-open.desktop`, and keeps any other handler the user chose (status says
  which). The file is read directly: `xdg-mime query` falls back to system
  caches, which are not a user choice.

Found on the way: install and uninstall passed `${DRY_RUN:+--dry-run}` to
`haseen plugin enable/disable`, but DRY_RUN is always "true" or "false", so
`install --enable` never enabled and `uninstall` never disabled. Both now pass
the flag only in a dry run, and uninstall disables the manifest id
(`dms.<name>`), which is what enable turned on. `registry_fetch` printed its dry
run plan into the commit its callers capture, so the plan came out inside the
"pin" line; it now goes to stderr.

Rejected: a `?repo=` parameter in the link (DMS ignores the query, and it would
let any web page pick the repository); reading `api.danklinux.com` (a second
index next to the registry clones install already uses); enabling the plugin
after install, as DMS does (it is a user plugin; the install line says how).

Verification: `tests/test-dms-url.sh` (77) with git serving
`https://example.invalid/*` from local repositories; a dry run of the real link
`dms://plugin/install/quickCapture` printed the plan (hthienloc/dms-plugins,
directory quickCapture); a real install of `dms://plugin/install/openrgbThemeSync`
into a scratch home pinned 3DTreeDee/openrgb-theme-sync and loaded it as
`dms.openrgb-theme-sync`; in a nested Hyprland, `xdg-open` of the link with the
handler registered in a scratch `mimeapps.list` opened the confirm prompt in a
`haseen.floating` foot.
