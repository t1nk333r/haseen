# Plan 088: Installed Security inventory and explicit workstation workflow

## Status

- **Priority**: P2
- **Effort**: L
- **Risk**: HIGH (installed metadata is untrusted; explicit help may execute only reviewed help-only bindings)
- **Depends on**: 087
- **Category**: vapt, CLI, shell
- **Planned at**: 2026-10-08
- **State**: Slice 2A-i implemented: discovery, usage/session commands, JSON status/doctor, effective optional-panel enablement, passive workflow defaults and hermetic tests. Service/network actions and the optional panel are separate slices, not claimed implemented here.

## Contract

Phase 1 provisions packages without executing them. This phase exposes read-only
installed inventory and explicit local workstation actions. No AUR, Omarchy
dependency, assessment execution, startup service or default-on plugin is added.
All new CLI commands have router headers, help and offline write-free dry-run.

### Discovery and JSON

`workflow.py` reuses `metadata.py`'s installed local database, safe repository,
identity and native-environment verification. Exact logical names and reviewed
aliases map packages to inventory roots; no report-only evidence, Provides,
suffix stripping, PATH lookup or package-to-command guesses are accepted.
Package file inventories and actual executable mode supply entrypoints. Every
file symlink hop and final file must be uniquely owned by the selected package.
Native console entries come from pinned distribution RECORD files inside the
verified environment; installed modules/interpreters are never imported/run.
Desktop files supply passive name/path/terminal metadata, not runnable actions.

All JSON stdout is one `schemaVersion: 1` object. Diagnostics use stderr.

- `tool-list`: `{schemaVersion, tools, sources, privateSource}`. A tool has
  `id`, `groups`, `state` (`installed|missing|unknown`), `reason`, `dataOnly`,
  `packages`, `entrypoints`, `desktopEntries`, and nullable `native` evidence.
  Packages have `name`, `version`, `source` (matching-source array),
  `provenance` (`verified|unknown`) and verified readable `files`.
  Entrypoints have absolute owned `id/path`, `kind` (`executable|native`),
  `documentation` (`{path,kind}`), and `usage` (`state: ready|unavailable`,
  nullable `kind: man|document|reviewed-argv`, `reason`). No discovery argv.
  Independent `ownership` (`present|missing`) and tool `provenance`
  (`verified|unknown`) describe current evidence separately.
  `--all` alone adds optional `resolution` (`state/source/target/reason`):
  a missing or unresolved inventory item is what diagnostic `--all` explains.
  This is recorded report evidence, never an installed-entrypoint authority.
- `status --json` and `doctor --json` add `provisioning` with
  `state: healthy|missing|degraded`, original `exitCode: 0|1|2`, and diagnostic
  lines; `workflow` includes effective settings, menu state, entrypoint and
  documentation-ready counts. Status preserves 0/1/2; doctor returns 1 for
  missing/degraded provisioning, 2 for usage. Neither repairs nor refreshes.
  `provisioning.resolutions` holds safe recorded-resolution rows with inventory
  `id`, `state/source/target/reason`; report.tsv stays eight-column v1.
  Doctor adds `workflow.capabilities` for fixed `listener`, `http-server`,
  `enumeration-host`, `proxy-ca`, `remmina`, each with `installed`, `available`,
  `state`, `prerequisitePackages`, `reason`. Installed prerequisites are checked;
  availability stays false until the separately assigned local-action slice
  establishes reviewed adapters. Missing/invalid settings remain diagnostic
  refusals, never hypothetical success.
- `menu`: `{schemaVersion,plugin:"haseen.security",enabled:boolean}`.
  File configuration deep-merges objects and replaces arrays/scalars, matching
  Config.qml. Only literal boolean `enabled: true` enables this optional surface;
  `--enabled` returns 0 when enabled, 1 otherwise. No shell IPC or mutation.
- Explicit help/session dry-run: `{schemaVersion,tool,entry,evidence,shellArgv,
  dryRun:true}`. Evidence describes the owned document or reviewed binding;
  no executable runs and no shell/terminal opens.

### Explicit usage and shell

Multiple entrypoints require `--entry` with an owned absolute entry ID. Prefer
one basename-matching owned man page, then one matching help document. Print
plain local document text (including roff source), stripping terminal control
bytes; never invoke man, a pager, installed rendering helpers or a terminal for
help. Multiple same-priority documents are ambiguous and refused. Otherwise,
only `files/help-bindings.json` reviewed package/entry/argv bindings qualify.
The initial registry is empty because no upstream-specific safe help argv was
established; missing evidence is an explicit refusal, not a universal `--help`.

`tool-run` validates usage and shell before lib/terminal.sh presentation,
shows the same explicit documentation and opens only an ordinary `-i` shell.
The executable shell must be listed in `/etc/shells`; bash fallback needs the
same independent presence checks. No selected program, prefilled command,
elevation, backend or service is started. Fixture sysroots can display documents
but refuse real binding/shell execution.

