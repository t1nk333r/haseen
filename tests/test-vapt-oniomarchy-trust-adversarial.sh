# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# Plan 087 adversarial: the private source's root state is never usable when
# a path is symlinked, hardlinked, replaceable or the wrong type; recorded
# keyring authority is the only signer set and cannot be widened or rolled
# back; signature statuses fail closed; a refresh that cannot verify changes
# nothing; a recovery record naming the private source is refused. curl, gpg,
# pacman-key, pacman and sudo are hermetic fixture stubs.
# shellcheck source=tests/fixtures/vapt-lib.sh
source "$FIXTURES/vapt-lib.sh"
# shellcheck source=tests/fixtures/vapt-onio-adversarial.sh
source "$FIXTURES/vapt-onio-adversarial.sh"

if ! command -v bsdtar >/dev/null 2>&1; then
    echo "  (note: bsdtar is not installed; private-source trust regressions were skipped)"
    return 0
fi

MARKER=var/lib/haseen/vapt/upgrade-pending

# --- unsafe state paths: never usable, preserved, never repaired -------------
state_mutate() { # CASE
    local s="$ROOT$SOURCES"
    case "$1" in
    hardlinked-descriptor) ln "$s/oniomarchy.conf" "$s/oniomarchy.conf.link" ;;
    group-writable-descriptor) chmod 0664 "$s/oniomarchy.conf" ;;
    descriptor-directory) rm "$s/oniomarchy.conf"; mkdir "$s/oniomarchy.conf" ;;
    world-writable-sources) chmod 0777 "$s" ;;
    world-writable-sync) chmod 0777 "$s/sync" ;;
    symlinked-sync) mv "$s/sync" "$SANDBOX/sync"; ln -s "$SANDBOX/sync" "$s/sync" ;;
    sources-regular-file) rm -rf "$s"; printf 'x\n' >"$s" ;;
    symlinked-state-ancestor)
        mv "$ROOT/var/lib/haseen/vapt" "$SANDBOX/vapt-real"
        ln -s "$SANDBOX/vapt-real" "$ROOT/var/lib/haseen/vapt" ;;
    symlinked-cached-database) mv "$s/sync/oniomarchy.db" "$SANDBOX/db"; ln -s "$SANDBOX/db" "$s/sync/oniomarchy.db" ;;
    database-note-directory) rm "$s/oniomarchy.database"; mkdir "$s/oniomarchy.database" ;;
    hardlinked-authority) ln "$s/oniomarchy.authority" "$SANDBOX/authority.link" ;;
    symlinked-keyring-archive)
        mv "$s/oniomarchy-keyring.pkg" "$SANDBOX/keyring.pkg"
        ln -s "$SANDBOX/keyring.pkg" "$s/oniomarchy-keyring.pkg" ;;
    keyring-archive-fifo) rm "$s/oniomarchy-keyring.pkg"; mkfifo "$s/oniomarchy-keyring.pkg" ;;
    *) return 97 ;;
    esac
}
# The private root state (with the stored keyring archive) and the pacman
# keyrings directory, which must stay free of oniomarchy files: type, mode,
# link count and content (no file is opened that could block, e.g. a FIFO).
trust_state() {
    find -P "$ROOT$SOURCES" "$ROOT/usr/share/pacman/keyrings" -printf '%P %y %m %n %s %l\n' 2>/dev/null | LC_ALL=C sort || true
    adv_digest "$ROOT$SOURCES"
    adv_digest "$ROOT/usr/share/pacman/keyrings" || true # absent: nothing is ever installed there
}
for case_name in hardlinked-descriptor group-writable-descriptor descriptor-directory world-writable-sources \
    world-writable-sync symlinked-sync sources-regular-file symlinked-state-ancestor symlinked-cached-database \
    database-note-directory hardlinked-authority symlinked-keyring-archive keyring-archive-fifo; do
    adv_approved "vapt-adv-trust-path-$case_name"
    state_mutate "$case_name"
    before="$(vapt_tree)"
    state_before="$(trust_state)"
    assert_not_contains "$case_name: never usable" "$(adv_state)" usable
    vapt_cli install --dry-run --with-oniomarchy --groups automotive
    assert_dry_pure "$case_name" "$OUTPUT"
    assert_eq "$case_name: planning invokes no stub" '' "$(ls -A "$CALLS")"
    assert_not_contains "$case_name: nothing is planned from the source" "$OUTPUT" $'\toniomarchy/'
    assert_eq "$case_name: planning changes nothing" "$before" "$(vapt_tree)"
    vapt_api repo-enable --yes
    assert_status "$case_name: approval refused" 1 "$STATUS"
    assert_eq "$case_name: no trust change" '' "$(adv_trust_ops)"
    assert_eq "$case_name: refused approval rewrote no private state" "$state_before" "$(trust_state)"
