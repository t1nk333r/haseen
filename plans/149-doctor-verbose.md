# Plan 149: doctor and status answer --verbose

## Status

- **Priority**: P2
- **Effort**: XS
- **Risk**: LOW. A new read-only rendering of an object both commands already
  built: no new probe, no write, no change to the JSON, the exit codes or any
  other flag. The flag is refused beside `--json` and on `tool-list`, where
  `tool-help`/`tool-run` already refuse anything they do not take.
- **Depends on**: 088 (the installed workflow, its JSON and its text report),
  148 (the last change to this layer)
- **Category**: vapt
- **Planned at**: 2026-10-31, owner: "vapt doctor i want --verbose"
- **State**: DONE 2026-10-31 (`tests/test-vapt-workflow.sh` 167/167; the live
  report on luna is in Verification)

## Problem

`haseen vapt doctor` printed two lines and nothing else
(`missing: no per-user VAPT provisioning report`, then
`workflow: 14838 owned entrypoints; 326 with matching documents`), and
`haseen vapt doctor --verbose` was rejected outright:
`workflow.py: error: unrecognized arguments: --verbose`, exit 2
(`bin/haseen-vapt-doctor` passes unknown operands through, and
`workflow.py`'s parser had no such flag).

Everything the two commands observe — each source and why it was refused, the
private source's state, the provisioning diagnostics and recorded resolutions,
the effective settings, the menu guard, the five capabilities with their
reasons, and all 204 inventory items — existed only in `--json`. That is the
right interface for a program and a poor one for a person deciding what to fix
before a lab, which is what the flag was asked for.

## What changed

- **`share/haseen/layers/vapt/workflow.py`** gains `--verbose` and
  `verbose_report(result)`, which renders the object `doctor` and `status`
  already build: `sources:` (one line per source with its cached-package count
  and reason), `private source:`, `provisioning:` with its diagnostics and
  resolutions, `workflow:` with the entrypoint/documentation counts, the
  effective settings, the menu guard and — for `doctor` only, because only
  `doctor` builds them — the capability rows with their command, prerequisite
  packages and reason, then `tools:` with a per-state count and one line per
  item naming its groups, its verified packages and their source, its native
  state when it has one, its entrypoint count and the reason it has that
  state. `--verbose` is refused with `--json`, with `tool-list` (which already
  prints one line per entrypoint) and on `tool-help`/`tool-run`, so the
  existing `parser.error('unsupported or missing operands')` covers it and the
  exit code stays the report's own.
- **`bin/haseen-vapt-doctor`** and **`bin/haseen-vapt-status`** advertise and
  accept it. The status router moves from an `if/elif` on `REST[0]` to a
  `case "${REST[*]:-}"` over the whole operand list, so `--json --verbose`
  (either order) is a usage error instead of the first flag silently winning.
  Provisioning status with no operand is unchanged, and no operand is still
  the only way to read the verifier's own report.

## Verification

- `tests/run.sh tests/test-vapt-workflow.sh` → **167/167**. The new cases, on
  the fixture host: `--verbose` keeps the report's exit code (1 while no
  provisioning report exists); both commands print `sources:`, a reviewed
  source, the private source, the diagnostics, `workflow: 3 owned entrypoints;`
  and `tools: 204 (installed 3, missing 200, unknown 1)` with a line for a
  missing item and a line for an installed one; neither prints
  `schemaVersion`; `doctor` carries `capability listener `, `command=net-listener`
  and `packages=openbsd-netcat`, while `status` carries no capability section;
  and `--json --verbose`, `--verbose --json --dry-run`, `tool-list --verbose`
  and `status --verbose --json` all exit 2.
- Against luna's live configuration (`bin/haseen-vapt-doctor --verbose`, 223
  lines from the merged tree): `omarchy unavailable (247 cached packages)`,
  `core safe (299)`, `extra safe (15040)`, `multilib safe (182)`,
  `chaotic-aur safe (3216)`, `blackarch safe (5087)`;
  `private source: oniomarchy absent (not approved (haseen vapt repo-enable
  oniomarchy))`; `provisioning: missing (exit 1)` with its one diagnostic;
  `workflow: 14838 owned entrypoints; 326 with matching documents`; the four
  available capabilities and `remmina missing`; `tools: 204 (installed 100,
  missing 103, unknown 1)`.
- `tests/run.sh --affected` → **6500/6500, exit 0** on 35 files: the whole VAPT
  set plus `test-aipanel.sh`, `test-core.sh`, `test-i18n.sh`, `test-keybinds.sh`,
  `test-menu.sh` and `test-omarchy-commands.sh` (the two bins are covered
  widely). `tools/lint.sh` OK, `tools/check-docs.sh` OK.
- **`test-menu.sh` cannot run from a checkout under `$HOME` in this
  environment, and that is not this change.** The menu model's pure JS runs
  under `node` (`tests/test-menu.sh:21-22` looks it up with `command -v node`
  *before* `sandbox()` narrows `PATH`), so it resolves to the mise shim, and
  that shim refuses with `~/.config/mise/config.toml are not trusted` whenever
  the working directory is under the user's home directory. Measured: a
  **pristine** `origin/main` worktree under that home directory fails the same
  way (0/1 aborted) with no change of mine present, the same commit checked out
  under `/tmp` passes 309/309, and
  `MISE_TRUSTED_CONFIG_PATHS=$HOME/.config/mise/config.toml` makes the checkout
  under `$HOME` pass 309/309 too — which is how the selection above was run.
  Nothing here touches `node`, the menu or mise. Worth its own fix (resolve
  `$NODE` after `sandbox()`, or check that it runs), not this plan's.

## Rejected options

- **A `--verbose` mode on `tool-list`.** It already prints one line per
  entrypoint; the report a person wants before working is the one `doctor` and
  `status` build.
- **Printing every entrypoint path in the verbose tool lines.** luna's
  inventory holds 14,838 of them; the count and the packages are what make the
  line readable. `tool-list` lists them.
- **Promising the text as a contract.** Only the JSON is
  `schemaVersion: 1`; the text is a rendering and is free to change.
- **A separate `haseen vapt report` command.** It would rebuild the same
  object for a second name to keep in sync.
- **Letting `--json` and `--verbose` combine** (JSON plus text, or text on
  stderr). One object has one rendering; a caller that wants both runs it
  twice.
