# Plan 087: VAPT inventory and opt-in signed oniomarchy source

## Status

- **Priority**: P2
- **Effort**: L
- **Risk**: MEDIUM (slice 1A widens the inventory and tightens identity matching; slice 1B adds a signed package source and is security-sensitive)
- **Depends on**: 007
- **Category**: vapt, packages
- **Planned at**: 2026-10-07, owner request: integrate the tool categories of the oniomarchy distribution into haseen's VAPT layer without depending on Omarchy
- **State**: DONE 2026-10-12 (merged as PR #39), amended 2026-10-13 (plan 090). Every path is exercised against hermetic fixtures only: no live fetch, key or package operation.

## Goal

The VAPT layer (plan 007) provisions explicit tool groups from reviewed signed
sources and never runs a tool. This plan adds ten tool groups and a few roots
to two existing groups, from oniomarchy's category facts (slice 1A), and an
opt-in, x86_64-only, signature-required package source for the items only its
repository publishes (slice 1B). The layer still never runs a listed tool,
starts or enables a service, or executes an assessment. The desktop workflow
is plan 088.

## Facts used

Supplied by the owner (not independently authenticated):

- oniomarchy's repository publishes exactly 52 packages
  (`tests/fixtures/vapt-oniomarchy/inventory.json`, `sourcePackages`).
- Its stanza is `[oniomarchy]`, `SigLevel = Required DatabaseRequired`,
  `Server = https://pkgs.oniomarchy.com/$arch`, x86_64 only. Its key is at
  `https://pkgs.oniomarchy.com/oniomarchy.gpg`, primary fingerprint
  `0F5F9214F312B067ECBF1DF125E2C00AA6340BD0`.
- None of the twelve official SDR names (airspy, gnuradio, gqrx, hackrf,
  inspectrum, limesuite, multimon-ng, qspectrumanalyzer, rtl-sdr, rtl_433,
  soapysdr, urh), wifite, reaver, bully, cowpatty, hostapd, hcxdumptool,
  hcxtools, kismet, pixiewps, keepassxc, mat2, veracrypt, macchanger, tor,
  openssh, remmina, ghidra's `jdk-openjdk`, hexstrike-ai or metasploit-mcp is
  in that repository. Its SDR packages are chirp-next, cubicsdr,
  dump1090-git and supersdr.

Public catalogues (what was published when queried, not what a machine's sync
databases hold):

- Arch exact-name queries (`https://archlinux.org/packages/search/json/?name=NAME`):
  in `extra` the twelve SDR names, the nine wireless names, keepassxc, mat2,
  veracrypt, macchanger, tor, routersploit, remmina, xorg-xhost,
  jdk17-openjdk, jdk-openjdk and python-wxpython; in `core` openssh. No result
  for chirp, supersdr, can-utils, gophish, social-engineer-toolkit, maltego,
  hexstrike-ai, metasploit-mcp, recon-ng, theharvester, wordlists,
  java17-openjfx or sleuthkit-java.
- BlackArch (`https://blackarch.org/tools.html` and its category pages) lists
  cubicsdr, dump1090, airgeddon, fern-wifi-cracker, can-utils, gophish, the
  toolkit as `set`, maltego, armitage, beef, recon-ng and theharvester. A
  listed recipe does not prove a published signed binary.

## Slice 1A: inventory

### Groups

`VAPT_GROUPS` (`share/haseen/layers/vapt/provision.sh:12`) holds 25 groups:
`core network web passwords ad osint cloud mobile forensics api htb-cjca
htb-cpts htb-cwes htb-cwee htb-coae sdr wireless privacy anonymity automotive
social reporting ai exploitation services`. `--all` selects exactly these;
there is no default. Every group file is validated on every run, selected or
not. The original fifteen memberships are unchanged; each new file and
addition starts with the line
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

The manifests and native rows name **204 distinct tool names** (158 before);
`tests/test-vapt-inventory.sh` computes the union and checks that `--all`
reports each once. `services` installs client and support packages and never
enables a unit; `anonymity` never changes an address or starts Tor; `ai`
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
| metasploit-mcp | — | blocked | — | blocked |
| armitage | — | BlackArch | `armitage-git` (alias) | `http://www.fastandeasyhacking.com` |
| beef | — | BlackArch | `beef-xss` (alias) | `https://github.com/beefproject/beef` |
| routersploit | `extra/routersploit` | usual order | — | — |
| openssh | `core/openssh` | usual order | — | — |
| remmina | `extra/remmina` | usual order | — | — |
| recon-ng | — | BlackArch | `recon-ng` | `https://github.com/lanmaster53/recon-ng` |
| theharvester | — | BlackArch | `theharvester-git` (alias) | `https://github.com/laramies/theHarvester` |
| wordlists | — | exact name only | `wordlists` | exact-name policy |

### Source order

VAPT's order is an explicit exception to haseen's package order (owner
decision, 2026-10-13; `docs/architecture.md:93-101`): explicit pins,
BlackArch, the pinned native (pipx) adapter, enabled Chaotic-AUR, CachyOS, Arch
`core`/`extra`/`multilib`, each matched by the item's name or its reviewed
alias only. Only when no tier publishes the name does a `Provides` count, and
only for an item with a reviewed upstream identity whose URL the provider
matches, in the same tier order; then the opted-in private source
(`provision.sh:248-342`: `vapt_repo_target`, `vapt_repo_provider`,
`vapt_resolve_item`). There is no Omarchy or AUR tier.

### Tables

All in `share/haseen/layers/vapt/packages/` and required: a missing table
refuses provisioning before anything runs.

- `pins.tsv` (`logical`, `repository/package`): 29 official pins added, plus
  `social-engineer-toolkit blackarch/set`. A pin must name an inventory root
  and appear once.
- `identities.tsv`: an upstream identity is a canonical `http(s)` URL.
  `httpx` and `katana-pd` moved from bare `github.com/projectdiscovery/...`
  substrings to full URLs; eight rows added.
- `identity-policy.tsv` (`logical`, `policy`, `reason`): `blocked` never
  resolves from any source; `exact-name` refuses Provides substitutes.
  `metasploit-mcp` is blocked: a PyPI project and differently named Metasploit
  MCP projects exist, and nothing says which is meant. `wordlists` is
  exact-name, so `seclists` or a provider cannot stand in for it.
- `aliases.tsv` (`logical`, `repository`, `package`): every reviewed
  non-identical package name; a row makes that repository's lookup exact.
  Rows: chirp→chirp-next, armitage→armitage-git, beef→beef-xss,
  dump1090→dump1090-git, fern-wifi-cracker→fern-wifi-cracker-git,
  theharvester→theharvester-git, java17-openjfx→java17-openjfx-bin (all
  oniomarchy) and social-engineer-toolkit→set (BlackArch). No `-git`/`-bin`
  suffix is stripped by rule.
- `dependencies.tsv` (`dependency`, `consumer`, `repository/package`,
  `install-reason`): powershell-bin and xorg-xhost (no assumed consumer),
  jdk17-openjdk, java17-openjfx and sleuthkit-java (autopsy), jdk-openjdk
  (ghidra), python-wxpython (wfuzz). A dependency may not appear in any
  manifest, so it is never selected, reported as a root or launched. It
  arrives only as a selected package's declared `Depends` and is recorded as
  a dependency. `xorg-xhost` is never run.

Pins and required targets may not name the private source.

### Identity matching

`vapt_identity_ok` (`provision.sh:220`) used to accept a URL containing the
identity as a substring and ignored `required-target`. Now:

- the package URL and the identity are split by `vapt_url_parse`
  (`provision.sh:61`); userinfo, ports, queries, fragments, escapes and empty
  or dot path segments refuse;
- the host must be equal and the path equal or a descendant at a `/`
  boundary (`.../katana-framework` no longer matches `.../katana`);
- an `https` identity needs `https`; an `http` identity also accepts `https`;
- a `required-target` is `*` or one exact `repository/package`, enforced;
- a blocked identity matches nothing; Microsoft PyRIT stays native-only.

URL identity is the publisher's own metadata, not proof of code provenance.

## Slice 1B: the private signed source

- **Opt-in, per operation.** `haseen vapt install --with-oniomarchy` (also
  `vapt_select`); `--all` is not consent and nothing stores the choice.
  `haseen vapt repo-status [--json]`, `repo-enable oniomarchy` and
  `repo-disable oniomarchy` have `--help` and a pure `--dry-run`; mutations
  refuse a fixture sysroot.
- **Private scope.** `share/haseen/layers/vapt/oniomarchy.sh` writes the
  exact stanza to `/var/lib/haseen/vapt/sources/oniomarchy.conf` (the
  descriptor is also the approval record). `metadata.py:read_config`
  (`share/haseen/layers/vapt/metadata.py:422`) takes any host `[oniomarchy]`
  section out of VAPT's view and adds the private stanza last, only with
  `--with-oniomarchy`, which the shell sets only when the source is usable for
  this operation or during read-only status. It is rendered with
  `Usage = Sync Search Install` (`metadata.py:48`). No recovery record names
  the source.
- **One mirror and policy rule.** `repository_mirror_safe` and
  `repository_policy_safe` (`metadata.py:721`, `:740`) serve snapshot,
  rendering, closure and the frozen configuration: the source only at
  `https://pkgs.oniomarchy.com/$arch` (or `/x86_64`), exactly `Required
  DatabaseRequired`; every other source keeps the HTTPS and Omarchy-host
  rules. Every other repository keeps the host's SigLevel, raised to at least
  `Required DatabaseOptional` (plan 090).
- **Trust anchor.** The key comes from the fixed URL (`curl --max-redirs 0
  --proto =https`) and must have exactly one primary, equal to
  `files/oniomarchy-signers.txt`, not revoked or expired (`key_primary`,
  `metadata.py:4217`). Database and keyring signatures go through
  `verify_status` (`:3853`). Root copies the fetched database into the run's
  root stage before verification.
- **Keyring audit and root state.** The keyring archive the database names is
  sealed against the database digest and audited by `oniomarchy-keyring`
  (`oniomarchy_keyring_audit`, `metadata.py:4451`: identity, exact layout,
  dependencies, population-only scriptlet, then `audit_archives` with a
  per-package population exemption). Root state under
  `/var/lib/haseen/vapt/sources/`: `oniomarchy.authority` (keyring version,
  digest, signer, accepted and revoked primaries, observed signers, digests of
  the archive's key-file members), `oniomarchy-keyring.pkg` (the audited
  archive), `sync/oniomarchy.db{,.sig}` and `oniomarchy.database` (which bytes
  were verified, and by whom). The authority binds to the stored archive, not
  to an installed package or files under `/usr/share/pacman/keyrings/`.
- **Population.** haseen never installs the keyring package and never runs
  `pacman-key --populate oniomarchy`: populate lsigns every trusted ID and
  imports the trusted file as ownertrust, so a pin-signed keyring could
  disable an unrelated key (`KEY:128:`) or mark Arch masters never-trust
  (`KEY:3:`), and installed list files would be applied again by any later
  manual populate. Instead (`vapt_oniomarchy_bootstrap_steps`,
  `oniomarchy.sh:179`): the newly accepted primaries (`trusted − revoked`,
  minus those already accepted) are exported from the archive's own
  `oniomarchy.gpg` (`keyring-gpg`), the export must hold exactly those
  primaries (`key-primaries`), and each is added with `pacman-key --add` and
  `--lsign-key`. Newly revoked keys are deleted with `pacman-key --delete`
  only when present in a strictly parsed `gpg --with-colons --list-keys`
  listing of pacman's keyring (`keyring_listing`, `metadata.py:4580`; GPGDir
  from `pacman_gpgdir`, `:4595`): every line a known colon record, every
  primary with its `fpr` record, an empty listing counts as no answer. The
  listing is read and parsed before any `pacman-key` call
  (`oniomarchy.sh:269`, first `--add` at `:279`), so a failed or
  uninterpretable listing fails the approval with no key added or deleted; a
  failed deletion fails it before the archive and authority are written, and
  the retry repeats it. Absence is concluded only from a parsed listing
  without the key. An approval refuses while an `oniomarchy-keyring` package
  or an `oniomarchy*` file from an earlier install remains. The ownertrust
  column is ignored, never imported (refusing it would also refuse the
  conventional `:4:`).
