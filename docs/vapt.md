# Optional VAPT workstation provisioning

The `vapt` layer provisions the owner's waydots tool inventory, plus tool
groups taken from oniomarchy's categories (plan 087), on **Arch, CachyOS and
an Omarchy host**. It does not run assessments, launch security tools, start
their backends, change firewall rules or enable services. It needs no
desktop, Omarchy, Chaotic-AUR or AUR layer, and selects no tools by default.
An Omarchy host is supported, not refused (owner, 2026-10-31): haseen replaces
Omarchy (ADR 0001), `share/haseen/lib/preflight.sh` already treats such a host
as supported, and Omarchy 4 ships an Arch mirrorlist
(`https://stable-mirror.omarchy.org/$repo/os/$arch`) that is an HTTPS mirror
of Arch's own repositories. Omarchy's packages and its own `[omarchy]`
repository stay refused either way.

Runtime prerequisites are `python3` with its standard library, `pacman`,
`vercmp`, `curl`, `gpg` and libalpm's own `libarchive.so.13`, through which
archives are read (`ctypes`); `bsdtar` is never used at runtime. Precheck
reports a missing prerequisite before changing the tree. A minimal Arch
installation may need Python installed first; there is no unchecked
interpreter bootstrap. For tests, several VAPT suites skip unless a host
`bsdtar` is installed, and `tools/lint.sh` needs `shellcheck`.

## Select and preview

```sh
# Install only the haseen tree and the selected VAPT environment:
./install.sh --layers vapt --vapt-groups core,web --dry-run

# Add VAPT to an existing haseen installation:
haseen vapt install --groups ad,mobile --dry-run
haseen vapt install --all --dry-run

# Equivalent layer interface:
haseen layer apply vapt --dry-run -- --groups htb-coae
```

Remove `--dry-run` only when deliberately provisioning the target workstation.
`--yes` accepts installer confirmations. `--vapt-groups all` selects all
groups, otherwise pass a comma-separated list. Without `--layers` the
installer's defaults still apply and VAPT is appended; `--layers vapt` is a
standalone, Omarchy-independent tooling installation. The install picker
never offers `vapt` (`LAYER_PICKABLE=false`) and drops it from a saved
choice, because the layer refuses to run without explicit groups.

A tooling-only installation skips sidecar compilation, migrations and
unrelated hardware quirks. Other selected layers behave as usual.

There are 25 groups. The owner's fifteen are `core`, `network`, `web`,
`passwords`, `ad`, `osint`, `cloud`, `mobile`, `forensics`, `api`,
`htb-cjca`, `htb-cpts`, `htb-cwes`, `htb-cwee` and `htb-coae`, unchanged in
`share/haseen/layers/vapt/packages/security/`. Plan 087 adds ten more and a
few roots to two existing ones:

| Group | Tools |
|---|---|
| `sdr` | airspy, chirp, cubicsdr, dump1090, gnuradio, gqrx, hackrf, inspectrum, limesuite, multimon-ng, qspectrumanalyzer, rtl-sdr, rtl_433, soapysdr, supersdr, urh |
| `wireless` | airgeddon, bully, cowpatty, fern-wifi-cracker, hcxdumptool, hcxtools, hostapd, kismet, pixiewps, reaver, wifite |
| `privacy` | keepassxc, mat2, veracrypt |
| `anonymity` | macchanger, tor (no address is changed and Tor is not started) |
| `automotive` | can-utils |
| `social` | gophish, social-engineer-toolkit |
| `reporting` | maltego |
| `ai` | hexstrike-ai, metasploit-mcp (inventory only; nothing is registered with an AI client and no MCP server starts) |
| `exploitation` | armitage, beef, routersploit |
| `services` | openssh, remmina (client and support packages; no unit is enabled or started) |
| `osint` (added) | recon-ng, theharvester |
| `passwords` (added) | wordlists, a data collection distinct from seclists |

With the native adapter entries the manifests represent **204 distinct tool
names**. Overlapping selections resolve each tool once and keep its
selected-group memberships. Every group file is validated on every run,
selected or not.

## Sources and identity

The layer does **not** use the general installer's AUR fallback. Its source
order keeps the waydots security policy and is an explicit exception to
haseen's general package order (owner decision, 2026-10-13):

1. Explicit repository pins (`packages/pins.tsv`): `extra` for `nmap`,
   `radare2`, `jadx`, `binwalk`, `dotnet-sdk`, the twelve SDR and nine
   wireless tools Arch publishes, `keepassxc`, `mat2`, `veracrypt`,
   `macchanger`, `tor`, `routersploit` and `remmina`; `core/openssh`;
   `blackarch/set` for the Social-Engineer Toolkit.
2. BlackArch.
3. The pinned native adapter, when one exists.
4. Already-enabled Chaotic-AUR binary packages.
5. Enabled CachyOS repositories.
6. Arch `core`, `extra` and `multilib`.

