# Optional VAPT workstation provisioning

The `vapt` layer provisions the owner's waydots tool inventory, plus tool
groups taken from oniomarchy's categories (plan 083), on **Arch and
CachyOS**. It does not run assessments, launch security tools, start their
backends, change firewall rules, or enable services. It has no required desktop,
Omarchy, Chaotic-AUR, or AUR layer. No tools are selected by default.

The installer runtime prerequisites are `python3` with its standard library,
`pacman`, `vercmp`, `bsdtar`, `curl`, and `gpg`. Precheck reports missing
prerequisites before changing the tree. A minimal Arch installation may need
Python installed first; this layer does not use an unchecked interpreter
bootstrap. Hosts whose OS identity is `omarchy` are refused by this layer:
its supported provisioning targets are Arch and CachyOS.

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
`--yes` accepts installer confirmations. `--vapt-groups all` selects all groups;
otherwise pass a comma-separated list. When `--layers` is omitted, the existing
installer defaults still apply and VAPT is appended; use `--layers vapt` for a
standalone, Omarchy-independent tooling installation. The interactive install
picker never offers `vapt` (its layer sets `LAYER_PICKABLE=false`) and drops it
from a saved choice, because the layer refuses to run without explicit groups;
`--vapt-groups` is the only installer route.

A tooling-only installation skips sidecar compilation, migration execution,
and unrelated hardware-quirk application. Other explicitly selected layers
retain their normal installer behavior.

There are 25 groups. The owner's fifteen are `core`, `network`, `web`,
`passwords`, `ad`, `osint`, `cloud`, `mobile`, `forensics`, `api`, `htb-cjca`,
`htb-cpts`, `htb-cwes`, `htb-cwee` and `htb-coae`; their original memberships
are retained in `share/haseen/layers/vapt/packages/security/`. Plan 083 adds
ten more and a few roots to two existing ones:

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

Together with the native adapter entries the manifests represent **204
distinct tool names**. Overlapping selections resolve each logical tool once
and retain its selected-group memberships. Every group file is validated on
every run, selected or not.

## Sources and identity

This layer intentionally does **not** use the general installer's AUR fallback.
Its source order preserves the waydots security policy:

1. Explicit repository pins (`packages/pins.tsv`): the original `extra` pins
   for `nmap`, `radare2`, `jadx`, `binwalk`, and `dotnet-sdk`; the twelve SDR
   and nine wireless tools Arch publishes, `keepassxc`, `mat2`, `veracrypt`,
   `macchanger`, `tor`, `routersploit` and `remmina` from `extra`;
   `core/openssh`; and `blackarch/set` for the Social-Engineer Toolkit.
2. BlackArch, with concrete package identity and reviewed providers.
3. The pinned native adapter, when one exists.
4. Already-enabled Chaotic-AUR binary packages.
5. Enabled CachyOS repositories.
6. Arch `core`, `extra`, and `multilib`.

Unavailable pins are reported before the remaining allowed tiers are considered.
AUR builds, arbitrary repositories, and Omarchy packages/providers are excluded
before source selection, so a forbidden provider cannot shadow a genuine package
from a later allowed tier. The dedicated pacman path checks dependency closure and
package scriptlets/relevant hooks; an unsafe or unverifiable item is reported
and skipped rather than sent through the general resolver.

The audit distinguishes current files, incoming payloads, and each package's
pre/post scriptlet phases. A helper changed by another package must be safe in
both possible snapshots; transaction-wide hooks use current/final snapshots.
Enabled systemd-unit links are refused even without an installer script.
Replacement/conflict removals, missing old file inventories, opaque helpers,
and relevant backup/NoExtract/NoUpgrade ambiguities require manual review and
are reported as unsupported. NoUpgrade-protected dropped hooks remain audited.

Hook matching follows libalpm's ordered targets and transaction-wide file events,
including ordered `NoExtract` exceptions. Hook grammar is validated before
basename overrides can mask lower-priority hooks; inline hashes are literal
values, not comments. Compressed `.MTREE` inventories are read without filesystem
lookups and must agree with the physical archive inventory. Malformed or
inconsistent inventories are refused. Hook `Exec` is a direct process invocation
from `/`, not a shell builtin or PATH search; builtin-shadowing shell functions
are also refused.
Delegated shell helpers accept no interpreter options or only `-e`/`-u`
combinations that preserve inspected file-body execution. Archive member names
are extracted as literal operands, never archiver options. Literal hashes also
remain part of shell command words; opaque trailing-comment syntax may require
manual review rather than a speculative shell interpretation.

