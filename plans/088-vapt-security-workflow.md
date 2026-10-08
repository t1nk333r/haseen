# Plan 088: Installed Security inventory and explicit workstation workflow

## Status

- **Priority**: P2
- **Effort**: L
- **Risk**: HIGH (installed metadata is untrusted; explicit help may execute only reviewed help-only bindings)
- **Depends on**: 087
- **Category**: vapt, CLI, shell
- **Planned at**: 2026-10-08
- **State**: Slices 2A-i, 2A-ii and 2B implemented: installed inventory, explicit usage/session commands, JSON health/readiness, owned service controls, foreground local helpers, fingerprint-bound CA actions and the optional off-by-default Security menu/panel. Independent rendered accessibility/theme review is not implied by hermetic engine evidence.

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

### Slice 2B: optional Security menu and panel

`haseen.security` is schema-1, version 1.0.0, panel-only, with review permissions
`exec` and `files:read`. Shipped shell defaults explicitly set `enabled:false`;
the id appears in neither bar nor services. The existing panel host creates it
only on demand. Missing inventory is diagnostic, not an unmet plugin requirement.
Disablement while open requests close without cancelling already-launched helpers.

The four pages are Overview, Tools, Services and Local actions. Root/empty/
loading/error/previous-snapshot views remain usable. Tool entry selection never
runs anything; multiple entries use EntryPicker, unavailable/ambiguous usage
disables documentation/session buttons, and missing diagnostics distinguish
recorded resolutions from current installed ownership. Source policy, retained
package provenance, usage evidence and actual service activity remain separate.
Service running/stopped/failed/transitioning/unknown states and ownership refusal
are shown without an enable/init/repair path. Local forms expose missing/refused
prerequisites, loopback/explicit path/blank port drafts, literal validation,
read-only authoritative preview, endpoint exposure review, certificate
inspection/foreign-or-modified refusal and full selectable fingerprint.

Component boundaries, one file each:

- `Panel.qml`: lazy overlay/navigation, independent reads, ephemeral drafts,
  typed one-shot menu route, explicit refresh, stale/error/terminal-request notice.
- `Model.js`: pure schema/identity/enum validation, filtering/state copy,
  fixed verb and separate-operand argv construction; never executes or persists.
- `Header.qml`, `Navigation.qml`: accessible Back/Refresh/Close and roving tabs.
- `Overview.qml`: provisioning/count/source uncertainty, no installation controls.
- `ToolRow.qml`, `ToolDetail.qml`, `EntryPicker.qml`: inventory, usage refusal,
  selected owned entry, documentation/shell handoff and explicit picker.
- `ServiceRow.qml`, `ServiceDetail.qml`: owned actual unit/activity/refusal,
  start/restart review and direct stop handoff.
- `QuickActions.qml`, `EndpointForm.qml`, `CertificateForm.qml`: fixed
  prerequisites, transient explicit selection, syntax/CLI validation and review.
- `Review.qml`, `Preview.qml`, `StateMessage.qml`: Cancel-focused intent review,
  real dry-run exit/output/refusal/overflow, empty/loading/error/stale copy.
- `Read.qml`: finite read-only Process transport; no timer or retry loop.
- `Inventory.qml`: identity-stable menu-model synchronization and roving
  arrows/jk/Enter/Right/l focus with scroll reveal; no activation on replacement.
- `ActionButton.qml`, `Label.qml`, `Field.qml`, `GroupFilter.qml`,
  `IncludeMissing.qml`: Theme-only readable controls, labelled native editing,
  visible focus, compact wrapped action geometry and missing-inventory checkbox.

Only `haseen.menu`'s existing static provider map is extended. Flat static ids:
`setup.security.vapt`, `.panel`, `.tools`, `.services`, `.local`, `.status`.
Every new static row has literal `haseen vapt menu --enabled`; the existing
Security setup leaves are unchanged. Tool rows are `.tools.t-<UTF8-hex-id>`;
service rows are `.services.{ssh,postgresql,apache,nginx,beef}`; local rows are
`.local.{listener,http-server,enumeration-host,proxy-ca,remmina}`. Reserved
`.loading/.empty/.error` provider rows are disabled information, not actions.
Scripts are exactly `haseen vapt tool-list --json`, `haseen vapt service-list
--json`, `haseen vapt doctor --json`. Dynamic rows carry internal typed
page/item roles and the exact fixed `haseen shell ipc panel toggle haseen.security`
action, never package/path shell interpolation or contributed executable argv.

