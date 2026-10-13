# Plan 088: Installed Security inventory and explicit workstation workflow

## Status

- **Priority**: P2
- **Effort**: L
- **Risk**: HIGH (installed metadata is untrusted; explicit help may execute only reviewed help-only bindings)
- **Depends on**: 087
- **Category**: vapt, CLI, shell
- **Planned at**: 2026-10-08
- **State**: DONE 2026-10-12 (merged as PR #40), amended 2026-10-13 (plan 090). Open: rendered-compositor and AT-SPI proof of the panel.

## Contract

Provisioning (plans 007, 087) installs packages without executing them. This
plan adds read-only installed inventory, explicit local workstation actions
and an optional panel. No AUR, Omarchy dependency, assessment execution,
startup service or default-on plugin is added. Every new command has a router
header, `--help` and an offline, write-free `--dry-run`.

### Discovery and JSON

`workflow.py` reuses `metadata.py`'s installed local database, safe
repository, identity and native-environment verification. Exact logical names
and reviewed aliases map packages to inventory roots; no report-only
evidence, Provides, suffix stripping, PATH lookup or package-to-command guess
is accepted. Package file inventories and actual executable mode supply
entrypoints; every symlink hop and the final file must be uniquely owned by
the selected package. Native console entries come from pinned distribution
RECORD files inside the verified environment; installed modules and
interpreters are never imported or run. Desktop files supply passive
name/path/terminal metadata, not actions. Repository records are indexed by
exact name once, sources computed once per installed record, and usage
documents indexed once per package; `tool-help`/`tool-run` discover only the
selected tool.

All JSON stdout is one `schemaVersion: 1` object; diagnostics go to stderr.

- `tool-list`: `{schemaVersion, tools, sources, privateSource}`. A tool has
  `id`, `groups`, `state` (`installed|missing|unknown`), `reason`, `dataOnly`,
  `packages`, `entrypoints`, `desktopEntries` and nullable `native` evidence.
  Packages have `name`, `version`, `source` (matching-source array),
  `provenance` (`verified|unknown`) and verified readable `files`.
  Entrypoints have absolute owned `id/path`, `kind` (`executable|native`),
  `documentation` (`{path,kind}`) and `usage` (`state: ready|unavailable`,
  nullable `kind: man|document|reviewed-argv`, `reason`); no discovery argv.
  `ownership` (`present|missing`) and tool `provenance` (`verified|unknown`)
  are separate. `--all` adds `resolution` (`state/source/target/reason`), the
  recorded report evidence that explains a missing item; it is never an
  installed-entrypoint authority.
- `status --json` and `doctor --json` add `provisioning` with
  `state: healthy|missing|degraded`, the original `exitCode: 0|1|2` and
  diagnostics, and `provisioning.resolutions`; `workflow` holds effective
  settings, menu state, entrypoint and documentation-ready counts. Status
  keeps 0/1/2; doctor returns 1 for missing/degraded, 2 for usage; neither
  repairs or refreshes. Doctor adds `workflow.capabilities` for `listener`,
  `http-server`, `enumeration-host`, `proxy-ca` and `remmina`, each with
  `installed`, `available`, `state`, `prerequisitePackages`, `reason` and a
  fixed `command` leaf verb (`enumeration-host` → `net-file-server`, no
  alias). Availability comes from owned adapters, source policy, settings and
  anchor state; invalid evidence is a refusal, never hypothetical success.
- `menu`: `{schemaVersion, plugin: "haseen.security", enabled}`. Files
  deep-merge objects and replace arrays and scalars, as `Config.qml` does;
  only literal `enabled: true` enables. `--enabled` exits 0 when enabled, 1
  otherwise. It is answered by `workflow_menu.py`, which imports only the
  standard library.
- `service-list`: `{schemaVersion, services: [{id, installed, package,
  ownership, unit, fragmentPath, state, activeState, subState,
  exposure: "unknown", reason}]}` for `ssh/postgresql/apache/nginx/beef`;
  ownership `verified|missing|ambiguous|refused|unknown`, state
  `running|stopped|transitioning|failed|unknown`.
- `net-addresses`: `{schemaVersion, addresses: [{interface, address, family,
  scope, prefixLength}]}`, read only on explicit request.
- `net-proxy-ca status`: `{schemaVersion, state: none|owned|foreign|modified|unknown,
  reason, anchor: null|{sha256, subject, issuer, path, unchanged,
  transaction: pending|removing|created}}`. Refusals are
  `{schemaVersion, state: "refused", reason}` (inspection also
  `certificate: null`). Interactive service, network, client, trust and
  remove actions have no JSON mode.
- Help/session dry-run: `{schemaVersion, tool, entry, evidence, shellArgv,
  dryRun: true}`; nothing runs and no terminal opens.

### Usage and shell

Several entrypoints require `--entry` with an owned absolute entry ID. Help
prefers one basename-matching owned man page, then one matching document, and
prints plain text (roff source included) with terminal control bytes
stripped; it never invokes man, a pager or a renderer. Translations under
`/usr/share/man/<lang>/` are one page; the untranslated copy wins, else the
first translation by path. Several same-priority documents are ambiguous and
refused. Retained input and gzip output are each capped at 4 MiB, read in 64
KiB chunks; overflow or a bad stream refuses before any byte is printed.
Otherwise only a reviewed package/entry/argv binding in
`files/help-bindings.json` qualifies; the shipped registry is empty, because
no upstream-specific safe help argv was established.

`tool-run` validates usage and shell, shows the same documentation (flushed
before exec) and opens only the user's login shell with `-i`, which must be
listed in `/etc/shells` (bash fallback with the same checks). No selected
program, prefilled command, elevation, backend or service starts. Fixture
sysroots display documents but refuse real binding or shell execution.

### Settings

Explicit provisioning seeds `default/vapt/workflow.json` into the user's VAPT
configuration once (`share/haseen/layers/vapt/provision.sh:495-497`);
observation never seeds and existing files are not edited. Defaults:
`showLocalAddresses: false`, `enumerationScript: null`,
`bindAddress: "127.0.0.1"`. Addresses are never stored.

### Services

`start`, `stop` and `restart` act only on reviewed package/unit bindings:
openssh → `sshd.service`, postgresql → `postgresql.service`, apache →
`httpd.service`, nginx → `nginx.service`. The bound unit must be a
non-template unit owned by one supported package with verified provenance,
`LoadState` loaded, and an owned current FragmentPath resolving to that path.
Auxiliary units (for example `sshdgenkeys.service`) do not change
selection; BeEF has no reviewed binding and stays refused. Optional
`--expect-unit UNIT --expect-fragment PATH` bind the snapshot the panel
displayed: a mismatch refuses with exit 1 before privilege. Start and
restart open a terminal and ask; stop asks nothing and needs no terminal.
All three re-read ownership, FragmentPath and state immediately before
`systemctl`; a small window remains between that read and the manager call,
which only a manager-level atomic API would close. Nothing enables, presets
or initialises a service; ownership covers the loaded fragment, not drop-ins.

### Local helpers

Endpoints accept literal IPv4/IPv6 addresses (IPv6 with at most one `%SCOPE`
matching `[A-Za-z0-9_.-]{1,64}`, preserved unchanged) and ports 1024–65535;
no DNS, bind or probe happens in preview. A server or a non-loopback listener
needs consent at an interactive terminal: `--yes` or piped input refuses. A
loopback listener needs none. After consent the wrapper `exec`s the reviewed
adapter or server, so signals cannot orphan a helper holding the endpoint.

`net-http-server` serves an explicitly selected directory through an opened
root descriptor; every component is opened without following links, only
single-link regular files are returned, and the link count is rechecked per
request. `net-file-server` serves one package-owned single-link regular file
at `/file`, pinned by inode. No listing, CGI, upload or escape. Requests
whose Host is not `localhost` or a local literal address of the bind, or that
carry several Host headers, get 421; an HTTP/1.0 request without Host is
served. Serving is serial with a 5 s idle wait and a 30 s absolute
connection deadline; the bind uses the literal address without reverse DNS.
`nc` writes raw peer bytes to the terminal. `net-remmina` launches only the
verified client, with no target or credentials.

### CA trust

`inspect` reads one bounded public PEM/DER certificate and reports subject,
issuer, uppercase SHA-256, validity and CA/private-key flags, never contents.
CA status comes only from OpenSSL's typed `basicConstraints` decoding
(`X509_check_ca == 1`); rendered text, printable malformed DER and legacy-only
evidence cannot confer it. Inspection, trust payload and the root helper
share that classifier. `trust` requires typing the full fingerprint, `--yes`
included, rechecks the immutable bytes and installs one fingerprint-owned
anchor through the root gateway. `remove` asks, and removes only the
unchanged recorded anchor.

The root journal (`/var/lib/haseen/vapt/proxy-ca.json`) is written before the
anchor and stores the certificate (optional `pem` field, checked against
`contentSha256`). Under the root lock, a `pending` journal whose anchor is
unchanged, missing or a partial write of that certificate allows trust retry
(same fingerprint and bytes) or removal; a `removing` journal with its anchor
absent allows only removal retry. Foreign, modified or unsafe state is
preserved and refused; under a journal without `pem` a partial anchor
proves nothing, so only a trust retry with the certificate completes it. Status reports such transactions as `unknown` with
`anchor.transaction`; success is claimed only after the updater succeeds.

### Optional Security panel

`haseen.security` is schema 1, version 1.0.0, panel-only, with review
permissions `exec` and `files:read`. Shipped defaults set `enabled: false`;
it is in neither bar nor services, and the panel host creates it only on
demand. The panel refuses construction before any read unless its merged
entry has literal `enabled: true`, and closes when that changes. Disablement
does not cancel launched helpers.

Pages: Overview, Tools, Services, Local actions. Selecting a row inspects;
several entrypoints use EntryPicker; unavailable or ambiguous usage disables
documentation and session buttons. Recorded resolutions, source policy,
package provenance, usage evidence and service activity are shown
separately. Local forms show missing or refused prerequisites, loopback and
explicit-path drafts, literal validation, an authoritative dry-run preview,
certificate inspection and the full selectable fingerprint.

Launch rules: every launch goes through `Apps.launch` with fixed whitelisted
verbs (`net-listener`, `net-http-server`, `net-file-server`, `net-proxy-ca`,
`net-remmina`, and the closed tool and service verbs) and untrusted operands
as separate argv elements. Preview runs the real `--dry-run` through Process.
Endpoint Review first captures a successful dry-run; a refusal stays in
Preview with the draft kept. No panel action passes `--yes`. Everything but
the remote desktop client opens in a terminal, which asks before a service
start or restart, a local server, a non-loopback listener and a CA trust
change; Stop and the client have no prompt, and Stop skips Review. Service
argv carries the displayed unit and FragmentPath expectations. A launch
announces "completion has not been checked", never success; status comes
only from reopen or Refresh, never from launch callbacks or polling. Paths,
addresses, fingerprints, drafts and the hand-off live only in memory.

Keyboard and layout: non-wrapping Up/Down/j/k, Home/End and viewport
PageUp/PageDown in all six lists; Enter/Right/l inspect or select, never
execute; Left/h go back outside text editors. Focused rows are revealed
fully when they fit, from their beginning when not. Header, navigation, body
and footer share one scroll viewport, so large text or fallback font metrics
cannot leave the body without a readable line. Detail headings take named
entry focus, Tab reaches the first control, Review focuses Cancel, every Tab
stop has a 2 px focus ring. Endpoint Enter validates and prepares Review;
certificate-path Enter only inspects; the first Escape closes an open address
chooser only. A repository-source read error stays labelled with Retry
without clearing other sections. Refusals are announced once per response
through Item accessibility.

Components, one file each in `share/haseen/shell/plugins/haseen.security/`:
`Panel.qml` (overlay, navigation, reads, drafts, launch), `Model.js`
(filtering, copy, fixed verb and argv construction; executes nothing),
`Header`, `Navigation`, `Overview`, `ToolRow`, `ToolDetail`, `EntryPicker`,
`ServiceRow`, `ServiceDetail`, `QuickActions`, `EndpointForm`,
`CertificateForm`, `Review`, `Preview`, `StateMessage`, `Read` (finite
read-only Process, no timer or retry), `Inventory` (identity-stable rows and
roving focus), `ActionButton`, `Label`, `Field`, `GroupFilter`,
`IncludeMissing`, `SelectableText`. Shared with the menu through `qs.Haseen`:
`Haseen/SecurityEvidence.js` (schema, identity and enum validation) and
`Haseen/SecurityRoute.qml` (the one-shot page/item hand-off). Neither plugin
imports the other's files.

### Menu rows

`haseen.menu`'s static provider map gains `setup.security.vapt` and its
`.panel`, `.tools`, `.services`, `.local`, `.status` rows. Every Security row
is guarded by `haseen vapt menu --enabled`, which the menu and the launcher's
`/` provider answer in-process from the shell's plugin flag and never run.
Service rows add `&& haseen-pkg-present openssh|postgresql|apache|nginx`,
BeEF `beef || beef-xss`, Remmina `remmina`; these are visibility only, the
CLI authorises. Provider scripts are exactly `haseen vapt tool-list --json`,
`haseen vapt service-list --json` and `haseen vapt doctor --json`, and read
nothing while Security is disabled. Dynamic rows (`.tools.t-<UTF8-hex-id>`,
`.services.<id>`, `.local.<id>`; `.loading/.empty/.error` are disabled
information) carry typed page/item roles and the fixed action `haseen shell
ipc panel toggle haseen.security`. Identical guard expressions run once per
batch. Cached rows are disabled previous snapshots until a fresh read; ✓
marks only present rows.

### Specification interpretations

The observed CLI shapes and the `command` leaf supersede proposed names
(`enumeration-host` uses `net-file-server`). CLI membership and ownership
policy is reused, not duplicated as a QML package allowlist; the panel
validates transport identities and enums and never accepts commands. "No
verified executable entrypoint" describes the evidence, not a claim that no
executable bytes exist. Nonzero status/doctor/CA objects are displayed;
malformed schemas refuse the affected section. The absence of a connectivity
probe is not an inferred offline state. No GUI fingerprint entry duplicates
terminal authorisation.

## Rejected options

- Package basename guesses, speculative `--help`, installed interpreter
  imports and man/helper execution during discovery: not trustworthy
  evidence. Rendering man pages with a pager or roff processor: a
  package-owned helper could run.
- Generic help bindings: arguments must be reviewed per package and entry.
- Report-driven installed menus: reports describe attempts, not files.
- Launching tools on session creation, shell prefill, elevation or a
  default-on Security UI: outside the explicit-workstation boundary.
- A second source/identity verifier, or changing plan 087's predicates for
  speed: one policy. Caching only filtered tools or trusting reports was
  also rejected for discovery speed; indexing keeps the predicates.
- Editing settings on read or reapply.
- Guessed unit names, or any single owned unit: ownership shows file
  association, not which daemon the owner authorised; only reviewed bindings.
- Payload-enabled listeners, directory listing, CGI, guessed enumeration
  paths, fetched scripts, detached daemons.
- Generic CA trust, `--yes` bypassing the typed fingerprint, removing foreign
  or modified anchors, optimistic updater success, or suppressing failed
  journals.
- Catching MemoryError after allocation, or trusting compressed size, for
  document limits.
- Caching guard results across menu opens or removing descendant guards.
- Changing generic `Config.isEnabled` to require literal true: it would
  change the opt-out behaviour of unrelated plugins; the panel checks itself.
- Stacking only the header to fix the fontless layout: it left 12.09 px for
  the body at 360×480, font size 17.
- Installing fonts or unrelated Python modules in CI, or turning engine
  differences into skips.

## Evidence

Discovery and usage:

- Reused verification: `share/haseen/layers/vapt/metadata.py:511`
  (`installed`), `:937` (`closure_identity_ok`), `:961` (`allowed_local`),
  `:3807` (`native_state`).
- `share/haseen/layers/vapt/workflow.py:88` (`index_repositories`), `:98`
  (`package_sources`), `:130` (`owned_file`), `:176`
  (`documentation_index`), `:199` (`documentation`), `:236`
  (`native_evidence`), `:291` (`discover`), `:441` (`show_help`), `:478-511`
  (`document_bytes`, 4 MiB caps).
- Status keeps the provisioning verifier: `workflow.sh:16`
  (`vapt_workflow_status`), `bin/haseen-vapt-status:12`.
- Tests: `tests/test-vapt-discovery.sh` "indexed source results equal reviewed
  linear predicates" (:113) and "large installed/repository/package fixture
  discovery within bound" (:152: 2,103 installed and 30,003 repository
  records, one package with 2,002 documented entries in 20,005 files, 20 s
  bound); `tests/test-vapt-workflow.sh` "translated man pages are one page"
  (:37), "one GiB expanded document bomb cleanly refused within 128 MiB"
  (:65), "piped document reaches the reader before the shell starts" (:119),
  the menu reader imports neither `metadata` nor `workflow_support` (:137).

