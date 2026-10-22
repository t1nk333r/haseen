# shellcheck shell=bash
# haseen:covers bin/haseen-layer-apply bin/haseen-secureboot-* share/haseen/VERSION
# haseen:covers share/haseen/layers/base/** share/haseen/layers/secureboot/**
# haseen:covers share/haseen/lib/layers.sh share/haseen/lib/packages.sh
# haseen:covers share/haseen/lib/preflight.sh
# haseen:covers tests/fixtures/{arch-bios,cachyos-grub-plain,cachyos-limine-luks-dualboot,nixos}/**
# haseen:covers tests/fixtures/sb-*/**
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# Secure Boot layer (plan 002): setup decisions per bootloader fixture, the
# refusals (BIOS, NixOS, outside Setup Mode, old sbctl, unready boot chain), the typed
# ENROLL confirmation that --yes cannot answer, BitLocker and TPM2 warnings,
# the Limine config/hash handling, the pacman hook, idempotency and dry-run
# purity. Every fixture is checksummed before and after: nothing may write it.

SB_LIB="$HASEEN_PATH/layers/secureboot"
FX_LIMINE="$FIXTURES/sb-limine-setup-windows"
FX_SDTPM="$FIXTURES/sb-sdboot-setup-tpm"
FX_SDON="$FIXTURES/sb-sdboot-enabled"
FX_GRUB="$FIXTURES/sb-grub-setup"

fixtures_sum() { (cd "$FIXTURES" && find . -type f -print0 | sort -z | xargs -0 b2sum | b2sum); }
FIXTURES_BEFORE="$(fixtures_sum)"

# sb_layer FIXTURE VERB — run the secureboot layer alone through the real
# runner. `haseen layer apply secureboot` would also resolve `base`, which
# belongs to another slice and is tested there.
sb_layer() {
    local fx="$1" verb="$2"
    capture env HASEEN_SYSROOT="$fx" bash -c 'source "$HASEEN_PATH/lib/layers.sh"; "layer_run_$1" secureboot' _ "$verb"
}

# sb_layer_root FIXTURE VERB — sb_layer in a user namespace that maps this
# user to root, after plant_tree: the hook's haseen is then a root-owned file.
sb_layer_root() {
    local fx="$1" verb="$2"
    capture env HASEEN_SYSROOT="$fx" unshare --map-root-user bash -c 'source "$HASEEN_PATH/lib/layers.sh"; "layer_run_$1" secureboot' _ "$verb"
}
userns() { unshare --map-root-user true 2>/dev/null; }
# skipped FN WHAT WHY — FN's checks were not run: one SKIP line in the log
# with how many there are, counted from FN itself, and why (plan 111).
skipped() { echo "  SKIP $(declare -f "$1" | grep -cE '^[[:space:]]*assert_') $2: $3" >&2; }

# plant_tree ROOT — this tree's router, sign command, libraries and layer at
# their own paths inside ROOT, nothing in ROOT writable by group or others.
plant_tree() {
    mkdir -p "$1$REPO/bin" "$1$REPO/share/haseen/lib" "$1$REPO/share/haseen/layers"
    cp "$REPO/bin/haseen" "$REPO/bin/haseen-secureboot-sign" "$1$REPO/bin/"
    cp "$REPO/share/haseen/lib/"* "$1$REPO/share/haseen/lib/"
    cp -R "$REPO/share/haseen/layers/secureboot" "$1$REPO/share/haseen/layers/"
    chmod -R go-w "$1"
}

# root_stat on|off — stat(1) answers root_node_stat (lib/common.sh) as if
# root owned every file, modes kept, so the hook's ownership decisions run
# where user namespaces do not (CI's container). Every other call is real.
REAL_STAT="$(command -v stat)"
root_stat() {
    if [[ $1 == off ]]; then
        rm -f "$SANDBOX/stubs/stat"
        return 0
    fi
    stub stat "$(sed "s|@STAT@|$REAL_STAT|g" <<'EOF'
if [ "$1" = --printf ] && [ "$2" = '%u %a %F\t%n\0' ]; then
    shift 2
    exec @STAT@ --printf '0 %a %F\t%n\0' "$@"
fi
exec @STAT@ "$@"
EOF
)"
}

# scratch NAME FIXTURE — a writable copy of FIXTURE as $SANDBOX/NAME.
scratch() {
    cp -a "$2" "$SANDBOX/$1"
    printf '%s\n' "$SANDBOX/$1"
}

# recorder — sudo that records its argv in $SANDBOX/sudo.log and runs nothing.
# `sbctl verify --json` answers with $SANDBOX/verify.json; the file writers
# (tee, and append_root_file's sh -c around tee) drain stdin.
# With HASEEN_TEST_STUBBED_SUDO set and sudo resolving into tests/.out (the
# stub dir), setup lets a non-dry run under HASEEN_SYSROOT proceed.
recorder() {
    : >"$SANDBOX/sudo.log"
    stub sudo "printf '%s\n' \"\$*\" >>'$SANDBOX/sudo.log'
case \"\$*\" in
'sbctl verify --json') cat '$SANDBOX/verify.json' ;;
tee* | 'sh -c'*) cat >/dev/null ;;
esac
exit 0"
    export HASEEN_TEST_STUBBED_SUDO=1
}

# verify_json FILE[=STATE]... — `sbctl verify --json` output in sbctl's own
# MarshalIndent shape. STATE is is_signed: 1 (default), 0 unsigned, -1 missing.
verify_json() {
    local e sep=""
    printf '[\n'
    for e in "$@"; do
        [[ $e == *=* ]] || e="$e=1"
        printf '%s  {\n    "file_name": "%s",\n    "is_signed": %s\n  }' "$sep" "${e%=*}" "${e##*=}"
        sep=$',\n'
    done
    printf '\n]\n'
}

# before LABEL HAYSTACK FIRST SECOND — FIRST occurs, and before SECOND.
before() {
    local head="${2%%"$4"*}"
    if [[ $2 == *"$4"* && $head == *"$3"* ]]; then _pass; else _fail "$1" "expected '$3' before '$4'"; fi
}

# --- router and help ---------------------------------------------------------
sandbox sb-router
capture haseen secureboot
assert_contains "group lists status" "$OUTPUT" "haseen secureboot status"
assert_contains "group lists setup" "$OUTPUT" "haseen secureboot setup [--dry-run] [--yes]"
assert_contains "group lists sign" "$OUTPUT" "haseen secureboot sign [--hook]"
for v in status setup sign; do
    capture haseen secureboot "$v" --help
    assert_status "$v --help" 0 "$STATUS"
    assert_contains "$v --help usage" "$OUTPUT" "Usage: haseen secureboot $v"
done
capture env HASEEN_SYSROOT="$FX_SDON" haseen secureboot status extra
assert_status "status rejects arguments" 2 "$STATUS"

