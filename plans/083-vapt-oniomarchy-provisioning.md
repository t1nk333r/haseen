# Plan 083: VAPT inventory and opt-in signed oniomarchy source

## Status

- **Priority**: P2
- **Effort**: L
- **Risk**: MEDIUM (slice 1A widens the inventory and tightens identity matching; slice 1B adds a signed package source and is security-sensitive)
- **Depends on**: 007
- **Category**: vapt, packages
- **Planned at**: 2026-10-07, owner request: integrate the tool categories of the oniomarchy distribution into haseen's VAPT layer without depending on Omarchy
- **State**: IN PROGRESS 2026-10-08. Slice 1A (inventory, aliases, dependency roles, official pins, identity semantics, docs) is implemented with `tests/test-vapt-inventory.sh`. Slice 1B is partly implemented and not complete: the private descriptor, `--with-oniomarchy`, the `repo-status`/`repo-enable`/`repo-disable` commands, the pinned HTTPS key check, database/keyring verification, keyring authority and rotation rules, strict `Required DatabaseRequired` rendering/freezing/recovery, the 52-name admission table and the last-tier resolver exist, with `tests/test-vapt-oniomarchy.sh`. The trust and transaction suites (`tests/test-vapt-oniomarchy-trust.sh`, `tests/test-vapt-oniomarchy-transactions.sh`) are not written, so the approval, rotation, frozen-signature and recovery paths are unexercised; the 1B docs updates are not done. Independent review of both slices is outstanding.

## Goal

The VAPT layer (plan 007) provisions explicit tool groups from reviewed signed
sources and never runs a tool. This plan adds ten tool groups and a few roots
to two existing groups, from oniomarchy's category facts, and then (slice 1B)
an opt-in, x86_64-only, signature-required package source for the items that
only its repository publishes. The layer still never runs a listed tool,
starts or enables a service, or executes an assessment.

The desktop-facing workflow (a Security menu, tool help, service control) is a
separate plan and is not part of this one.

## Facts used, and where they came from

Supplied facts (the owner's brief; not independently authenticated here):

- oniomarchy's repository publishes exactly 52 packages (the list is in
  `tests/fixtures/vapt-oniomarchy/inventory.json`, `sourcePackages`).
- Its stanza is `[oniomarchy]`, `SigLevel = Required DatabaseRequired`,
  `Server = https://pkgs.oniomarchy.com/$arch`, x86_64 only. Its key is
  published at `https://pkgs.oniomarchy.com/oniomarchy.gpg`, primary
  fingerprint `0F5F9214F312B067ECBF1DF125E2C00AA6340BD0`.
- None of the SDR suite; wifite, reaver, bully, cowpatty, hostapd,
  hcxdumptool, hcxtools, kismet, pixiewps; keepassxc, mat2, veracrypt;
  macchanger, tor; openssh, remmina; ghidra's `jdk-openjdk`; hexstrike-ai or
  metasploit-mcp is in that repository.

