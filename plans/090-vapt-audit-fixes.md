# Plan 090: VAPT audit fixes

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MEDIUM (shared pacman trust, root package transactions, local servers and the optional panel; every fix is checked against fixtures only)
- **Depends on**: 007 087 088
- **Category**: vapt
- **Planned at**: 2026-10-13, owner request: audit of PRs #38–#40
- **State**: DONE 2026-10-13

## Problem

An audit of the VAPT work in PRs #38–#40 (provisioning, plans 007 and 087;
workflow and panel, plan 088) found the defects below. Each entry gives what
failed, the fix, and the test that fails without the fix. Line numbers are
at this plan's commit.

## Trust

- **Private packages could write pacman's trust configuration.** The
  oniomarchy package audit refused only `usr/share/pacman/keyrings/`. A
  package could drop `/etc/pacman.d/gnupg/gpg.conf-2` (gpg reads it before
  `gpg.conf`) with a `trusted-key` and make an attacker key ultimately
  trusted for every repository. Fix: a private-source package may place
  nothing in the keyrings directory, the configured GPGDir (or the default),
  the rest of `/etc/pacman.d` or `/etc/pacman.conf*`. Each member is judged
  where it physically lands in both transaction views, through host links and
  links in the same transaction, case-insensitively, with path spellings
  normalised; directory headers of those directories and their parents pass
  (`share/haseen/layers/vapt/metadata.py:1380-1413` in `audit_archives`,
  `pacman_gpgdir` at `:4595`). Test: `tests/test-vapt-oniomarchy-transactions.sh`
  "nothing lands in the GPGDir" (:121) and the `refused_payload` cases
  (:168-201: both GPGDir files, a configured and a linked GPGDir, a
  mirrorlist, a hook, `pacman.conf`, `.pacnew`, a `.d` directory, `./`, `//`,
  `/./` and case-changed spellings, absolute, relative, incoming and retained
  links); controls at :164, :166, :193. Limit: pacman's DBPath and an
  `Include` target outside `/etc/pacman.d` are not covered.
- **The BlackArch keyring's lists were never audited.** `pacman-key
  --populate blackarch` lsigns every `blackarch-trusted` ID, imports that
  file's ownertrust and disables every `blackarch-revoked` ID in the shared
  keyring, but the audit did not read either list: a keyring signed by a
  pinned BlackArch key could disable an Arch master key. Fix: trusted IDs must
  be reviewed BlackArch signers (`files/blackarch-signers.txt`) with
  ownertrust at most 4 (marginal); revoked IDs must be reviewed signers or v4
  primaries of the package's own `blackarch.gpg`, never an Arch/CachyOS
  keyring key; malformed lines and non-plain list files refuse
  (`metadata.py:4715` `blackarch_keyring_lists`, run by
  `blackarch_keyring_audit` at `:4794`, before `blackarch.sh:113` populates).
  Test: `tests/test-vapt-trust.sh` "keyring lists: CASE: refused" (:265),
  "vendor revocation: no pacman-key trust change" (:169); controls at :260,
  :262, :285. Limit: the real BlackArch lists were not fetched; if they
  exceed these bounds, BlackArch preparation is refused (fails closed).
- **VAPT configurations lowered the host's SigLevel.** `render_config`
  replaced every SigLevel, `[options]` included, with `Required
  DatabaseOptional`, so a host that required database signatures lost that
  check in VAPT's `-Sp`/`-Sw` and its full upgrade. Fix: the host's level is
  read per repository as pacman reads it (Package and Database halves,
  repository lines over the global one) and only raised to VAPT's minimum; an
  unknown value refuses the configuration (`metadata.py:581`
  `siglevel_apply`, `:608` `siglevel_line`, `:617` `render_config`). Test:
  `tests/test-vapt-trust.sh` "signature level: CASE" (:387), the archive-only
  and frozen configurations (:401, :404), an unknown value (:407).
- **A re-approval trusted new keys before reading the keyring.** An
  oniomarchy re-approval that accepted and revoked keys added and lsigned the
  new ones before listing pacman's keyring; an uninterpretable listing then
  failed the approval with the new keys trusted and nothing recorded. Fix: the
  listing is read and parsed before the first `pacman-key` call
  (`share/haseen/layers/vapt/oniomarchy.sh:269`, first `--add` at `:279`).
  Test: `tests/test-vapt-oniomarchy-trust-adversarial.sh` "listing first: no
  key is added, signed or deleted" (:253).
- **The approval dry-run described an install that no longer happens.** It
  said the keyring package would be installed with `--noscriptlet`. Fix: both
  dry-run plans say the package is never installed and name what is recorded
  (`oniomarchy.sh:55`, `:66`). Test: `tests/test-vapt-oniomarchy-trust.sh`
  "enable dry-run: the keyring is never installed" (:229) and its re-approval
  twin (:235).

## Provisioning

- **An unreviewed `Provides` in an earlier tier beat Arch's own name.** On
  the real sync databases `nodejs` resolved to BlackArch's end-of-life
  `nodejs-lts-gallium` 16.20.2 (which conflicts with `nodejs`, while the same
  groups' `extra/npm` needs `nodejs>=20.17.0`), and `chirp` to Chaotic-AUR's
  `chirp-next` without `--with-oniomarchy`. Fix: every tier matches only the
  item's name or reviewed alias; a provider counts only with a reviewed
  upstream identity and only after every tier's name, Arch's included
  (`share/haseen/layers/vapt/provision.sh:261` `vapt_repo_provider`, `:282`
  `vapt_resolve_item`). The inline exception that let BlackArch's
  `android-sdk-platform-tools` stand for `android-tools` is gone;
  `android-tools` resolves to `extra/android-tools` by name. Test:
  `tests/test-vapt.sh` "Arch's nodejs beats a BlackArch provider" (:482), "a
  Chaotic provider never stands in for chirp" (:491), "Arch's own name beats
  an earlier reviewed provider" (:503), "two providers are never picked
  arbitrarily" (:506), "the genuine android-tools is planned" (:271);
  `tests/test-vapt-inventory.sh` "a Chaotic provider of chirp is no source for
  it" (:190).
- **Every run installed three packages nobody chose.** Each provisioning run
  planned, installed and recorded `openldap`, `perl-image-exiftool` and
  `python-pipx` whatever the groups. Fix: the up-front call is gone; pipx
  comes with a selected native adapter (`share/haseen/layers/vapt/native.sh:59`).
  Test: `tests/test-vapt.sh` "maltego alone plans no NAME" (:349), "maltego
  alone records no prerequisite" (:351), "a selected native adapter brings
  pipx" (:353). Limit: reports written before the fix keep their
  `# infrastructure` rows (report-merge keeps annotations, `metadata.py:4169`),
  and status still degrades when one of those packages is removed
  (`share/haseen/layers/vapt/layer.sh:105`).