# --- setup: Limine + Setup Mode + Windows on the ESP --------------------------
sandbox sb-limine
capture env HASEEN_SYSROOT="$FX_LIMINE" haseen secureboot setup --dry-run
assert_status "limine dry-run exit" 0 "$STATUS"
assert_dry_pure "limine setup" "$OUTPUT"
assert_contains "limine: keys created" "$OUTPUT" "DRYRUN: sudo sbctl create-keys"
assert_contains "limine: enrollment key appended to /etc/default/limine" "$OUTPUT" \
    "DRYRUN: append to /etc/default/limine:"
assert_contains "limine: enrollment set to yes" "$OUTPUT" "    | ENABLE_ENROLL_LIMINE_CONFIG=yes"
assert_not_contains "limine: ENABLE_VERIFICATION already yes, no drop-in" "$OUTPUT" "haseen-secureboot.conf"
splash_hash="$(b2sum "$FX_LIMINE/boot/limine-splash.png" | cut -d' ' -f1)"
assert_contains "limine: wallpaper gets its blake2b" "$OUTPUT" \
    "limine.conf:2 (missing hash): wallpaper: boot():/limine-splash.png#$splash_hash"
assert_contains "limine: asset helper runs as root" "$OUTPUT" \
    "DRYRUN: sudo $SB_LIB/limine-hash-assets.sh /boot/limine.conf /boot"
assert_contains "limine: limine-update" "$OUTPUT" "DRYRUN: sudo limine-update"
assert_contains "limine: config enrolled" "$OUTPUT" "DRYRUN: sudo limine-enroll-config"
assert_contains "limine: main binary signed and tracked" "$OUTPUT" \
    "DRYRUN: sudo sbctl sign -s /boot/EFI/limine/limine_x64.efi"
assert_contains "limine: fallback replaced by the enrolled binary" "$OUTPUT" \
    "DRYRUN: sudo cp /boot/EFI/limine/limine_x64.efi /boot/EFI/BOOT/BOOTX64.EFI"
assert_contains "limine: fallback signed and tracked" "$OUTPUT" \
    "DRYRUN: sudo sbctl sign -s /boot/EFI/BOOT/BOOTX64.EFI"
assert_not_contains "limine: kernels are hash-checked, not signed" "$OUTPUT" "sign -s /boot/vmlinuz"
assert_contains "limine: microsoft + firmware keys always" "$OUTPUT" \
    "DRYRUN: sudo sbctl enroll-keys --microsoft --firmware-builtin"
assert_contains "limine: BitLocker recovery URL" "$OUTPUT" "https://aka.ms/myrecoverykey"
before "BitLocker warning precedes enrollment" "$OUTPUT" "PCR 7" "sudo sbctl enroll-keys"
before "enrollment hash set before limine-update" "$OUTPUT" "ENABLE_ENROLL_LIMINE_CONFIG=yes" "limine-update"
before "wallpaper hashed before enrollment" "$OUTPUT" "limine-hash-assets.sh" "limine-enroll-config"
before "Limine enrolled before the fallback copy" "$OUTPUT" "limine-enroll-config" "sudo cp "
before "verify gate precedes enrollment" "$OUTPUT" "sbctl verify --json" "sudo sbctl enroll-keys"
assert_not_contains "limine: no TPM2 warning without a TPM2 binding" "$OUTPUT" "systemd-cryptenroll"

# /etc/default/limine already enrolls, and the config already verifies:
# nothing is appended a second time.
root="$(scratch limine-enrolled "$FX_LIMINE")"
printf 'ENABLE_ENROLL_LIMINE_CONFIG="yes"\n' >>"$root/etc/default/limine"
capture env HASEEN_SYSROOT="$root" haseen secureboot setup --dry-run
assert_not_contains "limine: no second append" "$OUTPUT" "append to /etc/default/limine"
# Without ENABLE_VERIFICATION anywhere, the drop-in supplies it.
sed -i '/^ENABLE_VERIFICATION/d' "$root/etc/limine-entry-tool.conf"
capture env HASEEN_SYSROOT="$root" haseen secureboot setup --dry-run
assert_contains "limine: verification drop-in" "$OUTPUT" \
    "DRYRUN: write /etc/limine-entry-tool.d/haseen-secureboot.conf (mode 0644):"
assert_contains "limine: drop-in content" "$OUTPUT" "    | ENABLE_VERIFICATION=yes"
assert_dry_pure "limine with drop-in" "$OUTPUT"
# An explicit ENABLE_VERIFICATION=no in /etc/default/limine wins over drop-ins.
printf 'ENABLE_VERIFICATION=no\n' >>"$root/etc/default/limine"
capture env HASEEN_SYSROOT="$root" haseen secureboot setup --dry-run
assert_status "limine: verification=no refused" 1 "$STATUS"
assert_contains "limine: verification=no reason" "$OUTPUT" "ENABLE_VERIFICATION"
assert_not_contains "limine: nothing planned before refusal" "$OUTPUT" "DRYRUN:"

# Limine without limine-entry-tool would go stale on the next kernel update.
root="$(scratch limine-notool "$FX_LIMINE")"
rm -r "$root"/var/lib/pacman/local/limine-mkinitcpio-hook-*
capture env HASEEN_SYSROOT="$root" haseen secureboot setup --dry-run
assert_status "limine without limine-entry-tool refused" 1 "$STATUS"
assert_contains "limine without tool: reason" "$OUTPUT" "limine-mkinitcpio-hook"

# sbctl before 0.17 enrolls only the expired 2011 Microsoft CAs.
root="$(scratch old-sbctl "$FX_LIMINE")"
mv "$root/var/lib/pacman/local/sbctl-0.18-2" "$root/var/lib/pacman/local/sbctl-0.16-1"
capture env HASEEN_SYSROOT="$root" haseen secureboot setup --dry-run
assert_status "sbctl 0.16 refused" 1 "$STATUS"
assert_contains "sbctl 0.16: 2023 CA reason" "$OUTPUT" "2011 CAs, which expired in June 2026"
assert_dry_pure "old sbctl" "$OUTPUT"

# Setup Mode but no sbctl: refuse with the next step.
capture env HASEEN_SYSROOT="$FIXTURES/cachyos-limine-luks-dualboot" haseen secureboot setup --dry-run
assert_status "no sbctl refused" 1 "$STATUS"
assert_contains "no sbctl: next step" "$OUTPUT" "haseen layer apply secureboot"

