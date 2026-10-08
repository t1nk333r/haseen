# Plan 014: End-to-end acceptance on a real CachyOS guest

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MEDIUM
- **Depends on**: 001-012
- **Category**: release
- **Planned at**: 2026-10-04, initial architecture (docs/architecture.md)
- **State**: IN PROGRESS: three of the four acceptance criteria met in a CachyOS VM on 2026-10-06; "doctor all green" open (see Acceptance)

## Why this matters

Fixture tests prove the plan logic, not the result. omacachy learned this in its plans 016/017.

## Scope

A CachyOS VM (OVMF with Secure Boot in Setup Mode, and a Windows ESP stub) running `./install.sh` with the default layers plus `secureboot`.

The scope originally named `--layers base,desktop,theme,shell,secureboot`. That list predates `omarchy-repo` (plan 024), and `desktop/packages.txt:31` expects that repo to be applied first: without it, herdr and ttfx are built from the AUR instead of installed prebuilt (finding 3). The run therefore used the default set plus `secureboot`: `base,chaotic,omarchy-repo,desktop,theme,shell,secureboot`.

## Acceptance

| Criterion | Result (2026-10-06) |
|---|---|
| The guest boots with Secure Boot enabled | Met. `bootctl status`: `Secure Boot: enabled (user)`; kernel log `Secure boot enabled`; `sbctl status`: Setup Mode disabled, Secure Boot enabled, vendor keys `microsoft`; `sudo haseen secureboot status` all `ok`, exit 0 (config hash enrolled and current, every boot path `#blake2b`, 3 files signed, Windows Boot Manager on the ESP). |
| The desktop logs in | Met, before and after enrollment. greetd + tuigreet with `uwsm start hyprland.desktop`; logging in starts Hyprland with the haseen bar; `hyprctl configerrors` empty; session `Type=wayland Service=greetd`. |
| `haseen doctor` is all green | Not met as written. As the user, doctor is all `ok` except three `warn: … not checked` lines for checks that need root (the ESP is 0700 and sbctl needs root). The same three checks are `ok` in `sudo haseen secureboot status`. `sudo haseen doctor` reports root's own per-user config as missing, which is not meaningful. Whether "not checked" should count against green is an owner decision. |
| Screenshot evidence | Met (list below). |

## Execution record

### Rig