Services and helpers:

- `share/haseen/layers/vapt/workflow_actions.py:34` (`SERVICE_BINDINGS`),
  `:92` (`service_list`), `:145` (`local_capabilities`), `:220`
  (`accepted_hosts`), `:248` (`LiteralHTTPServer`), `:271` (`DeadlineIO`),
  `:298` (`ConfinedHandler`; link count per request at `:355`), `:382`
  (`serve`; single-file startup at `:402`), `:420` (`certificate_payload`).
- `share/haseen/layers/vapt/workflow_actions.sh:15` (`vapt_program`), `:35`
  (`vapt_exposure_consent`), `:68` (`vapt_service_action`), `:99`
  (`vapt_endpoint_action`, `exec` at `:164-166`), `:170` (`vapt_ca_action`).
- `share/haseen/layers/vapt/workflow_support.py:15` (`host_program`), `:91`
  (`validate_endpoint`), `:117` (`open_selected`), `:138`
  (`selected_owned_file`), `:176` (`_basic_constraints_ca`), `:198`
  (`inspect_certificate_data`), `:252` (`read_certificate_bytes`).
- `share/haseen/layers/vapt/workflow_ca.py:89` (`record_read`), `:106`
  (`anchor_condition`), `:124` (`recoverable`), `:136` (`ca_status`), `:188`
  and `:195` (`trust_allowed`, `remove_allowed`), `:202` (`mutate`).