Every tier matches only the tool's own name (in BlackArch, the name
`security/native.tsv` records for a native adapter's tool) or the reviewed
alias for that repository, and the package must satisfy any upstream
identity. A `Provides` line counts only for an item with a reviewed upstream
identity, only when no tier publishes the name (Arch's included), and only
when the provider's URL matches that identity. So BlackArch's end-of-life
`nodejs-lts-gallium`, which provides `nodejs`, never displaces Arch's
`nodejs`, and Chaotic-AUR's `chirp-next` never stands in for `chirp`. The
opt-in oniomarchy source comes last (below).

An unavailable pin is reported before the remaining tiers are tried. AUR
builds, arbitrary repositories and Omarchy packages or providers are excluded
before source selection, so a forbidden provider cannot shadow a genuine
package from a later tier. An unsafe or unverifiable item is reported and
skipped, never handed to the general resolver.

A source's mirror must be HTTPS. A source that publishes its *own* packages —
BlackArch, Chaotic-AUR, CachyOS and the private source — is never mirrored by
an Omarchy host, and the private source's host mirrors nothing else. Arch's
own `core`, `extra` and `multilib` are the exception (owner, 2026-10-31): they
accept any HTTPS mirror, because their database and their packages are Arch's
and every package still has to satisfy the Arch keyring pacman verifies
against (`metadata.py` `ARCH_BASE`). A mirror is transport, not provenance.
Omarchy's own repository is not a usable source at all: it is absent from
`ALLOWED`, so it never reaches the mirror rule.

### Package audit

The dedicated pacman path checks dependency closure, scriptlets and relevant
hooks. The audit distinguishes current files, incoming payloads and each
package's pre/post scriptlet phases. A helper changed by another package
must be safe in both snapshots; transaction-wide hooks use current and final
snapshots. Enabled systemd-unit links are refused even without an install
script. Replacement or conflict removals, missing old file inventories,
opaque helpers and relevant backup/NoExtract/NoUpgrade ambiguities require
manual review and are reported unsupported; NoUpgrade-protected dropped hooks
are still audited.

Hook matching follows libalpm's ordered targets and transaction-wide file
events, including ordered `NoExtract` exceptions. Hook grammar is validated
before basename overrides can mask lower-priority hooks; inline hashes are
literal values, not comments. Compressed `.MTREE` inventories are read
without filesystem lookups and must agree with the archive; malformed or
inconsistent inventories are refused. Hook `Exec` is a direct process
invocation from `/`, not a shell builtin or PATH search; builtin-shadowing
shell functions are refused. Delegated shell helpers accept no interpreter
options, or only `-e`/`-u` combinations that keep the inspected file body
executing. Archive member names are literal operands, never archiver
options. Opaque trailing-comment syntax may require manual review.

Stock maintenance has a separate, narrow policy in
`share/haseen/layers/vapt/files/stock-hooks.tsv`: canonical hook paths, exact
arguments and reviewed script digests. Native helpers are accepted only from
authenticated Arch/CachyOS artifacts, not from a matching name, URL, version
or self-reported installed MTREE. Incoming maintenance and runtime artifacts
must match the reviewed repository checksum and a base-vendor package signer.
Retained helper bytes and symlink targets must equal an authenticated
reference artifact and have exactly one installed owner. Proof prefers the
installed version's record from the pre-refresh sync-DB snapshot or the
reviewed DB; incoming payloads stay bound to the reviewed DB; cached or
downloaded references must match that record and the vendor signature.
Missing or differing proof requires manual review: haseen never executes an
unproven helper to identify it, and its full-upgrade path cannot always
repair missing proof.

Read-only ELF and loader-selector inspection checks current and future helper
dependencies, interpreter and link paths, loader-cache/hwcaps candidates, NSS
services and gconv modules. Every reachable native candidate must be
base-proven; unknown formats or search rules are refused. Literal absolute
`DT_RUNPATH` directories and exact `$ORIGIN` are supported; a nonempty
`DT_RPATH` is refused. A new, unrelated library is not rejected for being a
shared object. Module-loading maintenance, daemon reloads, tmpfiles,
kernel/initramfs steps and opaque scriptlets stay unsupported.

Plans bind repository package filenames, not cache-dependent locations.
Downloads are sealed into a root-owned, nonreplaceable archive/signature set
before auditing, and every archive's identity and dependency, provider,
conflict and replacement metadata must match the reviewed plan. Each commit
installs those exact artifacts in one local `pacman -U` transaction, with no
live repository or provider re-resolution. A newly installed target is
explicit and its new dependencies are marked as dependencies; an upgraded
package, the target included, keeps its install reason. The new dependencies
are recorded in root state (`/var/lib/haseen/vapt/reasons-pending`) before
the commit and the record is cleared once they are marked. A bookkeeping
failure after installation is a reported mutation failure; the next VAPT
transaction, even one whose target is already installed, marks the recorded
packages still installed. Sealed files are readable, not confidential.

Package metadata, hook bodies, delegated helpers and MTREE input come from one
immutable libarchive snapshot with exact member-name lookup. Shell brace, glob
and tilde expansions are refused where they could change the inspected
command. Scriptlet and helper parsing uses LF line endings and ASCII shell
blanks; ambiguous control characters and other whitespace require manual
review. Retained helper bytes are read without newline rewriting. Every
non-exempt install script needs a proven shell in both transaction snapshots.

Hardlinks are accepted only as zero-body aliases of an earlier ordinary
regular payload in the same archive, with matching mode and ownership, no
extended attributes, no skip/backup ambiguity and plain destination parents
in both views. Package metadata members are not payload targets. Other
hardlink effects require manual review.

The root Python interpreter supports only the stock startup layout. Active
`._pth`, `pyvenv.cfg`, build selectors and alternative versioned prefix
landmarks refuse in both transaction views, even from an authenticated base
package; library-search overrides require manual review. The selected
version's stdlib prefix and `lib-dynload` must be physical directories and
its optional stdlib zip a regular file. Import-relevant links must resolve
inside that stdlib and outside its excluded `site-packages`; outward
redirects require manual review. Links inside `site-packages` are ordinary
package data, because that tree is outside the isolated root import path.

New directories on root import, loader, conversion, PAM/sudo, hook or
protected program/policy paths must keep root-only write authority. All
explicit creators, base packages included, are checked together at the
physical future path: root UID/GID, no group/other write, no extended
attributes. Implicit parents rely on the pinned root `022` umask, and the
nearest existing physical ancestor must have no default ACL. This covers
aliased namespace roots, their descendants and future empty stdlib version
directories. Existing directories keep their baseline, because libalpm does
not re-permission them, except a hand-over (an upgraded package drops a
directory another package ships a header for), which is checked as new.
Unrelated package data and `site-packages` get no blanket directory policy.
Removed paths are authenticated only when every package that owned them is a
base-authenticated plan row. A transaction that would remove the root
`/usr/bin/python3` used by post-commit steps is refused.

Every VAPT-owned privileged step uses an absolute environment launcher,
`PATH=/usr/bin` and `LC_ALL=C`, with loader and conversion overrides removed
(`LD_PRELOAD`, `LD_LIBRARY_PATH`, `LD_AUDIT`, `GLIBC_TUNABLES`, `LD_PROFILE`,
`LD_PROFILE_OUTPUT`, `GCONV_PATH`, `LOCPATH`). The inner launcher also
removes `PYTHONEXECUTABLE`, `__PYVENV_LAUNCHER__`, `BASH_ENV`, `ENV`,
`SHELLOPTS` and `PS4` after sudo/PAM environment construction: isolated
Python flags do not disable those, and noninteractive shells read their
startup file or trace options before the helper. The privilege gateway
resolves commands through the same PATH. `metadata.py`, the workflow
helpers and the install precheck run Python with `-I`, so the working
directory, `PYTHON*` variables and user site-packages cannot replace the
standard library. Neither the system nor the user's locale
changes. The layer runner's applied-marker write and the invoking user's
environment are outside this guarantee; root provisioning executables,
root-admin authentication configuration and vendor keyrings stay trust
anchors. This audit is not whole-machine attestation.

The running metadata auditor, its stock-hook and signer policies, and the
Arch/CachyOS vendor keyrings and revocation records are protected in the
current and future transaction views, including link targets and parent
redirects; the stock-hook policy guard follows the physical module parent
the auditor actually reads. Incoming changes or removals there require
authenticated base-repository provenance. The non-base identical-entry
exception also keeps file permissions and file/link ownership and refuses
incoming extended attributes. Other keyrings are ordinary package data,
except for the private source (below).

That identical-entry exception also needs a confined root-produced authority
record, because retained access/security attributes and a regular file's
parent default ACL can change its writer set when extraction recreates the
inode. Only ordinary `user.*` attributes are accepted. Production visibility
requires root with effective `CAP_SYS_ADMIN`; limited visibility, missing or
unsafe records, missing rows and ambiguous attributes require manual review.
The user-side audit rechecks visible attributes, so a stale positive record
cannot excuse a later visible ACL change. Archive, ELF and signature parsing
stay unprivileged; the root producer reads only retained filesystem metadata.
Fixture visibility cannot authorise live mutation.

Post-commit privilege steps also guard PAM includes, modules and path
arguments, sudo plugins, loader-environment selectors and their native
dependencies; unauthenticated incoming changes or removals cannot enter that
graph. Every present system and vendor PAM service file is checked without
assuming precedence. Nonliteral paths, relative `pam_exec` commands,
unsupported PAM forms and loader overrides require manual review; unsupported
sudoers includes, plugin source/backend arguments, nondefault plugin
directories and PAM-service overrides refuse. A root-produced, readable
record supplies sudoers group-plugin paths; missing or replaceable records,
or ancestry not owned by root, refuse the audit.

Public mutating VAPT entrypoints refuse a nonempty `HASEEN_SYSROOT` before
any change, so fixture evidence cannot authorise live package, key or
configuration operations. Dry-run and offline status remain available.

### Identities, aliases and dependencies

`httpx` and `katana-pd` mean the ProjectDiscovery tools, not Python HTTPX or
katana-framework. BlackArch's `pyrit` is the WPA cracker; COAE instead gets
**Microsoft PyRIT**, pinned to `pyrit==1.1.0`, and the BlackArch homonym
cannot satisfy it.

Upstream identities (`packages/identities.tsv`) are canonical `http(s)` URLs.
A package matches when its URL has the same host and the identity's path or a
descendant at a `/` boundary; case and a trailing slash do not matter. URLs
with userinfo, a port, a query, a fragment, escapes or dot segments never
match, an `https` identity refuses `http`, and a `required-target` other than
`*` must be the exact `repository/package`. This is the publisher's own
metadata, not proof of where the code came from.

Reviewed package names that differ from the tool's are in
`packages/aliases.tsv` (the toolkit is BlackArch's `set`). An alias makes
that repository's lookup exact; `-git`/`-bin` suffixes are never stripped by
rule. `packages/identity-policy.tsv` blocks `metasploit-mcp`, because the
inventory does not say which of several similarly named projects it means;
it is always reported unavailable. `wordlists` is exact-name only, so
`seclists` or a provider cannot stand in for it. `hexstrike-ai` has no
reviewed source and stays unavailable unless a package with its upstream
identity appears. Neither AI item falls back to PyPI or the AUR.

Dependency-only packages (`packages/dependencies.tsv`) are never tool roots:
`powershell-bin` and `xorg-xhost` with no assumed consumer, `jdk17-openjdk`,
`java17-openjfx` and `sleuthkit-java` for autopsy, `jdk-openjdk` for ghidra
and `python-wxpython` for wfuzz. Adding one to a group manifest refuses
provisioning. They arrive only as a selected package's declared dependencies
and are recorded as dependencies; `xorg-xhost` is never run. The consumer
column is enforced for the private source's rows (`java17-openjfx-bin` and
`sleuthkit-java` only in autopsy's closure); for Arch rows it documents and
enforces nothing.

The eight original native pins:

| Logical tool | Native fallback |
|---|---|
| impacket | `impacket==0.12.0` |
| netexec | NetExec Git commit `c7dc286ba65daf10402cdc470e531b84e6d3d911` |
| frida-tools | `frida-tools==13.7.1` |
| objection | `objection==1.11.0` |
| sherlock | `sherlock-project==0.16.0` |
| mitmproxy | `mitmproxy==12.2.3` |
| sigma-cli | `sigma-cli==3.1.0` |
| fickling | `fickling==0.1.12` |

The source's impacket probe is distro-specific (`impacket-smbserver`); the
pinned PyPI adapter checks the upstream `smbserver.py` executable path
without running it. Pipx installations live in the dedicated
`$XDG_DATA_HOME/haseen/vapt/pipx` store (default
`~/.local/share/haseen/vapt/pipx`) and never overwrite personal pipx
environments; `python-pipx` is installed only with a selected native
adapter. Satisfaction is checked through distribution, version, source-commit
metadata and executable-path presence, **never by executing a security
tool**.

### BlackArch trust

A real run can offer to prepare BlackArch. haseen never executes `strap.sh`:
it discovers the keyring artifact and checksum from repository metadata,
seals the archive and signature, verifies the pinned primary-key identity
(`files/blackarch-signers.txt`, from
[BlackArch's bootstrap source](https://blackarch.org/strap.sh)) and installs
the checked keyring from that sealed set under a repository-free
configuration. Existing repository configuration is preserved. A newly
prepared repository is staged privately for review; its bounded stanza is
appended to `/etc/pacman.conf` only after the reviewed full upgrade commits. A
rejected review leaves the global configuration unchanged and can be
retried; the keyring package and its populated trust may remain installed.

Package signatures stay required. VAPT's transaction configurations keep
each repository's own SigLevel as pacman reads it (Package and Database
halves, repository lines over the global one) and only raise it to VAPT's
minimum, `Required DatabaseOptional`; a host's `DatabaseRequired`, global or
per repository, is kept, and an unknown value refuses the configuration.
Database discovery is not described as authenticated.

The keyring's reviewed population-only scriptlet is suppressed for that
package alone and haseen runs the population itself; changed or unknown
scriptlets are refused. That population, `pacman-key --populate blackarch`,
lsigns every key `blackarch-trusted` lists, imports that file's ownertrust and
disables every key `blackarch-revoked` lists, in the shared keyring. Before
any trust change the audit therefore admits trusted entries only for the
reviewed signers, at no more than marginal ownertrust (4), and revocations
only of reviewed signers or of v4 primaries the package's own `blackarch.gpg`
publishes, never of an Arch or CachyOS keyring key. Malformed list lines and
list files that are not plain files refuse. A real keyring outside these
bounds is refused for review.

An interrupted commit or activation leaves an exact recovery record,
including whether BlackArch was staged. Malformed, unreadable or symlinked
records are preserved and refused, never treated as an ordinary core-only
upgrade. When the proofs are still available, recovery re-reviews and
completes the full upgrade, activates any staged repository, then clears the
record; a usable BlackArch canary cannot clear it. While recovery is pending,
package transactions, repository preparation and native/COAE infrastructure
provisioning stay suspended. Missing installed-version records or signed
archives (an already-refreshed system DB, an emptied cache with old artifacts
gone from mirrors, missing detached signatures, a partially committed upgrade
that lost the old records) are manual-refusal boundaries: the record stays,
with the reason. haseen does not promise automatic repair of a torn system
upgrade or a whole-workstation rollback.

A root-owned lifecycle mutex serialises haseen's shared package and recovery
state across users. Root state is supported only under `/var/lib/haseen`; a
different `HASEEN_STATE_DIR` is refused. The mutex does not serialise other
package managers: do not run another package transaction while haseen
provisions. Rejected trust or declined preparation is reported unavailable
and skipped, not a failed mutation; apply returns nonzero only for actual
mutation failures. Key rotation needs a reviewed change, and system
packages, keyring trust, repository configuration and upgrade results are
not reversed by removing this layer.

### oniomarchy: an opt-in private signed source

The plan 087 groups use oniomarchy's categories as facts; none of its
installer code is used. Its repository can also be the **last** source tier,
after Arch, only when you ask for it in that run:

```sh
haseen vapt repo-status                            # offline; never selects the source
haseen vapt repo-enable --dry-run oniomarchy       # describes approval; fetches nothing
haseen vapt repo-enable oniomarchy                 # approve the pinned source (asks first)
haseen vapt install --with-oniomarchy --groups sdr # use it for this run only
haseen vapt repo-disable oniomarchy                # remove the private descriptor
```

- **Per operation.** Without `--with-oniomarchy` there is no fetch, no key
  import, no private stanza and no candidate from it; attempted tiers record
  `oniomarchy:not-selected`. `--all` selects groups, never a repository, and
  nothing remembers the choice. If the source is not approved,
  `--with-oniomarchy` asks to approve it; declining is reported as
  `oniomarchy:declined` and does not degrade an otherwise complete run.
- **Private scope.** The approved stanza (`[oniomarchy]`,
  `SigLevel = Required DatabaseRequired`,
  `Server = https://pkgs.oniomarchy.com/$arch`) lives in
  `/var/lib/haseen/vapt/sources/oniomarchy.conf` and enters only VAPT's own
  transaction configuration, with `Usage = Sync Search Install`.
  `/etc/pacman.conf` is never changed. A host `[oniomarchy]` section is
  reported and the private source refused while it exists; a changed
  descriptor is preserved and reported, never repaired.
- **Trust anchor.** The key comes only from
  `https://pkgs.oniomarchy.com/oniomarchy.gpg` (HTTPS, no redirect, no
  keyserver, no bootstrap script) and must have exactly one primary, the
  reviewed `0F5F9214F312B067ECBF1DF125E2C00AA6340BD0`
  (`files/oniomarchy-signers.txt`), not revoked or expired. The database's
  detached signature must carry exactly one accepted primary before any
  filename is read from it. The keyring archive the database names is sealed
  against the database digest, its signature checked, and audited (identity,
  exact layout, dependencies, population-only scriptlet, hooks, protected
  paths) before any trust change.
- **What changes in the shared keyring.** The `oniomarchy-keyring` package is
  never installed, so its trusted and revoked files (and their ownertrust
  column) never reach `/usr/share/pacman/keyrings/`, and a manual
  `pacman-key --populate` has nothing of this source's to apply. haseen keeps
  the audited archive in root state
  (`/var/lib/haseen/vapt/sources/oniomarchy-keyring.pkg`), binds the recorded
  authority to it, and never imports publisher ownertrust. Approval adds and
  locally signs the pinned key, then only the newly accepted primaries,
  exported from the archive's key file (checked to hold exactly those) with
  `pacman-key --add` and `--lsign-key`. Newly revoked keys are deleted only
  when a strictly parsed `gpg --with-colons --list-keys` listing of pacman's
  keyring shows them; that listing is read before any key is added. A failed,
  empty, malformed or human-format listing fails the approval with nothing
  added or deleted, a failed deletion fails it before anything is recorded,
  and the revocation stays pending for a retry. An approval refuses while an
  `oniomarchy-keyring` package or `oniomarchy*` keyring file from an earlier
  install remains (remove it with `pacman -R oniomarchy-keyring`).
- **Private packages cannot change pacman's trust.** A package from the
  source that would place anything in `/usr/share/pacman/keyrings/`, pacman's
  GPGDir (default `/etc/pacman.d/gnupg`, where gpg reads `gpg.conf-2` before
  `gpg.conf`), the rest of `/etc/pacman.d/` or `/etc/pacman.conf*` is refused
  by the transaction audit. Each member is judged where it lands through
  links, case-insensitively and whatever its path spelling; only directory
  headers of those directories and their parents pass. pacman's DBPath and an
  `Include` target outside `/etc/pacman.d` are not covered.
- **Rotation.** Later signers come only from a keyring signed by a currently
  accepted, non-revoked primary. Revocations never roll back, the keyring
  version never goes down, and neither the downloaded key, the database nor a
  file on the host can add a signer. The accepted set is root-owned state; a
  stored archive or authority record that no longer matches makes the source
  `unverified`, and `repo-enable` refuses it for manual review. A rotation is
  applied only by an approval: `repo-enable`, or the approval an opted-in run
  asks for when the source is not approved (for example after
  `repo-disable`). The refresh an opted-in run performs never changes trust:
  a database not signed by a recorded primary makes the source `unverified`
  with a reason naming `haseen vapt repo-enable oniomarchy`, and a database
  that names another keyring package says so and names the same command. A
  database already moved to a key that is not yet accepted stays refused
  pending manual review.
- **Revocations only of keys this source has used.** A keyring may revoke
  only the pin, an earlier revocation, or a signer observed *before* this
  approval (a primary whose signature verified this source's database or
  keyring archive at an earlier approval or refresh, recorded in root state).
  A fingerprint merely listed as trusted is never revocable, so a keyring
  that first lists an Arch/CachyOS or administrator key and later revokes it
  is refused before any trust change, with the fingerprints named. A signer
  cannot revoke itself in the archive that introduces it; a retiring signer
  that has signed before may revoke itself while handing over.
- **Strict signatures.** `Required DatabaseRequired` is kept in the private
  and install configurations; a missing or unaccepted database signature
  makes the source unavailable rather than weaker. Its `Usage` excludes
  Upgrade and its prelude runs after any full upgrade: a full upgrade under
  the private scope is refused, and a recovery record that names the source
  is refused and preserved.
- **Trust changes are reported as such.** Once the pinned key is imported, or
  an audited keyring update reached the shared keyring, a later refusal is a
  mutation failure saying trust changed but the source is not approved. A
  busy root lock reports `unavailable` ("privileged transaction busy").
- **x86_64 only.** Other architectures report `unsupported-architecture`
  before any fetch or trust change; the other sources still work.
- **Admission.** Only the 52 names in `packages/oniomarchy.tsv` count: a
  candidate (serving an item by exact name or a reviewed `aliases.tsv` row,
  so `chirp` maps to `chirp-next`), a dependency (`java17-openjfx-bin`,
  `sleuthkit-java`, `powershell-bin`, the libsoup and webkit2gtk packages and
  thirteen `python-*` libraries; never a root) or the keyring. A 53rd name is
  ignored until a reviewed change admits it. The source satisfies a
  dependency only by exact name or a reviewed alias the package's own
  metadata backs, never wins over an acceptable earlier package or provider,
  and never declares replacements. It refuses any name, or the item an alias
  maps it to, that another configured source with readable metadata
  publishes, usable this run or not. A candidate is admitted only as the
  requested target; a dependency row serves only its recorded consumer (`*`
  for any). When the source wins while an earlier source could not be read,
  the reason says "earlier source unavailable this run; not proof this is the
  inventory tool". It is no base vendor and gains no stock-helper authority.
  The generic Omarchy refusals also match the string `oniomarchy`; such a
  match is still refused, reported as "oniomarchy self-reference requires
  review".
- **Reports.** `report.tsv` keeps its v1 columns; `selected_source` is
  `oniomarchy` and `target` the published name (for example
  `oniomarchy/chirp-next`) only after a real resolution. A `# oniomarchy`
  annotation records the run's source state and `# dependency` rows what a
  commit installed. A later run that cannot use the source keeps the earlier
  row of an item installed from it, with "source not selected this run;
  installed package retained" (or the state). A homonym in an earlier source
  replaces it as usual.
- **Status after the source is gone.** While the source is approved, status
  (which never selects it) re-checks installed private packages read-only
  from the cached database verified at the last refresh. After
  `repo-disable`, or while unverified, such an item is reported "oniomarchy
  source disabled or unverified … provenance unverifiable" (degraded), not as
  drift. A recorded dependency no longer installed degrades status too. The
  cache never offers a candidate or authorises an install.
- **What stays after `repo-disable`.** Only the descriptor is removed. The
  added keys stay in the shared keyring, which pacman does not scope per
  repository, so approval expands machine-wide trust; revoking them is a
  separate `pacman-key` decision. The authority record, stored archive and
  verified cache stay under `/var/lib/haseen/vapt/sources/`, inert without
  the descriptor.

A valid signature proves continuity with the reviewed key, not who built a
package, that its code is safe, or that it is the upstream tool its name
suggests.

## Environment and user files

Selecting `htb-coae` provisions a separate uv-managed **CPython 3.12**
environment at `$XDG_DATA_HOME/htb-coae` (default `~/.local/share/htb-coae`)
with the source's shared pins `torch==2.14.1`, `transformers==5.18.0`,
`modelscan==0.8.8` and `textattack==0.3.11`. `modelscan` requires Python
below 3.13; the environment stays apart from the system `python-pytorch`
stack, and uv supplies a managed 3.12 interpreter (the source names the minor
version only). Existing unmanaged or conflicting environments are preserved
and reported, not adopted. An unmanaged environment can satisfy read-only
reporting when its pins and uv-managed interpreter provenance match; it never
grants mutation authority or an interpreter for the native PyRIT adapter.
Owned environments with ambiguous or unsafe distribution metadata are left
untouched.

A passive shell fragment adds available native/local tool-bin directories
without launching anything or replacing system Python. It exposes
`HASEEN_VAPT_COAE_ENV` but does not activate that environment. The layer
seeds only an owned link to it, `~/.config/haseen/vapt/shell.sh`, and never
creates or edits a user file such as `~/.bashrc` or `~/.zshrc`. If a command
in one of them already sources the link (`.` or `source`, with the absolute
path, `~`, `$HOME` or `$XDG_CONFIG_HOME`; a comment or other mention does not
count), interactive shells pick it up. Otherwise apply and `haseen layer
status vapt` print the line you may add yourself (with the absolute path; a
missing line is reported, not degraded):

```sh
[ -r "$HOME/.config/haseen/vapt/shell.sh" ] && . "$HOME/.config/haseen/vapt/shell.sh"
```

The guard makes the line inert once `haseen layer remove vapt` deletes the
link. Only activation links this layer created are journaled for removal;
borrowed, conflicting, dangling or modified links are preserved.

When `~/.config/uwsm/env.d/` already exists, a second owned link,
`70-haseen-vapt`, loads the same fragment for future graphical sessions.
Standalone installations need no uwsm. Native-tool paths are appended, not
forced ahead of personal commands; an earlier PATH command shadowing an owned
adapter is reported as degraded. haseen uses its seed-once helpers here, not
GNU Stow or yadm.

## Reports, dry-run and removal

```sh
haseen vapt status
haseen vapt remove --dry-run
```

The per-user report is `$XDG_STATE_HOME/haseen/vapt/report.tsv` (default
`~/.local/state/haseen/vapt/report.tsv`). It distinguishes **resolved**,
**planned**, **installed**, **skipped** and failed mutations. Missing sources
do not stop independent tools. Status is degraded while reported items or
environment requirements stay unavailable, including a COAE environment
selected earlier; a resolution or a dry-run layer marker is not installation
evidence.

Apply validates source metadata before creating the lock or its parents. Real
apply and remove serialise the same user's ownership journals with a
nonblocking lifecycle lock; a busy operation is refused, and dry-run opens no
lock. Ownership records are written durably before their mutations, and
metadata inspection does not borrow files outside a fixture through symlinks.
Dry-run is offline and write-free: no downloads, managers, repository
bootstrap, security tools, temporary directories, reports or user files.

Removal reverses only unchanged activation links owned by haseen; changed or
unsafe ones are preserved and reported as incomplete removal. It keeps
packages, native/COAE environments, downloaded Python runtimes, repository
and keyring trust, reports, seeded user files, directories and user data. It
is not a package uninstaller or a workstation rollback.

## Omissions and limits

- `steghide` stays in its manifest. It was absent from the checked
  BlackArch/Arch/CachyOS metadata, and Chaotic-AUR could not be checked
  (documented mirrors returned HTTP 403), so it is reported unavailable, not
  removed.
- waydots' machine-specific LAN routing unit is not integrated: it is private
  routing that the source also leaves to manual installation. No routing
  values or VPN profiles ship.
- The source has no VAPT-specific aliases, launchers, workspace layout,
  notebooks or other workflow helper, and none was invented. GUI packages
  keep their own desktop entries; no Omarchy menu wiring is imported.
- Credentials, targets, assessment procedures, payloads and service
  activation are outside provisioning and are neither copied nor run.
- Repository and PyPI metadata establish names, identity and published
  versions, not installability on every future snapshot. Live installation,
  keyring bootstrap, native builds and tool execution were not performed as
  validation.

The engineering record is in [plan 007](../plans/007-vapt-layer.md),
[plan 087](../plans/087-vapt-oniomarchy-provisioning.md),
[plan 088](../plans/088-vapt-security-workflow.md),
[plan 090](../plans/090-vapt-audit-fixes.md) and
[plan 148](../plans/148-vapt-on-an-omarchy-host.md).

## Installed inventory and explicit usage (plan 088)

Provisioning never runs its tools. These commands inspect installed ownership
offline, or show documentation only when asked:

```sh
haseen vapt tool-list --json
haseen vapt tool-list --all --group network --dry-run
haseen vapt tool-help TOOL --entry /absolute/owned/entry --dry-run
haseen vapt tool-run TOOL --entry /absolute/owned/entry --dry-run
haseen vapt status --json
haseen vapt doctor --json --dry-run
haseen vapt menu --enabled --json
```

`tool-list` includes verified installed inventory roots; `--all` adds
missing and unknown items. Entrypoints come from installed package file
inventories and executable mode, or verified pinned native distribution
RECORD files; data packages may have none. Owned desktop metadata is read as
data. No package-name guess, PATH search, earlier report, installed module
import or presence probe is used. Ownership proves metadata association, not
unchanged bytes.

`tool-help` needs one entry (`--entry` when there are several). It prefers a
unique owned basename-matching man page, then a matching help document, and
prints it directly (man pages as plain roff source), never through man or a
pager. Translations of a man page (`/usr/share/man/<lang>/manN/`) count as one
page: the untranslated copy wins, otherwise the first translation by path.
Readability is established by a confined descriptor open; showing the
document reopens it and revalidates ownership and inode. Input and expanded
gzip output are each capped at 4 MiB; an oversized, invalid or truncated
document refuses with exit 1 and a diagnostic, printing nothing. Otherwise a
reviewed package/entry-specific help-only argv binding is required; the
shipped registry is empty, so there is no `--help` guess. Missing or
ambiguous evidence is a refusal. Dry-run reports the evidence and intended
argv without running anything.

`tool-run` shows the same documentation, then opens only the user's login
shell (`-i`, checked against `/etc/shells`, with an independently present
bash fallback); outside a terminal it uses the floating terminal helper. It
never runs the selected tool, prefills a command, elevates or starts a
backend, and has no `--json`. Fixture sysroots cannot run a help binding or
start a shell.

List, status, doctor and menu run no listed program, refresh nothing and write
nothing, dry-run or not. JSON is exactly one `schemaVersion: 1` object;
diagnostics go to stderr. Status keeps 0 healthy / 1 missing / 2 degraded;
doctor maps missing and degraded to 1 and usage to 2, and repairs nothing.
[Plan 088](../plans/088-vapt-security-workflow.md) has the full schema.

`menu` reads the deep-merged default and user shell configuration and returns
enabled only for literal `plugins.haseen.security.enabled: true`; it enables
nothing. Its reader loads no inventory, provisioning or local-action code.
The shell's menu and the launcher's `/` provider do not run this command:
they answer its guard from the plugin flag the shell already holds, so
opening them starts no Python. Identical guard expressions in one menu batch
run once. Security providers read nothing while the plugin is disabled.

Explicit provisioning seeds `~/.config/haseen/vapt/workflow.json` once from
the shipped defaults (`showLocalAddresses: false`, `enumerationScript: null`,
`bindAddress: "127.0.0.1"`); existing settings are untouched. Inventory never
discovers or stores addresses.

## Explicit services and local helpers (plan 088)

Provisioning starts, enables and configures nothing. These commands act only
on an explicit request; every dry-run is offline and write-free.

- `haseen vapt service-list --json`: the ids `ssh`, `postgresql`, `apache`,
  `nginx`, `beef` with installed package and unit ownership, current
  `FragmentPath`, raw manager states and exposure `unknown`. Reviewed
  bindings select `openssh/sshd.service`, `postgresql/postgresql.service`,
  `apache/httpd.service` and `nginx/nginx.service`; the exact non-template
  unit must be in that package's files, with one owner and verified
  provenance. Auxiliary units and templates do not change selection. BeEF has
  no reviewed binding and stays refused. A wrong-shaped manager snapshot
  emits one refused object with exit 1; malformed row fields report unknown
  evidence. Ownership covers the loaded fragment, not drop-ins.
- `service-start ID` and `service-restart ID` ask in a terminal (`--yes`
  accepts the unknown exposure); `service-stop ID` asks nothing and needs no
  terminal. Root authorisation is always required, ownership is rechecked
  right before the root gateway, and nothing is enabled, preset, initialised
  or installed. `--expect-unit UNIT --expect-fragment PATH` bind a displayed
  snapshot: a mismatch refuses before any privileged step; dry-run reports
  the check.
- `haseen vapt net-addresses --json`: local interface addresses, with no DNS
  or network probe, storage or logging. Endpoints accept literal IPv4/IPv6
  addresses and ports 1024–65535; missing ports are prompted for locally.
  IPv6 may carry one `%SCOPE` matching `[A-Za-z0-9_.-]{1,64}` (for example
  `fe80::1%enp5s0`); keep the scoped literal unchanged and never append
  another scope. The CLI is authoritative; preview does not check interface
  presence or promise a bind.
- `haseen vapt net-listener [--bind ADDRESS] [PORT]`: an owned, reviewed,
  neutral foreground listener (no received-data execution or payloads),
  loopback by default. A non-loopback bind needs consent at an interactive
  terminal; `--yes` or piped input refuses. The `nc` adapter writes raw peer
  bytes, control sequences included, to the terminal.
- `haseen vapt net-http-server [--bind ADDRESS] DIR PORT`: byte-only
  foreground HTTP for an explicitly selected directory. Opened descriptors
  confine requests; traversal, symlinks and multiply-linked files are
  refused, with the link count checked on every request. No listing, CGI,
  upload, firewall change, daemon or fetched content.
- `haseen vapt net-file-server [--file FILE] [--bind ADDRESS] [PORT]`: one
  explicitly selected package-owned single-link regular file at `/file`,
  from the `enumerationScript` setting or a prompt; it never guesses a
  script, exposes its directory, runs or fetches it. Doctor's
  `enumeration-host` capability maps to this command; there is no alias.
- Both servers need consent at an interactive terminal (`--yes` or piped
  input refuses), bind the literal address without reverse DNS, and serve
  serially with a five-second idle wait and a thirty-second absolute
  connection deadline. A request whose `Host` is neither `localhost` nor a
  local literal address of the bind (any local address of the family for a
  wildcard bind), or that carries several `Host` headers, gets 421, so a
  DNS-rebinding page cannot read served files; an HTTP/1.0 request without
  `Host` is served. After consent the wrapper hands its process to the
  helper, so a signal to it cannot leave a helper holding the endpoint.
- `haseen vapt net-remmina`: launch only the verified owned client, with no
  target, connection or credentials and no prompt; dry-run previews
  ownership.

The foreground commands have no JSON mode. Doctor readiness comes from actual
adapter, source and selection evidence; capability records carry fixed
`command` leaf verbs, which consumers must whitelist before building argv.

### Proxy CA ownership, not browser configuration

`haseen vapt net-proxy-ca status --json` reports none, owned, foreign,
modified or unknown (incomplete) anchor state. `inspect CERT --json` reads
one bounded public PEM/DER CA and reports subject, issuer, uppercase SHA-256,
validity and CA/private-key flags; it refuses bundles, private keys, non-CAs
and expired material, prints no certificate contents and changes no trust.
CA status comes only from OpenSSL's decoding of the `basicConstraints`
extension (the documented proper X509v3 CA result); subject or issuer text,
printable malformed extension bytes and legacy-only evidence cannot confer
it. Inspection, the trust payload and the root helper share this check.
Malformed ownership records report unknown, and doctor refuses that
readiness.

`trust CERT` requires typing the full displayed fingerprint, `--yes`
included. It rechecks the immutable certificate bytes and the owned updater,
then installs one fingerprint-owned system anchor through the root gateway
and updates trust; no browser or proxy is launched or configured. `remove
FINGERPRINT` asks, and removes only the unchanged recorded anchor; foreign or
modified files survive. Anchors must be regular single-link files. Dry-run
never requests privilege or writes an anchor.

The root journal, written before the anchor, records the certificate (its
optional `pem` field, checked against `contentSha256`) and a transaction
state shown as `anchor.transaction: pending|removing|created`. A failed
trust update reports `unknown` with `trust transaction pending; owned anchor
unchanged; system trust update incomplete`; a trust interrupted before its
anchor was completely written, `… owned anchor missing or incomplete; …`; a
failed removal, `removal transaction incomplete; anchor absent; system trust
may still contain CA`. Under its lock the root helper then allows:

- for a `pending` journal whose anchor is unchanged, missing or a partial
  write of the recorded certificate (a prefix, possibly zero-filled after a
  crash): `trust CERT` again with the same fingerprint and bytes (typed
  fingerprint still required), or `remove FINGERPRINT`, which rolls the trust
  back; either first deletes a partial write;
- for a `removing` journal: removal retry only, never trust.

Foreign, modified, unsafe or mismatched state stays a refusal. A journal
without `pem` cannot prove a partial anchor is haseen's: only a trust retry
with the certificate completes it. A completed trust whose anchor was deleted
by hand reports modified and refuses both. Doctor may report the proxy-CA
capability available for recovery; that does not mean trust completed, and
every retry reports success only after the updater succeeds. Until then,
system trust may still contain a removed CA, and a later system trust update
could activate an unchanged pending anchor.

## Optional Security workstation panel (plan 088)

`haseen.security` is a built-in **panel only**, explicitly **off by default**.
Enable it with `haseen plugin enable haseen.security`, then open Setup →
Security → VAPT workstation → Open panel, or `haseen shell ipc panel toggle
haseen.security`. No bar widget, startup service, polling, installation or
repository approval is added, and existing menu and shell files are not
rewritten. Without literal `enabled: true` the panel closes before any read.

Pages: Overview (provisioning and source uncertainty), Tools (installed
inventory, search, group filter, optional missing diagnostics), Services
(owned units and manager state) and Local actions (including unavailable
prerequisites). Enter inspects a row, not a program. Several owned entrypoints
need an explicit choice; undocumented or ambiguous entries get no usage or
shell action. "No verified executable entrypoint" describes the evidence, not
the bytes. Recorded resolutions are not installation evidence.

Every launch uses `Apps.launch` with fixed whitelisted verbs and separate argv
operands; local helper verbs come from the capability record
(`enumeration-host` → `net-file-server`). The panel never passes `--yes` and
passes the displayed service unit and FragmentPath as expectations.
Everything except the remote desktop client opens in a terminal, which asks
before a service start or restart, a local server, a non-loopback listener
or a CA trust change and revalidates first; Stop and the client have no
prompt, and Stop skips Review. A launch shows and announces "completion has
not been checked", never success; refusals after launch appear in that
terminal. The certificate form shows the anchor transaction: a `pending` one
offers removal (rollback) and, once the same certificate is inspected, trust
retry; a `removing` one only removal retry; a foreign or modified anchor
neither.

Reopen or Refresh reads a new snapshot; a launch never refreshes or polls.
Preview captures the real `--dry-run` output and exit code without
launching anything. Addresses are read only by the explicit chooser, and
certificate inspection reads only the selected file. Paths, addresses,
fingerprints, drafts and the menu hand-off live only in memory. No read probes
connectivity.

Keys: Tab visits controls; arrows/j/k move list focus without wrapping,
Home/End go to the first/last item and PageUp/PageDown move by the visible
viewport, in tools, services, entrypoints, quick actions and both endpoint
choice lists; tabs also take Home/End. Enter/Right/l inspect or select, never
execute; Left/h go back outside text editors. Detail and picker headings take
named entry focus, Tab then reaches the first control, and focus never
selects. Review focuses Cancel; every Tab stop has a visible focus ring. The
scrolling card reveals a focused row fully when it fits, an oversized one from
its beginning. Header, page navigation and footer share that viewport, so
large text and fallback font metrics cannot leave the body without a line.

Enter in endpoint fields validates the draft and prepares Review through the
dry-run; Enter in the certificate-path field inspects, never trusts. Syntax
errors show at the field with an accessible description, and submission
focuses the first invalid field; CLI refusals stay on a selectable Preview and
Back keeps the draft. The first Escape closes only an open address chooser.
A selected address keeps the CLI's scoped literal byte for byte; unscoped
link-local IPv6 requires a chosen interface scope.

A repository-source read failure stays labelled with its diagnostics and
Retry, without clearing the other sections. The existing anchor's ownership
and full selectable SHA-256 are shown independently of an inspected
certificate, and removal Review repeats that fingerprint and its machine-wide
effect. Each refusal is announced once. Paths, units, fingerprints and dry-run
output are copyable; rows grow with wrapped text and safety text is never
truncated.

The production components are tested offscreen (keyboard, scroll, rendering)
at 360×480, 560×640 and 720×640, with stock Flexoki Light and Everforest
tokens, enlarged text and an empty private font configuration. They never
touch a live desktop. The offscreen application was not exposed to the
accessibility bridge, so screen-reader order, names, state and announcement
delivery are unverified.