- **Shell activation matched substrings.** The rc check looked for the link
  path anywhere: a comment counted, a source of the nonexistent
  `default/shell/init.sh` counted, and the documented `$HOME` form of the
  line did not. Fix: the rc is read as shell words (comments, quotes,
  here-documents) and only a `.` or `source` command whose argument expands
  (`~`, `$HOME`, `$XDG_CONFIG_HOME`) to the link counts (`metadata.py:4102`
  `rc_sources`). Test: `tests/test-vapt-env.sh` cases `absolute home comment
  echo other none` (:354-379).
- **Install reasons.** Every commit marked its target `--asexplicit`, turning
  an upgraded dependency explicit; and new dependencies, which `pacman -U`
  installs as explicit, stayed explicit when a run stopped before `-D
  --asdeps`, because a rerun took the already-exact shortcut. Fix: no
  `--asexplicit`; the new dependencies are recorded in
  `/var/lib/haseen/vapt/reasons-pending` before `-U`, and the next VAPT
  transaction, exact target or not, finishes and clears the record
  (`share/haseen/layers/vapt/pacman.sh:348` `vapt_reasons_repair`, `:423-428`).
  Test: `tests/test-vapt-commit.sh` "reasons: an upgraded target keeps its
  dependency reason" (:87), "interrupted bookkeeping: the root record names
  it" (:108), "the rerun marks the dependency" (:114).

## Workflow

- **Python imported modules from the working directory.** `python3 -c`
  helpers put the cwd first on `sys.path`, and these commands often start in
  a cloned exploit or loot directory: a planted `json.py` ran, even under
  `--dry-run`. Fix: every VAPT interpreter runs with `-I`: the workflow
  helpers (`share/haseen/layers/vapt/workflow.sh:10-12`,
  `workflow_actions.sh:9`, `:25`), `metadata.py` (`pacman.sh:11`) and the
  install precheck (`layer.sh:39`). Test: `tests/test-vapt-net.sh` "planted
  json.py never imported" (:271). The `metadata.py` and precheck changes have
  no dedicated test.
- **An interrupted CA trust was unrecoverable.** The pending journal was
  written before the anchor; a crash or ENOSPC between them left a missing or
  partial anchor that status called modified, refusing trust and removal for
  good. Fix: the journal also stores the certificate (optional `pem` field,
  checked against `contentSha256`); under the root lock, trust completes and
  remove rolls back a pending journal whose anchor is missing or a partial
  write of that certificate (a prefix, possibly zero-filled); other bytes are
  preserved and refused (`share/haseen/layers/vapt/workflow_ca.py:89`
  `record_read`, `:106` `anchor_condition`, `:124` `recoverable`, `:202`
  `mutate`). The panel offers the same recovery
  (`share/haseen/shell/plugins/haseen.security/Model.js:89-97`). Test:
  `tests/test-vapt-net.sh` "interrupted trust is completable and reversible"
  (:499), "interrupted trust may be retried" (:518), "CLI rolls back an
  interrupted trust" (:524); `tests/test-vapt-ui-adversarial.sh` "pending
  trust with a missing anchor exposes retry" (:148). Limit: a completed trust
  whose anchor was deleted by hand still refuses both actions.