done

# --- the recorded authority is the signer set; it cannot be widened ----------
# The authority record must match the retained keyring files it was derived
# from: an accepted/revoked set the audited keyring never declared is not
# authority, even if the file digests still match.
adv_approved vapt-adv-trust-authority-widened
sed -i "s/^accepted\t.*/accepted\t$PIN,$ROT/" "$ROOT$SOURCES/oniomarchy.authority"
assert_not_contains 'an authority accepting a key the keyring never trusted is not usable' "$(adv_state)" usable
capture python3 "$VAPT_META" oniomarchy-signers --root "$ROOT"
assert_not_contains 'a widened authority never yields the undeclared signer' "$OUTPUT" "$ROT"
adv_case vapt-adv-trust-authority-unrevoked
vapt_onio_serve trusted=PIN revoked=OLD
vapt_onio_seed
sed -i 's/^revoked\t.*/revoked\t-/' "$ROOT$SOURCES/oniomarchy.authority"
assert_not_contains 'an authority dropping a revocation the keyring declares is not usable' "$(adv_state)" usable
adv_approved vapt-adv-trust-authority-garbage
printf 'haseen-vapt-oniomarchy-authority-v1\n' >"$ROOT$SOURCES/oniomarchy.authority"
assert_eq 'a truncated authority is a mismatch' mismatch "$(adv_field keyringAuthorityState)"
vapt_sudo_noop
vapt_api install --yes --with-oniomarchy --groups automotive
assert_eq 'a truncated authority: opted-in run fetches nothing' 0 "$(adv_onio_fetches)"
assert_eq 'a truncated authority: opted-in run changes no trust' '' "$(adv_trust_ops)"

# --- rotation away from the pin claims nothing it cannot back ----------------
# A keyring signed by the pin that trusts only ROT and revokes the pin is a
# legitimate rotation; the database it was verified with is signed by the now
# revoked pin, so the source is not usable until a ROT-signed refresh.
adv_case vapt-adv-trust-rotate-away
vapt_api repo-enable --yes
assert_status 'rotation: initial approval' 0 "$STATUS"
vapt_onio_serve keyring=20261101-1 trusted=ROT revoked=PIN pkgstatus=pinned
vapt_api repo-enable --yes
rotated_status="$STATUS"
rotated_output="$OUTPUT"
if [[ $(adv_state) == usable ]]; then
    assert_status 'rotation away: approval completes' 0 "$rotated_status"
else
    assert_not_contains 'rotation away: no approval claimed while the source is unverified' "$rotated_output" 'approved for dedicated'