# --- setup: systemd-boot, keys already present, TPM2-bound LUKS ---------------
sandbox sb-sdboot
capture env HASEEN_SYSROOT="$FX_SDTPM" haseen secureboot setup --dry-run
assert_status "sdboot dry-run exit" 0 "$STATUS"
assert_dry_pure "sdboot setup" "$OUTPUT"
assert_not_contains "keys present: no create-keys" "$OUTPUT" "create-keys"$'\n'
assert_contains "keys present: said so" "$OUTPUT" "keys exist in /var/lib/sbctl/keys; create-keys skipped"
assert_contains "sdboot: signed source for bootctl update" "$OUTPUT" \
    "DRYRUN: sudo sbctl sign -s -o /usr/lib/systemd/boot/efi/systemd-bootx64.efi.signed /usr/lib/systemd/boot/efi/systemd-bootx64.efi"
for f in /boot/EFI/systemd/systemd-bootx64.efi /boot/EFI/BOOT/BOOTX64.EFI /boot/vmlinuz-linux /boot/EFI/Linux/arch-linux.efi; do
    assert_contains "sdboot: signs $f" "$OUTPUT" "DRYRUN: sudo sbctl sign -s $f"$'\n'
done
assert_not_contains "sdboot: initramfs is not a PE image" "$OUTPUT" "initramfs-linux.img"
assert_contains "sdboot: enroll" "$OUTPUT" "DRYRUN: sudo sbctl enroll-keys --microsoft --firmware-builtin"
assert_not_contains "sdboot: no BitLocker warning without Windows" "$OUTPUT" "aka.ms"
assert_contains "TPM2 crypttab: warning" "$OUTPUT" "LUKS unlocked by the TPM2"
assert_contains "TPM2 crypttab: re-enroll command" "$OUTPUT" \
    "systemd-cryptenroll --wipe-slot=tpm2 --tpm2-device=auto --tpm2-pcrs=7 /dev/disk/by-uuid/0f3b2c1d-1111-4222-8333-944455556666"
before "TPM2 warning precedes enrollment" "$OUTPUT" "LUKS unlocked by the TPM2" "sudo sbctl enroll-keys"
# Same machine without the TPM2 option: no warning.
root="$(scratch no-tpm "$FX_SDTPM")"
printf 'root UUID=0f3b2c1d-1111-4222-8333-944455556666 none discard\n' >"$root/etc/crypttab"
capture env HASEEN_SYSROOT="$root" haseen secureboot setup --dry-run
assert_not_contains "passphrase LUKS: no TPM2 warning" "$OUTPUT" "systemd-cryptenroll"
# crypttab unreadable (0600 root on a real host): a conditional warning.
chmod 000 "$root/etc/crypttab"
capture env HASEEN_SYSROOT="$root" haseen secureboot setup --dry-run
chmod 644 "$root/etc/crypttab"
assert_contains "unreadable crypttab: conditional TPM2 warning" "$OUTPUT" "readable only by root"

# --- setup: firmware without built-in default keys ---------------------------
# sbctl's --firmware-builtin opens dbDefault and KEKDefault and aborts when
# either is missing (OVMF secboot in Setup Mode has neither): plan 002, decision 7.
sandbox sb-nodefaults
capture env HASEEN_SYSROOT="$FX_SDTPM" haseen secureboot setup --dry-run
assert_contains "default keys present: plan names the command" "$OUTPUT" \
    "(sbctl enroll-keys --microsoft --firmware-builtin)"
assert_not_contains "default keys present: no warning" "$OUTPUT" "without --firmware-builtin"
root="$(scratch no-defaults "$FX_SDTPM")"
rm "$root"/sys/firmware/efi/efivars/{db,KEK}Default-8be4df61-93ca-11d2-aa0d-00e098032b8c
capture env HASEEN_SYSROOT="$root" haseen secureboot setup --dry-run
assert_status "no default keys: dry-run exit" 0 "$STATUS"
assert_dry_pure "no default keys" "$OUTPUT"
assert_contains "no default keys: microsoft only" "$OUTPUT" "DRYRUN: sudo sbctl enroll-keys --microsoft"$'\n'
assert_not_contains "no default keys: no --firmware-builtin" "$OUTPUT" "enroll-keys --microsoft --firmware-builtin"
# The warning: present, names both variables as not both available, says the
# flag is left out, and never claims the firmware has no built-in keys.
warning="$(grep '^Warning:.*--firmware-builtin' <<<"$OUTPUT")"
assert_contains "no default keys: warning" "$warning" "Warning:"
assert_contains "no default keys: warning names both defaults" "$warning" "both dbDefault and KEKDefault"
assert_contains "no default keys: warning says the flag is omitted" "$warning" "without --firmware-builtin"
assert_not_contains "no default keys: warning makes no absence claim" "$warning" "no built-in"
assert_contains "no default keys: plan names the command" "$OUTPUT" "(sbctl enroll-keys --microsoft)"$'\n'
assert_contains "no default keys: plan says not both available" "$OUTPUT" "dbDefault and KEKDefault are not both available"
assert_contains "no default keys: enrollment text" "$OUTPUT" "Enrolling writes your keys and Microsoft's into"
before "no default keys: warning in the plan, before signing" "$OUTPUT" "without --firmware-builtin" "sbctl sign"
before "no default keys: TPM2 warning still precedes enrollment" "$OUTPUT" "LUKS unlocked by the TPM2" "sudo sbctl enroll-keys"
# One default alone is not enough: sbctl reads both, and the owner's policy is
# all-or-nothing. The text must not claim the other one is absent too.
for keep in db KEK; do
    gone=KEK
    [[ $keep == KEK ]] && gone=db
    root="$(scratch "$keep-default-only" "$FX_SDTPM")"
    rm "$root/sys/firmware/efi/efivars/${gone}Default-8be4df61-93ca-11d2-aa0d-00e098032b8c"
    capture env HASEEN_SYSROOT="$root" haseen secureboot setup --dry-run
    assert_status "${keep}Default only: dry-run exit" 0 "$STATUS"
    assert_eq "${keep}Default only: microsoft only" "DRYRUN: sudo sbctl enroll-keys --microsoft" \
        "$(grep 'enroll-keys' <<<"$OUTPUT" | grep '^DRYRUN')"
    assert_contains "${keep}Default only: plan names the command" "$OUTPUT" "(sbctl enroll-keys --microsoft)"$'\n'
    assert_contains "${keep}Default only: warning says the flag is omitted" "$OUTPUT" "without --firmware-builtin"
    assert_not_contains "${keep}Default only: no false absence claim" "$OUTPUT" "no built-in"
done

# --- setup: GRUB ---------------------------------------------------------------
sandbox sb-grub
capture env HASEEN_SYSROOT="$FX_GRUB" haseen secureboot setup --dry-run
assert_status "grub dry-run exit" 0 "$STATUS"
assert_dry_pure "grub setup" "$OUTPUT"
assert_contains "grub: CachyOS wiki grub-install" "$OUTPUT" \
    "DRYRUN: sudo grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=cachyos --modules=tpm --disable-shim-lock"