- **Rotation.** Accepted only from a keyring signed by a currently accepted,
  non-revoked primary; revocations never shrink, the version never goes down,
  the first keyring must trust the pin. Invariant: `revoked ⊆ previous
  revoked ∪ {pin} ∪ observed-before`, where observed-before is every signer of
  this source's database or keyring archive at an earlier approval or refresh
  (the authority's `observed` line, never derived from a declared list). This
  approval's own signers become observed only for later approvals, so a
  signer cannot revoke itself in the archive that introduces it; a key merely
  listed as trusted is admitted but never revocable. A legitimate rotation
  works: once OLD has signed something, an archive signed by OLD may revoke
  OLD and trust ROT, and ROT becomes revocable after it has signed. A record
  without an `observed` line reads as a mismatch (manual review). Rotations
  are applied only by an approval (`repo-enable`, or the approval an opted-in
  run asks for when the source is not approved). A refresh of an approved
  source never changes trust: an unverifiable database gets a reason naming
  `repo-enable`, and a published keyring whose digest differs from the
  authority adds a note naming it while the source stays usable. A database
  already signed by an unaccepted key stays refused for manual review.
- **Canary.** `oniomarchy_canary` (`metadata.py:4414`):
  unsupported-architecture, broken (host stanza, changed or redirected
  descriptor), absent, unverified (authority mismatch, cached database or
  signature not the verified bytes, no keyring record), usable. An opted-in
  run also refreshes and re-verifies the database (unavailable when
  unreachable; declined when the user refuses).
- **Admission.** `packages/oniomarchy.tsv` holds 52 rows, enforced by
  `VAPT_ONIOMARCHY_ADMITTED` (`provision.sh:16`) and `ONIOMARCHY_ADMITTED`
  (`metadata.py:53`). The resolver tries the source after Arch, by exact name
  or `aliases.tsv` only, refuses a package or logical name any other
  configured repository with readable, safe metadata publishes (usable this
  run or not; the set `closure` uses), and records
  `oniomarchy:not-selected|declined|unavailable|unsupported-architecture|identity-rejected`.
  When it wins while an earlier source was unreadable, the reason adds
  "earlier source unavailable this run (…); not proof this is the inventory
  tool". `closure` (`metadata.py:996`) admits a candidate only as the
  requested target (or an installed package), a non-target row only in the
  `dependency` role, and a `dependency` row named in `dependencies.tsv` only
  in its recorded consumer's closure (`*` for any). The source satisfies a
  dependency only by exact name or through a reviewed alias the package's own
  Provides backs, never wins over an earlier repository record satisfying the
  same dependency (by name or versioned Provides), refuses replaces and
  homonyms, and applies the inventory identities to every planned package;
  `audit_archives` re-checks the roles. A declared conflict is left to
  `reject_removals`; unmapped candidates are never installed; identity
  mismatches on planned upgrades of installed same-name packages are
  warnings. The source is not in `BASE_VENDOR`; the generic Omarchy substring
  refusals still match `oniomarchy` but label it "oniomarchy self-reference
  requires review".
- **Private packages and pacman's trust configuration.** A private-source
  package may place nothing but directory headers of a protected directory or
  its parents in the keyrings directory, the configured GPGDir, the rest of
  `/etc/pacman.d` or `/etc/pacman.conf*`, judged where each member lands in
  both transaction views, through links, case-insensitively
  (`metadata.py:1380-1413`; plan 090). The generic audit protects only the
  base-vendor anchors (`VENDOR_ANCHORS`, `metadata.py:3566`). The source's own
  keyring package is audited separately and never installed.
- **Transactions.** The verified cached database is copied into the private
  DBPath of an opted-in install. The source never joins a full upgrade (its
  `Usage` excludes Upgrade; its prelude runs after BlackArch preparation and
  recovery): `vapt_pacman_upgrade` refuses a set private scope, and recovery
  records stay the generic and blackarch-staged ones.
- **Report.** v1 schema kept, with `# oniomarchy` and `# dependency`
  annotations. `report-merge` keeps the earlier row of an item installed from
  the source when a later run could not use it, appending "source … this run
  (oniomarchy:STATE); installed package retained"; an identity-rejected or
  resolved row replaces it (`retained_private_row`, `metadata.py:4140`).
- **Status.** A private target whose source is not approved or not verified
  is reported "oniomarchy source disabled or unverified … provenance
  unverifiable" (degraded), distinct from drift. A recorded dependency that
  is no longer installed degrades status; one the user marked explicit only
  warns (`layer.sh:95-104`). Retained packages from the source are proven
  read-only by the cached database whose bytes were verified at the last
  refresh (`retained_private_records`, `metadata.py:971`), with or without
  opt-in and after `repo-disable`; that cache never supplies a candidate.
- **Installer.** `vapt` sets `LAYER_PICKABLE=false` (`layer.sh:8`): the
  install picker never offers it and drops it from a saved choice with a
  warning. `--vapt-groups` (alone or with `--layers vapt`) is the only
  installer route; `--pick --vapt-groups` is refused before the tree or any
  layer.
- **Shell activation.** The layer seeds only the owned link
  `~/.config/haseen/vapt/shell.sh` and never edits `~/.bashrc` or
  `~/.zshrc`. An rc whose own `.` or `source` command names the link (shell
  words; `~`, `$HOME`, `$XDG_CONFIG_HOME` expanded; `rc_sources`,
  `metadata.py:4102`) is reused. Otherwise apply and status print the line
  `[ -r "$HOME/.config/haseen/vapt/shell.sh" ] && . "$HOME/.config/haseen/vapt/shell.sh"`
  (with the absolute path), reported, not degraded.
- **Install reasons.** `pacman -U` keeps an upgraded package's reason and
  makes what it newly installs explicit. The commit records the new
  dependencies in `/var/lib/haseen/vapt/reasons-pending` before `-U` and marks
  them `-D --asdeps` after; the next VAPT transaction finishes a record it
  finds (`pacman.sh:348` `vapt_reasons_repair`; plan 090).

Choices where the design was silent: the descriptor doubles as the approval
record; a host `[oniomarchy]` section makes the private source `broken`;
dry-run plans from evidence verified at the last refresh and says it did not
re-verify; disable keeps the authority record, the stored keyring archive,
the cache and the keys already added to the shared keyring. Without the
descriptor this state authorises nothing; it serves only the read-only proof
of packages already installed from the source.

## Rejected options

- **`Usage = Search Install` (no Sync)**, so pacman never refreshes the
  source behind the pinned verifier: rejected for the design's `Sync Search
  Install`; every private refresh is re-verified against the accepted
  primaries instead.
- **Appending a source line to `~/.bashrc`/`~/.zshrc`** (the layer's first
  implementation): it edited a user file after seeding, against
  `docs/architecture.md` §3.
- **`pacman-key --populate oniomarchy`, or installing the keyring package**
  (even with `--noscriptlet`): see Population.
- **Falling back to a stale cached database when the host is unreachable**:
  the source is reported unavailable instead.
- **Using a host `[oniomarchy]` section beside the private one**: two
  definitions of one repository.
- **Every one of the 52 names as a root**, or a post-exploitation group just
  for powershell-bin: dependencies and infrastructure are not tools.
- **Suffix stripping** (`-git`, `-bin`): guesses. Every non-identical mapping
  is a reviewed `aliases.tsv` row.
- **Substring URL identities**: a lookalike host or a sibling path satisfied
  them.
- **Choosing a metasploit-mcp project**: the facts do not say which is meant.
  No PyPI or AUR fallback for either AI item.
- **Appending the stanza to `/etc/pacman.conf`**, trusting an already-enabled
  host stanza, or placing the source before BlackArch or Arch: each would let
  it shadow genuine packages outside the VAPT audit.
- **Relaxing `DatabaseRequired`**, keyserver lookups, or running a bootstrap
  script.
The rejected options of the 2026-10-13 amendment are in plan 090.

## Tests

Fixture sysroots with logging stubs; `curl`, `gpg`, `pacman-key`, `pacman`
and `sudo` are stubs; fixtures in `tests/fixtures/vapt-oniomarchy/`.

- `tests/test-vapt-inventory.sh`: `--all` selects exactly the 25 groups,
  writes and runs nothing, reports the computed union once per item, and
  `docs/vapt.md` publishes that number; the original fifteen keep 158 items;
  each added group reports its roots; dependency names never appear as roots;
  unknown groups refuse; malformed group files and table rows refuse an
  unrelated `--groups core`; pins win over BlackArch homonyms; without
  `--with-oniomarchy` nothing from the private source or Chaotic-AUR's
  chirp-next is planned; URL identity cases (normalisation, descendants,
  sibling prefixes, embedded hosts, subdomains, scheme downgrade, userinfo,
  ports, queries, dot segments); metasploit-mcp blocked; ghidra's
  jdk-openjdk committed as a dependency.
- `tests/test-vapt-oniomarchy.sh`: opt-in and `--all`, exact and alias
  resolution as the last tier, architectures, every canary state from
  `source-states.json`, shadowing and Provides cases, a 53rd name, the
  mirror/policy validator.
- `tests/test-vapt-oniomarchy-trust.sh`: the approval sequence and order,
  refresh, disable, key and database-signature failures, keyring signature,
  digest and hostile layouts, rotation cases from `trust/rotation.json`,
  dry-run text, sysroot refusal.
- `tests/test-vapt-oniomarchy-transactions.sh`: rendered and frozen policy,
  closure cases, an opted-in commit, a full upgrade that never carries the
  source, the recovery protocol, and private payloads in pacman's trust
  configuration.
- Adversarial suites `tests/test-vapt-oniomarchy-{consent,admission,trust,report}-adversarial.sh`,
  `-abuse.sh` and `-abuse-boundaries.sh` (helper
  `tests/fixtures/vapt-onio-adversarial.sh`): consumer enforcement, the
  earlier-source-unavailable reason, self-reference labels, the
  list-then-revoke and self-revocation attacks refused with no `pacman-key`
  call, hostile ownertrust columns admitted without populate or ownertrust
  import, failing, human-format, empty and malformed listings, a failing
  `--delete`, retained rows after a run without the source.
- `tests/test-vapt.sh`: the picker never offers `vapt`; a saved `vapt` choice
  is dropped with a reason; `--pick --vapt-groups` is refused.
- `tests/test-vapt-env.sh`: no rc is written or invented; an rc that sources
  the link (absolute or `$HOME`) is reused; a comment, an echo or another
  file's source is not.

## Evidence

- Final local run before the merge: `QT_QPA_PLATFORM=offscreen tests/run.sh
  tests/test-vapt*.sh tests/test-install-picker.sh`, 24 files, 4605/4605;
  `tools/lint.sh` and `tools/check-docs.sh` OK. PR #39 then merged on
  2026-10-12 through protected `main`, whose required CI checks are lint,
  test, docs, secrets and nix (`AGENTS.md`). The amendment's evidence is in
  plan 090.
- Published bytes observed on 2026-10-08 (fetched over HTTPS from the public
  repository by hand, not by haseen's code):
  `oniomarchy-keyring-20260906-1-any.pkg.tar.zst`, with a `.sig` beside it.
  `usr/share/pacman/keyrings/oniomarchy-trusted` holds exactly
  `0F5F9214F312B067ECBF1DF125E2C00AA6340BD0:4:` (the pin);
  `oniomarchy-revoked` is empty; `.INSTALL` calls only `pacman-key
  --populate oniomarchy`. An empty revoked list is admitted by the rotation
  invariant, and a first approval accepts only the pin, which the anchor
  already lsigns; the scriptlet never runs. Its signature was not verified
  and haseen's audit was not run on it.

Not verified:

- any live package installation, any fetch by haseen's code from the
  oniomarchy host, and the real key, database and keyring signatures;
- pacman's own handling of `Usage` and `DatabaseRequired` on a real system;
- a real publisher key rotation (fixture rotations only);
- the real database's dependency graph against the consumer, candidate-role
  and earlier-provider rules (a package that breaks one is refused);
- the activation line in a real interactive bash/zsh session;
- the gum picker UI (only the plain `select` path is driven);
- real `pacman-key --add`/`--lsign-key`/`--delete`, real `gpg --with-colons
  --list-keys` of pacman's keyring and `gpg --export` (stubbed; any listing
  that is not the strict colon format aborts the approval);
- the BlackArch keyring against its real `blackarch-trusted` and
  `blackarch-revoked`. It still runs `pacman-key --populate blackarch`; the
  audit admits only reviewed signers at no more than marginal ownertrust and
  revocations of reviewed signers or v4 primaries of its own `blackarch.gpg`
  (`metadata.py:4715`), so lists beyond that refuse preparation.

Accepted limits:

- Adding a key expands the **shared** pacman keyring. pacman does not scope
  keys per repository, so an accepted primary (including one only listed as
  trusted) is valid machine-wide, and a key dropped from the trusted list
  without being revoked stays locally signed. Disabling the descriptor keeps
  that trust, on purpose.
- The private-package rule does not cover pacman's DBPath (`/var/lib/pacman`)
  or an `Include` target outside `/etc/pacman.d`.
- The trust step stages `accepted.gpg`/`signer.gpg` as the invoking user and
  root reads them afterwards, so a process running as that same user could
  replace them in between. The layer lock and the caller's identity are the
  boundary.
- A 64-hex v5/v6 primary fingerprint in pacman's keyring is refused: fails
  closed, at the cost of liveness if such a key appears.