fi
assert_contains 'rotation away: the new authority accepts only ROT' "$(cat "$ROOT$SOURCES/oniomarchy.authority")" $'accepted\t'"$ROT"
vapt_onio_serve keyring=20261101-1 trusted=ROT revoked=PIN pkgstatus=rotated dbstatus=pinned
vapt_sudo_noop
vapt_api install --yes --with-oniomarchy --groups automotive
assert_not_contains 'rotation away: a database signed by the revoked pin is refused' "$(adv_annotation)" usable
assert_eq 'rotation away: a pin-signed database resolves nothing' none "$(vapt_field can-utils 3)"
assert_contains 'rotation away: the refusal names repo-enable' "$(adv_annotation_reason)" 'haseen vapt repo-enable oniomarchy'
vapt_onio_serve keyring=20261101-1 trusted=ROT revoked=PIN pkgstatus=rotated dbstatus=rotated
vapt_api install --yes --with-oniomarchy --groups automotive
assert_eq 'rotation away: a ROT-signed refresh is usable' usable "$(adv_annotation)"

# --- a refresh never applies a published keyring change, but says so --------
adv_case vapt-adv-trust-rotation-pending
vapt_api repo-enable --yes
authority="$(cat "$ROOT$SOURCES/oniomarchy.authority")"
vapt_onio_serve keyring=20261101-1 trusted=ROT revoked=PIN pkgstatus=pinned
: >"$CALLS/sudo"
vapt_sudo_noop
vapt_api install --yes --with-oniomarchy --groups automotive
assert_eq 'pending rotation: the refreshed source stays usable' usable "$(adv_annotation)"
assert_contains 'pending rotation: the run names repo-enable' "$(adv_annotation_reason)" \
    'differs from the recorded authority; a refresh never applies it: review it with haseen vapt repo-enable oniomarchy'
assert_eq 'pending rotation: the refresh changes no trust' '' "$(adv_trust_ops)"
assert_eq 'pending rotation: the authority is unchanged' "$authority" "$(cat "$ROOT$SOURCES/oniomarchy.authority")"

# --- a keyring's own trusted list never grants revocation authority ----------
# trusted={PIN,ARCH}, revoked={ARCH}, signed by PIN: populate would revoke the
# unrelated global ARCH key. Refused at the first approval, before any trust op.
adv_case vapt-adv-trust-revocation-launder
vapt_onio_serve trusted=PIN,ARCH revoked=ARCH
vapt_api repo-enable --yes
assert_status 'revocation launder: refused' 1 "$STATUS"
assert_contains 'revocation launder: the foreign key is named' "$OUTPUT" 'revokes primaries this source never used (D0D0D0D0D0D0D0D0D0D0D0D0D0D0D0D0D0D0D0D0)'
assert_eq 'revocation launder: no trust change (no populate)' '' "$(adv_trust_ops)"
assert_eq 'revocation launder: not approved' no "$(adv_exists "$ROOT$SOURCES/oniomarchy.conf")"

# --- a merely listed key never becomes revocable (two-stage) ------------------
# Stage 1 lists ARCH as trusted (admitted: listing is not use); stage 2 revokes
# it. ARCH never signed anything of this source, so stage 2 is refused before
# pacman-key --populate could disable the unrelated global key.
adv_case vapt-adv-trust-revocation-two-stage
vapt_api repo-enable --yes
assert_status 'two-stage: initial approval' 0 "$STATUS"
vapt_onio_serve keyring=20261015-1 trusted=PIN,ARCH revoked=
vapt_api repo-enable --yes
assert_status 'two-stage: a foreign key merely listed as trusted is admitted' 0 "$STATUS"
assert_not_contains 'two-stage: a listed key is not recorded as observed' \
    "$(awk -F'\t' '$1 == "observed" { print $2 }' "$ROOT$SOURCES/oniomarchy.authority")" D0D0D0D0D0D0D0D0D0D0D0D0D0D0D0D0D0D0D0D0
authority="$(cat "$ROOT$SOURCES/oniomarchy.authority")"
vapt_onio_serve keyring=20261101-1 trusted=PIN,ARCH revoked=ARCH
: >"$CALLS/sudo"
vapt_api repo-enable --yes
assert_status 'two-stage: revoking the listed foreign key is refused' 1 "$STATUS"
assert_contains 'two-stage: the reason names the never-used key' "$OUTPUT" 'revokes primaries this source never used'
assert_eq 'two-stage: no trust change (no populate)' '' "$(adv_trust_ops)"
assert_eq 'two-stage: no authority write' "$authority" "$(cat "$ROOT$SOURCES/oniomarchy.authority")"

