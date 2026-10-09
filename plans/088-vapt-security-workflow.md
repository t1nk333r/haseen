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
  start/restart review and immediate stop terminal handoff without Review.
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
- `SelectableText.qml`: wrapped copyable paths/units, full fingerprints and
  captured output with a 2px Tab focus ring.

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
- Owned-file discovery: `share/haseen/layers/vapt/workflow.py:107`
  (`owned_file`), `:184` (`native_evidence`), `:237` (`discover`).
- Preserved provisioning verifier: `share/haseen/layers/vapt/workflow.sh:9`
  (`vapt_workflow_status`) and `bin/haseen-vapt-status:11`.
- Seed-once boundary: `share/haseen/layers/vapt/provision.sh:491`.
- Behavioural suites: `tests/test-vapt-discovery.sh:1` and
  `tests/test-vapt-workflow.sh:1`; fail-if-executed inventory and owned-entry
  stubs, real pacman local-DB fixtures, native metadata, ambiguity, foreign
  ownership/symlinks, data-only roots, single-object JSON, no automatic launch.
- Shared local policy: `share/haseen/layers/vapt/workflow_support.py:72`
  (`validate_endpoint`) and `:203` (`inspect_certificate_data`). Helpers validate
  literal IP/1024–65535 ports, explicit owned files and confinement; certificate
  inspection parses one current CA via absolute OpenSSL only on explicit
  request and returns nonsecret fingerprint/validity metadata. It never trusts.
- Reviewed installed adapters and actual readiness:
  `share/haseen/layers/vapt/workflow_actions.py:43` (`adapter`) and `:134`
  (`local_capabilities`). Service unit/current-fragment checks are at `:83`;
  no candidate is inferred from a package basename.
- Terminal confirmation/root gateway and immediate revalidation:
  `share/haseen/layers/vapt/workflow_actions.sh:37`, `:68`, `:136`
  (`vapt_service_action`, `vapt_endpoint_action`, `vapt_ca_action`).
- Descriptor confinement and approved-inode checks:
  `share/haseen/layers/vapt/workflow_actions.py:256`, `:332`
  (`ConfinedHandler`, `serve`) and shared no-follow opener
  `share/haseen/layers/vapt/workflow_support.py:98` (`open_selected`).
- Immutable CA input and fingerprint binding:
  `share/haseen/layers/vapt/workflow_support.py:256` (`read_certificate_bytes`)
  and `share/haseen/layers/vapt/workflow_actions.py:370` (`certificate_payload`).
- Root-only unchanged-anchor journal:
  `share/haseen/layers/vapt/workflow_ca.py:109`, `:151` (`ca_status`, `mutate`).
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
every child component is opened without following links; regular single-link
file bytes only are returned. The opened descriptor's link count is checked on
every request, so links added after startup refuse with HTTP 404. No listing,
CGI, upload or directory escape is supported. Single-file selection requires
unique installed-package ownership and a single-link regular file, pins the
opened inode, and rechecks its link count at startup and every `/file` request.
No parent directory or guessed script path is exposed.
Local address discovery uses fixture state or libc getifaddrs;
only explicit help with `showLocalAddresses:true` or an explicit local-address
request reads it. Addresses are transient, never report data.

CA inspection is read-only, no privilege/trust change, no certificate/private-key
contents in output, no bundles, and no non-CA/expired material admitted.
CA classification uses OpenSSL's native typed `basicConstraints` decoding, not
rendered text. Only documented `X509_check_ca == 1` admits proper X509v3 CA
constraints; absent/false/malformed and legacy-only CA evidence refuse.
Inspection, immutable payload admission and privileged trust share the classifier.
The shared result is `{schemaVersion,state:valid|invalid|refused,reason,
certificate:null|{subject,issuer,sha256,notBefore,notAfter,isCa,
containsPrivateKey}}`; fingerprints are uppercase SHA-256, dates UTC ISO-8601.
`net-proxy-ca inspect` implements this read-only result. Trust requires the full
typed fingerprint even with `--yes`, rechecks immutable public certificate bytes,
and installs one fingerprint-owned system anchor through the root gateway.
Removal only accepts that unchanged recorded anchor. Foreign/modified anchors
and incomplete journals are refusals; updater failure never claims completed
trust. No trust decision follows from a panel launch or inspection.