- **Discovery scanned every package file per entrypoint.** Matching each
  entry against every file of its package cost about two minutes for
  metasploit, paid again by every command. Fix: document candidates are
  indexed once per package, readability is checked once per document, and
  `tool-help`/`tool-run` discover only the selected tool
  (`share/haseen/layers/vapt/workflow.py:176` `documentation_index`, `:212`
  `package_entries`, `:291` `discover`). Test: `tests/test-vapt-discovery.sh`
  "large installed/repository/package fixture discovery within bound" (:152):
  2,000 documented executables among 20,005 files of one package, 20 s bound;
  "indexed source results equal reviewed linear predicates" (:113) also checks
  that the per-tool discovery equals the full one.
- **Translated man pages made a tool ambiguous.** nmap's
  `/usr/share/man/<lang>/man1/nmap.1.gz` copies counted as separate pages,
  so help refused it. Fix: translations are one page; the untranslated copy
  wins, else the first by path (`workflow.py:176`, `:199`). Test:
  `tests/test-vapt-workflow.sh` "translated man pages are one page" (:37),
  "untranslated man page preferred" (:38).
- **"Never executed" assertions could not fail.** Actions run host programs
  by absolute path, so stubs on `PATH` never saw them, and a broken fixture
  guard would have run the host's binaries. Fix: every executed program is
  chosen as sysroot + path (`workflow_actions.sh:15` `vapt_program`,
  `share/haseen/layers/vapt/workflow_support.py:15` `host_program`), and the
  test runner executes nothing else (`tests/fixtures/vapt-actions-runner.sh:14`).
  Test: `tests/test-vapt-net.sh` "CLI trust ran the sysroot updater once"
  (:341); `tests/test-vapt-services.sh` "only restart no enable, through the
  sysroot seam" (:57).
- **The HTTP helpers ignored Host (DNS rebinding).** While `net-http-server`
  ran on loopback, a page under an attacker's name could read served files.
  Fix: a request whose Host is not `localhost` or a local literal address of
  the bind (every local address of the family for a wildcard bind), or that
  carries several Host headers, gets 421; an HTTP/1.0 request without Host is
  served (`share/haseen/layers/vapt/workflow_actions.py:220`
  `accepted_hosts`, `:237` `host_accepted`, `:325` `addressed_here`). Test:
  `tests/test-vapt-net.sh` "actual confined HTTP handler loopback exercise"
  (:189; the 421 cases at :131-138).
- **`--yes` gave exposure consent.** `confirm` returns true under `--yes`, so
  `net-http-server --yes --bind 0.0.0.0 ~ 8000` served the home directory to
  the LAN without a prompt. Fix: servers and non-loopback listeners require
  consent at an interactive terminal; `--yes` or piped input refuses
  (`workflow_actions.sh:35` `vapt_exposure_consent`). Test:
  `tests/test-vapt-net.sh` "--yes cannot accept a non-loopback listener"
  (:67), "piped answer cannot accept a non-loopback listener" (:74), "--yes
  loopback listener needs no consent" (:78).
- **`tool-run` lost piped output.** The document sat in Python's buffer when
  `os.execv` replaced the process. Fix: stdout is flushed first
  (`workflow.py:441` `show_help`). Test: `tests/test-vapt-workflow.sh` "piped
  document reaches the reader before the shell starts" (:119).

## UI

- **Assertions that could not fail.** Four Security UI assertions passed with
  their guard removed (for example "launch performs no status refresh"
  compared a count with itself, and "stale generation cannot apply" compared
  the snapshot a no-op leaves). Each was rewritten to fail without its guard
  (`tests/test-vapt-security-ui.sh:161-189`). The conformance runner now has
  five named QtTest functions (`tests/test-vapt-panel-conformance.sh:245`).
- **✓ on rows that are not present.** Security information, refused and
  previous-snapshot rows are disabled, and a disabled row got ✓ ("listener ✓",
  "No installed items ✓"). Fix: ✓ comes from a check or a `disabled:` guard
  (`share/haseen/shell/plugins/haseen.menu/MenuModel.js:416` `labelFor`).
  Test: `tests/test-menu.sh` "Security information rows: disabled, no ✓"
  (:235), "a refused local action: disabled, no ✓" (:236).