# --- publisher-declared ownertrust never reaches the shared keyring -----------
# A pin-signed keyring whose trusted list gives an unrelated key ownertrust
# 128 (disabled) and another 3 (never trust) revokes nothing, so the audit
# admits it. haseen populates the keyring itself: no --populate, no
# ownertrust import, only explicit --add of the exported accepted primaries
# and --lsign-key for each.
adv_case vapt-adv-trust-ownertrust
vapt_api repo-enable --yes
assert_status 'ownertrust: initial approval' 0 "$STATUS"
vapt_onio_serve keyring=20261015-1 trusted=PIN:4,ROT:3,ARCH:128 revoked=
: >"$CALLS/sudo"; : >"$CALLS/gpg"
vapt_api repo-enable --yes
assert_status 'ownertrust: the keyring (nothing revoked) is admitted' 0 "$STATUS"
assert_not_contains 'ownertrust: pacman-key --populate is never run' "$(adv_trust_ops)" '--populate'
assert_not_contains 'ownertrust: no ownertrust is imported (pacman-key)' "$(vapt_calls sudo)" 'import-ownertrust'
assert_not_contains 'ownertrust: no ownertrust is imported (gpg)' "$(vapt_calls gpg)" 'import-ownertrust'
assert_contains 'ownertrust: only exported accepted primaries are added' "$(adv_trust_ops)" 'pacman-key --add'
assert_eq 'ownertrust: exactly the newly accepted primaries are lsigned' \
    "$(printf 'pacman-key --lsign-key %s\n' "$ROT" D0D0D0D0D0D0D0D0D0D0D0D0D0D0D0D0D0D0D0D0 | LC_ALL=C sort)" \
    "$(grep -o 'pacman-key --lsign-key [A-F0-9]*' <<<"$(adv_trust_ops)" | LC_ALL=C sort)"
assert_not_contains 'ownertrust: no key is deleted or disabled' "$(adv_trust_ops)" '--delete'
# The archive's key file must hold exactly the newly accepted primaries.
adv_case vapt-adv-trust-key-file-short
vapt_api repo-enable --yes
vapt_onio_serve keyring=20261015-1 trusted=PIN,ROT revoked=
authority="$(cat "$ROOT$SOURCES/oniomarchy.authority")"
: >"$CALLS/sudo"
VAPT_GPG_EXPORT_DROP="$ROT" vapt_api repo-enable --yes
assert_status 'a key file lacking an accepted primary is refused' 1 "$STATUS"
assert_contains 'and says so' "$OUTPUT" 'does not hold exactly the newly accepted primaries'
assert_eq 'key file short: no trust change' '' "$(adv_trust_ops)"
assert_eq 'key file short: no authority write' "$authority" "$(cat "$ROOT$SOURCES/oniomarchy.authority")"