assert_contains "grub: weakest-path warning" "$OUTPUT" "GRUB is the weakest Secure Boot path"
assert_contains "grub: signs GRUB" "$OUTPUT" "DRYRUN: sudo sbctl sign -s /boot/EFI/cachyos/grubx64.efi"
assert_contains "grub: signs the kernel" "$OUTPUT" "DRYRUN: sudo sbctl sign -s /boot/vmlinuz-linux-cachyos"
before "grub-install before signing GRUB" "$OUTPUT" "grub-install" "sign -s /boot/EFI/cachyos/grubx64.efi"

# --- refusals: BIOS, not in Setup Mode -----------------------------------------
sandbox sb-refuse
capture env HASEEN_SYSROOT="$FIXTURES/arch-bios" haseen secureboot setup --dry-run
assert_status "BIOS refused" 1 "$STATUS"
assert_contains "BIOS reason" "$OUTPUT" "needs UEFI"
assert_dry_pure "BIOS setup" "$OUTPUT"
capture env HASEEN_SYSROOT="$FIXTURES/arch-bios" haseen secureboot setup
assert_status "BIOS refused without dry-run too" 1 "$STATUS"
assert_not_contains "BIOS: nothing ran" "$OUTPUT" "STUB-CALLED"
# NixOS is not supported: refused by name on UEFI in Setup Mode, before
# anything is planned or run.
root="$(scratch sb-nixos "$FX_SDTPM")"
cp "$FIXTURES/nixos/etc/os-release" "$root/etc/os-release"
capture env HASEEN_SYSROOT="$root" haseen secureboot setup --yes <<<"ENROLL"
assert_status "NixOS refused" 1 "$STATUS"
assert_contains "NixOS reason" "$OUTPUT" "NixOS is not supported"
assert_not_contains "NixOS: nothing ran" "$OUTPUT" "STUB-CALLED"
assert_not_contains "NixOS: nothing planned" "$OUTPUT" "DRYRUN:"

for fx in cachyos-grub-plain sb-sdboot-enabled; do
    capture env HASEEN_SYSROOT="$FIXTURES/$fx" haseen secureboot setup --yes
    assert_status "$fx: outside Setup Mode refused" 1 "$STATUS"
    assert_contains "$fx: firmware command" "$OUTPUT" "systemctl reboot --firmware-setup"
    assert_contains "$fx: clear keys to Setup Mode" "$OUTPUT" "Reset to Setup Mode"
    assert_contains "$fx: then re-run" "$OUTPUT" "haseen secureboot setup"$'\n'
    assert_not_contains "$fx: nothing ran" "$OUTPUT" "STUB-CALLED"
    assert_not_contains "$fx: nothing planned" "$OUTPUT" "DRYRUN:"
done
capture env HASEEN_SYSROOT="$FX_SDON" haseen secureboot setup
assert_contains "enabled with keys: points at status" "$OUTPUT" "Keys already exist in /var/lib/sbctl/keys"

# --- the typed confirmation: --yes never answers it ---------------------------
sandbox sb-typed
recorder
verify_json /boot/EFI/systemd/systemd-bootx64.efi /boot/EFI/BOOT/BOOTX64.EFI /boot/vmlinuz-linux \
    /boot/EFI/Linux/arch-linux.efi >"$SANDBOX/verify.json"
capture env HASEEN_SYSROOT="$FX_SDTPM" haseen secureboot setup --yes <<<"yes"
assert_status "--yes plus 'yes' typed: refused" 1 "$STATUS"
assert_contains "--yes plus 'yes': message" "$OUTPUT" "not confirmed: the keys were NOT enrolled"
assert_contains "--yes answered the first question (signing ran)" "$(<"$SANDBOX/sudo.log")" \
    "sbctl sign -s /boot/EFI/systemd/systemd-bootx64.efi"
assert_not_contains "--yes plus 'yes': no enrollment" "$(<"$SANDBOX/sudo.log")" "enroll-keys"

recorder
capture env HASEEN_SYSROOT="$FX_SDTPM" haseen secureboot setup --yes </dev/null
assert_status "--yes with no input: refused" 1 "$STATUS"
assert_not_contains "--yes with no input: no enrollment" "$(<"$SANDBOX/sudo.log")" "enroll-keys"

recorder
capture env HASEEN_SYSROOT="$FX_SDTPM" haseen secureboot setup --yes <<<"enroll"
assert_not_contains "typed word is case-sensitive" "$(<"$SANDBOX/sudo.log")" "enroll-keys"

recorder
capture env HASEEN_SYSROOT="$FX_SDTPM" haseen secureboot setup --yes <<<"ENROLL"
assert_status "typed ENROLL: enrolls" 0 "$STATUS"
assert_contains "typed ENROLL: microsoft + firmware-builtin" "$(<"$SANDBOX/sudo.log")" \
    "sbctl enroll-keys --microsoft --firmware-builtin"
assert_not_contains "typed ENROLL: keys present, no create-keys" "$(<"$SANDBOX/sudo.log")" "create-keys"
assert_contains "typed ENROLL: next steps" "$OUTPUT" "Keys enrolled. Secure Boot is still off"

# Without --yes the plain question takes one line and ENROLL the next.
recorder
capture env HASEEN_SYSROOT="$FX_SDTPM" haseen secureboot setup <<<$'n\nENROLL'
assert_contains "declined first question: cancelled" "$OUTPUT" "cancelled; nothing changed"
assert_eq "declined first question: nothing ran" "" "$(<"$SANDBOX/sudo.log")"
recorder
capture env HASEEN_SYSROOT="$FX_SDTPM" haseen secureboot setup <<<$'y\nENROLL'
assert_status "y then ENROLL: enrolls" 0 "$STATUS"
assert_contains "y then ENROLL: enrolled" "$(<"$SANDBOX/sudo.log")" "enroll-keys --microsoft --firmware-builtin"

# No built-in default keys: the real run enrolls without --firmware-builtin.
root="$(scratch typed-no-defaults "$FX_SDTPM")"
rm "$root"/sys/firmware/efi/efivars/{db,KEK}Default-8be4df61-93ca-11d2-aa0d-00e098032b8c
recorder
capture env HASEEN_SYSROOT="$root" haseen secureboot setup --yes <<<"ENROLL"
assert_status "no default keys, typed ENROLL: enrolls" 0 "$STATUS"
assert_eq "no default keys, typed ENROLL: microsoft only" "sbctl enroll-keys --microsoft" \
    "$(grep 'enroll-keys' "$SANDBOX/sudo.log")"
assert_contains "no default keys, typed ENROLL: warned" "$OUTPUT" "without --firmware-builtin"

