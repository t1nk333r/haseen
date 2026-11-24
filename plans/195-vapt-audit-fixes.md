# Plan 195: the VAPT findings of the 2026-11-24 audit

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: LOW-MEDIUM. Two audit rules get stricter (more systemd
  activation paths, the oniomarchy policy files), so a package that passed
  before can now need manual review. The desc parser follows libalpm's
  blocks, which every libalpm-written record already has. The rest are
  reporting, exit-code and usability fixes.
- **Depends on**: 007 (trust and transaction safety), 087 (oniomarchy), 088
  (workflow actions), 090 (install reasons, shell activation)
- **Category**: vapt
- **Planned at**: 2026-11-24, from the owner ("fix them", after the
  35-auditor audit)
- **State**: DONE 2026-11-24 (`tests/run.sh --affected` 36 files,
  6587/6587; review pending)

## Why

The audit, run on plan 182's branch before its squash merge, confirmed
thirteen VAPT findings (group g11). The VAPT layer,
`share/haseen/default/vapt/`, `default/shell/init.sh` and `docs/vapt.md` are
the same in plan 182's merge, `59207f25`, and in the base of this plan,
`9a9e82ab` (`git diff --stat 59207f25 9a9e82ab -- share/haseen/layers/vapt
share/haseen/default/vapt share/haseen/default/shell/init.sh docs/vapt.md`
prints nothing), and the audited branch head differs from `59207f25` in
none of them either, so every finding still applied. Each new test below was
run against the base code (the base tree with only the new tests copied in)
and failed there.

Line numbers in the sections are the base's.

## 1. The oniomarchy signer pin was not a guarded policy file

`guarded_paths` (`metadata.py:3592-3610`) guarded `files/blackarch-signers.txt`
beside the logical module and `files/stock-hooks.tsv` beside both modules,
but not `files/oniomarchy-signers.txt`, which `pinned_signers()`
(`metadata.py:4217-4223`) reads beside the resolved module as the private
source's only trust root, nor `packages/oniomarchy.tsv`, the admission table
`oniomarchy_admission()` reads the same way. An unauthenticated haseen
package upgrade that rewrote the pin passed the audit; the same change to
the BlackArch signers was refused. The future-view guard
(`metadata.py:1767-1773`) likewise checked only the stock-hook file.

**Fix.** `POLICY_FILES` lists the four policy files; `guarded_paths` guards
each beside both the logical and the physical module, and the future-view
guard checks each beside the future physical module.

**Test.** `tests/test-vapt-landed.sh`: `oniomarchy-pin-bytes` and
`admission-bytes` join the self-change loop (refused), the byte-identical
control carries both files (accepted), and
`vapt-auth-policy-target-physical-pin-changed` refuses a change to the pin
beside the physical module only.

**Rejected.** Guarding only the pin: the admission table decides which
oniomarchy names are records at all, and is read the same way.

## 2. Enabled-unit refusal missed `.upholds`, `/etc/xdg/systemd/user` and drop-ins

`audit_archives` (`metadata.py:1264-1269`) refused only `.wants`/`.requires`
components under seven systemd roots. systemd.unit(5) also enables through
`.upholds/` and reads user units from `$XDG_CONFIG_DIRS/systemd/user`
(default `/etc/xdg/systemd/user`); a drop-in such as
`multi-user.target.d/x.conf` with `Wants=x.service` enables a unit too.