Stock maintenance has a separate, narrow policy in
`share/haseen/layers/vapt/files/stock-hooks.tsv`: canonical hook paths, exact
arguments and reviewed script digests. Native helpers are accepted only from
authenticated Arch/CachyOS artifacts, not a matching package name, URL, version
or self-reported installed MTREE. Incoming maintenance/runtime artifacts must
match the reviewed repository checksum and a base-vendor package signer.
Retained helper bytes and symlink targets must equal an authenticated reference
artifact and have exactly one installed owner. Proof prefers the installed
version's record from the pre-refresh sync-DB snapshot or the reviewed DB;
incoming payloads remain bound to the reviewed DB. Cached or downloaded
references must match that record and the vendor signature. Missing or differing
proofs require manual review; haseen never executes an unproven helper to identify
it, and its full-upgrade path cannot always repair missing proof.

Read-only ELF and loader-selector inspection checks current and future helper
dependencies, interpreter and link paths, loader-cache/hwcaps candidates, NSS
services and gconv conversion modules. Every reachable native candidate must be
base-proven; unknown formats or search rules are refused. Literal absolute
`DT_RUNPATH` directories and exact `$ORIGIN` are supported; nonempty `DT_RPATH`
is refused because inherited search semantics are not modeled. A new, unrelated
library is not rejected merely because it is a shared object. Module-loading
maintenance, daemon reloads, tmpfiles, kernel/initramfs and opaque scriptlets
remain unsupported rather than receiving a general bypass.

Plans bind repository package filenames, not cache-dependent download locations.
Downloads are sealed into a root-owned, nonreplaceable archive/signature set
before auditing. Every archive's actual package identity and dependency,
provider, conflict and replacement metadata must match the complete reviewed
plan. Per-package commits use those exact artifacts in one local `pacman -U`
transaction, without live repository/provider re-resolution. New dependencies
are marked as dependencies; requested targets are explicit and existing
dependency upgrades retain their install reason. A bookkeeping failure after
installation is a reported mutation failure; its install reasons require manual
repair rather than silently retrying package installation. Sealed files are
readable for inspection, not confidential storage.

Package metadata, hook bodies, delegated helpers and MTREE input are read from
one immutable libarchive snapshot, with exact member-name lookup. Shell brace,
glob and tilde expansions are refused when they could change the inspected
command. Scriptlet and helper parsing uses LF line endings and ASCII shell
blanks; ambiguous control characters and non-shell whitespace require manual
review. Retained helper bytes are read without newline rewriting. Every
non-exempt install script requires a proven shell in both transaction snapshots.

Hardlinks are accepted only as zero-body aliases of an earlier ordinary regular
payload in the same archive. Both entries must have matching mode and ownership,
no extended attributes, no skip/backup ambiguity and plain destination parents
in both transaction views. Package metadata members are not payload targets.
Other hardlink effects require manual review rather than permission to write
through a retained or external inode.

The root Python interpreter supports only the stock startup layout. Active
`._pth`, `pyvenv.cfg`, build selectors and alternative versioned prefix landmarks
refuse in both transaction views, even when supplied by an authenticated base
package. Interpreter library-search overrides also require manual review.
The selected version's stdlib prefix and `lib-dynload` must be physical
directories, and its optional stdlib zip must be a regular file. Import-relevant
links must resolve inside that stdlib and outside its excluded `site-packages`;
outward redirects require manual review in either transaction view. Links
originating inside `site-packages` remain ordinary package data because that
tree is outside the isolated root import path.

New directories on root import, loader, conversion, PAM/sudo, hook or protected
program/policy paths must preserve root-only write authority. All explicit
creators, including base packages, are checked together at the physical future
path: root UID/GID, no group/other write and no extended attributes. Implicit
parents rely on the pinned root `022` umask. The nearest existing physical
ancestor must have no default ACL. These checks include aliased namespace roots,
their descendants and future stdlib version directories containing no files.
Existing directories keep their retained baseline because libalpm does not
re-permission them. A hand-over is the exception: an existing directory that an
upgraded package drops while another package ships an explicit header for it
may be removed and recreated, so it is checked as new. Unrelated package data
and the excluded `site-packages` subtree are not subjected to a blanket
directory policy. Removed paths are authenticated only when every transaction
package that owned them is a base-authenticated plan row. A transaction that
would remove the root `/usr/bin/python3` used by post-commit steps is refused
for manual review.

