# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# Runtime path handling for the shell and installer.
sandbox paths

# Exercise install.sh's dry-run branch with an absent install prefix and a fake
# installed CLI that reports the HASEEN_PATH it receives.
stage="$SANDBOX/stage"
mkdir -p "$stage/bin" "$stage/share"
cp "$REPO/install.sh" "$stage/install.sh"
ln -s "$REPO/share/haseen" "$stage/share/haseen"
cat >"$stage/bin/haseen" <<'EOF'
#!/usr/bin/env bash
printf 'HASEEN_PATH=%s\n' "$HASEEN_PATH"
EOF
chmod +x "$stage/bin/haseen"

capture env HASEEN_SYSROOT="$FIXTURES/desk-cachyos-amd" \
    "$stage/install.sh" --dry-run --yes --prefix "$SANDBOX/prefix" --layers base
assert_status "installer dry-run succeeds without an installed tree" 0 "$STATUS"
expected_haseen_path="$(readlink -f -- "$stage/share/haseen")"
assert_contains "installer dry-run passes the normalized checkout tree" \
    "$OUTPUT" "HASEEN_PATH=$expected_haseen_path"
assert_not_contains "installer dry-run path has no parent traversal" "$OUTPUT" "/../"
# A fresh HOME runs four CLI phases: layer apply, migrate --seal, setup nvim
# --if-absent (plan 065) and hw apply.
haseen_path_calls="$(grep -Fc "HASEEN_PATH=$expected_haseen_path" <<<"$OUTPUT" || true)"
assert_eq "all dry-run CLI phases receive the same normalized path" 4 "$haseen_path_calls"
if [[ ! -e $SANDBOX/prefix ]]; then
    _pass
else
    _fail "dry-run leaves the not-yet-installed prefix absent"
fi


# A pre-existing migration ledger takes the other branch at the migrate callsite.
mkdir -p "$XDG_STATE_HOME/haseen/migrations"
capture env HASEEN_SYSROOT="$FIXTURES/desk-cachyos-amd" \
    "$stage/install.sh" --dry-run --yes --prefix "$SANDBOX/prefix" --layers base
assert_status "reinstall dry-run succeeds without an installed tree" 0 "$STATUS"
assert_contains "reinstall dry-run passes the normalized checkout tree" \
    "$OUTPUT" "HASEEN_PATH=$expected_haseen_path"
assert_not_contains "reinstall dry-run path has no parent traversal" "$OUTPUT" "/../"
haseen_path_calls="$(grep -Fc "HASEEN_PATH=$expected_haseen_path" <<<"$OUTPUT" || true)"
assert_eq "reinstall CLI phases receive the same normalized path" 3 "$haseen_path_calls"
# The /proc scan cannot be faked in a hermetic test. Exercise the same argv/path
# matcher against NUL-separated cmdline fixtures instead.
source "$HASEEN_PATH/lib/doctor.sh"
prefix="$SANDBOX/prefix"
shell_dir="$prefix/share/haseen/shell"
other_shell_dir="$prefix/share/haseen/other-shell"
mkdir -p "$prefix/bin" "$shell_dir" "$other_shell_dir"
cmdline="$SANDBOX/qs.cmdline"

equivalent_shell_dir="$prefix/bin/../share/haseen/shell"
printf '%s\0' qs -p "$equivalent_shell_dir" >"$cmdline"
capture doctor_shell_cmdline_matches "$shell_dir" "$prefix" "$cmdline"
assert_status "doctor matches an equivalent Quickshell -p path" 0 "$STATUS"
# A space-joined search must not mistake text embedded in another argv value
# for the -p argument.
printf '%s\0' qs --description "-p $shell_dir" -p "$other_shell_dir" >"$cmdline"
capture doctor_shell_cmdline_matches "$shell_dir" "$prefix" "$cmdline"
assert_status "doctor only compares the actual -p argv value" 1 "$STATUS"

spaced_shell_dir="$prefix/share/haseen/shell with spaces"
mkdir -p "$spaced_shell_dir"
printf '%s\0' qs -p "$prefix/bin/../share/haseen/shell with spaces" >"$cmdline"
capture doctor_shell_cmdline_matches "$spaced_shell_dir" "$prefix" "$cmdline"
assert_status "doctor preserves spaces in a single -p argv value" 0 "$STATUS"

# Relative -p paths belong to the candidate process, not the doctor's cwd.
mkdir -p "$SANDBOX/doctor" "$SANDBOX/other-project/share/haseen/shell"
process_cwd="$SANDBOX/proc-cwd"
other_process_cwd="$SANDBOX/other-proc-cwd"
ln -s "$prefix" "$process_cwd"
ln -s "$SANDBOX/other-project" "$other_process_cwd"
relative_shell_dir="./share/haseen/shell"
printf '%s\0' qs -p "$relative_shell_dir" >"$cmdline"
run_doctor_shell_match() {
    (cd -- "$doctor_cwd" && doctor_shell_cmdline_matches "$shell_dir" "$process_cwd" "$cmdline")
}

doctor_cwd="$SANDBOX/doctor"
capture run_doctor_shell_match
assert_status "doctor matches a relative -p path from the process cwd" 0 "$STATUS"

# The same argv from another checkout must not match this checkout's shell.
doctor_cwd="$prefix"
process_cwd="$other_process_cwd"
capture run_doctor_shell_match
assert_status "doctor rejects a relative -p path from another project" 1 "$STATUS"
