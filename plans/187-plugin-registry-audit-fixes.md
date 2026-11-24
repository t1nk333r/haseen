# Plan 187: the plugin registry commands keep what they did not make

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW. Every change narrows what a plugin command touches:
  update and lock skip what is not a link into a checkout, install puts
  back what it moved when the new commit does not validate, and a fresh
  install is written down as off. A plugin someone already installed keeps
  the state it has.
- **Depends on**: 035 (the plugin registry and lockfile), 052 (the Omarchy
  settings mirror), 093 (omarchy-plugin-add never enables)
- **Category**: plugins
- **Planned at**: 2026-11-24, from the owner ("fix them", after the
  35-auditor audit of 2f7f472a)
- **State**: DONE 2026-11-24 (`tests/test-registry.sh` 95/95 and
  `tests/test-omarchy-menu.sh` 167/167, in the affected selection (14 files,
  2097/2097) against
  9a9e82ab; on 9a9e82ab's code the new registry test aborts after the
  emptied registries.json, and with only fix 2 applied 25 of its 95 checks
  fail)

## Problem

The audit found six defects in the plugin commands (group g03). Each was
re-checked on 9a9e82ab (main after plans 182–184); all six still applied.

### 1. `haseen plugin update` deleted a real directory the lockfile pins

`bin/haseen-plugin-update:72-75` (9a9e82ab) let the target id through the
family loop unconditionally (`[[ $mid == "$id" || -L ... ]]`), and
`registry_link` runs `run rm -rf "$PLUGIN_USER_DIR/$id"`
(`share/haseen/shell/lib/registry.sh:232`). Two ways a pin can name a real
directory: `haseen plugin restore` asks before replacing one and, on N,
leaves the directory and its pin (`bin/haseen-plugin-restore:64-68`); and
`haseen plugin lock --write` pinned any directory inside a git work tree with
an origin (`bin/haseen-plugin-lock:49-55`), so a plugin repository of the
user's own, or every plugin when `~/.config` is a dotfiles repository. The
next `update --all` after upstream moved deleted it, uncommitted edits
included. The sibling test `-L` also re-pointed a link to the user's own
checkout. `restore --prune` already used the right guard: a link that
resolves into `.repos` (`bin/haseen-plugin-restore:89`).

**Fix.** `registry_linked ID [URL]` in `registry.sh`: true only for a link
that resolves (`readlink -m`, so a link whose checkout is gone still counts)
into the checkouts, or into URL's own checkout. `update` skips a target that
exists and is not such a link, before it fetches, with a warning that names
`haseen plugin install` as the way to replace it; siblings must pass the same
test. `lock --write` pins only links into `.repos`.

**Test.** `tests/test-registry.sh`, second machine: the hand-written
`alice.load` (9.9.9) that restore skipped survives `haseen plugin update
alice.load` as a real directory, and the scaffolded `me.mine`, made a git
checkout with an origin, is not in `lock --write --dry-run`'s output. Both
fail on 9a9e82ab (`update says what it skipped`, `and leaves the directory as
it was`, `a real directory, not a link`, `but not the user's own checkout`).

**Rejected.** Asking before replacing, as restore does: `update --all`
walks every pin in one run (`omarchy-plugin-update` without an id runs it),
and there is nothing to update in a directory that is not the checkout. Moving the real directory aside: it is
still the user's, and the pin can be fixed with `install`.

### 2. `haseen plugin registry remove` emptied registries.json

`bin/haseen-plugin-registry:63-64` (9a9e82ab) piped `jq ... "$REGISTRY_CONFIG"`
into `write_user_file "$REGISTRY_CONFIG"`, whose `cat >"$dest"`
(`share/haseen/lib/common.sh:371`) truncates the file while jq is still
opening it. The auditor measured 19 empty files in 20 runs; the new test
failed on 9a9e82ab (`removing one source keeps the others`). After that,
`add` read the empty file into `current`, jq on an empty string printed
nothing, and `add` wrote 0 bytes again while reporting success.

**Fix.** `registry_config_read` reads the file whole first (a missing or
blank file is `{"sources":[]}`, anything else must be an object, or the
command stops), and `registry_config_write` refuses anything but one object
and writes through `replace_user_file` (temporary file and rename). Both
`add` and `remove` use them.

**Test.** `tests/test-registry.sh`: add and remove a source and the other
stays; removing it twice fails; an empty file is no sources and `add` writes
one; a file that is not JSON is refused and left as it was.

**Rejected.** `sponge` or a `.new` file inline in `remove` only: `add` had
the same blind write of empty output.

### 3. Installing left a plugin on, and a `haseen.*` id shadowed a built-in

CLAUDE.md: plugins are installed with `haseen plugin install`, "and
installing does not enable them". The shell counts a plugin as on unless
`shell.json` says `enabled: false`
(`share/haseen/shell/Haseen/Config.qml:102`); bar widgets and services also
need a place (`docs/architecture.md` §5.3), but a panel or a launcher
provider needs none. So an installed launcher provider was created on every
launcher open (`haseen.launcher/Panel.qml:163-167`), and an installed plugin
that `provides` a role won `Plugins.provider()` (`Plugins.qml:176-183`),
because user directories are scanned before the built-ins (`:352-355`).
`install` checked the id only against `^[A-Za-z0-9][A-Za-z0-9._-]*$`, so a
remote `haseen.lock` would have become the lock screen, although `haseen
plugin new` reserves the namespace (`bin/haseen-plugin-new:66`).

