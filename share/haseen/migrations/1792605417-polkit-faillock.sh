# shellcheck shell=bash
# Plan 101: restore polkit's brute-force lockout where Omarchy's old
# fingerprint or FIDO2 setup removed it. Those commands, run while
# /etc/pam.d/polkit-1 did not exist (Arch ships polkit's stack in
# /usr/lib/pam.d), wrote one listing pam_unix directly instead of
# `include system-auth`, which drops pam_faillock: polkit prompts had no
# lockout and their failures never counted. Omarchy repairs it in its
# migration 1788256455, which haseen's seal (1792605416) skips, so haseen runs
# the same check. haseen's own setup commands only add a line to an existing
# file (bin/haseen-setup-fingerprint, bin/haseen-setup-fido2), so they never
# write this stack.
#
# Adapted from Omarchy migrations/1788256455.sh@v4.5.0-rc1 (MIT, Copyright (c)
# David Heinemeier Hansson): only the exact stack those commands produced is
# touched (every meaningful line one they wrote, all four bare pam_unix lines,
# no system-auth include yet); only the bare pam_unix lines change; a backup
# is kept and restored if the result cannot be verified. Safe to re-run: a
# fixed or administrator-written file is left alone.

# shellcheck source=../lib/common.sh
source "$HASEEN_PATH/lib/common.sh"

POLKIT_PAM=/etc/pam.d/polkit-1

polkit_vulnerable_stack() {
    local file="$1" line phase
    local re_gate='^auth[[:space:]]+\[success=1 default=ignore\][[:space:]]+pam_exec\.so quiet /usr/bin/omarchy-hw-laptop-closed[[:space:]]*$'
    local re_fprintd='^auth[[:space:]]+sufficient[[:space:]]+pam_fprintd\.so[[:space:]]*$'
    local re_u2f='^auth[[:space:]]+sufficient[[:space:]]+pam_u2f\.so cue authfile=/etc/fido2/fido2[[:space:]]*$'
    local re_bare='^(auth|account|password|session)[[:space:]]+required[[:space:]]+pam_unix\.so[[:space:]]*$'
    grep -qE '^(auth|account|password|session)[[:space:]]+include[[:space:]]+system-auth' "$file" && return 1
    for phase in auth account password session; do
        grep -qE "^${phase}[[:space:]]+required[[:space:]]+pam_unix\.so[[:space:]]*\$" "$file" || return 1
    done
    while IFS= read -r line || [[ -n $line ]]; do
        [[ -z ${line//[[:space:]]/} || $line == \#* ]] && continue
        [[ $line =~ $re_gate || $line =~ $re_fprintd || $line =~ $re_u2f || $line =~ $re_bare ]] && continue
        return 1
    done <"$file"
}

file="$(sysroot_path "$POLKIT_PAM")"
[[ -f $file ]] && polkit_vulnerable_stack "$file" || exit 0

info "$POLKIT_PAM lists pam_unix directly (Omarchy's old fingerprint/FIDO2 setup): restoring pam_faillock through system-auth"
backup="$POLKIT_PAM.haseen-bak.$(date +%s)"
run_root cp -a "$POLKIT_PAM" "$backup" || die "could not back up $POLKIT_PAM; left unchanged, the migration retries"
# sed -i renames a complete file into place, so an interrupted run never
# leaves polkit-1 truncated.
if ! run_root sed -i -E 's/^(auth|account|password|session)([[:space:]]+)required[[:space:]]+pam_unix\.so[[:space:]]*$/\1\2include system-auth/' "$POLKIT_PAM"; then
    die "could not rewrite $POLKIT_PAM; left unchanged, the migration retries"
fi
$DRY_RUN && exit 0
if ! grep -qE '^auth[[:space:]]+include[[:space:]]+system-auth' "$file"; then
    run_root cp -a "$backup" "$POLKIT_PAM"
    die "the repair of $POLKIT_PAM could not be verified; the original is back"
fi
info "polkit's brute-force lockout restored; the previous file is $backup"