Every VAPT-owned privileged step uses an absolute environment launcher,
`PATH=/usr/bin` and `LC_ALL=C`, with loader/conversion overrides removed
(`LD_PRELOAD`, `LD_LIBRARY_PATH`, `LD_AUDIT`, `GLIBC_TUNABLES`, `LD_PROFILE`,
`LD_PROFILE_OUTPUT`, `GCONV_PATH`, `LOCPATH`).
The inner launcher also removes `PYTHONEXECUTABLE`, `__PYVENV_LAUNCHER__`,
`BASH_ENV`, `ENV`, `SHELLOPTS` and `PS4` after sudo/PAM environment
construction; isolated Python flags do not disable those executable overrides,
and noninteractive shells read their startup file or inherited trace options
before the requested helper. The privilege gateway itself resolves commands
through the same canonical PATH.
This changes neither the system nor the user's locale. The generic layer
runner's applied-marker write and the invoking user's environment are outside
that guarantee. Existing root provisioning executables, root-admin
authentication configuration and vendor keyrings remain trust anchors; this
audit is not whole-machine attestation.

The running metadata auditor, its stock-hook and signer policies, and the
Arch/CachyOS vendor keyrings and revocation records are protected in the current
and future transaction views, including link targets and parent redirects.
The stock-hook policy guard follows the physical module parent actually read
by the auditor, including a file-symlink deployment and authenticated redirects.
Incoming changes or removals require authenticated base-repository provenance.
The non-base identical-entry exception also preserves file permissions and
file/link ownership, and refuses incoming extended attributes. Existing
directories are not re-permissioned by libalpm, and symlink mode bits have no
Linux effect. Other keyrings remain ordinary package data.

The identical-entry exception also needs a confined root-produced authority
record: retained access/security attributes and a regular file's parent default
ACL can change its writer set when package extraction recreates the inode.
Only ordinary `user.*` attributes are accepted. Production visibility requires
root with effective `CAP_SYS_ADMIN`; limited visibility, missing or unsafe
records, missing rows and ambiguous attributes require manual review.
The user-side audit rechecks visible attributes, so a stale positive record
cannot excuse a later visible ACL change. Archive, ELF and signature parsing
remain unprivileged; the root producer reads only retained filesystem metadata.
Fixture visibility is explicitly separate and cannot authorize live mutation.

Post-commit privilege steps also guard PAM includes, modules and path arguments,
sudo plugins, loader-environment selectors and their native dependencies.
Unauthenticated incoming changes or removals cannot enter that retained graph.
Every present system and vendor PAM service file is checked without assuming
precedence. Nonliteral paths, relative `pam_exec` commands, unsupported PAM
forms and loader overrides require manual review. Unsupported sudoers includes,
plugin source/backend arguments, nondefault plugin directories and PAM-service
overrides also refuse rather than silently selecting an uninspected policy.
A root-produced, readable record supplies sudoers group-plugin paths; missing
records, replaceable records or ancestry not owned by root refuse the audit.

Public mutating VAPT entrypoints refuse a nonempty `HASEEN_SYSROOT` before any
change. Fixture evidence cannot authorize live package, key or configuration
operations. Dry-run and offline status remain available; the separate hermetic
test runner supplies its own confined mutation wrappers.

`httpx` and `katana-pd` mean the ProjectDiscovery tools, not Python HTTPX or
katana-framework. One source identity error is explicitly corrected:
BlackArch's `pyrit` is the WPA cracker. COAE instead receives **Microsoft
PyRIT**, pinned to `pyrit==1.1.0`; the BlackArch homonym cannot satisfy it.

Upstream identities (`packages/identities.tsv`) are canonical `http(s)` URLs.
A package matches when its URL has the same host and the identity's path or a
descendant at a `/` boundary; case and a trailing slash do not matter. URLs
with userinfo, a port, a query, a fragment, escapes or dot segments never
match, an `https` identity refuses `http`, and a `required-target` other than
`*` must be the exact `repository/package`. This is the publisher's own
metadata, not independent proof of where the code came from.