- Public Arch file lists for the bindings:
  [openssh 10.6p1-1](https://archlinux.org/packages/core/x86_64/openssh/files/)
  (`sshd.service`, `sshd@.service`, `sshdgenkeys.service`),
  [apache 2.4.69-1](https://archlinux.org/packages/extra/x86_64/apache/files/)
  (`httpd.service` only),
  [postgresql 18.6-2](https://archlinux.org/packages/extra/x86_64/postgresql/files/),
  [nginx 1.30.5-1](https://archlinux.org/packages/extra/x86_64/nginx/files/);
  [BlackArch's beef recipe](https://github.com/BlackArch/blackarch/blob/master/packages/beef/PKGBUILD)
  installs no unit. The fixture uses these unit sets
  (`tests/fixtures/vapt-actions-lib.sh:9`).
- Tests: `tests/test-vapt-services.sh` reviewed bindings (:9-16), snapshot
  expectations (:35-50), terminal-free stop (:104-106), unreviewed and
  auxiliary units, BeEF and duplicate owners (:148-176);
  `tests/test-vapt-net.sh` consent (:67-86), the confined HTTP handler and 421
  cases (:189), planted `json.py` (:271), `--yes` never bypasses the typed
  fingerprint (:287), failed trust and removal (:339-376), interrupted trust
  (:499-524), signal hand-off (:555); `tests/test-vapt-confinement-adversarial.sh`
  "failed removal updater cannot claim absent trust" (:147);
  `tests/test-vapt-workflow-adversarial.sh` outside snapshots, settings and
  records refused (:207-226). Every executed program is chosen as sysroot +
  path, and the runner executes nothing else
  (`tests/fixtures/vapt-actions-runner.sh:14`).

Panel and menu:

- `share/haseen/shell/plugins/haseen.security/Panel.qml:104-108` (signal
  payloads kept as plain JSON), `:145` (`launch`), `:157` (`prepare`),
  `:185-190` (literal opt-in before any read), `:251-253` (one scroll
  viewport), `:261-268` (Left/h); `Model.js:27`, `:32`, `:69` (argv
  builders), `:84` (`terminal`), `:89-97` (`anchorRemoval`, `anchorTrust`).
- `share/haseen/shell/plugins/haseen.menu/MenuModel.js:195-204` (guards),
  `:196` (`providerAllowed`), `:416` (`labelFor`), `:631`
  (`answerSecurityGuard`), `:638` (`guardScript`); callers
  `share/haseen/shell/plugins/haseen.menu/Panel.qml:875` and
  `share/haseen/shell/plugins/haseen.commands/Provider.qml:54`.
- Tests, in the real Qt engine with fixture modules
  (`tests/fixtures/vapt-qml-lib.sh`): `tests/test-vapt-security-ui.sh`
  (model, rows, preview, services, certificates, hand-off, "signal snapshot
  keeps plain JSON package arrays" :69, literal opt-in in `OptIn.qml` :311-351);
  `tests/test-vapt-ui-adversarial.sh` (hostile identities, Stop's terminal
  argv with expectations :81, certificate recovery);
  `tests/test-vapt-panel-conformance.sh` (five named QtTest functions,
  `test_all_list_surfaces`, `test_anchor_and_certificate_submission`,
  `test_contracts`, `test_left_and_h_go_back`, `test_keyboard_and_wrapping`
  (:245), rendered at 360×480, 560×640 and 720×640, font size 11 and 17, in
  stock Flexoki Light and Everforest tokens, then again with an empty private
  font directory (:250-263)); `tests/test-vapt-menu-providers.sh` (real
  Quickshell menu without the panel's directory, disabled providers read
  nothing, :87-88); `tests/test-menu.sh` (one observation per guard batch
  :193-205, in-process Security guard :250-257).
- Engine prerequisites: each suite names what it needs (`QML_BIN`,
  `QML_TEST_BIN`, `QS_BIN` with `dbus-run-session`) through
  `vapt_qml_available` (`tests/fixtures/vapt-qml-lib.sh:14`); a missing one is
  a named skip, and a counted failure under `HASEEN_REQUIRE_ENGINE=1`
  (`:5-12`), which CI sets (`.github/workflows/ci.yml:70`).

Final gate before the merge: `QT_QPA_PLATFORM=offscreen tests/run.sh`,
12,545/12,545 across 123 suites, all 33 VAPT suites without prerequisite
skips (plan 089); lint, check-docs and secrets OK. PR #40 merged on
2026-10-12 through protected `main` (required lint, test, docs, secrets and
nix checks, `AGENTS.md`).

## Verification limits

Fixtures cover service gateways without live control, listener argv without a
live listener, confined HTTP over ephemeral loopback sockets, and CA
transactions whose updater is the fixture root's recording stub. No external
target, live desktop, system trust store, installed security tool or real
interactive shell is exercised. Package ownership metadata does not attest
retained file bytes.

The panel runs offscreen in production QML with fixture modules. Not
established:

- rendered proof on a compositor: a nested compositor with the inert Security
  fixture reached `RENDER-READY`, but `grim -o IO` did not complete;
- AT-SPI exposure: the nested D-Bus accessibility registry started, but the
  offscreen application did not appear in its tree, so roles, names, state,
  reading order and announcement delivery are unverified;
- pixel measurements across all stock themes and text scales, and Nerd Font
  coverage.

Qt versions and font metrics are not pinned; geometry assertions derive from
rendered controls and allow only floating-point roundoff.
