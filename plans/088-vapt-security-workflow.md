# Plan 088: Installed Security inventory and explicit workstation workflow

## Status

- **Priority**: P2
- **Effort**: L
- **Risk**: HIGH (installed metadata is untrusted; explicit help may execute only reviewed help-only bindings)
- **Depends on**: 087
- **Category**: vapt, CLI, shell
- **Planned at**: 2026-10-08
- **State**: Slices 2A-i and 2A-ii implemented: installed inventory, explicit usage/session commands, JSON health/readiness, owned service controls, foreground local helpers and fingerprint-bound CA actions. The optional panel remains a separate slice.

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
  `state`, `prerequisitePackages`, `reason`, and a fixed `command` leaf verb.
  Actual owned adapters, source policy, settings and selected-file/anchor state
  establish availability; invalid evidence is diagnostic refusal, never
  hypothetical success. The `enumeration-host` capability maps to command
  `net-file-server`; there is no alias. Panel launchers must whitelist these
  fixed verbs and use argv, never shell text.
- `menu`: `{schemaVersion,plugin:"haseen.security",enabled:boolean}`.
  File configuration deep-merges objects and replaces arrays/scalars, matching
  Config.qml. Only literal boolean `enabled: true` enables this optional surface;
  `--enabled` returns 0 when enabled, 1 otherwise. No shell IPC or mutation.
- `service-list`: `{schemaVersion:1,services:[{id,installed,package,ownership,
  unit,fragmentPath,state,activeState,subState,exposure:"unknown",reason}]}`.
  Known ids are `ssh/postgresql/apache/nginx/beef`; ownership is
  `verified|missing|ambiguous|refused|unknown`, state is
  `running|stopped|transitioning|failed|unknown`; package/unit/fragment are null
  when evidence is absent. Current manager inspection is read-only and does
  not invoke an installed inventory tool.
- `net-addresses`: `{schemaVersion:1,addresses:[{interface,address,
  family:"ipv4"|"ipv6",scope:"loopback"|"link"|"global",prefixLength}]}`.
  Only explicit address requests read this ephemeral state.
- `net-proxy-ca status`: `{schemaVersion:1,state:"none"|"owned"|"foreign"|
  "modified"|"unknown",reason,anchor:null|{sha256,subject,issuer,path,unchanged}}`.
  Inspection uses the CA object below; operational JSON refusals include
  `schemaVersion:1,state:"refused",reason` (inspection also `certificate:null`).
  Interactive service/network/client/trust/remove actions have no JSON mode.
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
`enumerationScript:null`, `bindAddress:"127.0.0.1"`; explicit local actions
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
  (`validate_endpoint`) and `:159` (`inspect_certificate_data`). Helpers validate
  literal IP/1024–65535 ports, explicit owned files and confinement; certificate
  inspection parses one current CA via absolute OpenSSL only on explicit
  request and returns nonsecret fingerprint/validity metadata. It never trusts.
- Reviewed installed adapters and actual readiness:
  `share/haseen/layers/vapt/workflow_actions.py:40` (`adapter`) and `:115`
  (`local_capabilities`). Service unit/current-fragment checks are at `:64`;
  no candidate is inferred from a package basename.
- Terminal confirmation/root gateway and immediate revalidation:
  `share/haseen/layers/vapt/workflow_actions.sh:17`, `:42`, `:110`
  (`vapt_service_action`, `vapt_endpoint_action`, `vapt_ca_action`).
- Descriptor confinement and approved-inode checks:
  `share/haseen/layers/vapt/workflow_actions.py:188`, `:251`, `:272`
  (`ConfinedHandler`, `open_selected`, `serve`).
- Immutable CA input and fingerprint binding:
  `share/haseen/layers/vapt/workflow_support.py:211` (`read_certificate_bytes`)
  and `share/haseen/layers/vapt/workflow_actions.py:309` (`certificate_payload`).
- Root-only unchanged-anchor journal:
  `share/haseen/layers/vapt/workflow_ca.py:104`, `:146` (`ca_status`, `mutate`).
- Behavioural action suites: `tests/test-vapt-services.sh:1` and
  `tests/test-vapt-net.sh:1`; owned stubs fail if executed, fixture gateways
  capture consent/argv, loopback requests prove path confinement, fixture
  transactions prove typed fingerprint/modified-anchor preservation and
  failed-updater honesty, and byte manifests prove preview write-freedom.