# --- revoked-key removal: presence only from a parsed machine listing --------
# A rotation that revokes the pin (ROT already accepted, ROT-signed database).
# The shared keyring is listed in gpg's colon format and parsed. A failed
# lookup, a listing in a human presentation, an empty or malformed listing,
# or a failed deletion fails the approval before the archive and authority
# are written, so the revocation stays pending; a retry then completes it.
revoke_case() { # NAME — approved PIN,ROT source; the next keyring revokes PIN
    adv_case "vapt-adv-trust-revoke-$1"
    vapt_onio_serve trusted=PIN,ROT
    vapt_api repo-enable --yes
    assert_status "revoke $1: initial approval" 0 "$STATUS"
    vapt_onio_serve keyring=20261015-1 trusted=ROT revoked=PIN pkgstatus=pinned dbstatus=rotated
    authority="$(cat "$ROOT$SOURCES/oniomarchy.authority")"
    archive="$(sha256sum "$ROOT$SOURCES/oniomarchy-keyring.pkg")"
    : >"$CALLS/sudo"
}
while IFS='|' read -r failing listing keyfail reason; do
    revoke_case "$failing"
    VAPT_KEYRING_LISTING="$listing" VAPT_PACMAN_KEY_FAIL="$keyfail" vapt_api repo-enable --yes
    assert_status "revoke $failing: the approval fails" 1 "$STATUS"
    assert_contains "revoke $failing: with the retry reason" "$OUTPUT" "$reason"
    assert_eq "revoke $failing: the revocation is not recorded as completed" "$authority" "$(cat "$ROOT$SOURCES/oniomarchy.authority")"
    assert_eq "revoke $failing: the stored archive is unchanged" "$archive" "$(sha256sum "$ROOT$SOURCES/oniomarchy-keyring.pkg")"
    [[ $failing == delete ]] || assert_not_contains "revoke $failing: nothing is deleted on an uninterpretable answer" "$(adv_trust_ops)" '--delete'
    : >"$CALLS/sudo"
    vapt_api repo-enable --yes
    assert_status "revoke $failing: a retry after recovery completes" 0 "$STATUS"
    assert_contains "revoke $failing: the retry removes the revoked key" "$(adv_trust_ops)" "pacman-key --delete $PIN"
    assert_contains "revoke $failing: and records the revocation" "$(cat "$ROOT$SOURCES/oniomarchy.authority")" $'revoked\t'"$PIN"
done <<'EOF'
lookup-error|fail||shared pacman keyring lookup failed
human-listing|human||listing could not be interpreted
empty-listing|empty||listing could not be interpreted
malformed-listing|malformed||listing could not be interpreted
delete|colons|delete|could not be removed from the shared pacman keyring
EOF
# A parseable listing without the revoked key is positive absence: nothing to
# delete, and the revocation is recorded.
revoke_case absent
VAPT_KEYRING_LISTING=colons-no-pin vapt_api repo-enable --yes
assert_status 'revoke absent: a parsed listing without the key completes' 0 "$STATUS"
assert_not_contains 'revoke absent: nothing is deleted' "$(adv_trust_ops)" '--delete'
assert_contains 'revoke absent: the revocation is recorded' "$(cat "$ROOT$SOURCES/oniomarchy.authority")" $'revoked\t'"$PIN"

# --- an installed oniomarchy keyring package is never left in place ----------
# Its files are where a manual pacman-key --populate would apply them.
adv_case vapt-adv-trust-installed-keyring
mkdir -p "$ROOT/usr/share/pacman/keyrings"
printf '%s:128:\n' D0D0D0D0D0D0D0D0D0D0D0D0D0D0D0D0D0D0D0D0 >"$ROOT/usr/share/pacman/keyrings/oniomarchy-trusted"
vapt_api repo-enable --yes
assert_status 'an installed oniomarchy keyring file refuses approval' 1 "$STATUS"
assert_contains 'and names it' "$OUTPUT" '/usr/share/pacman/keyrings/oniomarchy-trusted'
assert_contains 'and why' "$OUTPUT" 'haseen never installs it'
assert_eq 'installed keyring: no trust change' '' "$(adv_trust_ops)"
assert_eq 'installed keyring: not approved' no "$(adv_exists "$ROOT$SOURCES/oniomarchy.conf")"

# --- repeated approval of an unchanged keyring changes no trust --------------
adv_case vapt-adv-trust-reapprove
vapt_api repo-enable --yes
: >"$CALLS/sudo"; : >"$CALLS/curl"
vapt_api repo-enable --yes
assert_status 're-approval completes' 0 "$STATUS"
assert_eq 're-approval changes no trust' '' "$(adv_trust_ops)"
assert_not_contains 're-approval never refetches the key' "$(vapt_calls curl)" 'oniomarchy.gpg'
assert_not_contains 're-approval installs no package' "$(vapt_calls sudo)" ' -U '