- `tools/lab.sh` drives a separate copy of the owner's lab at `~/.cache/haseen/lab` (`LAB_NAME=haseen-lab`, port 2242), so the owner's Omarchy guest in `~/Work/t1nk33r-lab` and its golden image were not touched.
- The lab gained a `LAB_SECUREBOOT=on|off` knob (owner's lab repo, `lab` `qemu_argv` and `lab.conf`). `on` boots `OVMF_CODE.secboot.4m.fd` with `smm=on` and `cfi.pflash01 secure=on`. The lab's key-less VARS put that firmware in Setup Mode; before enrollment `bootctl` reports `Secure Boot: disabled (setup)`.
- `tools/lab.sh` changes:
  - It forwards `LAB_CACHYOS_RELEASE` and `LAB_SECUREBOOT=on`.
  - It reports a lab checkout without the cachyos arm or the knob as a blocker.
  - It runs `./install.sh` as the guest user, without `sudo`. The previous `sudo ./install.sh` could never work, because `install.sh` calls `require_not_root` (independent review finding).
  - It installs the default layers plus `secureboot`.
- Egress: `LAB_NET=internet`, with the owner's consent, for pacman, the AUR and the theme fetch.

### Guest preparation (lab-side, not haseen)

- **The lab's CachyOS install is inconsistent.** It installs `x86_64_v4` packages (`pacman -Qi glibc`: `Architecture : x86_64_v4`) and syncs `cachyos-*-znver4` databases, but `/etc/pacman.conf` lists only `[cachyos]`, `[core]`, `[extra]` and `[multilib]`. As a result, the first install pulled Arch's generic `rust 1:1.99.0-1` against CachyOS's `llvm-libs 23.1.1-2`, and `rustc -vV` failed with `undefined symbol … version LLVM_23.1`.
  - Repaired in this guest only: `[cachyos-znver4]`, `[cachyos-core-znver4]` and `[cachyos-extra-znver4]` were added before `[cachyos]`, then `pacman -Syu`, then the golden was resealed.
  - This is a defect in the lab's cachyos arm, to be fixed in the lab repo.
- **Passwordless sudo.** `install.sh` escalates with plain `sudo`, and `lab ssh` has no tty, so a guest-only `/etc/sudoers.d/90-haseen-lab` grants the lab user NOPASSWD. Real installs prompt as usual; this run does not exercise the password prompts.
- **Windows stub.** A 24-byte placeholder at `/boot/EFI/Microsoft/Boot/bootmgfw.efi` makes `WINDOWS_ON_ESP` true. Root doctor prints `windows_on_esp=true`, and setup printed the BitLocker warning before enrolling.
- **ufw rate limit.** ufw's `22/tcp LIMIT` (from the CachyOS install) drops ssh after rapid reconnects. Batch guest commands into few connections.

### Install

- The first attempt used the plan's original list without `omarchy-repo`. herdr and ttfx fell to the AUR (finding 3):
  - herdr's `zig fetch` of `gtk4-layer-shell-1.1.0.tar.gz` hung for 44 minutes on an established TLS socket, while `curl` fetched the same URL in 0.43 s. Killing it let the PKGBUILD's retry loop continue.
  - ttfx failed.
- The clean run (`./lab reset`, then `./install.sh --yes --layers base,chaotic,omarchy-repo,desktop,theme,shell,secureboot`) exited 0, with all seven layers applied. The whole job, including the reset and a 30 s wait for the guest, took 136 s. herdr and ttfx came prebuilt from `[omarchy]`.
  - Three packages returned 404 from `cdn77.cachyos.org`; pacman skipped that mirror and used the others.
- The reinstall over the existing install, with the fixes below, also exited 0. Migrations: `no pending migrations`. Hardware quirks: `0 applied, 2 already recorded`.
- `tests/run.sh` inside the guest: `4701/4701 passed` (`SKIP model checks: node not found`).
- Shell memory under software rendering:
  - Before enrollment: 190.6 MiB RSS.
  - At login under Secure Boot (02:59): `rss=188 MiB pss=163 MiB` from doctor. Both readings are within the < 200 MiB budget (§6).
  - The same process (pid 1059) about 30 minutes later: `rss=204 MiB pss=179 MiB`, over the budget. No panel was opened, but two reinstalls in between rewrote files the shell watches (theme, `shell.json`, env.d). Two samples cannot tell a leak from reload growth, so this stays open as finding 6.
- The sidecar runs and feeds the sysusage widget.

### Secure Boot

1. The first `printf 'ENROLL\n' | haseen secureboot setup --yes` signed the chain and passed the verify gate (`boot chain verified: 3 signed file(s)`). It then failed at enrollment: `couldn't sync keys: could not enroll built-in firmware keys: open /sys/firmware/efi/efivars/dbDefault-8be4df61-…: no such file or directory`. Nothing was written; the firmware stayed in Setup Mode. Plan 002's claim that sbctl treats a missing default as empty was wrong (finding 1).
2. After the fix, setup enrolled `--microsoft` only (`With vendor keys from microsoft...✓`, `Setup Mode: ✓ Disabled`).
3. After a reboot under the same firmware, the signed Limine chain booted and Secure Boot was enforced (see Acceptance). No firmware menu step was needed: this OVMF build had Secure Boot on at the first boot after the PK was enrolled.

### Findings

1. **Fixed: `--firmware-builtin` on firmware without default keys** (plan 002, 2026-10-06 section).
   - Cause: sbctl 0.17/0.18 reads `dbDefault` and `KEKDefault` for `--firmware-builtin`, and its missing-variable branch never matches go-uefi's error.
   - Fix: setup passes the flag only when both variables exist; otherwise it warns and runs `sbctl enroll-keys --microsoft`. Owner decision 2026-10-06.
   - Security review (security_sol61) required two changes, both made. First, a non-dry-run under `HASEEN_SYSROOT` is refused, so a fixture cannot silently decide a live enrollment; the only way through is the test-only opt-in `HASEEN_TEST_STUBBED_SUDO=1` (never as root), which is not a privilege boundary. Second, the warning states the actual condition.
   - Regression tests in `tests/test-secureboot.sh`: 218/229 passed before the fix and 239/239 after both changes.
2. **Fixed: doctor reported `shell=not running` while the shell ran.**
   - Cause: `install.sh` handed the installed CLI `HASEEN_PATH=/usr/local/bin/../share/haseen`. The desktop layer wrote that path into `~/.config/uwsm/env.d/10-haseen`, the shell ran as `qs -p /usr/local/bin/../share/haseen/shell`, and doctor compared strings.
   - Fix: `install.sh` normalises the path once. Doctor parses the NUL-separated argv and compares canonical paths (`share/haseen/lib/doctor.sh`).
   - Verified live: after the reinstall, env.d holds `/usr/local/share/haseen` and doctor prints the shell's pid and memory.
   - Tests in `tests/test-paths.sh`: 2/8 passed before the fix and 12/12 after.
3. **Open: `desktop` silently depends on `omarchy-repo`.** `desktop/packages.txt:31` assumes `[omarchy]` is applied first, but `LAYER_REQUIRES` for desktop is `base chaotic`. With a custom `--layers` list that omits it:
   - herdr and ttfx build from the AUR;
   - paru's `--noconfirm` answers the `cargo` provider prompt with its default, which is `rustup` from `cachyos-extra-znver4`;
   - rustup has no toolchain, so ttfx's `prepare()` fails (`rustup could not choose a version of cargo to run`).

   Options for the owner: make desktop require `omarchy-repo`, or have `pkg_install_aur` make sure a working `cargo` exists before building.
4. **Open: a fresh install has no background.** The default theme `greek-noir-akane` is the owner's own and has no images to fetch (`theme-lib.sh:29-32`), so `current/background` does not exist and swaybg shows nothing. That is by design, but two things are wrong:
   - `haseen theme bg next` tells the user to run `haseen theme fetch greek-noir-akane`, which refuses: "not an Omarchy stock theme".
   - The `theme` row in architecture §3 credits the layer with a "pinned background fetch" that the layer does not perform.
5. **Open: the "doctor all green" criterion.** See Acceptance.
6. **Open: shell RSS crossed the budget in one long-running session** (204 MiB after about 30 minutes with two reinstalls, against 188 MiB at login). Needs a controlled measurement: idle with no reinstalls, then after one `shell.json` or theme change.

### Not exercised here (still open from handoff)

polkit dialog, real session lock, display power-off, Ollama on hardware, the live DMS switch, and Secure Boot on real firmware. OVMF has no `dbDefault`; the owner's laptop is the real-firmware target.

### Evidence

The screenshots are in `~/.cache/haseen/lab/run/shots/` on the author's machine and are not committed:

- `p014-before.png`: the guest before install, at a text console.
- `p014-greeter.png`: tuigreet after install.
- `p014-desktop.png`: the haseen bar after login, Secure Boot not yet enrolled.
- `p014-sb-boot.png`: the greeter after enrollment and reboot.
- `p014-sb-desktop.png`: the desktop under Secure Boot.

Logs in the guest: `~/install.log`, `~/reinstall.log`, `~/secureboot-setup.log`, `~/doctor-user.log`, `~/doctor-root.log`.

### Rejected options

- **Faking OVMF default-key variables in the lab:** the VM would pass, but real firmware without defaults would still abort. The owner chose to fix setup instead.
- **Running `install.sh` under `sudo` from `tools/lab.sh`:** `require_not_root` refuses it by design.
- **Piping the guest password to `sudo -S` for `install.sh`:** `run_root` calls plain `sudo`, which needs a tty or a cached timestamp. A guest-only NOPASSWD drop-in is simpler and leaves haseen unchanged.
- **Keeping the plan's original layer list:** that measures an AUR fallback no default install takes (finding 3).