### Phase-2 shared policy additions

The optional panel's final data contract preserves the CLI shapes above.
Shared endpoint validation performs no DNS/bind/probe. Every non-loopback bind
requires the local-action CLI's terminal confirmation; the panel is not consent.
Directory selection must be explicit. Serving holds an opened root descriptor;
every child component is opened without following links, and only regular file
bytes are returned. No listing, CGI, upload or directory escape is supported.
Single-file selection requires unique installed-package ownership and pins the
opened inode; only `/file` exists, never a directory or guessed script path.
Local address discovery uses fixture state or libc getifaddrs;
only explicit help with `showLocalAddresses:true` or an explicit local-address
request reads it. Addresses are transient, never report data.

CA inspection is read-only, no privilege/trust change, no certificate/private-key
contents in output, no bundles, and no non-CA/expired material admitted.
The shared result is `{schemaVersion,state:valid|invalid|refused,reason,
certificate:null|{subject,issuer,sha256,notBefore,notAfter,isCa,
containsPrivateKey}}`; fingerprints are uppercase SHA-256, dates UTC ISO-8601.
`net-proxy-ca inspect` implements this read-only result. Trust requires the full
typed fingerprint even with `--yes`, rechecks immutable public certificate bytes,
and installs one fingerprint-owned system anchor through the root gateway.
Removal only accepts that unchanged recorded anchor. Foreign/modified anchors
and incomplete journals are refusals; updater failure never claims completed
trust. No trust decision follows from a panel launch or inspection.


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
- Guessed service unit names or choosing among multiple owned non-template
  services: ambiguity is a refusal, not authorization to choose a backend.
- Payload-enabled listeners, directory listing/CGI, guessed enumeration paths,
  external script fetching or detached daemons: not neutral local helpers.
- Generic CA trust, `--yes` bypass of typed fingerprint, removal of foreign or
  modified anchors, and optimistic updater success: not ownership-safe.

## Verification limits

Hermetic fixture verification covers service gateways without live control,
neutral listener argv without a live listener, confined HTTP bytes over local
ephemeral loopback sockets, and CA filesystem transactions with an injected
updater. No external target, live desktop, system trust mutation, installed
security tool or real interactive workstation shell is exercised. Source
ownership metadata does not attest retained file bytes.

## Exercised checks

### Slice 2A-i baseline

- `QT_QPA_PLATFORM=offscreen tests/run.sh tests/test-vapt-discovery.sh tests/test-vapt-workflow.sh`: **105/105 passed**, including zero installed-program invocation, seed-once preservation, explicit usage-only local-address output, endpoint/file validation and CA inspection.
- `SHELLCHECK=/usr/bin/shellcheck tools/lint.sh`: **lint OK**, 383 shell, 33 Lua, 179 JSON, 233 QML and 41 Go files.
- `tools/check-docs.sh`: **check-docs OK**.

- `QT_QPA_PLATFORM=offscreen tests/run.sh tests/test-vapt*.sh tests/test-install-picker.sh`: **4,710/4,710 passed**, 26 suites. An earlier attempt hit a 900-second command deadline and exposed a native fixture setup-order error; the corrected full run completed with a 3,600-second deadline. No live programs or desktop actions were substituted for fixture evidence.

### Completed slice 2A action checks

- `QT_QPA_PLATFORM=offscreen tests/run.sh tests/test-vapt-services.sh tests/test-vapt-net.sh tests/test-vapt-discovery.sh tests/test-vapt-workflow.sh`: **232/232 passed**, four suites; explicit action and passive discovery regressions together.
- `SHELLCHECK=/usr/bin/shellcheck tools/lint.sh` after local-action cutover: **lint OK**, 396 shell, 33 Lua, 179 JSON, 233 QML and 41 Go files.
- `QT_QPA_PLATFORM=offscreen tests/run.sh tests/test-vapt*.sh tests/test-install-picker.sh` after local-action cutover: **4,837/4,837 passed**, 28 suites, 1,476.52 seconds with a 3,600-second deadline.
- `tools/check-docs.sh` after local-action documentation updates: **check-docs OK**.
