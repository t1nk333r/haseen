# Plan 002: Secure Boot layer for Windows dual boot

## Status

- **Priority**: P1
- **Effort**: L
- **Risk**: HIGH (firmware keys)
- **Depends on**: 001
- **Category**: security
- **Planned at**: 2026-10-04, initial architecture (docs/architecture.md)
- **State**: DONE 2026-10-04 for the code and fixture tests. Enrollment on real firmware is the owner's step and is part of plan 014. Integrator follow-ups: `layer_precheck` was added to the core so a BIOS machine is refused before sbctl is installed, and the hook's `Exec` is now rendered from the install prefix (`@HASEEN_BIN@`), so the PKGBUILD phase needs no edit.

## Why this matters

Requirement 8. Anti-cheat on Windows (Vanguard, FACEIT, EA Javelin) requires Secure Boot to be on. Neither Omarchy nor omacachy enrolls keys: Omarchy's manual tells users to turn Secure Boot off.

## Scope

- `share/haseen/layers/secureboot/`: `layer.sh`, a pacman hook and a re-sign script.
- `bin/haseen-secureboot-{status,setup,sign}`.
- See docs/architecture.md §8 for the full model.

## Acceptance

- Fixture tests for Limine and systemd-boot, Setup Mode and enabled, with and without Windows on the ESP.
- Dry-run is pure.
- Refuses outside Setup Mode.
- Typed confirmation is required.
- The BitLocker warning is printed when Windows is present.
- Microsoft and firmware-builtin keys are always enrolled.
- Real-hardware enrollment is an owner acceptance step (plan 014).

## Execution record

### What changed

- `share/haseen/layers/secureboot/`
  - `layer.sh`: `LAYER_REQUIRES=(base)`, `LAYER_DISTROS=(cachyos arch omarchy)`. `layer_apply` installs the hook (only when it differs) and prints the next step; it refuses BIOS and never creates or enrolls keys. `layer_status` returns 0 enforcing and signed, 1 sbctl or hook missing, 2 installed but incomplete. `layer_remove` deletes the hook only.
  - `secureboot.sh`: the shared logic (facts through `sysroot_path`, the verify classifier, Limine checks, warnings, `sb_report`, the root re-exec).
  - `limine-hash-assets.sh`: root helper that adds or refreshes the `#blake2b` of `wallpaper:`/`term_font:` lines. Kernel and module paths are never re-hashed.
  - `packages.txt` (`sbctl`) and `files/zz-haseen-secureboot.hook`.
- `bin/haseen-secureboot-status`: read-only, never escalates. Exit 0 only when Secure Boot is enabled, the boot chain verifies signed and, on Limine, the config hash is enrolled, current and every boot path is hashed.
- `bin/haseen-secureboot-setup`: refuses BIOS, NixOS and anything outside Setup Mode (prints the firmware steps, exit 1). Then: sbctl present and >= 0.17, Limine needs limine-entry-tool, rerun as root when the ESP is 0700. Order: plan, plain `confirm` (answered by `--yes`), create-keys if missing, sign per bootloader, verify gate, BitLocker and TPM2 warnings, `confirm_typed … ENROLL` (`--yes` cannot answer it), `sbctl enroll-keys --microsoft --firmware-builtin`, firmware instructions.
- `bin/haseen-secureboot-sign [--hook]`: Limine asset hashes, `limine-enroll-config`, fallback refresh. It signs and tracks (`-s`) boot-chain files sbctl does not track yet, runs `sbctl sign-all` and verifies. With `--hook` it exits 0 without doing anything when there is no UEFI, no sbctl or no keys, and it leaves sign-all to `zz-sbctl.hook` when that hook is active.
- `tests/test-secureboot.sh` (205 assertions) and the fixtures `tests/fixtures/sb-{limine-setup-windows,sdboot-setup-tpm,sdboot-enabled,grub-setup}` (each with `expected.preflight`, so `test-core.sh` checks preflight on them too).

### Decisions and their evidence