Public catalogue lookups (time-sensitive; they say what was published when
queried, not what a given machine's sync databases hold):

- Arch exact-name queries, `https://archlinux.org/packages/search/json/?name=NAME`:
  found in `extra` for the twelve official SDR names, the nine official
  wireless names, keepassxc, mat2, veracrypt, macchanger, tor, routersploit,
  remmina, xorg-xhost, jdk17-openjdk, jdk-openjdk and python-wxpython; in
  `core` for openssh. No result for chirp, supersdr, can-utils, gophish,
  social-engineer-toolkit, maltego, hexstrike-ai, metasploit-mcp, recon-ng,
  theharvester, wordlists, java17-openjfx or sleuthkit-java.
- BlackArch catalogue (`https://blackarch.org/tools.html` and the category
  pages): cubicsdr, dump1090, airgeddon, fern-wifi-cracker, can-utils,
  gophish, the toolkit as package `set`, maltego, armitage, beef, recon-ng and
  theharvester are listed. A listed recipe does not prove a published signed
  binary.

Read in this tree: `share/haseen/layers/vapt/provision.sh`
(`vapt_manifest_validate`, `vapt_identity_ok`, `vapt_repo_target`,
`vapt_resolve_item`), `share/haseen/layers/vapt/pacman.sh`
(`vapt_repo_allowed`, the `-D --asdeps`/`--asexplicit` install-reason
bookkeeping after a commit), and the 15 original manifests.

## Slice 1A: inventory (implemented)

### Groups

`VAPT_GROUPS` in `provision.sh` is now 25 groups, in this order: `core network
web passwords ad osint cloud mobile forensics api htb-cjca htb-cpts htb-cwes
htb-cwee htb-coae sdr wireless privacy anonymity automotive social reporting ai
exploitation services`. `--all` selects exactly these; there is still no
default. Every group file is validated on every run, selected or not, so a
missing or malformed new file refuses even `--groups core`.

The original fifteen memberships are unchanged. Each new file and each
addition to an existing file starts with the provenance line
`# Additional tool-name inventory from oniomarchy category facts; independently resolved by haseen; no upstream installer code copied.`

| Group | Roots |
|---|---|
| `sdr` | airspy, chirp, cubicsdr, dump1090, gnuradio, gqrx, hackrf, inspectrum, limesuite, multimon-ng, qspectrumanalyzer, rtl-sdr, rtl_433, soapysdr, supersdr, urh |
| `wireless` | airgeddon, bully, cowpatty, fern-wifi-cracker, hcxdumptool, hcxtools, hostapd, kismet, pixiewps, reaver, wifite |
| `privacy` | keepassxc, mat2, veracrypt |
| `anonymity` | macchanger, tor |
| `automotive` | can-utils |
| `social` | gophish, social-engineer-toolkit |
| `reporting` | maltego |
| `ai` | hexstrike-ai, metasploit-mcp |
| `exploitation` | armitage, beef, routersploit |
| `services` | openssh, remmina |
| `osint` (added) | recon-ng, theharvester |
| `passwords` (added) | wordlists |

The manifests and native rows now name **204 distinct tool names** (158
before). `tests/test-vapt-inventory.sh` computes the union from the files and
checks that `--all` reports each exactly once.

`services` installs client and support packages; provisioning never enables
or starts a unit. `anonymity` never changes an address or starts Tor. `ai`
registers nothing with an AI client and starts no MCP server.

### Per-item sources

| Item | Official pin | Other tiers | oniomarchy package (slice 1B) | Identity |
|---|---|---|---|---|
| airspy, gnuradio, gqrx, hackrf, inspectrum, limesuite, multimon-ng, qspectrumanalyzer, rtl-sdr, rtl_433, soapysdr, urh | `extra/NAME` | usual order | — | — |
| cubicsdr | — | BlackArch | `cubicsdr` | — |
| dump1090 | — | BlackArch | `dump1090-git` (alias) | — |
| chirp | — | — | `chirp-next` (alias) | — |
| supersdr | — | — | `supersdr` | — |
| bully, cowpatty, hcxdumptool, hcxtools, hostapd, kismet, pixiewps, reaver, wifite | `extra/NAME` | usual order | — | — |
| airgeddon | — | BlackArch | `airgeddon` | — |
| fern-wifi-cracker | — | BlackArch | `fern-wifi-cracker-git` (alias) | — |
| keepassxc, mat2, veracrypt, macchanger, tor | `extra/NAME` | usual order | — | — |
| can-utils | — | BlackArch | `can-utils` | `https://github.com/linux-can/can-utils` |
| gophish | — | BlackArch | `gophish` | — |
| social-engineer-toolkit | `blackarch/set` | BlackArch `set` (alias) | `social-engineer-toolkit` | `https://github.com/trustedsec/social-engineer-toolkit` |
| maltego | — | BlackArch | `maltego` | `https://www.maltego.com` |
| hexstrike-ai | — | — | — | `https://github.com/0x4m4/hexstrike-ai` (for a future source) |
| metasploit-mcp | — | blocked | — | blocked (see below) |
| armitage | — | BlackArch | `armitage-git` (alias) | `http://www.fastandeasyhacking.com` |
| beef | — | BlackArch | `beef-xss` (alias) | `https://github.com/beefproject/beef` |
| routersploit | `extra/routersploit` | usual order | — | — |
| openssh | `core/openssh` | usual order | — | — |
| remmina | `extra/remmina` | usual order | — | — |
| recon-ng | — | BlackArch | `recon-ng` | `https://github.com/lanmaster53/recon-ng` |
| theharvester | — | BlackArch | `theharvester-git` (alias) | `https://github.com/laramies/theHarvester` |
| wordlists | — | exact name only | `wordlists` | exact-name policy |

"Usual order" is plan 007's: pins, BlackArch, pinned native, enabled
Chaotic-AUR, CachyOS, Arch exact then reviewed Provides. Until slice 1B lands,
an item whose only publisher is oniomarchy is reported unavailable.

### Tables

All live in `share/haseen/layers/vapt/packages/` and are required: a missing
table refuses provisioning before anything runs.

- `pins.tsv` (unchanged columns `logical`, `repository/package`): 29 official
  pins added, plus `social-engineer-toolkit blackarch/set`. A pin must now name
  an inventory root and appear once.
- `identities.tsv` (unchanged columns): the upstream identity must be a
  canonical `http(s)` URL. `httpx` and `katana-pd` moved from the bare
  `github.com/projectdiscovery/...` substrings to full URLs. Eight rows added.
- `identity-policy.tsv` (new: `logical`, `policy`, `reason`): `blocked` never
  resolves from any source; `exact-name` refuses Provides substitutes.
  `metasploit-mcp` is blocked ("upstream project identity not established by
  package inventory facts": a PyPI project and differently named Metasploit
  MCP projects exist, and nothing says which one is meant). `wordlists` is
  exact-name, so `seclists` or any provider cannot stand in for it.
- `aliases.tsv` (new: `logical`, `repository`, `package`): every reviewed
  non-identical package name. A row makes that repository's lookup exact, with
  no Provides fallback. Rows: chirp→chirp-next, armitage→armitage-git,
  beef→beef-xss, dump1090→dump1090-git, fern-wifi-cracker→fern-wifi-cracker-git,
  theharvester→theharvester-git, java17-openjfx→java17-openjfx-bin (all
  oniomarchy) and social-engineer-toolkit→set (BlackArch). No `-git`/`-bin`
  suffix is ever stripped by rule.
- `dependencies.tsv` (new: `dependency`, `consumer`, `repository/package`,
  `install-reason`): powershell-bin (no assumed consumer), xorg-xhost (no
  assumed consumer), jdk17-openjdk, java17-openjfx and sleuthkit-java
  (autopsy), jdk-openjdk (ghidra), python-wxpython (wfuzz). A dependency may
  not appear in any manifest, so it can never be selected, reported as a root
  or (later) launched. It reaches a machine only as a selected package's own
  declared `Depends`, and the existing commit marks new dependencies
  `--asdeps` (`pacman.sh`, after the `-U` commit). `xorg-xhost` is never run to
  change X11 access.

The alias and dependency tables can name `oniomarchy`, which is listed in
`VAPT_FACT_ONLY_SOURCES`: its rows are validated but never consulted for
resolution. `vapt_repo_allowed` is unchanged, so a pin, required target or
transaction cannot use it.

### Identity matching

`vapt_identity_ok` used to accept a package whose URL contained the identity
as a substring, and parsed but ignored `required-target`. Now:

- the package URL and the identity are split by `vapt_url_parse`; userinfo,
  ports, queries, fragments, escapes and empty or dot path segments refuse;
- the host must be equal, and the path equal or a descendant at a `/`
  boundary (`.../katana-framework` no longer matches `.../katana`);
- an `https` identity needs `https`; an `http` identity also accepts `https`;
- a repository identity's `required-target` is `*` or one exact
  `repository/package`, and is enforced;
- a blocked identity matches nothing; Microsoft PyRIT stays native-only.

URL identity is the publisher's own metadata, not independent proof of code
provenance.

## Slice 1B: the private signed source (not started)

Planned contract, for review before any code:

- **Opt-in, per invocation.** `haseen vapt install --with-oniomarchy`; `--all`
  is not consent. New commands `haseen vapt repo-status`, `repo-enable
  oniomarchy`, `repo-disable oniomarchy`.
- **Private scope.** The stanza lives at
  `/var/lib/haseen/vapt/sources/oniomarchy.conf` and only VAPT's own
  transaction configuration includes it. `/etc/pacman.conf` is never changed;
  a host `[oniomarchy]` stanza is reported, not adopted. Importing the signing
  key still extends the shared pacman keyring, which is disclosed at approval.
- **Strict signatures.** `Required DatabaseRequired` is preserved everywhere,
  including frozen databases and recovery. The cost: no detached database
  signature, no source; a publisher outage makes the source unavailable rather
  than weaker.
- **Trust anchor.** The key is fetched over HTTPS from the fixed host only,
  must have exactly the pinned primary, and is never taken from a keyserver.
  The keyring package is discovered from the verified database, sealed,
  audited and installed through the existing sealed path. No bootstrap script
  runs. Rotation is accepted only from an authenticated keyring package signed
  by a currently accepted signer.
- **Canary.** Usable only when opted in, on x86_64, with the approved
  descriptor, a verified database signature, and an authenticated keyring
  record. States: not-selected, absent, declined, unsupported-architecture,
  unavailable, unverified, broken, usable.
- **Admission.** Last tier, after Arch. Only the exact 52 names, only through
  an item's exact name or its `aliases.tsv` row, never Provides. Roles:
  `oniomarchy-keyring` is infrastructure; java17-openjfx-bin, sleuthkit-java,
  powershell-bin, libsoup, libsoup-docs, webkit2gtk, webkit2gtk-docs and the
  thirteen `python-*` packages are dependencies; the rest are candidates that
  serve an existing item only through a reviewed mapping. A 53rd name in a
  newer database is refused until reviewed. Not `BASE_VENDOR`, no stock-hook
  authority, no full-upgrade selection.
- **Report.** `report.tsv` keeps its v1 schema; `selected_source` is
  `oniomarchy` only after a concrete resolution, and tiers record
  `oniomarchy:not-selected` and the other states. A declined source alone does
  not degrade an otherwise complete selection.
- **Removal.** `repo-disable` removes only an unchanged haseen-owned
  descriptor. Packages and keyring trust stay.

Its hermetic suites are planned as `tests/test-vapt-oniomarchy.sh`,
`tests/test-vapt-oniomarchy-trust.sh` and
`tests/test-vapt-oniomarchy-transactions.sh`.

## Rejected options

- **Adding every one of the 52 names as a root**, or a post-exploitation group
  just for powershell-bin: dependencies and infrastructure are not tools.
- **Suffix stripping** (`-git`, `-bin`) to map names: guesses. Every
  non-identical mapping is a reviewed `aliases.tsv` row.
- **Keeping substring URL identities**: a lookalike host or a sibling
  repository path satisfied them.
- **Choosing a metasploit-mcp project**: the inventory facts do not say which
  one is meant; it is blocked and reported, not guessed. No PyPI or AUR
  fallback for either AI item.
- **Appending the stanza to `/etc/pacman.conf`**, trusting an already-enabled
  host stanza, or placing the source before BlackArch or Arch: each would let
  it shadow genuine packages outside the VAPT audit.
- **Relaxing `DatabaseRequired`**, keyserver lookups, or running a bootstrap
  script.

## Tests

`tests/test-vapt-inventory.sh`, behavioural, against fixture sysroots with
logging stubs (no network, no host state):

- `--all` selects exactly the 25 groups, writes nothing, runs nothing, and
  reports the computed manifest/native union once per item; `docs/vapt.md`
  publishes that number. The original fifteen groups keep their 158 items and
  native-only injection.
- Each added group reports exactly its specified roots; `osint` and
  `passwords` gain theirs, and `seclists` stays distinct from `wordlists`.
- Dependency and infrastructure names never appear as roots; each named
  consumer is a real root.
- Unknown groups refuse; repeated groups collapse.
- A missing or malformed new group file, any dependency added as a root, a
  missing new table, and malformed alias, dependency, policy, pin and identity
  rows refuse an unrelated `--groups core` before anything runs.
- Official pins win over BlackArch homonyms; a missing pin falls through and
  is reported; `social-engineer-toolkit` is `blackarch/set` only with the
  TrustedSec identity, and a BlackArch provider cannot replace the alias.
- Rows from a fact-only source are never resolved or planned.
- URL identity: case and trailing slash normalised; descendants accepted;
  sibling prefixes, embedded hosts, subdomain tricks, scheme downgrade,
  userinfo, ports, queries, dot segments and a missing URL refused; an http
  identity accepts https. The ProjectDiscovery identities still refuse their
  Python and katana-framework homonyms. A `required-target` is enforced.
- metasploit-mcp is identity-blocked; hexstrike-ai resolves only with its
  identity; Microsoft PyRIT stays native; no provider substitutes for
  wordlists.
- A consumer's declared dependency (ghidra → jdk-openjdk) is committed with a
  dependency install reason and the consumer is explicit.

The fixture `tests/fixtures/vapt-oniomarchy/inventory.json` holds the expected
inventory: the 52 source packages with their roles, the added roots, aliases,
pins and dependencies.

## Evidence

Exercised in this tree before the slice 1A commit:

```sh
QT_QPA_PLATFORM=offscreen tests/run.sh tests/test-vapt*.sh   # 14 files, 3159/3159 checks
SHELLCHECK=$(command -v shellcheck) tools/lint.sh             # lint OK
tools/check-docs.sh                                           # check-docs OK
```

`tests/test-vapt-inventory.sh` alone is 329 checks. `tests/test-vapt-env.sh`
needed one fixture change: its "all non-COAE provisioning exact" control
selects `osint`, which now also contains recon-ng and theharvester, so the
fixture publishes and installs both.

Not exercised: any live package installation, any fetch from the oniomarchy
host, and the published signatures of its database or keyring. The
metadata.py dependency closure does not yet apply `identities.tsv` to
dependencies; that belongs with the source tier in slice 1B.
