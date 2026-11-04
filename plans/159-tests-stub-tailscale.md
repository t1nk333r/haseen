# Plan 159: The test suite no longer takes its machine off the tailnet

## Status

- **Priority**: P1
- **Effort**: XS
- **Risk**: LOW (tests only: `tests/lib.sh`'s stub list and one scenario of
  `tests/test-omarchy-remove.sh`; no shipped file changes)
- **Depends on**: 001 (the stub `PATH`), 093 (the remover and its test)
- **Category**: tests
- **Planned at**: 2026-11-04, owner: running the test suite switched
  Tailscale off on the machine that ran it
- **State**: DONE 2026-11-04 (`tests/test-omarchy-remove.sh` records `tailscale
  down` through its stub; the affected set, all 172 files, 18072/18473 in a
  bind mount, the 401 failures all VAPT and 4474/4474 from the real path;
  no tailscaled stop from this run)

## Problem

On a machine with Tailscale installed, every run of
`tests/test-omarchy-remove.sh` (and so every full or affected run that
selects it) ran the real `tailscale down`, and the machine running the suite
left its tailnet until something else brought it back.

The scenario `setup omarchy-remove-tailscale`
(`tests/test-omarchy-remove.sh:534-543` on `3e2835b`) runs
`capture fake omarchy-remove-service-tailscale` without `--dry-run`, and
stubs only `systemctl` (`:538`). The command's first step is
`have tailscale && { quiet tailscale down || true; }`
(`share/haseen/omarchy/bin/omarchy-remove-service-tailscale:37`), and outside
a dry run `quiet` runs its command with stderr discarded
(`share/haseen/omarchy/remove-lib.sh:33-39`).

`tailscale` was not in `STUBBED_CMDS` (`tests/lib.sh:23-28`), and the sandbox
`PATH` is `$SANDBOX/stubs:$REPO/bin:/usr/bin:/bin` (`tests/lib.sh:46`), so
`have tailscale` found the installed `/usr/bin/tailscale`. The sandbox cuts
off the session bus and the runtime directory (`tests/lib.sh:52-53`), but the
tailscale CLI talks to tailscaled over its own socket, which nothing in the
sandbox redirects. Where the user running the suite is tailscaled's operator,
`tailscale down` succeeds; elsewhere it fails, and `quiet` and `|| true` hid
both outcomes, so no assertion ever noticed. CI was unaffected only because
its container has no `tailscale` (`.github/workflows/ci.yml:39`,
`ARCH_PACKAGES`).

## Findings

- tailscaled's journal on the owner's workstation has 98
  `EditPrefs: MaskedPrefs{WantRunning=false}` entries since the journal
  begins (2026-08-31): one before 2026-10-20 and 97 from then to 2026-11-04 10:23.
- Each `tests/.out/omarchy-remove-tailscale` sandbox still on disk in that
  machine's checkouts matches one of those entries to within one second,
  including two on 2026-11-04 (09:41:37 and 09:58:52). One more entry, at
  10:15:46, has no sandbox left on disk.
- The scenario arrived with plan 093 (planned and done 2026-10-20, merged as
  `912a682`); the first of the 97 entries is from the evening of 2026-10-20.

## What changed

- **`tests/lib.sh`**: `tailscale` joins `STUBBED_CMDS`, so every sandbox has
  the fail-loud stub (`STUB-CALLED`, exit 97) in front of the real binary,
  with a comment saying why.
- **`tests/test-omarchy-remove.sh`**: the scenario stubs `tailscale` as a
  recorder in the same style as its `systemctl` stub and asserts that the
  first thing the command does is `tailscale down`, so the test still proves
  the remover leaves the tailnet.

The other tailscale paths in the tests were already stubbed:
`tests/test-omarchy-launch.sh:69` (its `setup` answers `exit 1`, used by the
`installed-service-tailscale` probes at `:569-574` and the install dry run at
`:148`), `tests/test-omarchy-restart.sh:716-754` (Taildrop send and receive,
each step behind its own stub) and the plugin-tree scenario of
`tests/test-omarchy-remove.sh` (`stub tailscale "exit 0"`, `:553-555`). The
remaining callers are `--help` sweeps, dry runs or the read-only
`tailscale status --json` of haseen.omaconnect
(`share/haseen/shell/plugins/haseen.omaconnect/Service.qml:536`), which no
test triggers.

Adding a stub makes `have tailscale` true in every sandbox, also in CI where
it was false. The dry runs then print `DRYRUN: tailscale down` instead of
skipping it, which no assertion forbids.

## Survey: other state-changing commands a test could reach

Not fixed here; for the owner to decide. Each command below is missing from
`STUBBED_CMDS` and talks to something the sandbox does not cut off (the
system bus, a device node, or a daemon socket of its own). Today every test
that runs these non-dry installs its own stub, so no current scenario was
found to reach the real one; the risk is the next scenario that forgets,
as the tailscale one did. Line numbers are those of `3e2835b`.

