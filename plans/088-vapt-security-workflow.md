# Plan 088: Installed Security inventory and explicit workstation workflow

## Status

- **Priority**: P2
- **Effort**: L
- **Risk**: HIGH (installed metadata is untrusted; explicit help may execute only reviewed help-only bindings)
- **Depends on**: 087
- **Category**: vapt, CLI, shell
- **Planned at**: 2026-10-08
- **State**: Slices 2A-i, 2A-ii and 2B implemented. The independent final review from another model family returned REQUEST CHANGES at `60be005`; its R1-R8 corrections are recorded below. Owner approval, landing PR #39 first, rebasing/re-verifying PR #40, and rendered compositor/AT-SPI proof remain outstanding.

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
  "modified"|"unknown",reason,anchor:null|{sha256,subject,issuer,path,unchanged,
  transaction:"pending"|"removing"|"created"}}`.
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
help. Translations of one man page under `/usr/share/man/<lang>/` are that
page, and the untranslated copy wins. Multiple same-priority documents are
ambiguous and refused. Otherwise,
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
- `Model.js`: filtering/state copy, fixed verb and separate-operand argv
  construction; never executes or persists.
- `shell/Haseen/SecurityEvidence.js`: pure schema/identity/enum validation,
  shared with the menu's providers; `shell/Haseen/SecurityRoute.qml`
  (`qs.Haseen`): the typed one-shot menu hand-off. Neither plugin imports the
  other's files.
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
- `Inventory.qml`: identity-stable synchronization by id and roving
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
Removal accepts that unchanged recorded anchor or a safe incomplete removal
transaction. A pending trust whose anchor is unchanged, missing or a partial
write of the certificate the journal records permits matching-certificate
trust retry or removal; a removing journal with its anchor absent permits
removal retry only. These checks repeat under the root lock. Foreign/modified or unsafe
journals remain refusals; updater failure never claims completed trust.
No trust decision follows from a panel launch or inspection.

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
- Guessed service unit names or choosing an unreviewed unit among package-owned
  services: ownership alone cannot select a backend. The R2 reviewed table below
  replaces the earlier blanket multiple-unit refusal with explicit bindings.
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

Security UI/adversarial suites require executable `QML_BIN` and a framework-only
offscreen QtQuick/Controls probe. Keyboard/render conformance additionally
requires `QML_TEST_BIN` and QtTest. The menu-provider suite uses executable
`QS_BIN`, `dbus-run-session` and its own isolated Quickshell framework probe.
None requires Python dbus/gi modules. Missing prerequisites retain named skips
and CLI checks, without manufactured engine passes. `HASEEN_REQUIRE_ENGINE=1`
makes every such omission a counted failure; CI sets it. A framework-only probe
cannot convert production-component or behavioral failures into skips.

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

## Independent final review (other model family)

The supplied independent review returned REQUEST CHANGES for PR #40 at
`60be0053f3302030ef8a510904688e40b5b617ce`, based on PR #39 at `8e0c067`.
The remote head still matched at the start of this follow-up. All edits use a
fresh worktree, synthetic HOME/sysroot, stub PATH and private offscreen engines.
No live service, trust store, owner session or external assessment target is used.

### R1: indexed installed discovery, fixed

The old loop called the linear source predicate for every one of 204 tools
and every installed record before filtering the name. Each call scanned all
safe repository records again through `allowed_local` and `package_sources`.
`workflow.py:85` indexes repository records by exact name without dropping
duplicates, forbidden rows or unknown metadata. `:95` passes only same-name
candidate lists through the unchanged phase-1 predicates. `:258` computes
sources once per installed record, then visits only exact names and verified
reviewed aliases per tool. `workflow_actions.py:41` uses the same index.
Version, URL/trailing-slash, metadata_unknown, forbidden, repository_safe,
ALLOWED and closure_identity_ok checks remain unchanged. `metadata.py` has
no diff from the reviewed head.

`tests/test-vapt-discovery.sh:69` compares the frozen linear source algorithm
against the index on both existing fixture snapshots and policy variations:
**540 comparisons**, including private-source aliases, unsafe sources, URL/
version drift, unknown/forbidden rows and duplicate repository records.
`:115` executes the public CLI with **2,103 installed packages and 30,003
repository records** across core/extra/blackarch. The bound is **20 seconds**,
deliberately generous for CI and disk-backed fixture reads.
On the review's smaller **203 / 17,300** fixture, before was **30.352 s** and
after was **0.106 s**. The larger original implementation exceeded the bound
and was terminated at **20.019 s**; the fixed regression measured **0.146 s**
in the focused CLI run. These are measured durations, not desktop extrapolations.
Rejected: caching only filtered tools, trusting reports, changing provenance
policy, or altering phase-1 predicate semantics to gain speed.

### R2: reviewed package/unit bindings, fixed

The previous candidate scan counted every owned non-template service, so SSH's
key-generation helper made its daemon ambiguous. `workflow_actions.py:30`
binds openssh to sshd.service, postgresql to postgresql.service, apache to
httpd.service and nginx to nginx.service. `:87` still requires one supported
package owner, verified provenance, a non-template owned unit, LoadState loaded,
an owned current FragmentPath resolving to that exact path, every expectation
operand and the existing second read. Unlisted bindings remain refusals.

Public Arch file lists read during this follow-up provide the reviewed evidence:
[openssh 10.6p1-1](https://archlinux.org/packages/core/x86_64/openssh/files/)
lists sshd.service, sshd@.service and sshdgenkeys.service;
[apache 2.4.69-1](https://archlinux.org/packages/extra/x86_64/apache/files/)
lists **httpd.service only**, not htcacheclean.service;
[postgresql 18.6-2](https://archlinux.org/packages/extra/x86_64/postgresql/files/)
and [nginx 1.30.5-1](https://archlinux.org/packages/extra/x86_64/nginx/files/)
list their corresponding bindings. The review separately supplied local
openssh-10.5p1-1 evidence with the same three units.
[BlackArch's beef recipe](https://github.com/BlackArch/blackarch/blob/master/packages/beef/PKGBUILD)
contains no unit installation. No BeEF/beef-xss binding is invented.

`tests/fixtures/vapt-actions-lib.sh:9` now contains the actual Arch unit sets.
`tests/test-vapt-services.sh:135` adds unreviewed SSH and auxiliary Apache units,
checks unchanged selection, exercises all four families, refuses an unreviewed
BeEF unit and duplicate package owners. Existing expectation/foreign-fragment/
confirmation/second-read assertions retain their gates and use the reviewed
unit names. The old synthetic "any single owned unit works" requirement was
incorrect: ownership establishes file association, not which daemon the owner
authorized. A reviewed exact binding is supported by package evidence and still
must be present and owned; it is not the rejected inferred package-basename guess.

### R3: honest and recoverable CA transactions, fixed

An updater failure retained a pending/removing journal, but CLI guards accepted
only complete owned state. The missing anchor after failed removal was also
misclassified as modified. `workflow_ca.py:109` now reports safe incomplete
transactions as unknown and adds `anchor.transaction` without changing the enum
or schema version. Failed trust reason is exactly `trust transaction pending;
owned anchor unchanged; system trust update incomplete`. Failed removal reason
is exactly `removal transaction incomplete; anchor absent; system trust may
still contain CA`. Actual changed or foreign anchors remain refusals.

`workflow_ca.py:153`/`:159` admit only matching safe retry/removal evidence;
`:167` repeats fingerprint, hash, ownership, foreign-file and transaction checks
under the root lock. Removing state never authorizes trust. CLI guards at
`workflow_actions.py:401` and `workflow_actions.sh:136` use these predicates
before consent and again before the root gateway. Doctor exposes explicit safe
recovery, never completed-trust success. `Model.js:152`, `CertificateForm.qml:31`
and `Panel.qml:165` display the transaction and limit actions to matching
pending trust retry/removal or removal retry. The new transaction label exists
to distinguish incomplete trust from absent/modified evidence. Review and full
terminal typed-fingerprint authorization remain, including with --yes.

`tests/test-vapt-net.sh:276` exercises failing/successful CLI fixture updaters,
exact JSON state/reason/transaction, --yes refusal without typing, pending
removal and a changed anchor at the root lock. The fixture gateway calls the
real mutation library with its library-only root/updater seams, never the host
updater. `tests/test-vapt-confinement-adversarial.sh:125` strengthens failed_remove
to require unknown, the exact reason, removing, unchanged false and absent
anchor. `tests/test-vapt-ui-adversarial.sh:106` exercises real form visibility,
retry Review, separate fingerprint/path operands and foreign/modified refusal.
The three action suites pass **424/424**; the four Security engine suites pass
**417/417**. Rejected: optimistic completion, --yes authorization, deleting
foreign/changed anchors or suppressing failure journals.

### R4: Security engines required on CI, fixed

The shared prerequisite gate incorrectly borrowed battery/media's Python
dbus/gi and Quickshell requirements for QML-only tests. CI lacked those Python
modules and skipped all four Security suites. `tests/fixtures/vapt-qml-lib.sh:9`
now requires only each caller's engine/framework prerequisites. Its framework
probe remains separate from production assertions. `:3` retains named skips
but records a failure when HASEEN_REQUIRE_ENGINE=1; `.github/workflows/ci.yml:70`
sets that switch in the required test job. No CI packages are added for battery
or media. `tests/test-vapt-menu-providers.sh:4` creates a short private runtime
directory to keep Quickshell's Unix socket under Linux's path limit. Its probe
defers Qt.quit until configuration loading finishes, with no added timer.

The final three QML suites also ran with QS_BIN=/nonexistent and required-engine
mode and passed **412/412**, proving the unrelated prerequisite was removed.
The final four-suite focused run passes **417/417** with every named engine
section executing. Missing QML retains the named skip and **7/7** static checks
in optional mode, but required mode exits 1 with **7/8**. Missing Quickshell
affects only the provider suite: optional mode is **0/0** with its named skip,
required mode exits 1 with **0/1**. These are deliberate negative probes, not
skips in the full gate. Rejected: installing unused
Python modules, converting engine differences into skips, relaxing geometry
assertions or treating the framework probe as production conformance.

The first actual CI execution at `0cb9a9c` (run
[38236524175](https://github.com/t1nk333r/haseen/actions/runs/38236524175))
used Qt **6.12.0** and exposed **29 failed assertions**, giving
**12,527/12,556**. Lint, docs, secrets and nix passed. All four Security engines
executed rather than skipped. This failed test job is recorded as failure,
not accepted evidence of completed conformance.

Two production causes were reproduced with task-owned extracted Arch Qt 6.12
libraries, without installing packages or contacting the desktop:

- Signal delivery marshalled JSON package arrays into QVariantList sequences.
  The strict `Array.isArray` model check then refused valid capabilities at
  Review. `Panel.qml:101` converts the already-validated snapshot to plain JSON
  at the receiving boundary. No parser/model assertion is relaxed.
  `tests/test-vapt-security-ui.sh:215` asserts plain package arrays after
  actual signal delivery. Existing Review, CA recovery and close-count cases
  exercise the resulting behavior.
- CI has no font packages. A private empty fontconfig reproduced a **1 px**
  body viewport at **360x480 / font size 17**: wrapped fixed chrome consumed
  the available height. `Panel.qml:247` puts header, navigation, body and footer
  in one scroll viewport. Focus reveal now applies to those controls too.
  `tests/test-vapt-panel-conformance.sh:242` repeats every original conformance
  case with a private empty font directory and adds bounds to failure messages.
  Every visibility, oversized-first-line, keyboard, contrast and render
  assertion remains. Stacking only the header was tried and rejected because
  it still left **12.09 px**, too little for the first line.

The correction passes the three QML suites on Qt 6.12, including the fontless
matrix. Final local totals and the current-head CI result are recorded below
and in the delivery report. No fonts or unrelated Python modules are added to
CI, and no engine failure is turned into a skip.

### R5: bounded document reads and expansion, fixed

Whole-file read and gzip.decompress allocated unbounded input/output.
`workflow.py:428` now reads 64 KiB chunks with a **4 MiB input and expanded
output cap**, using zlib.decompressobj(wbits=31) and max_length. All gzip
members share the cap; malformed/truncated data or overflow refuses before
printing document bytes. `tests/test-vapt-workflow.sh:34` expands a
**1,043,669-byte owned gzip to 1 GiB**, runs help under a **128 MiB address-space
limit**, and requires clean exit 1, the expanded-limit diagnostic and no
Traceback/MemoryError. Concatenated-member, truncated-stream and uncompressed
input-limit controls retain positive/negative behavior. The supplied p3 probe
also returns exit 1 with `owned document exceeds 4 MiB expanded limit; refused`.
Rejected: catching MemoryError after allocation, trusting compressed size alone
or rendering partial output as if it were complete usage.

### R6: one guard observation and lean enablement reader, fixed

Six identical static enablement guards imported provisioning code six times
per menu open. `MenuModel.js:614` shares each expression's boolean across row
ids and when/checked/disabled tags within one batch, observing again next batch.
`workflow.sh:6` dispatches the enablement command to `workflow_menu.py:43`,
which imports only the standard library. Deep merge, literal boolean true,
single-object JSON and fixture symlink semantics remain unchanged.
The small unprivileged resolver matches phase-1's observation behavior; it
does not add a privileged metadata import or alter that auditor's trust graph.

`tests/test-menu.sh:193` counts shared observations and checks all row/tag outputs,
literal true and fresh-batch re-observation. `tests/test-vapt-workflow.sh:94`
checks absence of metadata/workflow_support imports and relative/absolute/
escaped configuration links against the existing resolver. The disabled/enabled
real provider harness retains zero-read and literal-consent assertions.
Five samples of the actual six-row disabled guard batch measured median wall
**0.584977 s before / 0.040268 s after**, child CPU **0.57 s / 0.04 s**.
Rejected: removing descendant guards, caching across menu opens, changing generic
plugin consent or extracting an unguarded dependency into the root auditor.

### R7: signal handoff deadline and diagnostics, fixed

The readiness deadline assumed an adapter would start within three seconds
under any host load. `tests/test-vapt-net.sh:374` allows **15 seconds** and
`:380` captures/prints stdout, stderr, kind, signal and exit status on failure.
All existing PID handoff, signal exit and reclaimed-loopback-endpoint assertions
remain. The changed suite passes in the **424/424** focused action run and in
the complete gate below. No production timer, polling or signal behavior changes.
Rejected: skipping the signal case or accepting a surviving wrapper/helper.

### R8: unused path helpers confined to test reference, fixed

`confined_path` and selected_directory resolved symlinks but had no production
caller. They are removed from `workflow_support.py`, and workflow.py no longer
imports the former. `tests/fixtures/vapt_reference_paths.py:1` retains their
historical pathname checks as test reference only; `tests/test-vapt-workflow.sh:186`
retains those assertions with an explicit fixture import. Actual serving still
uses descriptor traversal at `workflow_actions.py:266`, refusing symlink/hardlink
escapes in the unchanged confinement cases. Production helper definitions/imports
now number **zero**; no assertion was discarded. Rejected: promoting the old
path resolver to serving authority or deleting its checks to hide the difference.

The informational limits are now explicit in docs/vapt.md: unit ownership does
not inspect systemd drop-ins, and nc writes raw peer bytes to the terminal.
Rendered compositor and actual AT-SPI proof remain outstanding. This follow-up
does not approve or merge either PR; PR #39 must land before PR #40's rebase and
verification, then the owner gives final approval.

### Follow-up verification

These results produced the first review-fix commit `0cb9a9c`. The subsequent
Qt 6.12 correction is verified separately below.

The canonical isolated worktree is `~/.cache/haseen-wt/f40`, with disk-backed
`TMPDIR=~/.cache/hf40/tmp`. The first full run was stopped after Themegen's
private IPC pathname reached Linux's 108-byte Unix socket limit. A symlink
alias shortened the runtime path but conflicted with existing canonical-path
assertions. Moving only this task's worktree to the shorter canonical name
resolves both constraints. Every assertion remains active. Neither aborted
attempt is counted as a passing full gate.

- Five changed CLI/menu suites pass **733/733**, including **540** source
  equivalence comparisons and the large discovery fixture at **0.132 s**.
  `tests/test-vapt-workflow-adversarial.sh:192` also makes the review's nearby
  sysroot probes permanent: relative/absolute outside manager snapshots,
  escaped workflow ancestry and outside report records all refuse without
  borrowing evidence. The supplied p7 probe agrees after adapting only its
  old synthetic SSH unit name to the reviewed Arch binding.
- Six CA/network/confinement/Security suites pass **706/706**. All four
  Security engine suites execute, with their **417/417** checks included.
- The three QML-only suites also pass **412/412** with `QS_BIN=/nonexistent`
  and `HASEEN_REQUIRE_ENGINE=1`; deliberate missing-engine controls are
  documented under R4 above.
- Complete `QT_QPA_PLATFORM=offscreen HASEEN_REQUIRE_ENGINE=1
  TMPDIR=<short disk-backed directory> GO=<installed Go 1.27.1> tests/run.sh`:
  **12,689/12,689 passed**, 123 suites, exit 0. All 33 VAPT suites execute
  without prerequisite skips, including all four Security engines. The only
  skip line is `skip: ttfx is installed system-wide; the missing-ttfx message
  is not exercised`. The large discovery fixture measures **0.171 s** during
  this complete run against its 20-second bound.
- `SHELLCHECK=/usr/bin/shellcheck GO=<installed Go 1.27.1> tools/lint.sh`:
  **lint OK**, 402 shell, 33 Lua, 180 JSON, 256 QML and 41 Go files.
- `tools/check-docs.sh`: **check-docs OK**.
- `GITLEAKS=<checksum-verified 8.30.1> tools/secrets.sh`: **secrets OK**,
  222 commits scanned before the fix commit, no leaks. The release archive SHA-256 is
  `551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb`,
  matching the upstream checksum pinned in CI.

The pushed head's five CI checks and the actual Security engine log lines must
be verified separately. The earlier green test check skipped these engines and
is not evidence for R4. The delivery report records the current run's results.

### Qt 6.12 correction verification

- Three QML suites on task-owned Qt **6.12.0** pass **421/421**, including
  the complete private-empty-font conformance matrix and the actual signal
  snapshot assertion. Four Security suites on installed Qt **6.11.2** pass
  **426/426**. No prerequisite skips occur in either focused run.
- The final complete offscreen gate passes **12,698/12,698**, **123 suites**,
  exit 0. All **33 VAPT suites** run without prerequisite skips. Every Security
  engine executes, including the named fontless conformance run. The sole
  skip line is `skip: ttfx is installed system-wide; the missing-ttfx message
  is not exercised`.
- The large discovery fixture measures **0.091 s** during this full gate,
  with **2,103 installed / 30,003 repository records** against the unchanged
  **20 s** bound. The original implementation exceeded that bound at 20.019 s.
- Lint passes with **402 shell, 33 Lua, 180 JSON, 256 QML and 41 Go files**,
  using `/usr/bin/shellcheck` and Go **1.27.1**. Docs pass. Gitleaks **8.30.1**
  passes with **223 commits** scanned before the correction commit; a fresh
  committed-history scan is required before its push. The downloaded archive's
  pinned SHA-256 and the active extracted binary were re-compared and match.
- The source diff from `60be005` adds no `sudo ` occurrences and leaves
  `metadata.py` unchanged. A repository-wide literal grep is not empty:
  inherited comments/help text and `layers/chaotic/layer.sh:48`'s fingerprint
  read already exist at the reviewed head. This follow-up does not claim that
  broad textual check is empty or alter unrelated Chaotic provisioning.

The correction does not change the CLI/JSON beyond R3's additive
`anchor.transaction` and explicit recovery availability. The final delivery
report supplies the new head's five CI checks and exact engine log lines.
Rendered compositor and AT-SPI proof remain outstanding.

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

### Additional review: fixture addresses and initial panel consent

The 2026-10-12 review compares phase 2 at `ee07ac6` with phase 1 at
`8e0c067`. Separate Standards and Spec passes found one concrete issue each.
Both passes used Sol, so they add evidence without satisfying the outstanding
request for a final reviewer from another model family.

- **Standards:** `share/haseen/layers/vapt/workflow_support.py:15` followed fixture address-file and
  ancestor symlinks outside `HASEEN_SYSROOT`. The reader now reuses
  `metadata.observed_resolve` and the bounded, descriptor-based
  `metadata.metadata_read`. Missing address metadata still returns an empty
  list. The two external-fixture regressions in `tests/test-vapt-net.sh`
  failed all four new assertions before the fix (**178/182**) and passed
  afterward (**182/182**). They use only disposable synthetic metadata.
- **Spec:** the generic panel host accepts every enablement value except
  literal false, while this optional surface requires literal true.
  `share/haseen/shell/plugins/haseen.security/Panel.qml:172` now refuses construction before any read when
  its merged entry does not contain `enabled: true`. The real-engine
  `OptIn.qml` scenarios in `tests/test-vapt-security-ui.sh` construct the
  production component with false, string true, null, a null entry and an
  empty entry. Every case requires zero reads, zero pending requests and
  exactly one close. All five formerly started six reads; the suite was
  **93/95** before the fix and **95/95** afterward. Existing literal-true
  scenarios retain the positive discovery control.
- The blanket Python wording in architecture §6 conflicted with the explicit
  on-demand workflow contract in §3. It now distinguishes shell startup and
  polling from the finite reads/actions already implemented by this optional
  panel. No new sampler, timer or default is introduced.
- A fresh read-only check of both fixes found no residual issue. The initial
  ten-suite workflow/panel regression run passed **990/990** before adding the
  new regressions. The complete gate results below describe the final tree.

Rejected changes: altering generic `Config.isEnabled` would change the
existing opt-out behavior of unrelated plugins; a second address resolver
would duplicate the established fixture-confinement policy. Neither is needed.

Final verification uses the short isolated worktree and disk-backed
`TMPDIR=~/.cache/hv12`. Longer worktree/runtime paths can exceed Unix socket
limits; the hard-coded `/tmp` paths in the clock and greeter harnesses still
encounter this account's existing quota. No unrelated temporary files were
removed and no production checks were weakened.

- Focused regressions through `tests/run.sh`: **182/182** for
  `tests/test-vapt-net.sh` and **95/95** for `tests/test-vapt-security-ui.sh`.
- Complete `QT_QPA_PLATFORM=offscreen GO=<installed Go 1.27.1> tests/run.sh`:
  **12,494/12,511 passed**, 123 suites, exit 1. All VAPT suites passed. The
  17 failure counts reproduce on unchanged `main` at `da73029`: the aborted
  clock harness counts once, greeter has ten failures from its `/tmp` logging
  and IPC quota, launcher providers has four failures, and two ydotool checks
  select the installed program ahead of the fixture stub. The baseline runs
  of clock/compat IPC/compat desktop and greeter/launcher providers/menu back
  report **45/48** and **124/138** respectively. No new failure was introduced
  by this follow-up; the local whole-suite gate at `4577c27` failed for these
  baseline limitations, repaired by plan 089 below.
- `SHELLCHECK=/usr/bin/shellcheck GO=<installed Go 1.27.1> tools/lint.sh`:
  **lint OK**, 402 shell, 33 Lua, 180 JSON, 256 QML and 41 Go files.
- `tools/check-docs.sh`: **check-docs OK**.
- `GITLEAKS=<verified upstream 8.30.1> tools/secrets.sh`: **secrets OK**,
  no leaks found. The release archive's SHA-256 matched its upstream checksum.
- A nested compositor with the inert Security fixture reached `RENDER-READY`,
  but `grim -o IO` did not complete. The recorded compositor and capture
  processes were stopped; no compositor screenshot or AT-SPI proof is claimed.
- The owner explicitly keeps the review from another model family pending.
  This follow-up does not approve or merge either PR in the stack.

### Local gate follow-up: desktop fixture isolation

The owner requested repairs for all 17 local baseline failure counts. Plan
089 records the reproduced failures and controlled probes. Clock/greeter
runtime directories now honor `TMPDIR`; ydotool passthrough tests isolate
their lookup PATH; `sandbox()` clears inherited uwsm launch markers. The
launcher failures were caused by those markers selecting the uwsm branch
instead of the systemd scope branch expected by this fixture.

The four original failing suites, core isolation regressions and Apps launch
matrix pass **279/279** with inherited markers deliberately present. All
original behavioral assertions remain active. The complete final run passes
**12,545/12,545**, 123 suites, exit 0; all 33 VAPT suites ran without
prerequisite skips. Lint, docs and secrets gates pass. Plan 089 records the
commands and evidence. Runtime VAPT contracts and the pending review from
another model family are unchanged.