Reviewed package names that differ from the tool's name are listed in
`packages/aliases.tsv`; for example the toolkit is BlackArch's `set`. An alias
makes that repository's lookup exact, so no Provides declaration can replace
it, and `-git`/`-bin` suffixes are never stripped by rule.
`packages/identity-policy.tsv` blocks `metasploit-mcp`, because the inventory
does not establish which of several similarly named projects it means; it is
always reported unavailable. `wordlists` is exact-name only, so `seclists` or
a provider cannot stand in for it. `hexstrike-ai` has no reviewed source and is
reported unavailable unless a package with its upstream identity appears.
Neither AI item falls back to PyPI or the AUR.

Dependency-only packages (`packages/dependencies.tsv`) are never tool roots:
`powershell-bin` and `xorg-xhost` with no assumed consumer,
`jdk17-openjdk`, `java17-openjfx` and `sleuthkit-java` for autopsy,
`jdk-openjdk` for ghidra and `python-wxpython` for wfuzz. Adding one to a group
manifest refuses provisioning. They arrive only through a selected package's
own declared dependencies and are recorded as dependencies; `xorg-xhost` is
never run to change display access. The consumer column is enforced for the
private source's rows: `java17-openjfx-bin` and `sleuthkit-java` are admitted
only in autopsy's closure. Rows from Arch repositories are ordinary packages
there, so the column documents them and enforces nothing.

The eight original native pins are retained:

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

The source's impacket probe is distro-specific (`impacket-smbserver`).
The pinned PyPI adapter instead checks the upstream `smbserver.py` executable
path without running it; the package/version pin and logical tool stay unchanged.

Pipx installations live in the dedicated
`$XDG_DATA_HOME/haseen/vapt/pipx` store (default `~/.local/share/haseen/vapt/pipx`).
They do not overwrite existing personal pipx environments. Satisfaction is
checked through distribution/version/source-commit metadata and executable-path
presence, **never by executing a security tool**.

### BlackArch trust

A real run can offer to prepare BlackArch. The implementation never executes
`strap.sh`: it discovers the keyring artifact and checksum from repository
metadata, seals the archive and signature, and verifies the pinned upstream
primary-key identity. The checked keyring is installed from that sealed set
under a repository-free configuration.
Existing repository configuration is preserved. A newly prepared repository is
staged privately for review; its bounded stanza is appended globally only after
the reviewed full upgrade commits. A rejected review leaves the global config
unchanged and can be retried. The checked keyring package and populated trust
may remain installed even when that review is rejected.

Package signatures remain required; database discovery is not described as
authenticated. The signed keyring's reviewed population-only scriptlet is
suppressed for that package alone; haseen explicitly performs the checked
keyring-population action. Changed or unknown scriptlets are refused, not given
a general execution bypass.

An interrupted commit or activation leaves an exact recovery record, including
whether BlackArch was staged. Malformed, unreadable or symlinked records are
preserved and refused, never treated as an ordinary core-only upgrade. When
the required proofs remain available, recovery re-reviews and completes the
full upgrade, activates any staged repository, then clears the record.
A usable BlackArch canary cannot clear this requirement.
While recovery is pending, package transactions, repository preparation and
native/COAE infrastructure provisioning stay suspended, including when their
prerequisites already appear installed.

Missing installed-version records or signed archives are manual-refusal
boundaries. This includes an already-refreshed system DB, an emptied package
cache with old artifacts no longer on mirrors, missing detached signatures,
and a partially committed upgrade that lost the old repository records.
The recovery record remains intact with the reported reason; haseen does not
promise automatic repair of a torn system upgrade or whole-workstation rollback.

A root-owned lifecycle mutex serializes haseen's shared package/recovery state
across users. VAPT supports root state only under `/var/lib/haseen`; a different
`HASEEN_STATE_DIR` is refused rather than used to repair permissions or create
the lock elsewhere. This mutex does not serialize other package managers:
administrators must not run another package transaction while haseen is
provisioning.
Rejected trust/policy or declined preparation is reported as unavailable and
skipped, not a failed mutation. Apply returns nonzero for actual mutation
failures; unavailable sources alone do not make it fail.