# A sysroot redirects reads only: without the recorder marker a real run would
# decide from the fixture's efivars and enroll this machine's firmware. Refused
# before anything privileged, even with the typed word.
recorder
capture env -u HASEEN_TEST_STUBBED_SUDO HASEEN_SYSROOT="$root" haseen secureboot setup --yes <<<"ENROLL"
assert_status "sysroot without dry-run: refused" 1 "$STATUS"
assert_contains "sysroot without dry-run: reason" "$OUTPUT" "use --dry-run with HASEEN_SYSROOT"
assert_eq "sysroot without dry-run: nothing privileged ran" "" "$(<"$SANDBOX/sudo.log")"
assert_not_contains "sysroot without dry-run: no plan" "$OUTPUT" "enrollment:"
# The marker alone does not open it: the sudo on PATH has to be the stub under
# tests/.out. Here a recorder outside it stands in for any other sudo.
elsewhere="$(mktemp -d "${TMPDIR:-/tmp}/haseen-sb-sudo-XXXX")"
cp "$SANDBOX/stubs/sudo" "$elsewhere/sudo"
capture env HASEEN_TEST_STUBBED_SUDO=1 PATH="$elsewhere:$PATH" HASEEN_SYSROOT="$root" haseen secureboot setup --yes <<<"ENROLL"
assert_status "sysroot, marker, sudo outside the stubs: refused" 1 "$STATUS"
assert_contains "sysroot, marker, sudo outside the stubs: reason" "$OUTPUT" "use --dry-run with HASEEN_SYSROOT"
assert_eq "sysroot, marker, sudo outside the stubs: nothing privileged ran" "" "$(<"$SANDBOX/sudo.log")"
ln -s "$elsewhere/sudo" "$SANDBOX/stubs/sudo-link"
mv -f "$SANDBOX/stubs/sudo-link" "$SANDBOX/stubs/sudo"
capture env HASEEN_TEST_STUBBED_SUDO=1 HASEEN_SYSROOT="$root" haseen secureboot setup --yes <<<"ENROLL"
assert_status "sysroot, marker, a stub that links outside: refused" 1 "$STATUS"
assert_eq "sysroot, marker, a stub that links outside: nothing privileged ran" "" "$(<"$SANDBOX/sudo.log")"
rm -f "$SANDBOX/stubs/sudo"
rm -rf "$elsewhere"

# --- the verify gate: an unsigned boot file blocks enrollment -----------------
recorder
verify_json /boot/EFI/systemd/systemd-bootx64.efi /boot/EFI/BOOT/BOOTX64.EFI /boot/EFI/Linux/arch-linux.efi \
    >"$SANDBOX/verify.json"
capture env HASEEN_SYSROOT="$FX_SDTPM" haseen secureboot setup --yes <<<"ENROLL"
assert_status "kernel not verified: refused" 1 "$STATUS"
assert_contains "kernel not verified: named" "$OUTPUT" "not ready: /boot/vmlinuz-linux"
assert_not_contains "kernel not verified: no enrollment" "$(<"$SANDBOX/sudo.log")" "enroll-keys"

recorder
verify_json /boot/EFI/systemd/systemd-bootx64.efi /boot/EFI/BOOT/BOOTX64.EFI /boot/vmlinuz-linux=0 \
    /boot/EFI/Linux/arch-linux.efi /boot/EFI/Microsoft/Boot/bootmgfw.efi=0 >"$SANDBOX/verify.json"
capture env HASEEN_SYSROOT="$FX_SDTPM" haseen secureboot setup --yes <<<"ENROLL"
assert_status "unsigned kernel: refused" 1 "$STATUS"
assert_contains "unsigned kernel: named" "$OUTPUT" "not ready: /boot/vmlinuz-linux: not signed"
assert_not_contains "Microsoft's binaries are not blockers" "$OUTPUT" "not ready: /boot/EFI/Microsoft"
assert_not_contains "unsigned kernel: no enrollment" "$(<"$SANDBOX/sudo.log")" "enroll-keys"

# Limine: every file signed, but the config hash is not enrolled in the
# binaries (the recorder ran nothing): enrollment must still be refused.
recorder
verify_json /boot/EFI/limine/limine_x64.efi /boot/EFI/BOOT/BOOTX64.EFI >"$SANDBOX/verify.json"
capture env HASEEN_SYSROOT="$FX_LIMINE" haseen secureboot setup --yes <<<"ENROLL"
assert_status "limine unenrolled: refused" 1 "$STATUS"
assert_contains "limine unenrolled: reason" "$OUTPUT" "limine_x64.efi has no config hash enrolled"
assert_not_contains "limine unenrolled: no enrollment" "$(<"$SANDBOX/sudo.log")" "enroll-keys"

# Limine fully enrolled and hashed: the gate passes.
root="$(scratch limine-ready "$FX_LIMINE")"
cfg="$root/boot/limine.conf"
sed -i "s|^wallpaper: boot():/limine-splash.png$|wallpaper: boot():/limine-splash.png#$(b2sum "$root/boot/limine-splash.png" | cut -d' ' -f1)|" "$cfg"
enrolled="$(printf 'MZ fixture Limine 12.8.0 EFI binary\n++CONFIG_B2SUM_SIGNATURE++%s\n' "$(b2sum "$cfg" | cut -d' ' -f1)")"
printf '%s\n' "$enrolled" >"$root/boot/EFI/limine/limine_x64.efi"
printf '%s\n' "$enrolled" >"$root/boot/EFI/BOOT/BOOTX64.EFI"
printf 'ENABLE_ENROLL_LIMINE_CONFIG=yes\n' >>"$root/etc/default/limine"
recorder
verify_json /boot/EFI/limine/limine_x64.efi /boot/EFI/BOOT/BOOTX64.EFI >"$SANDBOX/verify.json"
capture env HASEEN_SYSROOT="$root" haseen secureboot setup --yes <<<"ENROLL"
assert_status "limine enrolled: enrolls" 0 "$STATUS"
assert_contains "limine enrolled: microsoft + firmware-builtin" "$(<"$SANDBOX/sudo.log")" \
    "sbctl enroll-keys --microsoft --firmware-builtin"
assert_not_contains "limine enrolled: wallpaper already hashed" "$(<"$SANDBOX/sudo.log")" "limine-hash-assets"
# A shadowing config would make the fallback read a different file.
touch "$root/boot/EFI/BOOT/limine.conf"
recorder
capture env HASEEN_SYSROOT="$root" haseen secureboot setup --yes <<<"ENROLL"
assert_status "shadowing limine.conf refused" 1 "$STATUS"
assert_contains "shadowing limine.conf named" "$OUTPUT" "/boot/EFI/BOOT/limine.conf shadows /boot/limine.conf"
rm "$root/boot/EFI/BOOT/limine.conf"
# An unhashed kernel path in a Linux entry would panic under Secure Boot.
sed -i 's|^\(        path: boot():/vmlinuz-linux-cachyos\)#.*|\1|' "$cfg"
recorder
capture env HASEEN_SYSROOT="$root" haseen secureboot setup --yes <<<"ENROLL"
assert_status "unhashed kernel path refused" 1 "$STATUS"
assert_contains "unhashed kernel path named" "$OUTPUT" "path: boot():/vmlinuz-linux-cachyos (no #blake2b"
assert_not_contains "efi chainload entry is exempt" "$OUTPUT" "bootmgfw.efi (no #blake2b"

