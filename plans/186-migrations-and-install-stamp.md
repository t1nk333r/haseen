# Plan 186: migrations, the install stamp and the update cache, from the 2026-11-24 audit

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW. A shell.json without a `bar` keeps the default bar. A
  first install now runs two migrations it used to seal. The install stamp
  is written later in the run and records its scope. `haseen update check`
  without `$XDG_RUNTIME_DIR` moves its cache to the state dir. The only
  removal is the base layer's pacman hook, and only when its `Exec` names
  the prefix being uninstalled.
- **Depends on**: 098 (adopt-integrations), 101 (the Omarchy guard and the
  polkit repair), 113 (migrations read their own stdin), 134 (the install
  stamp), 183 (`haseen update`)
- **Category**: migrations
- **Planned at**: 2026-11-24, from the owner ("fix them", after the
  35-auditor audit)
- **State**: DONE 2026-11-24 (`tests/test-migrate.sh` 64/64,
  `tests/test-migrate-integrations.sh` 49/49, `tests/test-update-haseen.sh`
  109/109, `tests/test-paths.sh` 36/36, `tests/test-omarchy-guard.sh`
  157/157, `tests/test-bar-basics.sh` 147/147, `tests/test-theme-haseen.sh`
  80/80; the new assertions fail on 9a9e82ab, as listed under each finding)

Seven audit findings, re-checked on 9a9e82ab (main after plans 182-184).
Two of them describe the same defect (the malformed-name abort), so there
are six fixes. Every one still applied on 9a9e82ab.

## 1. adopt-integrations writes `"bar": null` and empties the bar

**Evidence.** In `share/haseen/migrations/1791560300-adopt-integrations.sh:55`
(9a9e82ab) the jq program runs
`.bar |= (if type == "object" then ... else . end)`, and jq's `|=` creates a
key that is missing: `jq -n '{} | .bar |= .'` gives `{"bar":null}`. So a
shell.json with no `bar` of its own, such as
`{"plugins":{"io.github.ilyazar.syncthing":{"enabled":false}}}`, became
`{"plugins":{"haseen.syncthing":{"enabled":false}},"bar":null}`. Both
merges let a non-object override win: `shell_merged_json` uses `. * $u`
(`shell/lib/plugin.sh`), and `Config.qml`'s deepMerge does
`out[k] = bothObjects ? ... : b`. `bar: _object(merged.bar)` is then `{}`,
so every bar section is empty. The migration is recorded as applied, so
nothing repaired it. Every fixture in `tests/test-migrate-integrations.sh`
had a `bar` key. The sibling migrations already guard this step (adopt-wooting
`if .bar then`, adopt-todoist `(.bar | type) == "object"`).

**Fix.** The update runs only when `(.bar | type) == "object"`. A new
migration, `1795510386-bar-null.sh`, deletes a `bar` that is exactly `null`
from shell.json, through `shell_config_lock` and `shell_config_write` like
the other shell.json migrations. No haseen command writes a null bar, and
the shell has only ever read one as an empty bar. A bar the user set, even
an empty object, is left alone.