The trust anchors are documented upstream at
[BlackArch's bootstrap source](https://blackarch.org/strap.sh) and stored in
`share/haseen/layers/vapt/files/blackarch-signers.txt`. Key rotation requires a
reviewed change, not automatic trust adoption. System packages, keyring trust,
repository configuration, and upgrade results are not reversible by removing
this layer.

### oniomarchy: an opt-in private signed source

The plan 083 groups use oniomarchy's tool categories as facts; none of its
installer code is used. Its package repository can also serve as the **last**
source tier, after Arch, but only when you ask for it in that run:

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
  nothing remembers the choice. If the source is not yet approved,
  `--with-oniomarchy` asks to approve it; declining is reported as
  `oniomarchy:declined` and does not make an otherwise complete run degraded.
- **Private scope.** The approved stanza (`[oniomarchy]`,
  `SigLevel = Required DatabaseRequired`,
  `Server = https://pkgs.oniomarchy.com/$arch`) lives in
  `/var/lib/haseen/vapt/sources/oniomarchy.conf` and enters only VAPT's own
  transaction configuration, with `Usage = Sync Search Install` (never a
  full-upgrade source). `/etc/pacman.conf` is never changed. A host
  `[oniomarchy]` section is reported and the private source is refused while
  it exists; a changed descriptor is preserved and reported, never repaired.
- **What stays global.** Approval imports and locally signs the pinned key and
  installs the `oniomarchy-keyring` package, which populates the shared pacman
  keyring. That trust is machine-wide, not isolated to VAPT, and it is kept
  when the source is disabled; revoking it is a separate `pacman-key`
  decision. A full upgrade that carried the private source leaves its frozen
  database copy in pacman's sync directory; pacman ignores it unless
  `/etc/pacman.conf` declares the repository.
- **Trust anchor.** The key comes only from
  `https://pkgs.oniomarchy.com/oniomarchy.gpg` (HTTPS, no redirect, never a
  keyserver, no bootstrap script) and must have exactly one primary, the
  reviewed `0F5F9214F312B067ECBF1DF125E2C00AA6340BD0`
  (`files/oniomarchy-signers.txt`), not revoked or expired. The database's
  detached signature must carry exactly one accepted primary before any
  filename is read from it. The keyring archive the database names is sealed
  against the database digest, its own signature checked, and audited
  (identity, exact layout, dependencies, a population-only scriptlet, hooks,
  protected paths) before any trust change.
- **Rotation.** Later signers come only from a keyring package signed by a
  currently accepted, non-revoked primary. Revocations never roll back, the
  keyring version never goes down, and neither the downloaded key nor the
  database nor an installed file can add a signer. The accepted set is
  recorded in root-owned state; missing proof after a local keyring change
  makes the source `unverified`, and `repo-enable` refuses it for manual
  review. A rotation is applied only by an approval: `repo-enable`, or the
  approval an opted-in run asks for when the source is not approved (for
  example after `repo-disable`). The refresh an opted-in run performs on an
  approved source never changes trust. When its database is not signed by a
  recorded primary, the source is `unverified` and the reason names
  `haseen vapt repo-enable oniomarchy`. When the database names a keyring
  package other than the recorded one, the run says so and names the same
  command. An approval can apply a rotation only while the database is still
  signed by an accepted primary. Once the publisher has moved its database to
  a key that is not yet accepted, the source stays refused pending manual
  review.
- **Strict signatures everywhere.** `Required DatabaseRequired` is kept in the
  private and install configurations. A missing or unaccepted database
  signature makes the source unavailable rather than weaker. The source's
  `Usage = Sync Search Install` excludes Upgrade and its prelude runs after
  any full upgrade, so a full upgrade never carries it: a full upgrade under
  the private scope is refused, and no recovery record names the source (a
  record that does is refused and preserved for review).
- **Revocations stay inside the source's authority.** `pacman-key --populate
  oniomarchy` applies the keyring's revoked list to the shared keyring, so an
  audited keyring may revoke only a previously accepted or revoked, pinned or
  trusted primary; any other revocation (an Arch/CachyOS or administrator key)
  refuses the keyring with the offending fingerprints named. The recorded
  authority must equal what the retained keyring lists declare.
- **Trust changes are reported as such.** Once the pinned key is imported (or
  an audited keyring update reached the shared keyring), any later refusal is
  a mutation failure saying the trust changed but the source is not approved;
  approval is claimed only when the recorded evidence makes the source usable.
  A busy root lock reports `unavailable` ("privileged transaction busy").
- **x86_64 only.** Other architectures report `unsupported-architecture`
  before any fetch or trust change; the other sources still work.
- **Admission.** Only the 52 published names in `packages/oniomarchy.tsv`
  count, each a candidate (serving an item by its exact name or a reviewed
  `aliases.tsv` row, so `chirp` maps to `chirp-next`), a dependency
  (`java17-openjfx-bin`, `sleuthkit-java`, `powershell-bin`, the libsoup and
  webkit2gtk packages and thirteen `python-*` libraries; never a root target)
  or the keyring. A 53rd name in a newer signed database is ignored until a
  reviewed change admits it. The source never satisfies anything through
  `Provides`, never wins over an acceptable earlier package, and never
  declares replacements. It refuses any name, or the logical item an alias
  maps it to, that another configured source with readable metadata
  publishes, usable this run or not (the resolver and the dependency closure
  check the same repository set). A candidate is admitted only as the
  requested target, never as somebody's dependency. A dependency row named in
  `dependencies.tsv` serves only its recorded consumer (`*` for any), so
  `java17-openjfx-bin` and `sleuthkit-java` serve only `autopsy`; rows marked
  `-` there have no recorded consumer. When the source wins while an earlier
  configured source could not be read this run, the reason says
  "earlier source unavailable this run; not proof this is the inventory
  tool". It is not a base vendor and gains no stock-helper authority. Its
  `metasploit-mcp` and `hexstrike-ai` gaps stay unavailable. The generic
  Omarchy refusals (names, dependencies, hook text, helpers, mirrors) also
  match the string `oniomarchy`. Such a match is still refused, but it is
  reported as "oniomarchy self-reference requires review" rather than as
  Omarchy.
- **Reports.** `report.tsv` keeps its v1 columns; `selected_source` is
  `oniomarchy` and `target` the actual published name (for example
  `oniomarchy/chirp-next`) only after a real resolution. A `# oniomarchy`
  annotation records the run's source state and `# dependency` rows the
  dependencies a commit installed. A later run that cannot use the source
  (not selected, declined, unavailable or unsupported architecture) keeps the
  earlier row of an item installed from it, with "source not selected this
  run; installed package retained" (or the state) appended. A homonym that
  appeared in an earlier source replaces it as usual.
- **Status after the source is gone.** While the source is approved, status
  (which never selects it) re-checks installed private packages, read-only,
  from the cached database verified at the last refresh. After
  `repo-disable` (or while it is unverified), status reports such an item as
  "oniomarchy source disabled or unverified … provenance unverifiable" (degraded),
  not as drift. A recorded dependency that is no longer installed is degraded
  too. Packages retained from the source still prove themselves from that
  verified cache when other items' closures depend on them. The cache never
  offers a candidate or authorises an install.

A valid signature proves continuity with the reviewed key, not who built a
package, that its code is safe, or that it is the upstream tool its name
suggests. Package URLs are the publisher's own metadata.

## Environment and user files

Selecting `htb-coae` provisions a separate uv-managed **CPython 3.12** environment
at `$XDG_DATA_HOME/htb-coae` (default `~/.local/share/htb-coae`) with the source's
shared pin set:

- `torch==2.14.1`
- `transformers==5.18.0`
- `modelscan==0.8.8`
- `textattack==0.3.11`

`modelscan` requires Python below 3.13. This environment remains distinct from
the system `python-pytorch` stack. The source specifies the Python minor version,
not a patch release; uv supplies a managed 3.12 interpreter. Existing unmanaged
or conflicting environments are preserved and reported rather than adopted.
An unmanaged environment can satisfy read-only reporting when its pins and
uv-managed interpreter provenance match; it never grants mutation authority or
an interpreter for the native PyRIT adapter. Owned environments with ambiguous
or unsafe distribution metadata are left untouched, not reconciled by uv.

A passive shell fragment adds available native/local tool-bin directories
without launching anything or replacing system Python. It exposes
`HASEEN_VAPT_COAE_ENV` but does not auto-activate that environment. The layer
links the fragment as `~/.config/haseen/vapt/shell.sh` and appends one marked,
guarded line to `~/.bashrc` (and to `~/.zshrc` only when that file exists),
written with the link's absolute path:

```sh
# haseen VAPT: passive native-tool PATH only.
[ -r "$HOME/.config/haseen/vapt/shell.sh" ] && . "$HOME/.config/haseen/vapt/shell.sh"
```

The line is appended once; an rc that already names the link, or that sources
the optional shell-rc layer's `default/shell/init.sh` (which loads the same
link), is left unchanged, so tooling-only provisioning never opts the user into
unrelated aliases or tool initialization. Symlinked or non-regular rc files are
preserved and reported. `haseen layer remove vapt` deletes the owned link and
keeps the line: rc files stay user-owned, and the guard makes the line inert
once the link is gone. Only activation links created by this layer are
journaled for reversible removal; borrowed, conflicting, dangling, or
subsequently modified links are preserved.