# --- limine-hash-assets.sh -------------------------------------------------------
sandbox sb-assets
esp="$SANDBOX/esp"
cp -a "$FX_LIMINE/boot" "$esp"
conf="$esp/limine.conf"
orig="$(<"$conf")"
capture "$SB_LIB/limine-hash-assets.sh" "$conf" "$esp"
assert_status "assets: exit" 0 "$STATUS"
h1="$(b2sum "$esp/limine-splash.png" | cut -d' ' -f1)"
assert_contains "assets: wallpaper hashed" "$(<"$conf")" "wallpaper: boot():/limine-splash.png#$h1"$'\n'
assert_eq "assets: only the wallpaper line changed" \
    "$(sed '2d' <<<"$orig")" "$(sed '2d' "$conf")"
capture "$SB_LIB/limine-hash-assets.sh" "$conf" "$esp"
assert_eq "assets: second run is silent" "" "$OUTPUT"
assert_contains "assets: second run keeps the hash" "$(<"$conf")" "#$h1"
printf 'a new splash\n' >"$esp/limine-splash.png"
printf 'MZ tampered kernel\n' >"$esp/vmlinuz-linux-cachyos"
capture "$SB_LIB/limine-hash-assets.sh" "$conf" "$esp"
h2="$(b2sum "$esp/limine-splash.png" | cut -d' ' -f1)"
assert_contains "assets: stale wallpaper hash refreshed" "$(<"$conf")" "limine-splash.png#$h2"
assert_not_contains "assets: old hash gone" "$(<"$conf")" "#$h1"
assert_contains "assets: kernel hash never rewritten" "$(<"$conf")" \
    "vmlinuz-linux-cachyos#$(b2sum "$FX_LIMINE/boot/vmlinuz-linux-cachyos" | cut -d' ' -f1)"

# --- sign ----------------------------------------------------------------------
sandbox sb-sign
# The hook must never block pacman: no keys, or no UEFI, is a quiet exit 0
# even without --dry-run.
for fx in "$FX_LIMINE" "$FX_GRUB" "$FIXTURES/arch-bios" "$FIXTURES/cachyos-grub-plain"; do
    capture env HASEEN_SYSROOT="$fx" haseen secureboot sign --hook
    assert_status "hook no-op ${fx##*/}" 0 "$STATUS"
    assert_not_contains "hook no-op ${fx##*/}: nothing ran" "$OUTPUT" "STUB-CALLED"
done
capture env HASEEN_SYSROOT="$FX_LIMINE" haseen secureboot sign
assert_status "manual sign without keys: refused" 1 "$STATUS"
assert_contains "manual sign without keys: next step" "$OUTPUT" "haseen secureboot setup"

# zz-sbctl.hook runs right after ours: the hook only adds the untracked kernel.
capture env HASEEN_SYSROOT="$FX_SDON" haseen secureboot sign --hook --dry-run
assert_status "hook sdboot exit" 0 "$STATUS"
assert_dry_pure "hook sdboot" "$OUTPUT"
# Exactly one step: tracked files and sign-all are zz-sbctl.hook's job.
assert_eq "hook: only the new kernel is signed and tracked" \
    "DRYRUN: sudo sbctl sign -s /boot/vmlinuz-linux-lts" "$OUTPUT"
capture env HASEEN_SYSROOT="$FX_SDON" haseen secureboot sign --dry-run
assert_dry_pure "manual sign sdboot" "$OUTPUT"
assert_contains "manual sign: sign-all" "$OUTPUT" "DRYRUN: sudo sbctl sign-all"
# zz-sbctl.hook masked: the hook signs everything itself.
root="$(scratch masked "$FX_SDON")"
mkdir -p "$root/etc/pacman.d/hooks"
ln -s /dev/null "$root/etc/pacman.d/hooks/zz-sbctl.hook"
capture env HASEEN_SYSROOT="$root" haseen secureboot sign --hook --dry-run
assert_contains "masked zz-sbctl: hook runs sign-all" "$OUTPUT" "DRYRUN: sudo sbctl sign-all"

# Limine with keys: re-enroll, refresh a raw fallback, never sign UKIs.
root="$(scratch limine-keys "$FX_LIMINE")"
cp -a "$FX_SDON/var/lib/sbctl" "$root/var/lib/sbctl"
printf '{}\n' >"$root/var/lib/sbctl/files.json"
printf 'ENABLE_ENROLL_LIMINE_CONFIG=yes\n' >>"$root/etc/default/limine"
mkdir -p "$root/boot/EFI/Linux"
printf 'MZ fixture UKI\n' >"$root/boot/EFI/Linux/omarchy_linux.efi"
capture env HASEEN_SYSROOT="$root" haseen secureboot sign --hook --dry-run
assert_status "hook limine exit" 0 "$STATUS"
assert_dry_pure "hook limine" "$OUTPUT"
assert_contains "hook limine: wallpaper hashed" "$OUTPUT" "limine-hash-assets.sh /boot/limine.conf /boot"
assert_contains "hook limine: re-enrolled" "$OUTPUT" "DRYRUN: sudo limine-enroll-config"
assert_contains "hook limine: raw fallback replaced" "$OUTPUT" \
    "DRYRUN: sudo cp /boot/EFI/limine/limine_x64.efi /boot/EFI/BOOT/BOOTX64.EFI"
assert_not_contains "hook limine: UKIs left to mkinitcpio's sbctl hook" "$OUTPUT" "omarchy_linux.efi"
before "hook limine: assets before enrollment" "$OUTPUT" "limine-hash-assets" "limine-enroll-config"

# --- status --------------------------------------------------------------------
sandbox sb-status
capture env HASEEN_SYSROOT="$FX_LIMINE" haseen secureboot status
assert_status "status limine setup mode" 1 "$STATUS"
assert_dry_pure "status is read-only" "$OUTPUT"
assert_contains "status: setup mode" "$OUTPUT" "warn: secure boot: Setup Mode"
assert_contains "status: windows" "$OUTPUT" "ok: windows: Boot Manager on the ESP"
assert_contains "status: no keys" "$OUTPUT" "missing: keys: none"
assert_contains "status: drop-in enrollment does not count" "$OUTPUT" \
    "warn: limine: ENABLE_ENROLL_LIMINE_CONFIG is not yes in /etc/default/limine"
