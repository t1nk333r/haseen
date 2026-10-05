# shellcheck shell=bash
# Hardware quirks: what this machine is, which rows match it, and the dispatcher
# that runs a matched body once.
sandbox hardware

# --- DMI matching against a machine we do not own ----------------------------
export HASEEN_SYSROOT="$FIXTURES/hw-asus-rog"

capture haseen hw match
assert_status "a fixture machine is readable" 0 "$STATUS"
assert_contains "the vendor is printed" "$OUTPUT" "vendor:  ASUSTeK COMPUTER INC."
assert_contains "the product is printed" "$OUTPUT" "product: ROG Zephyrus G14 GA402RJ"
assert_contains "the family is printed" "$OUTPUT" "family:  ROG Zephyrus G14"

matched="$(haseen hw match --json | jq -r '.matched | join(" ")')"
assert_contains "a DMI rule matches (vendor + family)" "$matched" "asus-rog"
assert_contains "a probe rule matches (lid switch)" "$matched" "clamshell"
assert_contains "a PCI rule matches (Turing NVIDIA)" "$matched" "nvidia-gsp"
assert_contains "an always rule matches" "$matched" "fkeys"
assert_not_contains "a pre-Turing rule does not match a Turing card" "$matched" "nvidia-no-gsp"
assert_not_contains "another vendor's rule does not match" "$matched" "framework16"
assert_not_contains "a USB rule without the device does not match" "$matched" "elgato-camlink-4k"

capture haseen hw match zephyrus
assert_status "a pattern matches the product name, case-insensitively" 0 "$STATUS"
assert_eq "a pattern prints nothing" "" "$OUTPUT"
capture haseen hw match XPS
assert_status "a pattern that does not match exits 1" 1 "$STATUS"

# --- a machine that matches almost nothing -----------------------------------
export HASEEN_SYSROOT="$FIXTURES/hw-vm-guest"
capture haseen hw match
assert_contains "a virtual machine matches the vm quirk" "$OUTPUT" "vm "
assert_not_contains "it has no lid, so no clamshell" "$OUTPUT" "clamshell"
assert_not_contains "it has no wifi, so no regdom" "$OUTPUT" "wireless-regdom"
assert_eq "a firmware placeholder family reads as empty" "family:  " "$(grep '^family:' <<<"$OUTPUT")"

capture haseen hw apply --dry-run --yes
assert_dry_pure "vm quirk dry run" "$OUTPUT"
assert_contains "the vm quirk turns animations off" "$OUTPUT" "animations = { enabled = false }"

export HASEEN_SYSROOT="$FIXTURES/hw-asus-rog"
capture haseen hw apply --dry-run --yes
assert_dry_pure "asus fixture dry run" "$OUTPUT"
assert_contains "the fkeys body writes the modprobe drop-in" "$OUTPUT" "options hid_apple fnmode=2"
assert_contains "the nvidia body writes early-KMS modules" "$OUTPUT" "MODULES+=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)"
assert_contains "a matched quirk with no body is reported" "$OUTPUT" "matched but not implemented yet:"
assert_contains "and it is named" "$OUTPUT" "asus-rog"
assert_contains "the summary line counts it" "$OUTPUT" "unimplemented"

states="$(haseen hw list --json)"
assert_eq "a matched quirk with a body is pending" pending "$(jq -r '.[] | select(.id == "clamshell") | .state' <<<"$states")"
assert_eq "a matched quirk without a body is unimplemented" unimplemented "$(jq -r '.[] | select(.id == "asus-rog") | .state' <<<"$states")"
assert_eq "an unmatched quirk says so" not-matched "$(jq -r '.[] | select(.id == "surface") | .state' <<<"$states")"
assert_eq "every row carries its match rule" "vendor:Framework,product:Laptop 16" "$(jq -r '.[] | select(.id == "framework16") | .match' <<<"$states")"
assert_eq "--matched drops the rest" 0 "$(haseen hw list --matched | grep -c not-matched || true)"

# --- the dispatcher runs a body once -----------------------------------------
# A table of our own: the shipped bodies need root, and what is under test here
# is the dispatcher, not any one quirk.
table="$SANDBOX/hardware"
mkdir -p "$table"
export HASEEN_HARDWARE_DIR="$table"
printf '%s\t%s\t%s\n' \
    "probe-row" "probe:laptop" "Runs on a laptop" \
    "never-row" "vendor:NothingLikeThis" "Never runs here" \
    "bodyless-row" "*" "Has no body yet" >"$table/quirks.tsv"
cat >"$table/probe-row.sh" <<'QUIRK'
printf 'ran\n' >>"$QUIRK_LOG"
QUIRK
export QUIRK_LOG="$SANDBOX/ran.log"

capture haseen hw apply --yes
assert_status "the dispatcher runs" 0 "$STATUS"
assert_eq "the matched body ran once" 1 "$(grep -c ran "$QUIRK_LOG")"
capture haseen hw apply --yes
assert_eq "a second run runs nothing again" 1 "$(grep -c ran "$QUIRK_LOG")"
assert_contains "the second run says it is recorded" "$OUTPUT" "1 already recorded"
assert_contains "the bodyless row is still reported" "$OUTPUT" "matched but not implemented yet: bodyless-row"

capture haseen hw apply --force --yes
assert_eq "--force runs it again" 2 "$(grep -c ran "$QUIRK_LOG")"

assert_eq "the ledger records how it ran" "applied" "$(cut -d' ' -f1 "$XDG_STATE_HOME/haseen/hardware/probe-row")"

capture haseen hw apply never-row --yes
assert_contains "naming an unmatched quirk refuses it" "$OUTPUT" "does not match this machine"
assert_eq "and it is not recorded" "" "$(compgen -G "$XDG_STATE_HOME/haseen/hardware/never-row" || true)"

capture haseen hw apply no-such-quirk --yes
assert_status "an unknown id is an error" 1 "$STATUS"
assert_contains "the error points at the list" "$OUTPUT" "unknown quirk: no-such-quirk"

# A body that fails keeps no marker, so the next run retries it.
cat >"$table/probe-row.sh" <<'QUIRK'
printf 'ran\n' >>"$QUIRK_LOG"
false
QUIRK
rm -f "$XDG_STATE_HOME/haseen/hardware/probe-row"
capture haseen hw apply probe-row --yes
assert_status "a failing quirk fails the run" 1 "$STATUS"
assert_contains "the failure names the quirk" "$OUTPUT" "hardware quirk probe-row failed"
assert_eq "a failed quirk keeps no marker" "" "$(compgen -G "$XDG_STATE_HOME/haseen/hardware/probe-row" || true)"

# A malformed table is refused rather than half-read.
printf 'Bad Id\t*\tnope\n' >"$table/quirks.tsv"
capture haseen hw list
assert_status "a malformed id aborts" 1 "$STATUS"
assert_contains "the abort names the id" "$OUTPUT" "malformed quirk id"