- **The menu started Python on every open.** The always-on menu, and the
  launcher's `/` provider, ran `haseen vapt menu --enabled` for the Security
  guard even with Security off. Fix: both answer that guard from the plugin
  flag the shell holds and start no process (`MenuModel.js:631`
  `answerSecurityGuard`, `:638` `guardScript`; callers
  `share/haseen/shell/plugins/haseen.menu/Panel.qml:875`,
  `share/haseen/shell/plugins/haseen.commands/Provider.qml:54`). Test:
  `tests/test-menu.sh` "Security guard answered in-process" (:250), "without
  the flag the guard runs as written" (:257);
  `tests/test-vapt-menu-providers.sh` "disabled Security hides its rows
  without running the CLI" (:88). The launcher caller has no dedicated test.
- **A tool named `remmina` launched without a terminal.** The panel chose a
  direct launch by item id. Fix: launch follows the prepared intent; only the
  remote desktop client starts without a terminal
  (`share/haseen/shell/plugins/haseen.security/Panel.qml:145-151`). Test:
  `tests/test-vapt-security-ui.sh` "its documentation opens in a terminal"
  (:275).
- **Spurious "This item changed" after Back.** Back to a list kept the
  selection, so ticking Include missing reported the reshaped records as a
  changed item. Fix: Back to a list clears the selection (`Panel.qml:72-83`).
  Test: `tests/test-vapt-security-ui.sh` "Back to the list leaves nothing
  selected" (:250), "records reshaped by --all are not a changed selection"
  (:259).
- **Left and h did not go back.** The ScrollView took Left for its hidden
  bar. Fix: both are handled before it, outside text editors
  (`Panel.qml:261-268`). Test: `tests/test-vapt-panel-conformance.sh`
  `test_left_and_h_go_back` (:159).
- **Shadowed QML built-ins.** Panel properties named `scale` and `state`
  and a function `move()` shadowed built-in members; they are now
  `textScale`, `kind` and `moveBy` (`ActionButton.qml`, `StateMessage.qml`,
  `Inventory.qml`). No behavioural test.
- **The menu and the panel imported each other's files.** The menu imported
  the panel's `Model.js`, the panel the menu's `MenuModel.js`, so the menu
  failed to load without the panel's directory. Fix: JSON validation moved to
  `share/haseen/shell/Haseen/SecurityEvidence.js` and the hand-off to the
  `qs.Haseen` singleton `share/haseen/shell/Haseen/SecurityRoute.qml`. Test:
  `tests/test-vapt-menu-providers.sh` "the menu loads without the
  haseen.security directory" (:87); `tests/test-vapt-security-ui.sh` "hand-off
  refuses a hostile item" (:119), "the hand-off is taken once" (:282).
- **The UI suite ran three times per CI run.** The adversarial and
  conformance suites sourced the whole UI suite. Fix: the fixture modules
  moved to `tests/fixtures/vapt-qml-lib.sh` (`vapt_qml_fixture`, :66), and
  each suite runs only its own cases (`tests/test-vapt-ui-adversarial.sh:7-9`,
  `tests/test-vapt-panel-conformance.sh:6-9`).

## Rejected options

- **Reordering VAPT's sources to haseen's general order** (repos,
  Chaotic-AUR, `[omarchy]`, AUR): rejected by the owner on 2026-10-13. VAPT
  keeps pins, BlackArch, pinned native adapters, Chaotic-AUR, CachyOS, Arch as an
  explicit exception (`docs/architecture.md:93-101`, `provision.sh:276-281`).
- **A unique unreviewed `Provides` in any tier**: it picked the homonyms
  above. Providers need a reviewed identity.
- **Refusing only `gpg.conf*` in the GPGDir**: its keyring and trustdb files,
  and the rest of `/etc/pacman.d` (mirrorlists, hooks), are pacman
  configuration too.
- **BlackArch revocations limited to the pinned signers**: that would refuse
  a keyring retiring a key it still publishes. **Ownertrust above marginal**:
  one BlackArch certification would then validate keys for every repository.
- **`Required DatabaseRequired` for every repository**: the reviewed
  BlackArch stanza is `Required DatabaseOptional`
  (`metadata.py:39` `BLACKARCH_STANZA`) and a host's mirrors need not sign
  databases.
- **Matching rc text for the link path**: the defect above.
- **Recovering install reasons by hand after a failed `-D --asdeps`**: the
  rerun's exact shortcut never reached that code.
- **Staging the CA anchor under a temporary name in the anchors directory**
  (the trust store may load any file there, and it is a second name to
  recover) and **writing the anchor before the journal** (a crash then leaves
  an anchor indistinguishable from a foreign one).

## Verification

Every case above runs against fixture sysroots through `tests/run.sh`; no
live package, key, service or trust store is touched. The full gate for the
branch is CI's required lint, test, docs, secrets and nix checks
(`AGENTS.md`, `.github/workflows/ci.yml`).