assert_contains "status: unenrolled limine" "$OUTPUT" "limine_x64.efi has no config hash enrolled"
assert_contains "status: raw fallback" "$OUTPUT" "fallback /boot/EFI/BOOT/BOOTX64.EFI is a Limine copy"
assert_contains "status: wallpaper without hash" "$OUTPUT" "limine.conf:2: wallpaper/font has no #blake2b"
assert_contains "status: hook missing" "$OUTPUT" "missing: pacman hook: /etc/pacman.d/hooks/zz-haseen-secureboot.hook"
capture env HASEEN_SYSROOT="$FIXTURES/arch-bios" haseen secureboot status
assert_status "status BIOS" 1 "$STATUS"
assert_contains "status BIOS reason" "$OUTPUT" "Secure Boot needs UEFI"
capture env HASEEN_SYSROOT="$FX_SDTPM" haseen secureboot status
assert_contains "status: TPM2 volume" "$OUTPUT" "warn: luks: root (UUID=0f3b2c1d-1111-4222-8333-944455556666) unlocks with the TPM2"
capture env HASEEN_SYSROOT="$FX_SDON" haseen secureboot status
assert_status "status fixture never claims signatures" 1 "$STATUS"
assert_contains "status: sbctl skipped under a fixture" "$OUTPUT" "warn: signatures: not checked (sbctl is a live-only probe"
assert_contains "status: enabled" "$OUTPUT" "ok: secure boot: enabled"

# sbctl answers through the probe seam: exit 0 only when enforcing, the whole
# chain is signed and Microsoft's keys are enrolled.
root="$(scratch status-ok "$FX_SDON")"
install -Dm644 "$SB_LIB/files/zz-haseen-secureboot.hook" "$root/etc/pacman.d/hooks/zz-haseen-secureboot.hook"
chain=(/boot/EFI/systemd/systemd-bootx64.efi /boot/EFI/BOOT/BOOTX64.EFI /usr/lib/systemd/boot/efi/systemd-bootx64.efi.signed
    /boot/vmlinuz-linux /boot/vmlinuz-linux-lts /boot/EFI/Linux/arch-linux.efi)
verify_json "${chain[@]}" >"$SANDBOX/verify.json"
printf '{\n  "installed": true,\n  "setup_mode": false,\n  "secure_boot": true,\n  "vendors": [\n    "microsoft",\n    "builtin-db"\n  ]\n}\n' >"$SANDBOX/status.json"
sb_probe() {
    capture env HASEEN_SYSROOT="$root" SB_DIR_OUT="$SANDBOX" bash -c '
        source "$HASEEN_PATH/layers/secureboot/secureboot.sh"
        sb_sbctl_readable() { return 0; }
        sb_sbctl_query() { cat "$SB_DIR_OUT/$1.json"; }
        preflight_all
        sb_report'
}
sb_probe
assert_status "status: enforcing and signed" 0 "$STATUS"
assert_contains "status: signatures ok" "$OUTPUT" "ok: signatures: 6 file(s) signed, boot chain complete"
assert_contains "status: vendor keys" "$OUTPUT" "ok: enrolled vendor keys: microsoft builtin-db"
verify_json "${chain[@]:0:4}" /boot/vmlinuz-linux-lts=0 "${chain[@]:5}" >"$SANDBOX/verify.json"
sb_probe
assert_status "status: one unsigned kernel" 1 "$STATUS"
assert_contains "status: unsigned kernel named" "$OUTPUT" "missing: signature: /boot/vmlinuz-linux-lts: not signed"
verify_json "${chain[@]}" >"$SANDBOX/verify.json"
printf '{\n  "installed": true,\n  "vendors": []\n}\n' >"$SANDBOX/status.json"
sb_probe
assert_status "status: Microsoft keys missing" 1 "$STATUS"
assert_contains "status: Microsoft keys missing named" "$OUTPUT" "Microsoft's are missing"

# --- the pacman hook -----------------------------------------------------------
sandbox sb-hook
hook="$SB_LIB/files/zz-haseen-secureboot.hook"
expected_hook='[Trigger]
Type = Package
Operation = Install
Operation = Upgrade
Target = limine
Target = limine-mkinitcpio-hook
Target = linux*
Target = systemd
Target = mkinitcpio
[Trigger]
Type = Path
Operation = Install
Operation = Upgrade
Operation = Remove
Target = boot/*
Target = efi/*
Target = usr/lib/modules/*/vmlinuz
Target = usr/lib/modules/*/extramodules/*
Target = usr/lib/initcpio/*
Target = usr/lib/**/efi/*.efi*
Target = usr/share/**/*.efi*
[Action]
Description = haseen: re-enrolling the Limine config and signing new boot files...
When = PostTransaction
Exec = @HASEEN_BIN@ secureboot sign --hook'
assert_eq "hook content" "$expected_hook" "$(grep -v -e '^#' -e '^$' "$hook")"
capture bash -c 'source "$HASEEN_PATH/layers/secureboot/secureboot.sh"; sb_hook_render'
assert_contains "hook Exec rendered from the install prefix" "$OUTPUT" "Exec = $REPO/bin/haseen secureboot sign --hook"
assert_not_contains "no placeholder left in the rendered hook" "$OUTPUT" "@HASEEN_BIN@"
# The hook runs that haseen as root: from a tree a user owns (this checkout)
# it is not written (plan 101, root_trusted_exec).
capture env HASEEN_SYSROOT="$FIXTURES/sb-limine-setup-windows" haseen layer apply secureboot --dry-run
assert_not_contains "from a tree root does not own, the hook is not written" "$OUTPUT" "zz-haseen-secureboot.hook (mode"
assert_contains "and the layer says why and what to do" "$OUTPUT" \
    "pacman hook not written: the hook's $REPO/bin/haseen runs as root, but / is owned by uid $(id -u), not root; install haseen as root (./install.sh)"
# Every Path target of sbctl's own hook is ours too, so ours always runs first.
while read -r t; do
    assert_contains "hook mirrors zz-sbctl target $t" "$(<"$hook")" "$t"$'\n'
done < <(grep '^Target' "$FX_SDON/usr/share/libalpm/hooks/zz-sbctl.hook")
# pacman orders hooks by file name (strcmp): after Limine's and Omarchy's,
# before sbctl's sign-all.
order=$'60-limine-mkinitcpio-remove-pre.hook\n80-limine-efi-deploy.hook\n90-mkinitcpio-install.hook\n99-omarchy-limine.hook\nzz-haseen-secureboot.hook\nzz-sbctl.hook'
assert_eq "hook sorts after limine/omarchy, before zz-sbctl" "$order" "$(LC_ALL=C sort <<<"$order")"
assert_eq "hook file name" "zz-haseen-secureboot.hook" "${hook##*/}"