1. **`ENABLE_ENROLL_LIMINE_CONFIG` cannot be a drop-in.** limine-entry-tool's `load_config` reads the `/etc/limine-entry-tool.d/*.conf` drop-ins and then resets the key ("Do not use ENABLE_ENROLL_LIMINE_CONFIG in any random configs", `ENABLE_ENROLL_LIMINE_CONFIG=""`). This is `/usr/lib/limine/limine-common-functions:143-144`, from limine-mkinitcpio-hook 1.38.0-1.1 on the reference machine. Only `/etc/default/limine` (loaded last, line 146-149) can set it, and the CachyOS wiki also puts it there. So setup appends a commented `ENABLE_ENROLL_LIMINE_CONFIG=yes` there, and only when the effective value is not `yes`. `ENABLE_VERIFICATION` does work as a drop-in, so it goes to `/etc/limine-entry-tool.d/haseen-secureboot.conf`, and only when the effective value is not already `yes` (the package's `/etc/limine-entry-tool.conf` ships `yes`). `sb_limine_value` reproduces the tool's load order and quote stripping. A fixture drop-in that sets the key proves it is ignored (test "status: drop-in enrollment does not count").
2. **Limine under Secure Boot** (`/usr/share/doc/limine/USAGE.md:24-43`, `CONFIG.md:144-146,422-427`, Limine 12.8.0):
   - with a config hash enrolled, any boot path without `#blake2b` panics;
   - wallpapers and fonts without a hash are skipped;
   - `hash_mismatch_panic` is forced on, so a *stale* wallpaper hash panics.

   Consequences:
   - the wallpaper is hashed before enrollment, and `sign` refreshes stale asset hashes;
   - the verify gate refuses enrollment on any unhashed `path`/`module_path`/… in a non-EFI entry. `protocol: efi` entries are exempt, because the firmware checks those;
   - the gate also refuses a config file that would shadow `ESP/limine.conf` (CONFIG.md:5-21).
3. **Detecting enrollment.** Limine binaries carry `++CONFIG_B2SUM_SIGNATURE++` followed by 128 hex digits, all `0` when nothing is enrolled. This was observed in `/usr/share/limine/BOOTX64.EFI` with `grep -a -o … | od -c`. `limine enroll-config` writes the config's b2sum there (limine-common-functions:367). Status compares that value with `b2sum limine.conf`, for the main binary and for a Limine fallback.
4. **The fallback is a copy of the enrolled binary, not the raw binary signed.**
   - `limine-install` copies the raw package binary to `EFI/BOOT/BOOTX64.EFI` (`/usr/bin/limine-install:299-336,391-401`), and limine-entry-tool.conf notes that "the default fallback is not signed automatically by limine-update".
   - omacachy signs that raw copy (`install-omarchy-quattro.sh:2016-2023`). But USAGE.md:39-43 says "If no config checksum is enrolled, Limine treats Secure Boot as inactive". A signed raw Limine therefore lets anyone who can write the ESP boot an unhashed kernel and initramfs: a Secure Boot bypass.
   - So setup and sign `cp` the enrolled, signed main binary over a Limine fallback, then `sbctl sign -s` it (that step only tracks it; the binary is already signed). A fallback that is not Limine (Windows, systemd-boot) is never touched.
5. **What `zz-sbctl.hook` already covers.**
   - Arch's PKGBUILD installs `contrib/pacman/ZZ-sbctl.hook` as `/usr/share/libalpm/hooks/zz-sbctl.hook` (gitlab.archlinux.org/archlinux/packaging/packages/sbctl, `pkgver=0.18`). Its Path targets are `boot/* efi/* usr/lib/modules/*/vmlinuz usr/lib/modules/*/extramodules/* usr/lib/**/efi/*.efi* usr/share/**/*.efi*`, and it runs `sbctl sign-all -g`. sbctl also ships `/usr/lib/initcpio/post/sbctl`, which signs every UKI mkinitcpio builds.
   - It re-signs *tracked* kernels and loaders. It does not cover: Limine config re-enrollment, the fallback refresh, or new untracked files (a newly installed `linux-lts`).
   - Our hook adds exactly those: `--hook` runs `sbctl sign -s` only for untracked boot-chain files and leaves `sign-all` to zz-sbctl (test "hook: only the new kernel is signed and tracked" asserts the full output). When zz-sbctl is masked, ours runs `sign-all` itself.