### Settings ownership

Explicit provisioning seeds `default/vapt/workflow.json` into the user's VAPT
configuration once through common.sh. Existing files/redirected paths are not
edited. Observation never seeds. Defaults are `showLocalAddresses:false`,
`enumerationScript:null`, `bindAddress:"127.0.0.1"`; later local-action slices
consume these settings. Addresses are not discovered or persisted by inventory.

## Evidence

- Installed DB reuse: `share/haseen/layers/vapt/metadata.py:510` (`installed`).
- Identity/provenance reuse: `share/haseen/layers/vapt/metadata.py:886`
  (`closure_identity_ok`) and `:910` (`allowed_local`).
- Native metadata reuse: `share/haseen/layers/vapt/metadata.py:3727`
  (`native_state`); no installed Python execution.
- Owned-file discovery: `share/haseen/layers/vapt/workflow.py:106`
  (`owned_file`), `:158` (`native_evidence`), `:211` (`discover`).
- Preserved provisioning verifier: `share/haseen/layers/vapt/workflow.sh:9`
  (`vapt_workflow_status`) and `bin/haseen-vapt-status:11`.
- Seed-once boundary: `share/haseen/layers/vapt/provision.sh:491`.
- Behavioural suites: `tests/test-vapt-discovery.sh:1` and
  `tests/test-vapt-workflow.sh:1`; fail-if-executed inventory and owned-entry
  stubs, real pacman local-DB fixtures, native metadata, ambiguity, foreign
  ownership/symlinks, data-only roots, single-object JSON, no automatic launch.
- Shared local policy: `share/haseen/layers/vapt/workflow_support.py:71`
  (`validate_endpoint`) and `:159` (`inspect_certificate`). Helpers validate
  literal IP/1024–65535 ports, explicit owned files and confinement; certificate
  inspection parses one current CA via absolute OpenSSL only on explicit
  request and returns nonsecret fingerprint/validity metadata. It never trusts.

### Phase-2 shared policy additions

The optional panel's final data contract preserves the CLI shapes above.
Shared endpoint validation performs no DNS/bind/probe. Every non-loopback bind
requires the local-action CLI's terminal confirmation; the panel is not consent.
Directory selection must be explicit and served paths remain confined. The
serving implementation must bind/revalidate opened descriptors against races;
resolution-level checks alone do not establish race-safe serving. Single-file
selection requires unique installed-package ownership, never a directory or
guessed script path. `local_addresses` uses fixture state or libc getifaddrs;
only explicit help with `showLocalAddresses:true` or an explicit local-address
request reads it. Addresses are transient, never report data.

CA inspection is read-only, no privilege/trust change, no certificate/private-key
contents in output, no bundles, and no non-CA/expired material admitted.
The shared result is `{schemaVersion,state:valid|invalid|refused,reason,
certificate:null|{subject,issuer,sha256,notBefore,notAfter,isCa,
containsPrivateKey}}`; fingerprints are uppercase SHA-256, dates UTC ISO-8601.
The separate local-action slice owns `net-proxy-ca inspect` CLI and
fingerprint-bound typed-confirmation trust/removal. No trust decision can be
inferred from a panel launch or the inspection result.


## Rejected options

- Package basename guesses, speculative `--help`, installed interpreter imports
  and man/helper execution during discovery: not trustworthy evidence.
- Rendering man pages with an external pager or roff processor: document display
  must not permit a package-owned helper to execute implicitly.
- Generic help bindings: reviewed arguments must be per actual package/entry.
- Report-driven installed menus: reports describe attempts, not retained files.
- Launching tools on session creation, shell prefill, privilege escalation or
  default-on Security UI: outside the approved explicit-workstation boundary.
- A second source/identity verifier: phase-1 metadata is the single policy.
- Editing settings on read/reapply: user configuration remains owner-controlled.

## Verification limits

Hermetic fixture verification is required before handoff. No live desktop,
installed security tool, network target or real interactive workstation shell
is exercised. Source ownership metadata does not attest retained file bytes.

## Exercised checks

- `QT_QPA_PLATFORM=offscreen tests/run.sh tests/test-vapt-discovery.sh tests/test-vapt-workflow.sh`: **105/105 passed**, including zero installed-program invocation, seed-once preservation, explicit usage-only local-address output, endpoint/file validation and CA inspection.
- `SHELLCHECK=/usr/bin/shellcheck tools/lint.sh`: **lint OK**, 383 shell, 33 Lua, 179 JSON, 233 QML and 41 Go files.
- `tools/check-docs.sh`: **check-docs OK**.

- `QT_QPA_PLATFORM=offscreen tests/run.sh tests/test-vapt*.sh tests/test-install-picker.sh`: **4,710/4,710 passed**, 26 suites. An earlier attempt hit a 900-second command deadline and exposed a native fixture setup-order error; the corrected full run completed with a 3,600-second deadline. No live programs or desktop actions were substituted for fixture evidence.