**Fix.** `install` without `--enable` writes a new id as off with `haseen
plugin disable` unless `shell.json` already switches it (`plugins.<id>.enabled`
present) or places it (a bar section or `services`), and its last line says
`off until: haseen plugin enable <id>`. It refuses `haseen.*` before anything
is fetched; a deliberate copy of a built-in is still made by hand, as the
skill shows. `docs/architecture.md` §5.3 says both.

**Test.** `tests/test-registry.sh`: after `install alice.load`,
`plugins["alice.load"].enabled` is `false` and the output names `haseen
plugin enable`; an `alice.clock` that `shell.json` already turned on stays
on through its install; `install .../haseen.lock` fails with "reserved for
built-in plugins" and links nothing.

**Rejected.**
- Making every non-built-in plugin count as off unless `enabled: true`
  (`Config.qml`): it would turn off every Omarchy, DMS and hand-written
  panel the owner already uses without an entry, which is a change of the
  default set, not of installing.
- Reordering `provider()` to prefer built-ins: a user copy that overrides a
  built-in is documented on purpose (`docs/architecture.md` §5.2), and an
  installed plugin is now off, so it never reaches `provider()`.
- Writing `enabled: false` in `restore` too: restore reproduces another
  machine, whose `shell.json` decides.

### 4. Install moved the shared checkout without validating or rolling back

`bin/haseen-plugin-install:95-98` (9a9e82ab) fetched into the checkout every
plugin pinned from the repository shares (`registry.sh:195-218`, `reset
--hard` there), validated only the new id, and on failure died before
`lockfile_pin`, with the checkout moved: siblings ran a commit nobody
validated under pins that named another one. On success `lockfile_pin` moved
the siblings' pins to that commit unchecked. A confirmed replace lost the old
link to `registry_link`'s `rm -rf`, then the new one to `registry_validate`'s.
`update` already validates the family and rolls back
(`bin/haseen-plugin-update:64-87`); install did neither.

**Fix.** Before fetching, `install` notes the checkout's HEAD and sets an
EXIT trap, `put_back`, that runs unless the install is kept. After the fetch
it moves an existing `plugins/<id>` (link or directory) aside to a hidden
`.<id>.replaced.<pid>` (`haseen plugin lock` and the shell skip dot
entries), links and validates the id, then checks every lockfile sibling
linked into that checkout with the new `registry_check` (validate without
removing). If anything fails, or the link step dies, `put_back` checks the
old HEAD out again, removes the new link and puts the aside entry back; on
success the aside copy is removed and the pins move. The move aside comes
after the fetch, so a fetch that fails (no network, no such commit) never
touches the installed plugin.

**Test.** `tests/test-registry.sh`: reinstalling `alice.load` at a commit
that breaks `alice.clock` fails, names the sibling, leaves `alice.load` at
1.1.0, its pin at the second commit, the sibling valid and no aside copy;
reinstalling at a commit where `alice.load` itself does not validate fails
and leaves the old, valid `alice.load`. On 9a9e82ab's install (with fix 2
applied so the test gets this far) all seven of these checks fail.

**Rejected.**
- Validating siblings with `registry_validate`: it removes a failing link,
  which would then have to be re-made after the rollback, as update does; a
  check that removes nothing needs no repair.
- A rollback function called only where validation fails: the first draft
  did that and moved the old plugin aside before the fetch, so a fetch that
  died under `set -e` left the plugin missing. The trap covers every exit.
- Putting the checkout back through `registry_fetch URL PREV`: it fetches
  again, over the network, to return to a commit the clone already holds.

### 5. A plugin link whose target is gone could not be removed

`omarchy-plugin-remove` accepts a dangling link (`-e || -L`,
`share/haseen/omarchy/bin/omarchy-plugin-remove:90`) and hands it to `haseen
plugin uninstall` (`:136`), which refused it: `[[ -e $PLUGIN_USER_DIR/$id ]]`
(`bin/haseen-plugin-uninstall:30`) is false for a dangling link.

**Fix.** `uninstall` accepts `-e || -L`; its `run rm -rf` removes the link
itself.

**Test.** `tests/test-omarchy-menu.sh`: `omarchy-plugin-remove me.gone --yes`
on a dangling link succeeds, says `Unlinked me.gone.` and the link is gone.
`tests/test-registry.sh`: `haseen plugin uninstall alice.gone` on a pinned
dangling link removes the link and the pin. Both fail on 9a9e82ab.

### 6. The skill said no Omarchy settings file is written

`share/haseen/agents/skills/haseen/plugins.md:248` and `:273` (9a9e82ab) said
"no Omarchy settings file is updated by haseen" and that scoped settings
"never write back to the original source". `bin/haseen-plugin-settings:108-145`
mirrors an Omarchy plugin's entry into an existing `~/.config/omarchy/shell.json`
and keeps `shell.json.haseen-bak` on the first write (`:134`), as
`docs/architecture.md` §5.4 records (plan 052).

**Fix.** Both passages now describe the mirror: only an existing file and an
existing entry, nothing else changes, an atomic write, the `.haseen-bak` kept
on the first one, and do not hand-edit the file while such a plugin saves.

**Test.** Documentation only; `tests/test-compat-mirror.sh` already holds
the behaviour the text now describes.

**Rejected.** Adding the mirror to the "never edit the user's files" ground
rule in CLAUDE.md: that rule is about files haseen seeded, and Omarchy's
`shell.json` is not one; plan 052 and `docs/architecture.md` §5.4 are its
record. Whether the ground rule should name it is the owner's call, and
nothing in the code depends on it.