# --- signature status edge cases (database) -----------------------------------
while IFS='|' read -r label status; do
    adv_case "vapt-adv-trust-status"
    adv_db_status "$(printf '%b' "$status")"
    vapt_api repo-enable --yes
    assert_status "database status $label: refused" 1 "$STATUS"
    assert_eq "database status $label: no trust change" '' "$(adv_trust_ops)"
    assert_not_contains "database status $label: no keyring fetched" "$(vapt_calls curl)" 'oniomarchy-keyring'
    assert_eq "database status $label: not approved" no "$(adv_exists "$ROOT$SOURCES/oniomarchy.conf")"
done <<EOF
VALIDSIG without primary field naming a subkey|[GNUPG:] NEWSIG\n[GNUPG:] GOODSIG 25E2C00AA6340BD0 x\n[GNUPG:] VALIDSIG 1111222233334444555566667777888899990000 2026-10-07 1791331200 0 4 0 22 10 00
truncated VALIDSIG|[GNUPG:] NEWSIG\n[GNUPG:] VALIDSIG $PIN 2026-10-07
second signature unverifiable|[GNUPG:] NEWSIG\n[GNUPG:] VALIDSIG 1111222233334444555566667777888899990000 2026-10-07 1791331200 0 4 0 22 10 00 $PIN\n[GNUPG:] NEWSIG\n[GNUPG:] ERRSIG 25E2C00AA6340BD0 22 10 00 1791331200 9 -
key expired notice|[GNUPG:] NEWSIG\n[GNUPG:] KEYEXPIRED 1700000000\n[GNUPG:] VALIDSIG 1111222233334444555566667777888899990000 2026-10-07 1791331200 0 4 0 22 10 00 $PIN
lowercase pin|[GNUPG:] NEWSIG\n[GNUPG:] VALIDSIG 1111222233334444555566667777888899990000 2026-10-07 1791331200 0 4 0 22 10 00 ${PIN,,}
pin plus another primary|[GNUPG:] NEWSIG\n[GNUPG:] VALIDSIG 1111222233334444555566667777888899990000 2026-10-07 1791331200 0 4 0 22 10 00 $PIN\n[GNUPG:] NEWSIG\n[GNUPG:] VALIDSIG 1111222233334444555566667777888899990000 2026-10-07 1791331200 0 4 0 22 10 00 $ROT
empty status|
EOF

# --- refresh that cannot verify changes nothing -------------------------------
for variant in bad wrong none unreachable; do
    adv_approved "vapt-adv-trust-refresh-$variant"
    cached="$(adv_digest "$ROOT$SOURCES")"
    case "$variant" in
    unreachable) rm "$SANDBOX/onio/serve/oniomarchy.db" ;;
    *) vapt_onio_serve "dbstatus=$variant" ;;
    esac
    vapt_sudo_noop
    vapt_api install --yes --with-oniomarchy --groups automotive
    assert_not_contains "refresh $variant: not usable" "$(adv_annotation)" usable
    assert_eq "refresh $variant: nothing resolves from the source" none "$(vapt_field can-utils 3)"
    assert_eq "refresh $variant: cached private state byte-identical" "$cached" "$(adv_digest "$ROOT$SOURCES")"
    assert_eq "refresh $variant: no trust change" '' "$(adv_trust_ops)"
    assert_contains "refresh $variant: tier recorded" "$(vapt_field can-utils 8)" 'oniomarchy:'
    [[ $variant != wrong ]] ||
        assert_contains 'refresh wrong: the reason names repo-enable for a rotation' "$(adv_annotation_reason)" 'haseen vapt repo-enable oniomarchy'
done

