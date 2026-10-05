# Plan 027: Luna plugin compatibility beyond bar widgets

## Status

- **Priority**: P1
- **Effort**: L
- **Risk**: MEDIUM (foreign plugin processes and service lifecycle)
- **Depends on**: 005 011 025 026
- **Category**: shell
- **Planned at**: 2026-10-04, owner request to tackle the plugins
- **State**: DONE 2026-10-05

## Problem

The existing compatibility adapter handles only bar widgets. A live survey of
luna's 37 plugin directories reported 22 errors: unsupported service manifests,
one single-segment id, and missing Omarchy panel/control types. Some widgets
that compile still cannot work because the adapter exposes `bar.shell = null`
and never activates their companion services.

## Decision

Extend compatibility instead of rewriting or modifying the owner's plugins:

- Provide the Omarchy UI/control contracts the actual plugins consume, backed
  by haseen's theme tokens. Preserve inline QML ids; legacy inline Item bodies
  may be eager, but popup surfaces map only while open. New component bodies
  can use a lazy Loader. Native haseen panels remain lazy.
- Inject a real, scoped shell facade before plugin construction: settings,
  dependency lookup, popup coordination, panel navigation, and atomic writes
  solely to `~/.config/haseen/shell.json`.
- Activate declared service and overlay companions once per plugin, not once
  per monitor. Stable model keys distinguish both kinds when a plugin provides
  both. Settings updates must not restart a service.
- Namespace foreign single-segment ids for haseen's registry, retaining the
  upstream id for lookups. Leave original directory names unchanged.
- Keep the native bar, frame, lock, pager and prayers as defaults. A legacy
  full-bar replacement is not a second standalone shell.
- Distinguish absent external backends/hardware from missing host APIs. Do not
  claim an action works simply because its widget renders.

No original directory or live user configuration is changed. Source snapshots
and safe backend stubs used in verification are temporary and are not published.

## Verification

- Real-engine headless lifecycle regression: companion services start once,
  receive their settings and source manifest at construction, remain stable
  across settings changes, and unregister on disable. Overlays remain distinct
  from services and receive structured summon payloads.
- CLI/runtime manifest adaptation agrees for services, overlays, panels and
  foreign ids; original plugin trees remain byte-identical.
- Live safe smoke on one isolated shell with no D-Bus service activation or
  input injection. Exercise real owner widgets and their panels through IPC,
  observe errors/visual output, record resource use, and classify dependencies.
- Final lint, tests, docs/secret gates and required GitHub CI checks.

## Execution record

Implemented 2026-10-04/05.

- UI and host contracts: the `qs.Ui`/`qs.Commons` primitives the real plugins
  import, a scoped shell facade (`Compat/ShellApi.qml`), one runtime singleton
  (`Compat/Runtime.qml`), service and overlay companions registered once per
  plugin, and foreign single-segment ids namespaced without renaming any
  directory.
- Standalone panels: the panel-loader injections (`service` as a live binding,
  the manifest as written, the registries a panel declares) are initial
  properties; `panel toggle` routes legacy records through the compat
  open/payload path; a panel that creates its own window is loaded without the
  native popup wrapper, whose focus grab used to read the plugin's own window as
  an outside click and destroy it.
- Pointer input: the closed-state guard now applies to the effective mask, not
  only the default `Region`, and the cross-monitor dismissal twins suspend with
  it, so a plugin that empties its own mask (flea-shelf's drag) is not blocked.
- IPC: `Compat/Omarchy/Commons/ShellIpc.qml` is a real `IpcHandler`, so
  Quickshell parses wire arguments against each function's declared types
  (`src/io/ipc.cpp` `IpcValueSlot::setString`). The generated string-only
  transport turned `select 0` into a true `bool`.
- Settings and lifetimes: `updateEntryInline()` persists the delta against the
  settings an instance was delivered (two screens no longer revert each other),
  every `shell.json` writer shares one lock and a per-transaction staging file,
  CLI id resolution follows the runtime's search order, native overlays register
  as overlays, and a completed `Component` is released with its instance.

Verified: 3,060+ assertions including new real-engine lifecycle, pointer-input,
concurrency and typed-IPC regressions; a protected offline sandbox built 29 of
the owner's imported widgets with their original bytes unchanged (278 MiB RSS,
291 MiB with panels open). Open limits are recorded in `handoff.md`.