**Fix.** `SYSTEMD_ROOTS` adds `etc/xdg/systemd/`, `SYSTEMD_ENABLING` adds
`.upholds`, and a `*.d/*.conf` member under those roots is refused when its
body sets `Wants=`, `Requires=`, `BindsTo=`, `Upholds=`, `OnFailure=` or
`OnSuccess=`, or when the body cannot be read from the archive (a symlink or
hardlink). After review, a link under those roots is accepted only when its
name ends in a unit type of systemd.unit(5) (`.service`, `.socket`, `.target`
and the rest: an alias or a mask). A link such as
`usr/lib/systemd/system/multi-user.target.d -> /opt/pkg/dropins` hides the
drop-ins behind it from the archive listing, and systemd follows it at boot;
`etc/systemd/system.control` and `usr/local/lib/systemd/system` (neither
normally exists, so pacman can create the link) do the same for whole unit
directories. After the second review, a link at a systemd root or above one
(`usr/local/lib/systemd`, `etc/xdg/systemd`, `usr/share/systemd`,
`run/systemd`, `lib/systemd`, `usr/local/lib`, `etc/xdg`) is refused too
(`systemd_ancestor_link` in `metadata.py`): the rules above see only names
below a root, so such a link swapped in a whole tree of units and drop-ins.
A link that maps every root below it onto another root is still accepted:
filesystem's `lib -> usr/lib` (`pacman -Ql filesystem` lists `/lib`), which
the private `-Syuw` (`pacman.sh:483`) brings in whenever filesystem updates,
makes `lib/systemd/` the `usr/lib/systemd/` root.

**Test.** `tests/test-vapt-followups.sh`: the link loop covers
`etc/xdg/systemd/user` and `usr/lib/systemd/user` with `wants`, `requires`
and `upholds`; the drop-in loop refuses `Wants=`, an indented
`Requires =`, `BindsTo=`, `Upholds=` and a symlinked drop-in, and accepts an
`Environment=` drop-in. The directory-link loop accepts each package without
the link and refuses it with a link at
`usr/lib/systemd/system/multi-user.target.d`,
`usr/lib/systemd/user/default.target.d`, `etc/systemd/system.control`,
`usr/local/lib/systemd/system` or a top-level `subject.conf`, whose target
`opt/subject/dropins/subject.conf` holds `Wants=subject.service`. The
root-link loop does the same for a link at each ancestor listed above, to a
tree whose `system/multi-user.target.d/subject.conf` and
`user/default.target.d/subject.conf` hold `Wants=subject.service`; a `lib`
link to `usr/lib` or `/usr/lib` stays provisionable and one to `opt/subject`
is refused.