Tool/adapter rows retain the fixed enablement guard. The closed service guard
map adds `&& haseen-pkg-present openssh|postgresql|apache|nginx` respectively;
BeEF adds `&& ( haseen-pkg-present beef || haseen-pkg-present beef-xss )`.
Remmina adds `&& haseen-pkg-present remmina`. These are coarse visibility only;
installed owned evidence, fixed capabilities and CLI revalidation authorize
actions. Installed-but-refused diagnostics remain inspectable in the panel.
Cached menu rows are disabled previous snapshots until a fresh provider read.

All launchers use `Apps.launch`. Local argv uses the capability record's
`command` after the closed id/verb whitelist: `net-listener`, `net-http-server`,
`net-file-server`, `net-proxy-ca`, `net-remmina`. Tool/service verbs are also
closed. All untrusted operands remain separate argv elements. Preview uses
Process with `--dry-run`, never discovery-provided evidence/shell argv.
Endpoint Review first captures successful authoritative dry-run; refusal remains
in Preview with the draft preserved. No panel action passes `--yes`; the terminal
confirms and revalidates. Detached launch never implies success. New status
comes only from reopen/explicit Refresh, never launch callbacks or polling.

#### Displayed service snapshot binding

The existing start/stop/restart commands accept additive optional
`--expect-unit UNIT` and `--expect-fragment PATH`. The panel sends the exact
displayed record. Either mismatch refuses with exit 1 before privilege;
dry-run displays the expectation check. Absent expectations preserve direct
CLI behaviour. Consent is still in the terminal, then the existing second
ownership/FragmentPath/state read precedes the manager call. There remains a
small change window between that final read and systemctl: acceptable because
the CLI invokes only the revalidated explicit unit, without enabling or
selecting a replacement; eliminating it requires a manager-level atomic API.

#### Specification interpretations

The version-2 observed CLI shapes and plan's `command` leaf supersede proposed
old names: enumeration-host uses `net-file-server`, not an alias. CLI inventory
membership/ownership policy is reused, not duplicated as a QML package allowlist.
The panel validates transport identities/enums and never accepts arbitrary
commands. No verified executable entrypoint is neutral data-only/unavailable
evidence copy, not a claim that no executable bytes exist. Semantic nonzero
status/doctor/CA diagnostic objects are displayed; malformed schemas refuse the
entire affected section. The terminal, not QML, reports refusal after consent.
The absence of a connectivity probe is not an inferred offline condition.
Optional verified-file choices are collapsed until explicitly requested; manual
absolute selection always works. Controls stack at compact sizes and retain
native text editing. No GUI fingerprint entry duplicates terminal authorization.


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
- Security UI suite: `tests/test-vapt-security-ui.sh` runs the production
  `Model.js`, menu row builders and all referenced QML components under the
  real Qt JS/QML engine, with fixture-only read/Apps modules. **81 behavioural
  engine cases** cover explicit enablement/guards, the fixed verb whitelist,
  hostile IDs/commands and separate path operands, semantic degraded status,
  multi-entry picker, rendered empty/refusal/error/preview states, finite
  discovery without launch, terminal-authoritative notices, endpoint validation
  and no automatic refresh. The test fails on QML runtime errors.
- Service snapshot suite: `tests/test-vapt-services.sh` exercises matching,
  absent, changed-unit and changed-fragment expectations in dry-run and at the
  fixture root gateway; mismatches make no privileged call.

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
The panel is exercised in an offscreen Window with production QML and mocked
module boundaries, including compact viewport and Cancel focus checks.
Pixel measurements across all stock themes/text scales, Nerd Font coverage,
actual Wayland/AT-SPI screen-reader exposure and independent DESIGNER:VERIFY
are not established by those engine assertions. No owner's desktop is used.

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

### Completed slice 2B UI checks

- `QT_QPA_PLATFORM=offscreen tests/run.sh tests/test-vapt-security-ui.sh tests/test-menu.sh tests/test-menu-view.sh tests/test-apps.sh`: **430/430 passed**, four suites.
- `QT_QPA_PLATFORM=offscreen tests/run.sh tests/test-vapt-security-ui.sh tests/test-menu.sh tests/test-menu-view.sh tests/test-apps.sh tests/test-vapt-services.sh`: **500/500 passed**, five suites, including the additive displayed-snapshot service expectations.
- `SHELLCHECK=$(command -v shellcheck) tools/lint.sh`: **lint OK**, 397 shell, 33 Lua, 180 JSON, 255 QML and 41 Go files.
- `tools/check-docs.sh` after panel/menu/CLI documentation updates: **check-docs OK**.
- `tests/run.sh tests/test-vapt*.sh tests/test-install-picker.sh` with the UI and displayed-snapshot checks included: **4,953/4,953 passed**, 29 suites, 1,534.49 seconds with a 3,600-second deadline.

