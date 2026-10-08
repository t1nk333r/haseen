# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# tools/lab.sh's report and plan, as a dry run (its default): a fresh host
# with no lab checkout and no ~/.cache/haseen gets a full report and a plan
# that clones the lab, and a checkout without the knobs it needs blocks.

sandbox lab
LAB="$REPO/tools/lab.sh"
stub docker 'exit 0'
for t in ssh ssh-keygen openssl timedatectl; do stub "$t" 'exit 0'; done
stub curl 'exit 0'
export KVM_DEV=/dev/null # a writable character device standing in for /dev/kvm

# --- a fresh host: neither the checkout nor its parent exists ---------------------
export HASEEN_LAB_DIR="$SANDBOX/none/haseen/lab"
capture "$LAB"
assert_status "fresh host: the dry run completes" 0 "$STATUS"
assert_dry_pure "fresh host" "$OUTPUT"
assert_contains "fresh host: disk is measured on a directory that exists" "$OUTPUT" "free under $SANDBOX"
assert_contains "fresh host: the lab's knobs wait for the clone" "$OUTPUT" "checked after the clone"
assert_not_contains "fresh host: nothing is missing" "$OUTPUT" "MISSING"
assert_contains "fresh host: the plan clones the lab" "$OUTPUT" "DRYRUN: git clone --depth 1"
assert_contains "fresh host: then bootstraps it" "$OUTPUT" "./lab bootstrap"
assert_eq "fresh host: nothing was created" "no" "$([[ -e $SANDBOX/none ]] && echo yes || echo no)"

# --- a checkout with both knobs ----------------------------------------------------
export HASEEN_LAB_DIR="$SANDBOX/lab-ok"
mkdir -p "$HASEEN_LAB_DIR/.git"
printf 'case "$LAB_DISTRO" in\n  cachyos) ;;\nesac\n: "${LAB_SECUREBOOT:-off}"\n' >"$HASEEN_LAB_DIR/lab"
capture "$LAB"
assert_status "checkout: the dry run completes" 0 "$STATUS"
assert_contains "checkout: guest mode read from it" "$OUTPUT" "LAB_DISTRO=cachyos is supported by the lab"
assert_contains "checkout: firmware knob read from it" "$OUTPUT" "LAB_SECUREBOOT=on"
assert_not_contains "checkout: no clone" "$OUTPUT" "git clone"

# --- a checkout without them blocks -------------------------------------------------
export HASEEN_LAB_DIR="$SANDBOX/lab-old"
mkdir -p "$HASEEN_LAB_DIR/.git"
printf '#!/bin/sh\n' >"$HASEEN_LAB_DIR/lab"
capture "$LAB"
assert_status "old checkout: blocked" 1 "$STATUS"
assert_contains "old checkout: names the missing arm" "$OUTPUT" "no LAB_DISTRO=cachyos arm"
assert_contains "old checkout: nothing ran" "$OUTPUT" "the prerequisites above are not met; nothing was run"
assert_not_contains "old checkout: no plan" "$OUTPUT" "Plan:"
