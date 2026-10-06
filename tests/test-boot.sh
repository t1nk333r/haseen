# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# EFI boot entries: the four states, the parsing rules efibootmgr's output needs,
# and the checks that keep BootNext from starting the wrong system.
sandbox boot

sysroot="$SANDBOX/sysroot"
mkdir -p "$sysroot/sys/firmware/efi"
export HASEEN_SYSROOT="$sysroot"

listing="BootCurrent: 0001
Timeout: 2 seconds
BootOrder: 0001,0000,0002,0010
Boot0000* Windows Boot Manager	HD(1,GPT,5240f4f3,0x800,0x32000)/\\EFI\\Microsoft\\Boot\\bootmgfw.efi
Boot0001* Limine	HD(1,GPT,b0ab8fe1,0x800,0x400000)/\\EFI\\limine\\limine_x64.efi
Boot0002* kali	HD(1,GPT,b8a63faa,0x800,0x1e8000)/\\EFI\\kali\\grubx64.efi
Boot0010  Setup	FvFile(721c8b66)
Boot0011* Windows Boot Manager	HD(2,GPT,aaaa,0x800,0x1000)/\\EFI\\Microsoft\\Boot\\bootmgfw.efi"
printf '%s\n' "$listing" >"$SANDBOX/efibootmgr.out"
stub efibootmgr 'cat "$HASEEN_BOOT_FIXTURE"'
export HASEEN_BOOT_FIXTURE="$SANDBOX/efibootmgr.out"

capture haseen boot list
assert_status "a UEFI machine lists its entries" 0 "$STATUS"
assert_contains "the running entry is marked" "$OUTPUT" "* 0001 Limine"
assert_contains "another system is listed" "$OUTPUT" "  0000 Windows Boot Manager"
assert_not_contains "an inactive firmware entry is skipped" "$OUTPUT" "Setup"
assert_not_contains "the device path is not part of the label" "$OUTPUT" "bootmgfw.efi"

capture haseen boot list --json
json="$OUTPUT"
assert_eq "json reports the ready state" ready "$(jq -r .status <<<"$json")"
assert_eq "json reports the running entry" 0001 "$(jq -r .currentId <<<"$json")"
assert_eq "json lists only active entries" 4 "$(jq '.entries | length' <<<"$json")"
assert_eq "the label stops at the tab" "Windows Boot Manager" "$(jq -r '.entries[0].label' <<<"$json")"

# noEfi: booted in legacy mode, so there are no entries to list at all.
rm -rf "$sysroot/sys/firmware/efi"
capture haseen boot list --json
assert_status "a non-UEFI machine reports noEfi" 3 "$STATUS"
assert_eq "noEfi is a state, not an error" noEfi "$(jq -r .status <<<"$OUTPUT")"
mkdir -p "$sysroot/sys/firmware/efi"

# noTool: UEFI, but efibootmgr is not installed. A mirror of /usr/bin without
# that one binary proves it, without hiding the machine's own copy.
mkdir -p "$SANDBOX/minimal"
ln -sf /usr/bin/* "$SANDBOX/minimal/" 2>/dev/null || true
rm -f "$SANDBOX/minimal/efibootmgr"
capture env PATH="$REPO/bin:$SANDBOX/minimal" HASEEN_SYSROOT="$sysroot" haseen boot list --json
assert_status "a missing efibootmgr reports noTool" 4 "$STATUS"
assert_eq "noTool is a state, not an error" noTool "$(jq -r .status <<<"$OUTPUT")"
assert_contains "noTool names what is missing" "$(jq -r .error <<<"$OUTPUT")" efibootmgr

# error: the tool is there and fails; the reason is kept, not swallowed.
stub efibootmgr 'echo "EFI variables are not supported on this system." >&2; exit 2'
capture haseen boot list --json
assert_status "a failing efibootmgr is an error" 1 "$STATUS"
assert_eq "error is its own state" error "$(jq -r .status <<<"$OUTPUT")"
assert_contains "the error keeps the tool's reason" "$(jq -r .error <<<"$OUTPUT")" "not supported"

stub efibootmgr 'cat "$HASEEN_BOOT_FIXTURE"'

capture haseen boot next 0000 --dry-run --yes
assert_dry_pure "boot next dry run" "$OUTPUT"
assert_contains "a dry run plans the BootNext write" "$OUTPUT" "DRYRUN: sudo efibootmgr --bootnext 0000"

capture haseen boot next "kali" --dry-run --yes
assert_contains "an entry can be named by label" "$OUTPUT" "DRYRUN: sudo efibootmgr --bootnext 0002"

capture haseen boot next "Windows Boot Manager" --dry-run --yes
assert_status "an ambiguous label is refused" 1 "$STATUS"
assert_contains "the refusal lists the candidate ids" "$OUTPUT" "0000 0011"

capture haseen boot next 0010 --dry-run --yes
assert_status "an inactive entry cannot be chosen" 1 "$STATUS"

capture haseen boot next 0000 --label "Windows Boot Manager" --dry-run --yes
assert_contains "a matching label is accepted" "$OUTPUT" "--bootnext 0000"

capture haseen boot next 0000 --label "kali" --dry-run --yes
assert_status "a renumbered entry is refused" 1 "$STATUS"
assert_contains "the refusal says what the id is now" "$OUTPUT" "is now 'Windows Boot Manager'"

capture haseen boot next 0001 --dry-run --yes
assert_contains "choosing the running system warns" "$OUTPUT" "this session was started from"

# A real run is a single BootNext write; the reboot is opt-in and separate.
# The sudo stub answers here so the step after the write is reached.
stub sudo 'echo "STUB-CALLED: sudo $*" >&2; exec "$@"'
stub efibootmgr 'cat "$HASEEN_BOOT_FIXTURE"'
capture haseen boot next 0000 --yes
assert_contains "the write goes through sudo" "$OUTPUT" "STUB-CALLED: sudo efibootmgr --bootnext 0000"
capture haseen boot next 0000 --reboot --yes
assert_contains "--reboot reboots after the write" "$OUTPUT" "STUB-CALLED: systemctl reboot"
