# Plan 031: Hardware quirk table and dispatcher

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: LOW (matching is read-only; each body is one drop-in, applied once)
- **Depends on**: 001 003 028
- **Category**: system
- **Planned at**: 2026-10-05, owner request
- **State**: DONE 2026-10-05

## Problem

haseen knew nothing about the machine it installs on beyond the GPU vendor.
Omarchy carries about 30 per-model fixes, but as a fixed list of scripts that
each decide for themselves whether they apply, so the knowledge of *what matches
what* is spread across 30 files and the dispatcher must change to add one.

## Decision

Port the mechanism and the table, not all the bodies:

- `share/haseen/hardware/quirks.tsv` is the dispatcher: one row of
  `id<TAB>match<TAB>summary`. A match rule is `*` or comma-separated terms that
  must all hold: `vendor:` `product:` `family:` `chassis:` (case-insensitive ERE
  over DMI, which is Omarchy's `omarchy-hw-match` generalised), `probe:NAME`,
  `pci:VENDOR[/CLASS][:DEVICE]`, `usb:VID:PID`, `input:RE`, `cpu:RE`.
- A body is `share/haseen/hardware/<id>.sh`, sourced by the dispatcher so it uses
  the same `run_root`/`write_root_file`/`write_user_file` helpers, and
  `--dry-run` prints its plan instead of changing anything. Adding a quirk is one
  file and one row; the dispatcher never changes.
- A matched quirk with no body is reported as **unimplemented**, by
  `haseen hw list`, `haseen hw match` and a warning from `haseen hw apply`. It is
  never skipped in silence — the table is the to-do list.
- Each applied body is recorded in the shared ledger (plan 028,
  `~/.local/state/haseen/hardware/<id>`), so a second run, a reinstall and every
  upgrade are no-ops. `--force` re-runs. A failure writes no marker and stops the
  run, so the next one retries it.
- Every probe reads through `sysroot_path`, so `HASEEN_SYSROOT` points the whole
  thing at a fixture tree and any machine can be exercised without owning it.
- `install.sh` runs `haseen hw apply` after the layers.
- Bodies shipped now: `fkeys` (hid_apple fnmode=2), `wireless-regdom` (domain
  from the timezone), `vm` (no animations or blur), `clamshell` (lid switch binds
  to `haseen hardware laptop-display`, which already refuses to disable the only
  display), `nvidia-gsp` (mkinitcpio early KMS; layers/desktop already owns the
  modeset drop-in and never touched the initramfs). The other 35 rows are table
  entries with no body yet.

The five existing `haseen hardware *` commands are **not** replaced: they are
runtime user toggles (touchpad, touchscreen, laptop/mirror display, hybrid GPU)
reachable from the menu, not boot-time quirks. `haseen hw` is the new group, and
the clamshell body calls one of them rather than duplicating it.

## Verification

- `tests/test-hardware.sh` (47): DMI printing and matching against two fixture
  machines (`hw-asus-rog`, `hw-vm-guest`), each match-rule kind, the pattern form
  of `hw match` and its exit code, the four states, dry-run plans for the shipped
  bodies, the dispatcher running a body once, `--force`, the unimplemented
  report, an unmatched or unknown id, a failing body leaving no marker, and a
  malformed table aborting.
- Live on the reference laptop (LENOVO / 20WNS0CV05 / ThinkPad T14s Gen 2i,
  chassis 10): `haseen hw match` printed the real triple and matched
  `fkeys wireless-regdom clamshell` plus eight unimplemented rows;
  `haseen hw apply clamshell wireless-regdom` applied both, a second run reported
  "0 applied, 2 already recorded", and the markers were removed again afterwards.
  The clamshell bind string was proved against the running compositor with
  `hyprctl eval 'hl.bind("switch:on:Lid Switch", …)'`, which registered
  `key: "switch:on:Lid Switch", locked: true`, then `hl.unbind`.
- `HASEEN_SYSROOT=tests/fixtures/hw-vm-guest haseen hw match` shows the
  non-matching path: QEMU firmware, no lid, no wifi, so only `fkeys` and `vm`.

## Execution record

`share/haseen/lib/hardware.sh`, `share/haseen/lib/ledger.sh` (the run-once
markers, factored out of `lib/migrate.sh` so migrations and quirks share one
ledger), `share/haseen/hardware/`, `bin/haseen-hw-{match,list,apply}`, the
`hw apply` step in `install.sh`, fixtures `tests/fixtures/hw-{asus-rog,vm-guest}`
and `tests/test-hardware.sh`.