6. **Hook order.** pacman sorts hooks by file name. On the reference machine the Limine-side hooks are:
   - `80-limine-efi-deploy.hook` (`limine-install`);
   - `/etc/pacman.d/hooks/90-mkinitcpio-install.hook` (limine-mkinitcpio-install, whose post hooks enroll the config);
   - `99-omarchy-limine.hook`, which copies the raw `/usr/share/limine/BOOTX64.EFI` over `EFI/limine/limine_x64.efi` after every limine upgrade and so undoes enrollment and signature.

   `zz-haseen-secureboot.hook` sorts after all of them and before `zz-sbctl.hook` (`h` < `s`), so limine.conf is final when we re-enroll, and sbctl's sign-all follows. The test suite asserts this order with `LC_ALL=C sort`. Our Path targets are a superset of zz-sbctl's (asserted line by line), so ours always runs first when sbctl's runs.
7. **Microsoft 2023 CAs.** The question was whether `--microsoft` in current sbctl enrolls the 2023 certificates. It does. Evidence is from the sbctl source, cloned 2026-10-04 at `3ae0c7e…` on master:
   - [commit 6df94e4](https://github.com/Foxboron/sbctl/commit/6df94e4c8ed7bb8eeaca32370cbb87ed867eb1d5) "certs: import 2023 Microsoft keys" (2025-04-26, sourced from microsoft/secureboot_objects) adds `certs/microsoft/db/{windows uefi ca 2023,microsoft uefi ca 2023,microsoft option rom uefi ca 2023}.der` and `certs/microsoft/KEK/microsoft corporation kek 2k ca 2023.der`, next to the 2011 ones;
   - `git tag --contains 6df94e4` lists 0.17 and 0.18;
   - `certs/certs.go` `GetOEMCerts` appends every file in the directory, and `cmd/sbctl/enroll-keys.go:152-167` appends the db and KEK sets for `microsoft`.

   So sbctl >= 0.17 enrolls the 2011 *and* 2023 CAs (Arch ships 0.18-2). Setup refuses an older sbctl, because it would enroll only the CAs that expired in June 2026. `--firmware-builtin` reads the volatile `dbDefault`/`KEKDefault` and treats a missing default as empty (`certs/builtin.go`), so enrolling both is always possible.
8. **sbctl output and permissions.**
   - `sbctl verify --json` prints `[{file_name, is_signed}]` through `json.MarshalIndent` (`cmd/sbctl/verify.go`, `main.go:69-79`), with `is_signed` 1/0/-1. It walks the whole ESP, so Microsoft's own binaries show as unsigned (by our key) and are ignored by the classifier. On Limine, plain kernels are checked by hash, not signature.
   - Key files are written 0400 (`backend/backend.go:99`) in 0755 directories, and `files.json` is 0644 (`database.go:45`). Key presence and the tracked list can therefore be read without root. Signatures cannot: sbctl itself fails with "sbctl requires root" (`main.go:196`).
9. **Root.** `/boot` is `drwx------ root` on the reference machine (`ls -ld /boot`), and `/etc/crypttab` is unreadable as a user. Rather than escalating read by read, setup and manual sign rerun themselves as root once (`sb_reexec_as_root`, never under a sysroot or `--dry-run`). Status never escalates; it says which checks need root.
10. **Confirmation order.** Architecture §8 says enrollment "refuses if any boot file sbctl tracks is unsigned", so the order is sign, verify, then enroll. The typed `ENROLL` comes right before enrollment, after the gate and after the BitLocker and TPM2 warnings. The earlier plain question covers key creation and signing, which are reversible.

### Evidence that ran

- `/tmp/tools/shellcheck --severity=warning -x bin/haseen-secureboot-* share/haseen/layers/secureboot/*.sh tests/test-secureboot.sh` → no findings. `bash -n` passes on all seven shell files. `jq empty` passes on both `files.json` fixtures.
- `tests/run.sh tests/test-secureboot.sh tests/test-core.sh` → `237/237 passed` (secureboot 205, core 32, including `expected.preflight` for the four new fixtures).
- Mutation check on a scratch copy of the tree. Each mutation turned tests red:
  - honouring the drop-in for `ENABLE_ENROLL_LIMINE_CONFIG` → 4 failures;
  - dropping the tracked/boot-chain blocker → 4;
  - removing the `protocol: efi` exemption → 3;
  - reordering the hook names → 1.
- `grep -rn 'sudo ' bin share | grep -v common.sh`: no hit in any secureboot file.
- Live machine, normal user, no sudo (Omarchy 4.0.4, Limine 12.8.0, firmware in Setup Mode, sbctl not installed, `/boot` 0700):

```
$ haseen secureboot status; echo rc=$?
ok: firmware: UEFI
warn: secure boot: Setup Mode, no keys enrolled (next: haseen secureboot setup)
ok: bootloader: limine, ESP /boot (firmware LoaderInfo: Limine 12.8.0)
warn: windows: not checked (ESP /boot is readable only by root)
missing: sbctl: not installed (haseen layer apply secureboot)
missing: keys: none (haseen secureboot setup)
warn: limine: ENABLE_ENROLL_LIMINE_CONFIG is not yes in /etc/default/limine (setup sets it)
warn: limine: enrollment not checked (ESP /boot is readable only by root)
warn: signatures: not checked (sbctl not installed)
warn: luks: TPM2 binding not checked (/etc/crypttab is readable only by root)
missing: pacman hook: /etc/pacman.d/hooks/zz-haseen-secureboot.hook (haseen layer apply secureboot)
rc=1
$ haseen secureboot sign --hook; echo rc=$?
haseen: no Secure Boot keys yet; nothing to sign
rc=0
```

### Rejected options

- *A drop-in for `ENABLE_ENROLL_LIMINE_CONFIG`*: the tool ignores it (decision 1).
- *Signing the raw Limine fallback, as omacachy does*: a signed Limine without an enrolled config enforces nothing (decision 4).
- *`sbctl sign -s` on UKIs under Limine*: signing after limine-entry-tool hashed the UKI breaks its `#blake2b`. mkinitcpio's sbctl post hook signs before hashing (limine-mkinitcpio-install:205 says so), and setup runs `limine-update` to rebuild them.
- *Re-hashing kernel/module paths automatically*: re-hashing whatever is on the ESP defeats the check. Only wallpaper and `term_font` are re-hashed.
- *Limine without limine-entry-tool*: the next kernel update would leave the enrolled config stale and Limine would panic. Setup refuses and names `limine-mkinitcpio-hook`.
- *Calling sbctl from status under a fixture, or with sudo*: status is read-only and never escalates, and core says live probes skip under a sysroot. Tests replace the `sb_sbctl_readable`/`sb_sbctl_query` seam to exercise the exit-0 path.
- *`sudo cat` per privileged read*: one root re-exec is simpler and keeps every read on the same code path.
- *jq for sbctl's JSON*: the reference machine's `jq` is jaq 2.3.0. sbctl's MarshalIndent shape is fixed, so a grep-based parser is enough.
- *Typed confirmation up front*: it would precede the verify gate, so the user would confirm before knowing whether enrollment is safe.
- *Omitting `--firmware-builtin` on ASUS/Gigabyte* (CachyOS wiki caution): the owner requires both flags always. Recorded as a risk below.

### Open risks

- Real-hardware enrollment, and `haseen secureboot status` run as root with sbctl installed, are **unverified**. This session has no sudo; owner acceptance is plan 014.
- CachyOS wiki: on some ASUS/Gigabyte boards `--firmware-builtin` duplicates `builtin-db` entries and the firmware reports a Secure Boot Violation once Secure Boot is turned on. Setup's closing text gives the way back (turn Secure Boot off in the same menu). Re-enrolling without the flag is deliberately not offered.
- GRUB follows the CachyOS wiki (`--modules=tpm --disable-shim-lock`) and is untested. Under lockdown, GRUB may need more embedded modules. Setup prints the weakest-path warning.
- `limine-update` and `limine-install` run outside pacman (manually, limine-snapper-sync) with `ENABLE_LIMINE_FALLBACK=yes` put a raw, unsigned fallback back. That fails closed: the firmware refuses it and the main entry is unaffected. The next `haseen secureboot sign` or hook run repairs it.
- Omarchy rewriting limine.conf outside pacman can drop the wallpaper hash. The wallpaper is then skipped, which is cosmetic, until the next sign.
- The hook's `Exec` hard-codes `/usr/local/bin/haseen`. The PKGBUILD phase (PREFIX `/usr`) must rewrite it.
- `sb_sbctl_version` looks for the `sbctl` package only, so `sbctl-git` reads as "not installed".
- The runner installs `packages.txt` before `layer_apply` runs, so on a BIOS machine sbctl is installed and then the layer refuses. See the core request in the report.