### Security finding fixes F1/F2

- **F1 (Medium), fixed:** whole-output `CA:TRUE` matching could admit a non-CA
  through subject/issuer text. `inspect_certificate_data` delegates CA authority
  to OpenSSL's typed extension classifier, accepting only
  [the documented X509v3 result 1](https://docs.openssl.org/3.5/man3/X509_check_ca/).
  Text-only extension output is also unsafe: malformed DER containing printable
  `CA:TRUE` is rendered as apparent extension text. The native decoder avoids
  that fallback, with no custom certificate parser or native struct layout.
  Evidence: `share/haseen/layers/vapt/workflow_support.py:181`
  (`_basic_constraints_ca`), `:203` (shared inspection),
  `share/haseen/layers/vapt/workflow_actions.py:370` (payload reuse),
  `share/haseen/layers/vapt/workflow_ca.py:162` (privileged reuse).
  Actual certificate fixtures cover genuine critical/noncritical CAs and
  self-signed subject/issuer `CA:TRUE` spoofing with absent, false and malformed
  constraints, including critical/noncritical printable malformed DER.
  PEM/DER inspection, payload and privileged paths agree; rejected trust
  creates no state. Native OpenSSL certificate decoding is invoked only on
  explicit inspection; discovery/doctor never classify certificates.
- **F2 (Medium), fixed:** no-follow pathname traversal alone admitted hardlinks.
  The request handler now requires `st_nlink == 1` on the opened regular leaf
  before sending bytes, for both directory and single-file modes. Selection
  and startup also refuse multiply-linked selected files. Evidence:
  `share/haseen/layers/vapt/workflow_actions.py:305` (every request), `:352`
  (single-file startup), `share/haseen/layers/vapt/workflow_support.py:162`
  (owned-file selection). Real ephemeral loopback fixtures serve a normal file,
  refuse an inside hardlink to outside bytes, refuse a second link added after
  startup, and refuse multiply-linked `/file` bytes. The CA anchor/state path
  already enforced the same descriptor-time single-link rule at
  `share/haseen/layers/vapt/workflow_ca.py:53`; it was not changed.


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

Security engine suites use the same complete desktop-engine qualification as
the battery/media suites, not merely the presence of a `qml` executable:
executable `QS_BIN` (default `/usr/bin/qs`), `dbus-daemon`, `dbus-run-session`,
and `python3` importing both `dbus` and `gi`. All four Security engine suites
also require executable `QML_BIN` (default `/usr/lib/qt6/bin/qml`) and a
successful isolated offscreen QtQuick/QtQuick.Controls import probe. The
keyboard/render suite additionally requires executable `QML_TEST_BIN`
(default `/usr/lib/qt6/bin/qmltestrunner`) and the QtTest import. Missing
prerequisites produce named skips, not successful engine-case claims; the
manifest/CLI enablement checks still run. Dependent adversarial and conformance
sections name their own skipped scenarios. A framework-only probe cannot
convert production-component or behavioural failures into skips.

Qt versions and font metrics are not pinned or treated as automatic skips.
Qualified engines must run the full cases: fit rows must be fully revealed;
oversized rows must expose their beginning and a readable first line, without
requiring one absolute scroll offset. Geometry and padding assertions derive
from rendered controls and allow only floating-point roundoff. Test fixtures
deliberately delay responses across an event-loop boundary and wait for all
read/inspection/preview completions and rendering before comparing submissions,
focus or fingerprints. Named scenario completion replaces fixed pass totals.
The Qt 6.12.0 CI environment needs a fresh run of these corrected fixtures;
local Qt 6.11.2 evidence cannot establish Qt 6.12.0 or real AT-SPI conformance.

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


### Security fix batch F1/F2 checks

- `QT_QPA_PLATFORM=offscreen tests/run.sh tests/test-vapt-net.sh tests/test-vapt-workflow.sh`: **183/183 passed**, two suites, including genuine critical/noncritical CAs, printable malformed extension spoofing, admission-path agreement and link-count fixtures.
- `SHELLCHECK=$(command -v shellcheck) tools/lint.sh`: **lint OK**, 397 shell, 33 Lua, 180 JSON, 255 QML and 41 Go files. An initial fixture-array SC2054 diagnostic was corrected by quoting the single extension operand.
- `QT_QPA_PLATFORM=offscreen tests/run.sh tests/test-vapt*.sh tests/test-install-picker.sh tests/test-vapt-security-ui.sh`: **5,070/5,070 passed**, 30 suite executions (29 unique; the requested explicit UI suite also matches the glob), 1,607.96 seconds with a 3,600-second deadline. An intermediate run was cancelled before final native-classifier fixtures landed; it is not counted as verification.
- `tools/check-docs.sh`: **check-docs OK** after the finding, scope and evidence documentation updates.

### Batch J: CLI/actions findings

- **AUD-04 / TEST-02 / TEST-03 — fixed for CLI records:** CA ownership records
  require an object, integer schema version, typed fingerprint/content hash,
  known transaction state and control-free subject/issuer strings before use.
  Service manager snapshots require an object and validated consumed field
  types/enums. Wrong-shaped top-level manager snapshots emit one explicit
  refused object with exit 1 and diagnostics only on stderr; unsafe row evidence
  is unknown. No new catch-all handler masks programming failures.
  Inspection rejects malformed JSON certificate input; source/package status
  retains its provisioning exit meanings, while doctor refuses unsafe CA
  readiness. Evidence: `workflow_ca.py:88`, `workflow_actions.py:56` under
  `share/haseen/layers/vapt/`; settings shape/refusal cases also cover status and
  doctor. `tests/test-vapt-{net,services,workflow}.sh` exercise `[]`, null,
  numeric and string containers, malformed consumed fields/enums, one-object
  stdout and stderr-only diagnostics without traceback leakage.
- **AUD-05 — fixed:** documentation readiness requires a confined read-only
  descriptor open. Installed identity and owned file inventory are retained
  separately from readable usage evidence. Real help reopens the document,
  freshly checks owned evidence and revalidates its opened inode before reading.
  Evidence: `share/haseen/layers/vapt/workflow.py:124`, `:130`, `:140`, `:149`.
  Workflow fixtures deny document opens, revoke readability after discovery and
  replace the document with a cross-owner symlink before presentation; neither
  preview nor real help invents successful usage or prints substituted bytes.
- **AUD-01 — fixed:** after validation and consent, the common foreground
  gateway executes `exec` with the reviewed adapter/server argv, replacing
  the wrapper rather than leaving a long-lived child. Dry-run still returns
  before any handoff. Evidence: `share/haseen/layers/vapt/workflow_actions.sh:130`,
  `:132`; fixture SIGTERM/SIGHUP checks prove the adapter has the wrapper PID,
  signal exit codes propagate and literal loopback endpoints can be rebound.
- **AUD-02 — fixed:** `LiteralHTTPServer.server_bind` uses the literal
  TCP binding primitive and assigns server-name metadata without reverse DNS.
  Scoped IPv6 bindings resolve only the local interface index, not a host name.
  Evidence: `share/haseen/layers/vapt/workflow_actions.py:207`; loopback startup
  succeeds with `getfqdn` and `gethostbyaddr` patched to fail if called.
- **AUD-03 — fixed:** deliberately serial serving has no unbounded thread pool.
  Accepted-client idle waits are five seconds; one monotonic thirty-second
  absolute connection deadline spans reading and writing, preventing slow-drip
  clients from extending the budget indefinitely. Known timeout/disconnect
  failures close the connection without attempting another expired write.
  Evidence: `share/haseen/layers/vapt/workflow_actions.py:229`, `:256`.
  Real loopback fixtures prove idle, slow-drip and stopped-reader clients cannot
  monopolize the helper; ordinary requests and descriptor confinement survive.
- **AUD-06 — CLI contract completed:** accept IPv4/IPv6 literals, with at most
  one optional IPv6 `%SCOPE` matching `[A-Za-z0-9_.-]{1,64}`. Preserve the
  complete CLI-provided scoped address unchanged; validate literal and scope
  separately. The CLI remains authoritative, with no interface-presence/DNS
  probe in preview. Evidence: `share/haseen/layers/vapt/workflow_support.py:72`;
  fixtures accept `%enp5s0`, `%wlan0`, `%lo` and refuse duplicate scope suffixes.
  The panel half is a separate batch; no panel/menu files change here.
- **TEST-01 — CLI fixed:** stop does not request a terminal or confirmation,
  but retains displayed-unit/fragment expectations and the immediate second
  ownership read before normal root authorization. Start/restart still require
  the terminal and consent, propagating the unavailable-terminal gateway status
  rather than rewriting it. Evidence:
  `share/haseen/layers/vapt/workflow_actions.sh:37`. Hermetic unavailable-terminal
  fixtures prove stop succeeds, stale expectations/current fragments refuse,
  and start/restart cannot reach the root gateway. The panel half is separate.

The adversarial confinement suite previously modelled a `makefile`-backed
in-memory transport. Its fixture now models `recv_into`, `settimeout` and explicit
idle/total server deadlines, matching the production socket/descriptor contract.
The same traversal, encoded traversal/NUL, symlink, hardlink, FIFO, directory,
parent/root replacement and single-file assertions remain reachable and unchanged;
no production test shim or weakened assertion was introduced.

- `QT_QPA_PLATFORM=offscreen TMPDIR="$HOME/.cache/haseen-wt/jtmp" tests/run.sh tests/test-vapt-workflow.sh tests/test-vapt-services.sh tests/test-vapt-net.sh tests/test-vapt-confinement-adversarial.sh tests/test-vapt-workflow-adversarial.sh`: **613/613 passed**, five suites, after the final terminal-status and top-level service-refusal corrections.
- `SHELLCHECK=$(command -v shellcheck) tools/lint.sh`: **lint OK**, 400 shell, 33 Lua, 180 JSON, 255 QML and 41 Go files.
- An earlier default-scratch full run reported **5,478/5,484**. Four CLI
  expectation mismatches prompted the final corrections above; one panel stop
  launcher mismatch belongs to its separate batch. The last shared-prerequisite
  assertion was invalidated by `/tmp` `EDQUOT` errors while creating heredocs,
  an environmental scratch-quota artifact, not evidence of a package/action
  regression. Subsequent checks use a real-filesystem `TMPDIR` outside the
  checkout; no unrelated scratch is removed.
- `QT_QPA_PLATFORM=offscreen TMPDIR="$HOME/.cache/haseen-wt/jtmp" tests/run.sh tests/test-vapt*.sh tests/test-install-picker.sh`: **5,491/5,492 passed**, 32 suites. The only failure is the separately scoped panel stop consumer launching through `config terminal` instead of directly. All CLI/action and confined transport cases passed; the relocated run had no scratch-quota failure.
- `tools/check-docs.sh`: **check-docs OK**.

### Batch K: panel conformance and disabled-provider boundary

The final panel interaction requirements are implemented without reinstating
the superseded wide-form layout, decorative badge/icon or special-width rules.
The single-column layout, wrapped rows, generic Review label, header Refresh
and persistent offline-safe copy remain the approved simplified treatments.

1. **Keyboard:** `Inventory.key/focusIndex/pageMove` handles non-wrapping
   Up/Down/j/k, Home/End and viewport PageUp/PageDown in all six surfaces.
   Enter/Right/l explicitly inspect/select only; tabs add Home/End and clamp
   at their edges. `Field` retains native editing and separates submission
   from blur. Real Qt keyboard events cover each list and editing/Tab paths.
2. **Reveal/focus:** all six lists forward focused items to `Panel.reveal`,
   including Tab/mouse focus and identity-stable refresh fallback. Layout/focus
   notifications also reveal read-only controls after wrapping settles. A surviving
   id stays focused; a removed id uses the surviving index, or the named empty
   action/heading. Fitting rows are fully revealed; oversized wrapped rows
   reveal their beginning. Wrapped content determines row height plus 12px
   scaled padding on each side. Read-only controls have visible 2px rings.
3. **Accessible entry:** the card declares pane role/name “Security workstation”;
   full row names/state/reason and explicit “Item N of M” metadata are retained.
   Nested headings receive focus/announcement, normal Tab reaches the next
   control, and focus never selects. Review still initially focuses Cancel.
   Real heading/Tab/picker tests pass; actual bridge exposure is limited below.
4. **Long content:** row height follows wrapped text, with no safety-text cap.
   `SelectableText` keeps paths, unit/FragmentPath, captured diagnostics and full
   labelled fingerprints wrapped and copyable, using only Theme tokens.
5. **Scoped literals / AUD-06:** `Model.addressError` validates IPv4/IPv6
   separately from a single optional `%SCOPE` matching `[A-Za-z0-9_.-]{1,64}`.
   Chooser records use stable interface/family/address identities and preserve
   the selected `address` unchanged, including `%enp3s0/%wlan0`;
   duplicate scopes, malformed numeric literals and missing link-local scope
   refuse without DNS. `localArgv` retains the whole address as one operand;
   CLI dry-run remains locality/ownership authority.
6. **Submission:** endpoint Enter performs field-related syntax validation,
   focuses the first invalid field and prepares authoritative dry-run/Review
   only. Certificate-path Enter only inspects. Blur errors use accessible
   descriptions; drafts survive validation and Back. Actual CLI refusals remain
   selectable Preview output rather than stderr-derived invented field types.
7. **Chooser Escape:** explicit `showAddresses` state closes on the first Escape
   only, preserves the draft and closes after selection. Another Escape backs
   out normally. Opening the chooser remains the only address-read trigger.
8. **Source errors:** a source-labelled `repo-status` error and Retry/Refresh
   remain visible independently, while successful sections stay intact.
   A fixture injects the source refusal and proves retained tool evidence.
9. **Anchor/refusals:** the existing anchor's ownership and labelled full
   selectable SHA-256 are independent of inspection. Removal Review repeats
   that fingerprint and machine-wide consequence; unchanged owned state is
   still mandatory. Each inspection/read/preview refusal response announces
   once through an Item's supported Accessible API, not a Process/Read attachment
   or a change-triggered duplicate. Real certificate Enter/anchor/Review tests
   reject unsupported accessibility attachments. No private certificate contents
   or GUI authorization field exist.
10. **Rendered evidence and limit:** production components render offscreen at
    360×480, 560×640 and 720×640, fontSize 11 and 17, using tokens generated by
    the existing pure theme renderer for stock Flexoki Light and Everforest.
    Twelve fixture screenshots are generated; the six lists undergo **72**
    keyboard/focus/scroll matrix checks, with additional oversized wrapped rows.
    Rendered row text/focus token contrasts meet
    4.5:1/3:1 in both palettes. The nested D-Bus AT-SPI registry initialized,
    but the offscreen QML application was not exposed in its accessible tree.
    Actual AT-SPI roles/names/state, screen-reader order and announcement
    delivery are **not verified**. No live owner session was accessed.

- **TEST-01 panel presentation — corrected in batch L:** `Panel.launch` presents
  `service-stop` in a foreground terminal without Review/confirmation, preserving
  `--expect-unit/--expect-fragment`. CLI stop does not require a terminal; the
  panel deliberately chooses terminal presentation. Start/restart retain Review
  and terminal confirmation. See the corrected assertion and evidence below.
- **Disabled providers:** `MenuModel.providerAllowed` gates only the three
  fixed Security providers on literal resolved enablement. `loadProvider`,
  queued dispatch and response application use that gate. The real offscreen
  menu harness deliberately returns a stale successful row guard: disabled
  root search/direct load still queue/run zero reads; enabled search performs
  exactly tool-list/service-list/doctor and produces guarded rows. Unrelated
  provider conventions and existing default-menu guards remain unchanged.
- Both tester-authored adversarial suites are included without weakening their
  assertions. New conformance/provider suites use production components and
  fixture transports, never a live service, terminal, certificate trust change
  or installed security tool.
- `QT_QPA_PLATFORM=offscreen TMPDIR=~/.cache/haseen-wt/ktmp tests/run.sh tests/test-vapt-panel-conformance.sh tests/test-vapt-menu-providers.sh tests/test-vapt-ui-adversarial.sh`: **252/252 passed**, three suites. The conformance runner includes four test functions plus Qt init/cleanup (**6 passed, 0 failed**) alongside the existing **81** UI behavioural engine cases.
- `TMPDIR=~/.cache/haseen-wt/ktmp SHELLCHECK=$(command -v shellcheck) tools/lint.sh`: **lint OK**, 402 shell, 33 Lua, 180 JSON, 256 QML (qmllint included) and 41 Go files.
- `tools/check-docs.sh`: **check-docs OK** after the panel behavior, scoped-address
  and agent-skill documentation updates.
- `QT_QPA_PLATFORM=offscreen TMPDIR=~/.cache/haseen-wt/ktmp tests/run.sh tests/test-vapt*.sh tests/test-install-picker.sh`: **5,591/5,591 passed**, 34 suites, 1,583.76 seconds. This includes both unchanged tester adversarial suites, the direct-stop consumer, real disabled/enabled menu providers and the complete panel conformance matrix.

### Batch L: retained terminal presentation and launch announcement

- **L1 — corrected design requirement, not a weakened assertion:** the tester's
  original direct-stop assertion encoded an interpretation that conflated
  “Stop has no confirmation” with “Stop has no terminal presentation.” The
  retained design requires foreground terminal presentation for explicit panel
  Stop. The corrected adversarial assertion checks the exact
  `haseen config terminal -- haseen vapt service-stop ssh` argv, followed by the
  unchanged displayed-unit/fragment expectations. A companion assertion checks
  that Stop skips Review and returns to service detail; the existing no-`--yes`
  and unchecked-completion assertions remain. The CLI's independent no-terminal
  capability is unchanged, as are start/restart confirmation gates.
- **L2 — one-time launch announcement:** `Panel.launch` explicitly announces its
  completion-unchecked notice once for each actual launch request, including
  repeated requests with identical notice text. It does not reintroduce a
  broad notice-change announcement that would duplicate the existing one-time
  inspection/read/preview refusal announcements. All announcements use
  supported Item accessibility attachments. Actual screen-reader delivery
  remains subject to the batch-K offscreen AT-SPI limitation.
- The rest of batch K, including disabled-provider gating, scoped operands,
  keyboard/layout behavior and the approved simplified presentation, is unchanged.
- `TMPDIR=~/.cache/haseen-wt/ktmp SHELLCHECK=$(command -v shellcheck) tools/lint.sh`: **lint OK**, 402 shell, 33 Lua, 180 JSON, 256 QML (qmllint included) and 41 Go files.
- `tools/check-docs.sh`: **check-docs OK** after the corrected terminal-presentation
  and one-time launch-announcement documentation updates.
- `QT_QPA_PLATFORM=offscreen TMPDIR=~/.cache/haseen-wt/ktmp tests/run.sh tests/test-vapt*.sh tests/test-install-picker.sh`: **5,604/5,604 passed**, 34 suites, 1,551.69 seconds. The corrected terminal argv, skipped Stop Review, preserved expectations/no-`--yes`, unchecked completion and all batch-K regressions pass.

### CI hygiene and portable Security engine fixtures

- All eight newly introduced suites that lacked the standard direct-run guard
  now refuse with status 2 before sourcing helpers or creating fixtures:
  confinement-adversarial, discovery, net, panel-conformance, services,
  ui-adversarial, workflow-adversarial and workflow. The provider suite uses the
  same standard diagnostic. The existing core hygiene assertions remain intact.
- `fixtures/vapt-qml-lib.sh` centralizes the named prerequisite gates documented
  above. Missing stack/framework prerequisites retain CLI checks, name omitted
  engine sections and do not manufacture engine pass totals. The Qt import
  probe enables stderr logging like the actual runners; a silent console is
  not mistaken for an unavailable framework.
- The mock transport deliberately replies after a timer boundary and maintains
  an outstanding-response count. Baseline and adversarial sequencing waits for
  all replies; certificate and removal checks additionally settle rendering
  before injecting/checking independent anchor and certificate records.
  A clean offscreen window may produce no new frame, so optional frame waits
  are bounded while actual geometry checks retain their five-second polling.
- Geometry uses the rendered row, viewport, native text-line height and padding.
  A fitting row still has to be completely revealed. An oversized row still has
  to reveal its beginning and a readable first line, but need not align with one
  hardcoded scroll offset when Qt adds focus margins. Wrapped height permits
  only a few floating-point ulps, not a physical clipping allowance.
- All six CI behavioural assertions are retained: authoritative endpoint Review,
  scope explanation, selectable refusal Preview, actual refusal exit, actual
  refusal text, and exactly one disablement close. Anchor-removal Review and
  certificate-path Enter checks are retained too. No production panel/menu or
  CLI contract is changed and no failing behavioural case is converted to a
  skip. Scenario completion and each named QtTest function are checked instead
  of demanding a fixed total of engine passes.
- `TMPDIR=~/.cache/haseen-wt/ktmp tests/run.sh tests/test-vapt-panel-conformance.sh`:
  **97/97 passed**, including all four named QtTest functions, baseline model/UI
  cases, six-list light/dark/size/font matrix and rendered keyboard/wrapping
  assertions, on Qt 6.11.2. This is not Qt 6.12.0 or AT-SPI evidence.
- `TMPDIR=~/.cache/haseen-wt/ktmp SHELLCHECK=/usr/bin/shellcheck tools/lint.sh`:
  **lint OK**, 402 shell, 33 Lua, 180 JSON, 256 QML and 41 Go files.
- `/usr/bin/shellcheck --severity=warning -x --source-path=tests --source-path=tests/fixtures tests/test-vapt-panel-conformance.sh tests/test-vapt-ui-adversarial.sh tests/test-vapt-menu-providers.sh && bash -n tests/fixtures/vapt-qml-lib.sh`:
  **passed**; checks the shared helper through its actual consumers as well as
  its shell syntax, since the project lint glob does not enumerate fixture
  helper scripts separately.
- `QT_QPA_PLATFORM=offscreen TMPDIR=~/.cache/haseen-wt/ktmp tests/run.sh tests/test-vapt*.sh tests/test-install-picker.sh`:
  **5,607/5,607 passed**, 34 suites, 1,578.24 seconds. All qualified engine cases
  ran; no prerequisite skips were reported.
- `TMPDIR=~/.cache/haseen-wt/ktmp QS_BIN=/nonexistent tests/run.sh tests/test-core.sh tests/test-vapt-security-ui.sh tests/test-vapt-panel-conformance.sh tests/test-vapt-ui-adversarial.sh tests/test-vapt-menu-providers.sh`:
  **94/94 passed**. Core proves every direct-run refusal and an untouched direct
  HOME; CLI/manifest checks pass while every omitted engine section is named.
- `TMPDIR=~/.cache/haseen-wt/ktmp QML_BIN=/usr/bin/false tests/run.sh tests/test-vapt-security-ui.sh tests/test-vapt-panel-conformance.sh tests/test-vapt-ui-adversarial.sh tests/test-vapt-menu-providers.sh`:
  **21/21 passed**. An executable but non-working Qt prerequisite is rejected
  by the framework-only probe; no engine pass is claimed.
- `TMPDIR=~/.cache/haseen-wt/ktmp QML_TEST_BIN=/nonexistent tests/run.sh tests/test-vapt-panel-conformance.sh`:
  **91/91 passed**. The full baseline runs; only the explicitly named four
  keyboard/render tests are skipped for the missing QtTest runner.
- Documentation gate: `tools/check-docs.sh`.