When the desktop's `~/.config/uwsm/env.d/` already exists, a second owned link,
`70-haseen-vapt`, loads the same passive fragment for future graphical sessions.
Standalone installations do not require uwsm. Native-tool paths are appended,
not forced ahead of personal commands; an earlier PATH command shadowing an
owned adapter is reported as degraded rather than silently changing user priority.

There is no current GNU Stow convention to extend: waydots migrated to yadm and
haseen uses seed-once helpers. This integration uses those established helpers;
it does not migrate dotfiles or introduce Stow/yadm as a hidden dependency.

## Reports, dry-run, and removal

```sh
haseen vapt status
haseen vapt remove --dry-run
```

The per-user report is `$XDG_STATE_HOME/haseen/vapt/report.tsv` (default
`~/.local/state/haseen/vapt/report.tsv`). It distinguishes **resolved**, **planned**,
**installed**, **skipped**, and failed mutations. Missing sources do not prevent
independent tools from being provisioned. Status returns degraded when reported
items or environment requirements remain unavailable, including a previously
selected COAE environment after a later selection of another group. A completed
resolution or a dry-run layer marker is not installation evidence.

Apply validates source metadata before creating the lock or its parent directories.
Real apply/remove operations serialize the same user's ownership journals with
a nonblocking lifecycle lock. A busy operation is refused; dry-run neither opens
nor creates a lock. Ownership records are written durably before their mutations,
and metadata inspection does not borrow files outside a fixture through symlinks.