# --- layer apply / status / remove ----------------------------------------------
sandbox sb-layer
root="$(scratch nosbctl "$FIXTURES/cachyos-limine-luks-dualboot")"
DRY_RUN=true sb_layer "$root" apply
assert_status "apply exit" 0 "$STATUS"
assert_dry_pure "layer apply" "$OUTPUT"
assert_contains "apply installs sbctl" "$OUTPUT" "DRYRUN: sudo pacman -S --needed sbctl"$'\n'
assert_not_contains "apply from this checkout writes no hook" "$OUTPUT" "zz-haseen-secureboot.hook (mode"
assert_contains "apply prints the next step" "$OUTPUT" "next: haseen secureboot setup"
assert_not_contains "apply never creates keys" "$OUTPUT" "create-keys"
assert_not_contains "apply never enrolls" "$OUTPUT" "enroll-keys"
assert_contains "apply marks the layer" "$OUTPUT" "write /var/lib/haseen/layers/secureboot"
plant_tree "$root"
root_stat on
DRY_RUN=true sb_layer "$root" apply
assert_status "apply exit from a root-owned tree" 0 "$STATUS"
assert_contains "apply installs the hook" "$OUTPUT" \
    "DRYRUN: write /etc/pacman.d/hooks/zz-haseen-secureboot.hook (mode 0644):"
assert_contains "installed hook Exec points at that tree" "$OUTPUT" "| Exec = $REPO/bin/haseen secureboot sign --hook"
chmod g+w "$root$REPO/bin"
DRY_RUN=true sb_layer "$root" apply
assert_not_contains "a bin directory its group can write: no hook" "$OUTPUT" "zz-haseen-secureboot.hook (mode"
assert_contains "and the reason" "$OUTPUT" "but $REPO/bin is writable by its group or by others"
chmod g-w "$root$REPO/bin"
# What the sign command sources and runs as root counts too.
for f in lib/preflight.sh layers/secureboot/secureboot.sh layers/secureboot/limine-hash-assets.sh; do
    chmod o+w "$root$REPO/share/haseen/$f"
    DRY_RUN=true sb_layer "$root" apply
    assert_not_contains "$f others can write: no hook" "$OUTPUT" "zz-haseen-secureboot.hook (mode"
    assert_contains "$f is named" "$OUTPUT" "but $REPO/share/haseen/$f is writable by its group or by others"
    chmod o-w "$root$REPO/share/haseen/$f"
done
# So does the template the hook is rendered from, and every directory on its
# path: it decides the Exec root runs (plan 111).
for f in layers/secureboot/files layers/secureboot/files/zz-haseen-secureboot.hook; do
    chmod g+w "$root$REPO/share/haseen/$f"
    DRY_RUN=true sb_layer "$root" apply
    assert_not_contains "the template's $f its group can write: no hook" "$OUTPUT" "zz-haseen-secureboot.hook (mode"
    assert_contains "and it is named" "$OUTPUT" "but $REPO/share/haseen/$f is writable by its group or by others"
    chmod g-w "$root$REPO/share/haseen/$f"
done
sed "s|@HASEEN_BIN@|$REPO/bin/haseen|" "$SB_LIB/files/zz-haseen-secureboot.hook" | install -Dm644 /dev/stdin "$root/etc/pacman.d/hooks/zz-haseen-secureboot.hook"
chmod -R go-w "$root"
DRY_RUN=true sb_layer "$root" apply
assert_contains "re-apply: hook up to date" "$OUTPUT" "pacman hook up to date"
assert_not_contains "re-apply: no reinstall" "$OUTPUT" "write /etc/pacman.d/hooks/zz-haseen-secureboot.hook"
printf '# edited\n' >>"$root/etc/pacman.d/hooks/zz-haseen-secureboot.hook"
DRY_RUN=true sb_layer "$root" apply
assert_contains "drifted hook reinstalled" "$OUTPUT" "write /etc/pacman.d/hooks/zz-haseen-secureboot.hook"
root_stat off
# The same with the real stat, as root, where user namespaces are available.
sb_real_stat() {
    DRY_RUN=true sb_layer_root "$root" apply
    assert_contains "real stat, as root: the hook is reinstalled from the root-owned tree" "$OUTPUT" \
        "DRYRUN: write /etc/pacman.d/hooks/zz-haseen-secureboot.hook (mode 0644):"
}
if userns; then
    sb_real_stat
else
    skipped sb_real_stat "real-stat root-owned tree check" "user namespaces are not available here"
fi
DRY_RUN=true sb_layer "$FIXTURES/arch-bios" apply
assert_status "apply on BIOS refused" 1 "$STATUS"
assert_contains "apply on BIOS reason" "$OUTPUT" "needs UEFI"
assert_not_contains "apply on BIOS refuses before installing sbctl" "$OUTPUT" "pacman -S"

sb_layer "$FX_SDON" status
assert_status "layer status: hook missing" 1 "$STATUS"
root="$(scratch layer-installed "$FX_SDON")"
sed "s|@HASEEN_BIN@|$REPO/bin/haseen|" "$SB_LIB/files/zz-haseen-secureboot.hook" | install -Dm644 /dev/stdin "$root/etc/pacman.d/hooks/zz-haseen-secureboot.hook"
sb_layer "$root" status
assert_status "layer status: installed, signatures unverified = degraded" 2 "$STATUS"
assert_contains "a hook that runs a tree a user owns is a warning" "$OUTPUT" \
    "warn: pacman hook: the hook's $REPO/bin/haseen runs as root, but / is owned by uid $(id -u)"
plant_tree "$root"
root_stat on
sb_layer "$root" status
assert_contains "from a root-owned tree it is reported in place" "$OUTPUT" "ok: pacman hook: /etc/pacman.d/hooks/zz-haseen-secureboot.hook"
root_stat off

DRY_RUN=true sb_layer "$FX_SDON" remove
assert_status "remove exit" 0 "$STATUS"
assert_dry_pure "layer remove" "$OUTPUT"
assert_contains "remove deletes the hook" "$OUTPUT" "DRYRUN: sudo rm -f /etc/pacman.d/hooks/zz-haseen-secureboot.hook"
assert_eq "remove plans only the hook and the marker" \
    $'DRYRUN: sudo rm -f /etc/pacman.d/hooks/zz-haseen-secureboot.hook\nDRYRUN: sudo rm -f /var/lib/haseen/layers/secureboot' \
    "$(grep '^DRYRUN' <<<"$OUTPUT")"
assert_contains "remove says keys stay" "$OUTPUT" "kept: Secure Boot keys"

# --- no test wrote to a fixture ----------------------------------------------------
assert_eq "fixtures untouched" "$FIXTURES_BEFORE" "$(fixtures_sum)"