**Test.** `tests/test-migrate-integrations.sh` runs the migration on a file
with no `bar`, and on one with only `services`. It asserts that no `bar` key
is written and that `shell_merged_json` keeps the default bar. It also runs
the repair migration with no shell.json, as a dry run, for real, a second
time, and over three files it must not touch. On 9a9e82ab four assertions
fail ("no bar key is written", "the plugin entry still moves", "the merged
config keeps the default bar", "services alone: re-pointed, still no bar
key").

**Rejected.** Editing 1791560300 alone: users who already ran it keep the
empty bar. Making `Config.qml` and `shell_merged_json` ignore a null
override: that changes what an explicit null means everywhere to cover one
migration's slip.

## 2. A first install seals the polkit repair and Omarchy's seal

**Evidence.** On 9a9e82ab `install.sh:372` runs `haseen migrate --seal` for
any HOME without haseen state, and that includes a former Omarchy user's
HOME. `bin/haseen-migrate` recorded every pending name as `sealed`.
`1792605417-polkit-faillock.sh:7-8` says it exists because haseen's seal
(1792605416) skips Omarchy's repair migration 1788256455. Once the base
layer's hook seals Omarchy's ledger on the next omarchy upgrade, neither
repair ever runs on that machine, and `/etc/pam.d/polkit-1` keeps a bare
`pam_unix` with no faillock. No other code repairs that file: a grep for
`polkit-1|pam_faillock` outside `migrations/` finds only the fingerprint and
FIDO2 setup commands, which add lines.

**Fix.** A migration may carry the line `# haseen:seal run`
(`migrate_runs_on_seal` in `lib/migrate.sh`). `haseen migrate --seal` runs
such a migration and records it `applied`, and seals the rest. A failure is
named and that migration stays pending, so the next `haseen migrate` (or the
login notice) retries it. The other migrations are still sealed, because
stopping there would leave them to run later as upgrades of a HOME that
never had them. Two migrations carry the marker: `1792605417-polkit-faillock.sh`
(it checks and repairs `/etc`) and `1792605416-seal-omarchy-migrations.sh`
(it seals Omarchy's ledger, which is Omarchy's state in that HOME, not
haseen's). The run is shared with the normal path through `run_migration`,
so the fd 3 and ASSUME_YES handling from plan 113 apply to both.

**Test.** `tests/test-migrate.sh`: a dry seal plans the marked migration's
run and the others' records and runs nothing; a real seal runs only the
marked one, records it `applied` and the rest `sealed`; a failing marked
migration does not fail the seal, is named, and stays pending; a mention of
the marker inside another comment is not the marker. The test also asserts
that the shipped marked set is exactly these two migrations. On 9a9e82ab
seven of these assertions fail. `tests/test-theme-haseen.sh` asserted that a
fresh install's dry run runs no migration at all. It now asserts that the
run covers exactly these two.

**Rejected.** A hard-coded list of names in `haseen-migrate`: the marker
sits next to the reason in the migration itself. Running the polkit check
from the base layer as well: it repeats the repair and still leaves
Omarchy's seal sealed on a fresh install. Not sealing anything on an
Omarchy user's HOME: their HOME has no haseen state to upgrade, so the other
migrations would rewrite files haseen seeds in the same run.

## 3. The install stamp is written before layers and migrations

**Evidence.** On 9a9e82ab `install.sh:270` writes the stamp inside
`install_tree`, before the layer apply, `haseen migrate`, `seed user` and
`hw apply`, all under `set -Eeuo pipefail`. When one of them fails, the stamp
already names HEAD. `bin/haseen-update-haseen:245` then says "already
installed" and exits before the reload, so a re-run skips the failed steps
until the next upstream commit or `--force`. A `--tree-only` run stamps the
commit as well (`install.sh:336`), so a later full update of that commit is
skipped the same way. Since plan 183, `haseen update` installs with
`--tree-only` every time.

**Fix.** `install_tree` only sets `BUILD_VERSION`, and `stamp_install SCOPE`
writes the stamp after the whole run succeeds: after `hw apply` with no
installer error (`full`), after the tree for `--tree-only` (`tree`), or
after the VAPT tooling alone (`tree`, because no layer or migration of the
update path ran). `install_stamp_write` takes the scope and writes
`scope=`. A stamp without the field is older than this plan and reads as
full, so existing installs are not reinstalled for nothing.
`haseen update haseen` counts a `scope=tree` stamp as current only for
another `--tree-only` run, which is what `haseen update` asks for. A full
`haseen update haseen` of that commit runs the installer, and `--check`
says "layers and migrations: this commit is installed tree-only".

**Test.** `tests/test-paths.sh` runs install.sh from a staged copy with a
stub CLI that fails the phase `HASEEN_STUB_FAIL` names. A full run writes
the stamp, with `scope=full`, after its last phase. A failed `layer`,
`migrate` or `hw` phase leaves the stamp unwritten. `--tree-only` stamps
`scope=tree` and runs no phase. `tests/test-update-haseen.sh`: a full update
over a tree-only stamp runs the installer; `--tree-only` takes the stamp as
current; `--check` names the waiting layers; a `scope=full` stamp is
current; the stamp round-trips its scope. On 9a9e82ab ten of these
assertions fail.

**Rejected.** Writing the stamp from `haseen update haseen` after install.sh
returns: install.sh run by hand would stop stamping. Only adding `--force`
to the "already installed" message: the failed steps would still be
skipped by default.

## 4 and 5. A malformed migration name does not abort (two reports)

**Evidence.** On 9a9e82ab `lib/migrate.sh:31` calls `die` inside the
`for ... done | LC_ALL=C sort` pipeline, which only ends that subshell, and
`migrate_pending` reads it through `done < <(migrate_names)` (`:43`), which
drops the exit status. So `migrate_pending` returned 0 with the names that
sort before the bad one. `pending="$(migrate_pending)"` in
`bin/haseen-migrate` succeeded, and `--pending`, the run and `--seal` all
exited 0 having handled a partial list. `tests/test-migrate.sh:87-91` added
the bad file after everything had been sealed, so `--pending` exited 1
because nothing was pending, whether or not the abort worked.

**Fix.** `migrate_names` checks every name in its own shell and collects
them in an array before anything is printed. `migrate_pending` captures the
list with `names="$(migrate_names)" || return 1`, so the `die` reaches
`haseen-migrate`, which fails under `set -e` before it runs or seals
anything.

**Test.** With every migration pending and a mis-cased
`1790000002-Bad.sh` among them, `--pending` fails and lists nothing, the
run fails, names the file and runs nothing, and `--seal` fails and records
nothing. Once the name is fixed, sealing records all three again. On
9a9e82ab six of these assertions fail.

**Rejected.** `set -o pipefail` plus `shopt -s lastpipe` inside the
function: it still depends on the process substitution's status, which bash
drops. A lint check on names alone: it does not protect a tree that skipped
lint, and the runtime promise is "refused rather than silently skipped".

## 6. The base layer's pacman hook is never removed

**Evidence.** `share/haseen/layers/base/layer.sh` writes
`/etc/pacman.d/hooks/50-haseen-omarchy.hook`, whose `Exec` is
`PREFIX/bin/haseen omarchy guard --hook`. base defines no `layer_remove`, so
`haseen layer remove base` dies ("layer base has no remove step",
`lib/layers.sh:194`). `uninstall_tree` (`install.sh:198-219` on 9a9e82ab)
removed the binaries, the tree and the notify drop-in, but not the hook.
After an uninstall, every pacman transaction that touched omarchy or
omarchy-settings ran a missing binary as root and reported a failed hook.

**Fix.** `uninstall_omarchy_guard_hook` in install.sh removes the hook with
`run_root rm -f` when its `Exec` line is exactly this prefix's haseen
(`${PREFIX%/}/bin/haseen omarchy guard --hook`). A hook naming another
haseen belongs to that install. It stays, with a warning. `--help` and
docs/architecture.md say so.

**Test.** `tests/test-omarchy-guard.sh` renders the hook into a copied
fixture root. The uninstall dry run plans its removal, with and without a
trailing slash on the prefix. A hook for `/usr/bin/haseen` stays and is
named. A root with no hook plans nothing for it. On 9a9e82ab three
assertions fail.

**Rejected.** A `layer_remove` for base: base also installs packages and
firewall rules that a remove step would have to decide about, which is a
larger change than the defect. Removing the hook whatever its `Exec`: it
could belong to a second install under another prefix.

## 7. update-check falls back to a shared `/tmp/haseen`

**Evidence.** On 9a9e82ab `bin/haseen-update-check:55` used
`${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/haseen`. `mkdir -p` (`:148`) accepted
a directory another user had created. A fresh `updates.json` in it was
served as this user's result, and `exec {lock_fd}>"$lock_file"` (`:149`)
truncated whatever a planted `updates.lock` link pointed at.
`fs.protected_symlinks` does not cover a non-sticky directory.

**Fix.** Without `$XDG_RUNTIME_DIR` the run dir is
`$HASEEN_USER_STATE/updates`, created 0700. Before anything in the run dir
is read, `require_run_dir_ours` checks that it is a real directory this
user owns, not a link, or does not exist yet. It checks again after
`mkdir`. Otherwise the command reports the error in its JSON and exits 0,
like its other errors. haseen.updates' `Widget.qml` reads the cache from
the same place.

**Test.** `tests/test-bar-basics.sh` plants a fresh cache and a lock linked
to a file of the user's in `$TMPDIR/haseen` and runs without
`XDG_RUNTIME_DIR`. The planted cache is not served, the linked file keeps
its contents, the cache lands in the state dir, and that dir is mode 700. A
run dir that is a link is refused before anything in it is read. On
9a9e82ab four assertions fail.

**Rejected.** `mktemp -d` per run: the cache and the lock exist so that
concurrent callers share one result, which a private dir per run would
lose. Refusing to run without `XDG_RUNTIME_DIR`: a cron or su check has a
safe place in the state dir.

## Review

An independent Sonnet review of the first head approved it with two nits.
Both were taken.

- **`haseen layer remove base` still refuses.** True, and intended: finding
  6 rejects a base remove step (see its Rejected paragraph), and the hook
  goes with `install.sh --uninstall-tree`. The reviewer's other option, a
  note in the layer docs, was cheap. The `base` row of docs/architecture.md
  §3 now says base has no remove step and that the uninstall removes the
  hook.
- **The notifier hides a malformed-name refusal.** `bin/haseen-migrate-notify`
  ran `haseen-migrate --pending 2>/dev/null || exit 0`, so after fix 4 and 5
  a bad name made the notifier say nothing, anywhere. It still exits 0 with
  no toast, since a toast cannot tell the user how to fix a shipped file,
  but it no longer discards stderr, so the refusal lands in
  `haseen-migrate-notify.service`'s journal. `--pending` prints nothing on
  stderr when nothing waits, so a quiet login stays quiet. A new
  `tests/test-migrate.sh` case runs the notifier with a mis-cased
  `1790000005-Bad.sh`: exit 0, no toast, and the refusal on its output. With
  the old notifier that last assertion fails (63/64).