# --- a served database differing from the cached one is never planned from ---
adv_approved vapt-adv-trust-cache-swap
printf 'x' >>"$ROOT$SOURCES/sync/oniomarchy.db"
vapt_plan 'cached database bytes changed' --with-oniomarchy --groups automotive
assert_eq 'changed cached bytes: unverified' unverified "$(adv_annotation)"
assert_eq 'changed cached bytes: nothing resolves' none "$(vapt_field can-utils 3)"

# --- a record naming the private source is not part of the protocol ---------
recover_case() { # NAME
    adv_approved "$1"
    : >"$SANDBOX/plan.tsv"
    export VAPT_PLAN="$SANDBOX/plan.tsv" VAPT_ARCHIVES="$SANDBOX/archives" VAPT_MOCK_SIGNATURES=1
    mkdir -p "$SANDBOX/archives"
    printf 'original system sync DB\n' >"$ROOT/var/lib/pacman/sync/extra.db"
    # The private source never joins a full upgrade (plan 087), so no scope
    # digest exists to bind; any such record is refused and preserved.
    DIGEST="$(printf 'recorded scope' | sha256sum | cut -d' ' -f1)"
}
recover_case vapt-adv-trust-recover-disabled
printf 'reviewed-full-upgrade-commit-pending\toniomarchy-private\t%s\n' "$DIGEST" >"$ROOT/$MARKER"
rm "$ROOT$SOURCES/oniomarchy.conf"
vapt_api recover
assert_status 'recovery after disable is refused' 2 "$STATUS"
assert_eq 'recovery after disable: record preserved' yes "$(adv_exists "$ROOT/$MARKER")"
assert_eq 'recovery after disable: nothing reviewed' '' "$(vapt_calls review-repos)"
recover_case vapt-adv-trust-recover-uppercase
printf 'reviewed-full-upgrade-commit-pending\toniomarchy-private\t%s\n' "${DIGEST^^}" >"$ROOT/$MARKER"
vapt_api recover
assert_status 'a case-changed scope digest is refused' 2 "$STATUS"
recover_case vapt-adv-trust-recover-host-stanza
printf 'reviewed-full-upgrade-commit-pending\toniomarchy-private\t%s\n' "$DIGEST" >"$ROOT/$MARKER"
weak_stanza=$'[oniomarchy]\nSigLevel = Optional TrustAll\nServer = http://pkgs.oniomarchy.com/$arch'
vapt_conf_add "$weak_stanza"
conf_before="$(cat "$ROOT/etc/pacman.conf")"
vapt_api recover
assert_not_contains 'recovery never renders the host stanza policy' "$(vapt_calls frozen-config)$(vapt_calls commit-config)" 'TrustAll'
assert_not_contains 'recovery never renders the host stanza mirror' "$(vapt_calls frozen-config)$(vapt_calls commit-config)" 'http://pkgs'
assert_eq 'recovery with a host stanza leaves pacman.conf' "$conf_before" "$(cat "$ROOT/etc/pacman.conf")"
recover_case vapt-adv-trust-recover-generic
printf 'reviewed-full-upgrade-commit-pending\n' >"$ROOT/$MARKER"
vapt_sudo_noop
vapt_transactions
vapt_api install --yes --with-oniomarchy --groups automotive
assert_not_contains 'a generic record resumes without the private scope even when this run opts in' \
    "$(vapt_calls review-repos | head -n1)" 'oniomarchy'
recover_case vapt-adv-trust-recover-symlink
printf 'reviewed-full-upgrade-commit-pending\toniomarchy-private\t%s\n' "$DIGEST" >"$SANDBOX/record"
ln -s "$SANDBOX/record" "$ROOT/$MARKER"
vapt_api recover
assert_status 'a symlinked recovery record is refused' 2 "$STATUS"
assert_eq 'a symlinked recovery record reviews nothing' '' "$(vapt_calls review-repos)"
vapt_tools_untouched 'trust adversarial'