**Rejected.** `PartOf=` and `Requisite=` (they do not start the other
unit); refusing every drop-in (packages ship harmless ones for limits and
environment); refusing only links whose name ends in `.d` (the review's
first suggestion), which leaves `system.control` and
`usr/local/lib/systemd/system` open; refusing every link (unit aliases and
masks are ordinary); refusing every link above a root without the mapping
exception (the second review's suggestion), which would refuse the
`filesystem` package's `lib -> usr/lib` and so every VAPT run that meets a
filesystem update.

## 3. A selected tool could end up recorded as a dependency

Each item commits on its own; `vapt_pacman_apply_transaction` marked every
newly installed name except the current target `--asdeps`
(`pacman.sh:422-424`). A later selected root already in that closure then
found itself exact (`pacman.sh:389-393`) and stayed a dependency, so
`pacman -Rs` of its consumer or an orphan purge would remove a tool the user
chose.

**Fix.** Names that are a repository target of this run (`VAPT_TARGET`,
native items excluded) are never added to the dependency list.

**Test.** `tests/test-vapt-commit.sh` `vapt-commit-reasons-two-roots`: two
roots where the second is in the first one's closure; both stay explicit,
an unselected new dependency is still a dependency. The runner's new
`pacman-run` operation applies several roots in order, as `vapt_provision`
does.

**Rejected.** Marking a later root `--asexplicit` when its row is exact:
plan 090 removed `--asexplicit` so an upgraded dependency keeps its reason,
and an exact row cannot tell a package this run installed from one the user
had as a dependency before.

## 4. `doctor`/`status --verbose` crashed on a non-string `bindAddress`

`verbose_report` concatenated the raw setting (`workflow.py:465`);
`settings()` does not validate a hand-edited `workflow.json`, so `null` or
`8080` raised TypeError and the whole report became one error line.

**Fix.** The settings line prints each value through `clean()`, which
stringifies it.

**Test.** `tests/test-vapt-workflow.sh`: with `bindAddress` `null` and
`8080`, `doctor --verbose` and `status --verbose` still print their sources
and the setting, and doctor shows the refused listener capability.

## 5. `service-*` failed silently for a unit in `maintenance` or `refreshing`

`manager_record` accepts both states (`workflow_actions.py:69`), and a
verified row reads `state: unknown` for them (`:131`). `main()` exits 1 for
any `unknown` state (`:492`), so `service-plan` failed and
`vapt_service_action` returned 1 with nothing on stderr
(`workflow_actions.sh:70`).

**Fix.** `service-plan` exits 0 once it printed a row: a service row's
`state` is the unit's manager state, not a verdict, and `service_selected`
already refuses unverified ownership with a reason.

**Test.** `tests/test-vapt-services.sh`: a verified `sshd.service` in
`maintenance` and in `refreshing` lists as `unknown`, and `service stop`
runs the service manager with `stop -- sshd.service`.

**Rejected.** Refusing with a message: the unit is verified and systemctl
can act on it; refusing would leave `service-stop` unusable on a unit
`systemctl clean` put in maintenance.

## 6. `tool-help`/`tool-run` deleted tabs from documents

`clean()` drops every character below a space (`workflow.py:35-36`), tab
included, so `-h<TAB>show help` printed as `-hshow help` (`:517`).

**Fix.** Each document line is `expandtabs()`-ed before `clean()`.

**Test.** `tests/test-vapt-workflow.sh`: a tab-separated document prints
`-h      show help`, and an OSC title sequence is still removed.

**Rejected.** Letting `clean()` keep tabs: it guards every other output too,
where a tab breaks fields.

## 7. Relative `DIR`/`CERT` operands were refused as "invalid owned absolute path"

`physical()` rejects any path not starting with `/` (`workflow.py:39-41`),
and the wrappers passed operands and the `Local directory:` prompt answer
unchanged (`workflow_actions.sh:131`, `:173-190`), so `net-http-server . 8000`
or `~/www` at the prompt failed with a message about ownership.

**Fix.** `vapt_absolute_path` resolves a relative operand against `$PWD` and
expands a leading `~` (the prompt does not), for the endpoint `DIR`/`FILE`
and for `net-proxy-ca inspect|trust CERT`. `..` and control bytes still
reach `physical()`, whose message now says what it requires.

**Test.** `tests/test-vapt-net.sh`: `www`, `./www`, `.` and `~/www` preview
from a working directory mirrored in the fixture sysroot, `../cwd/www` is
refused with the new message, and `inspect ca.pem` from the working
directory reports the same fingerprint as the absolute path.

**Rejected.** `realpath` in the wrapper: it would resolve symlinks before
`physical()` checks them.

## 8. The local servers could not restart on their port for about 60 s

`LiteralHTTPServer` set `allow_reuse_address = False`
(`workflow_actions.py:250`), overriding http.server's default, and the
handler closes from the server side, so a download left the port in
TIME_WAIT and a restart failed with `[Errno 98] Address already in use`.
No plan or commit recorded a reason (`git log -S` shows only the commit that
added it).

**Fix.** `allow_reuse_address = True`, with `allow_reuse_port = False`
stated: on Linux SO_REUSEADDR never binds over a socket still listening,
and SO_REUSEPORT, which would, stays off.

**Test.** `tests/test-vapt-net.sh`: binding a second helper over a listening
one fails; after a download whose connection the server closed first, a new
helper binds the same port.

## 9. `field_data` read any `%KEY%` value line as a new section

`field_data` (`metadata.py:111-120`) started a new key at every `%…%` line
and reset an earlier one, so a package's own `%GROUPS%` or `%LICENSE%`
values spelled `%NAME%`, `%VERSION%` or `%URL%` rewrote the name, version
and URL haseen saw. libalpm reads a list up to the next blank line and
headers only at a block start.

**Fix.** A header opens a block only at the start of the record or after a
blank line; a blank line ends a block; a repeated header is malformed
(ValueError) instead of a reset.

**Test.** `tests/test-vapt-discovery.sh`: a local `evil-1-1/desc` with forged
group and licence values no longer makes `installed blackarch httpx …` print
`exact`; its own name, version and lists parse intact; a repeated `%NAME%`
fails.

**Rejected.** Also requiring the entry directory to match `%NAME%-%VERSION%`:
with block parsing a package can no longer forge either field (a value
cannot hold a blank line: `.PKGINFO` is line-based), and skipping or failing
on a mismatched directory would add a second refusal path for no case that
reaches it.

## 10. `repo-enable` left its stages behind on an interrupt

`vapt_repo` (`layer.sh:173-197`) runs enable without traps, while enable
creates a user `transaction.*` stage and a root `/var/cache/haseen-vapt.*`
stage (`oniomarchy.sh:189-191`) that only a normal return removes
(`oniomarchy.sh:347-354`). `vapt_provision` has the traps
(`provision.sh:460-462`). Disable creates no stage, so it needs none.

**Fix.** `vapt_oniomarchy_enable_staged` runs the enable command in a
subshell with the EXIT/INT/TERM traps `vapt_provision` uses, plus HUP for a
closed terminal; `vapt_repo` calls it. The fixture runner's `repo-enable`
calls `vapt_repo enable` itself (its sysroot guard is the runner's no-op, and
it sources `lib/preflight.sh` as `layer_run_function` does), so the tests
reach the public wiring.

**Test.** `tests/test-vapt-oniomarchy-trust.sh`
`vapt-onio-trust-interrupted`: the curl stub sends TERM to the enable
subshell while the database downloads (after both stages exist); the run
exits 143 and neither stage is left.

**Rejected.** A sweep of stale `haseen-vapt.*` directories on the next run:
another user's live transaction may own one.

## 11. BlackArch bootstrap failures were always reported as "BlackArch absent"

`vapt_blackarch_prepare` set `VAPT_SOURCE_REASON="BlackArch $state"`
(`blackarch.sh:172`) before the bootstrap, so the fallback at `:206` never
fired, and most failure paths (`:36-99`) set no reason. A keyserver key with
another primary fingerprint, a possible substitution, read like a host that
never tried.

**Fix.** The reason is cleared before the bootstrap, so the fallback works,
and the downloads, the keyring record discovery, the keyserver key checks
and the `pacman-key --init/--add/--lsign-key` steps each set their own
reason (the `--lsign-key` one says global trust changed).

**Test.** `tests/test-vapt-trust.sh`: a substituted keyserver key and a
failed keyserver download each name their cause on the `# source` line,
never "BlackArch absent", with no `pacman-key` call.

## 12. Archive member names reached the terminal and `report.tsv` raw

Audit refusals quote member names (`metadata.py:1269`) and are printed as
is (`metadata.py:5033`); `pacman.sh:312-316` put them in
`VAPT_APPLY_REASON`, and the report stripped only `\n` and `\t`
(`provision.sh:427`), so ESC/OSC sequences from a repository package reached
the terminal and the saved report. The BlackArch keyring path already
stripped `[[:cntrl:]]` (`blackarch.sh:88-89`).

**Fix.** `metadata.py` prints every error with control bytes escaped
(`\x1b`), and the report replaces every control byte with a space in item,
infrastructure, `# source` and `# oniomarchy` reasons; the full-upgrade
source reason strips `[[:cntrl:]]` too.

**Test.** `tests/test-vapt-commit.sh` `vapt-commit-escaped-member`: an
enabled link named `subject<ESC>]0;pwned<BEL>.service` is refused, the
reason shows `subject\x1b]0;pwned\x07.service`, and no raw ESC or BEL
reaches the output.

**Rejected.** Escaping only at each shell sink: warnings print reasons
outside the report too, so the metadata side escapes once for all of them.

## 13. VAPT said no rc sourced its link on a seeded machine

`default/shell/init.sh:69-74` sources the VAPT link, and `haseen seed user`
includes init.sh from the rc, but `vapt_shell_active` (`provision.sh:442-448`)
looked only for a direct source of the link, so apply and status asked for
a redundant line. Plan 090 assumed init.sh did not exist; it and init.sh's
VAPT block landed the same day.

**Fix.** `vapt_shell_active` also counts an rc command that sources this
haseen's `default/shell/init.sh`; the headers of `default/vapt/shell.sh`
and `environment.sh` and `docs/vapt.md` say so.

**Test.** `tests/test-vapt-env.sh`: an `init` rc case (the seeded line) is
active with nothing reported; `other` now sources `aliases.sh` and still
reports the line.

**Rejected.** Counting an include of any `share/haseen/default/shell/init.sh`
path, as `shellrc_include` does for mise: another prefix's init.sh may
predate the VAPT block.

## Verification

From the worktree's real path through the hermetic wrapper:

- `tools/lint.sh`: lint OK.
- `tests/run.sh --affected 9a9e82ab`: 36 test files (every VAPT file plus
  the ones covering `docs/` and `share/haseen/default/vapt/`), 6587/6587.
- The new tests on the base code (base tree, new tests copied in; the
  runner given a trapless `vapt_oniomarchy_enable_staged`, as `vapt_repo`
  had): `test-vapt-commit` 119/123, `-followups` 75/86, `-landed` 788/791,
  `-net` 242/251, `-services` 142/146, `-workflow` 169/185, `-discovery`
  35/38, `-env` 252/254, `-trust` 234/238, `-oniomarchy-trust` 268/270;
  every failure is a new assertion.
- `tools/check-docs.sh`: OK.
- After the first review round (below): `tools/lint.sh` lint OK;
  `tests/run.sh --affected 9a9e82ab` 36 test files, 6607/6607;
  `tools/check-docs.sh` OK.
- After the second review round: `tools/lint.sh` lint OK;
  `tests/run.sh --affected 9a9e82ab` 36 test files, 6642/6642;
  `tools/check-docs.sh` OK.

## Review

The first round (an independent Sonnet review of the first head) asked for
changes, with two should-fix findings and one nit:

- **A symlinked drop-in directory bypassed section 2.** A package that ships
  `usr/lib/systemd/system/multi-user.target.d` as a link to `/opt/pkg/dropins`,
  whose `subject.conf` holds `Wants=subject.service`, passed the audit: the
  drop-in rule only read regular `*.conf` members under a `.d` parent. The
  same was true of `usr/lib/systemd/user/default.target.d` and
  `etc/systemd/system.control`. Fixed as section 2 now describes: a link under
  a systemd root must be named like a unit. The review suggested refusing
  links whose name ends in `.d`; that leaves `system.control` (which the
  review also listed) and `usr/local/lib/systemd/system` open, so the rule
  allows unit names instead. The new directory-link cases fail without the
  rule (96/106) and pass with it.
- **No test reached `vapt_repo enable`.** The fixture runner called
  `vapt_oniomarchy_enable_staged` directly, so reverting `layer.sh`'s
  `enable)` branch to `vapt_oniomarchy_enable_command` kept
  `test-vapt-oniomarchy-trust.sh` at 270/270. The runner now calls
  `vapt_repo enable` (section 10); with that revert the two interrupted
  approval checks fail (268/270).
- **Nit: docs lines.** The `docs/vapt.md` paragraphs this plan touched are
  re-wrapped, and the `inspect CERT` parenthetical moved after its object.

The second round (an independent Sonnet review of the fixed head) asked for
changes with one should-fix finding:

- **A link above a systemd root bypassed the link rule.** Every root ends in
  `/`, so a link named exactly `usr/local/lib/systemd` (owned by no package)
  pointing at a tree with `system/multi-user.target.d/subject.conf`
  (`Wants=subject.service`) matched no root and the audit called it safe; so
  did `etc/xdg/systemd`, `usr/share/systemd`, `run/systemd` and
  `lib/systemd`. Fixed as section 2 now describes: a link at a root or above
  one is refused. The review suggested refusing every such link; the
  `filesystem` package's `lib -> usr/lib` is one, and the private `-Syuw`
  installs filesystem updates, so a link that maps each root below it onto
  another root stays accepted. The root-link loop fails on the previous head
  (125/141: every new refusal, including `lib -> opt/subject`) and passes
  with the rule (141/141).