Dry-run is offline and write-free: no downloads, managers, repository bootstrap,
security tools, temporary directories, reports, or user files are created.
Fixture metadata can establish a plan; missing metadata stays unknown.

Removal reverses only unchanged activation links owned by haseen. Changed or
unsafe owned activation is preserved and reported as incomplete removal, not
marked as successfully deactivated. It retains packages, native/COAE environments,
downloaded Python runtimes, repository/keyring trust, reports, seeded user files,
directories, and user data. It is not a whole-workstation rollback or package
uninstaller.

## Explicit omissions and evidence limits

- `steghide` remains in its original manifest. It was absent from the checked
  BlackArch/Arch/CachyOS metadata; Chaotic-AUR availability could not be verified
  because documented mirrors returned HTTP 403. It is reported as unavailable
  in that metadata fixture, not silently removed or declared absent everywhere.
- `etc/luna-local-lan-route.service` from waydots is not integrated: it is
  private, machine-specific routing that the source also leaves for manual
  installation. No private routing values or VPN profiles are shipped.
- No VAPT-specific aliases, launchers, workspace layout, notebooks, or additional
  local workflow helper was found in the source. None was invented. GUI packages
  retain their own packaged desktop entries; no Omarchy menu wiring is imported.
- Credentials, targets, assessment procedures, payloads, and service activation
  are outside provisioning scope and are not copied or executed.
- Repository/PyPI metadata establishes names, identity, and published versions,
  not complete installability on every future repository snapshot. Live package
  installation, keyring bootstrap, native dependency builds, and tool execution
  were intentionally not performed as implementation validation.

The engineering record and exercised checks are in
[`plans/007-vapt-layer.md`](../plans/007-vapt-layer.md) and
[`plans/083-vapt-oniomarchy-provisioning.md`](../plans/083-vapt-oniomarchy-provisioning.md).