| Command | What it reaches | Shipped caller that changes state outside `--dry-run` | Tests today |
|---------|-----------------|------------------------------------------------------|-------------|
| `ssh` | The real `~/.ssh` (OpenSSH reads the passwd home, not `$HOME`) and the inherited `SSH_AUTH_SOCK`, which `sandbox()` keeps | `share/haseen/omarchy/bin/omarchy-theme-set-herdr-machines:73`; `share/haseen/default/shell/functions.sh:124`, `:172` | stubbed per scenario: `tests/test-omarchy-45.sh:503`, `:663`, `tests/test-agent-accounts.sh:543` |
| `nmcli` | NetworkManager on the system bus | `bin/haseen-network-band:154-156` (`connection up`, `modify` on failure); `bin/haseen-vpn-openconnect:294`, `:326` | stubbed in `tests/test-network-panel.sh:191`, `:279`, `:310`, `:319`; `tests/test-adopted-tools.sh:257-262` stops at the usage check (`bin/haseen-vpn-openconnect:128`) before any `nmcli` |
| `bluetoothctl` | BlueZ on the system bus | `share/haseen/omarchy/bin/omarchy-bluetooth-power:54` (`power on`, not through `run`); `share/haseen/omarchy/bin/omarchy-bluetooth-device:52`, `:55` | stubbed in `tests/test-omarchy-system.sh:452` |
| `rfkill` | `/dev/rfkill`, writable by the seat's user through its uaccess ACL, so no root is needed | `share/haseen/omarchy/bin/omarchy-bluetooth-power:49`, `:62`, `:65`; `bin/haseen-restart:46`, `:58` | stubbed in `tests/test-omarchy-system.sh:454`; `tests/test-catalog.sh:354-363` runs `haseen restart` only with `--dry-run` |
| `loginctl` | logind on the system bus; the test process still belongs to the user's login | `bin/haseen-system:111` (`lock-session` when the shell's IPC fails, as it does under the `qs` stub); `share/haseen/shell/plugins/haseen.session/Panel.qml:138` | only `--dry-run` (`tests/test-omarchy45-boot.sh:374`) and a source grep (`tests/test-surfaces.sh:207`) |
| `powerprofilesctl` | power-profiles-daemon on the system bus | `bin/haseen-powerprofile-set:104` (through `run`) | stubbed for the whole file in `tests/test-powerprofile.sh:14` |
| `nordvpn` | nordvpnd's own socket | `share/haseen/shell/plugins/haseen.vpn/NordVpnBackend.qml:206`, `:212` | no test starts the plugin's engine; `tests/test-adopted-tools.sh:120` runs its pure JS only |

Checked and not a risk from the sandbox: `kdeconnect-cli`, `gdbus --session`,
`busctl --user`, `playerctl` (session bus, dead at `tests/lib.sh:52`),
`wpctl` and `pactl` (sockets under `XDG_RUNTIME_DIR`, moved at `:53`),
`wtype`, `wl-copy` and `ydotool` (no Wayland display), and `timedatectl`,
`usermod`, `keyd reload` and `uwsm stop`, which change state only through
`run_root` or `run` with `sudo` or under a dry run. The `busctl --system`
calls (`share/haseen/omarchy/bin/omarchy-network-wifi-connected:20`, `:23`,
`omarchy-system-lid-inhibit:64`, `omarchy-system-sleep-lock:43`) only read.

Two ways to close the gap, for a later plan:

- add the table's commands to `STUBBED_CMDS`; every scenario that needs an
  answer already installs its own stub, so only an unforeseen call changes;
- in `sandbox()`, point `DBUS_SYSTEM_BUS_ADDRESS` at a dead socket and unset
  `SSH_AUTH_SOCK`, which closes the system bus as a class rather than by
  command name. A test that reads the system bus on purpose would then need
  a fake.

## Verification

- `tests/run.sh --affected` against `3e2835b`: `tests/lib.sh` is global, so
  the selection is all 172 test files. Run at 10:27:18 local time from a
  bwrap bind of the worktree at `/tmp/s159` (the worktree's long path breaks
  the tests' Unix sockets): 18072/18473. All 401 failures are in 19
  `test-vapt-*.sh` files, and only under that bind mount: from the
  worktree's real path those 19 files, with `test-capture-upload.sh` (which
  skips a check under bwrap), pass 4474/4474. Every other file passed.
- In that run the scenario's call log begins `tailscale down`, written by
  the stub at 10:35:53, and tailscaled logged no `WantRunning=false` from
  10:27:18 until 10:38:55.
- The 10:38:55 entry, and the 10:15:46 one before the run, did not come from
  this branch. At 10:38:55 this run was in `test-update-haseen.sh` and the
  VAPT files, which call no `tailscale`, and no other test sandbox on the
  machine was written between 10:37:30 and 10:40:30. Both entries fall
  inside review rounds of PR #119 (10:07-10:20 and 10:31-10:42), whose
  reviewer ran `tests/run.sh --affected` on a branch without this fix in a
  scratch copy it then removed. That selection includes
  `tests/test-omarchy-remove.sh`, because the PR changes a plugin
  `manifest.json` (`tests/test-omarchy-remove.sh:15`). Any branch without
  this fix that selects the file keeps doing it until it rebases.
- `tools/lint.sh`: lint OK. `tools/check-docs.sh`: OK.

## Rejected options

- **Run the scenario with `--dry-run`.** The dry run is already covered for
  every remover (`tests/test-omarchy-remove.sh:105-116`); this scenario
  exists to check what a real run calls (`haseen-remove`, `systemctl`, the
  web app), which only a real run with recorders shows.
- **Stub `tailscale` in the scenario only.** It fixes this scenario but not
  the next one: the fail-loud default in `STUBBED_CMDS` is what makes a
  forgotten stub fail inside the test instead of reaching tailscaled.
- **Point the CLI at a dead socket instead** (`tailscale --socket=`). The
  remover calls `tailscale` with no flags, and there is no sandbox-wide
  setting that every call would honour.
- **Fix the survey's commands in this change.** The owner asked for the
  tailscale fix alone and a list of the rest to decide on.
