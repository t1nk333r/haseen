# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# Plan 083 slice 1B: approving the private oniomarchy source. The key comes
# only from the fixed HTTPS URL with exactly the reviewed primary; the
# database signature is checked before any filename is read from it; the
# keyring archive is sealed, signature-checked and audited before any trust
# change; rotation needs a keyring signed by a currently accepted primary.
# curl, gpg, pacman-key, pacman and sudo are hermetic fixture stubs.
# shellcheck source=tests/fixtures/vapt-lib.sh
source "$FIXTURES/vapt-lib.sh"

if ! command -v bsdtar >/dev/null 2>&1; then
    echo "  (note: bsdtar is not installed; trust regressions were skipped)"
    return 0
fi

ONIO_FX="$FIXTURES/vapt-oniomarchy"
PIN=0F5F9214F312B067ECBF1DF125E2C00AA6340BD0
ROT=B0B0B0B0B0B0B0B0B0B0B0B0B0B0B0B0B0B0B0B0
CONF=$'[options]\nArchitecture = auto\nDownloadUser = alpm\nSigLevel = Required DatabaseOptional\n\n[core]\nServer = https://geo.mirror.pkgbuild.com/$repo/os/$arch\n\n[extra]\nServer = https://geo.mirror.pkgbuild.com/$repo/os/$arch'
SOURCES=/var/lib/haseen/vapt/sources

trust_case() { # NAME [serve key=value...]
    vapt_sandbox "$1"
    shift
    vapt_root
    printf '%s\n' "$CONF" >"$ROOT/etc/pacman.conf"
    vapt_repos "${VAPT_BASE[@]}"
    vapt_installed
    vapt_onio_arch x86_64
    vapt_transactions
    vapt_onio_stubs
    vapt_onio_serve "$@"
    CONF_BEFORE="$(cat "$ROOT/etc/pacman.conf")"
}
approved() { [[ -f $ROOT$SOURCES/oniomarchy.conf ]] && echo yes || echo no; }
trust_ops() { vapt_calls sudo | grep -F pacman-key || true; }
no_trust_change() { # LABEL
    assert_status "$1: refused" 1 "$STATUS"
    assert_eq "$1: no keyring trust change" '' "$(trust_ops)"
    assert_eq "$1: no package installed" '' "$(vapt_calls commit-config)"
    assert_eq "$1: not approved" no "$(approved)"
    assert_eq "$1: pacman.conf untouched" "$CONF_BEFORE" "$(cat "$ROOT/etc/pacman.conf")"
}

# --- approval: the complete pinned sequence -----------------------------------
trust_case vapt-onio-trust-approve
vapt_api repo-enable --yes
assert_status 'approval completes' 0 "$STATUS"
assert_eq 'the private descriptor is exactly the reviewed stanza' "$(cat "$ONIO_FX/source-descriptor.conf")" "$(cat "$ROOT$SOURCES/oniomarchy.conf")"
assert_eq 'pacman.conf is never changed' "$CONF_BEFORE" "$(cat "$ROOT/etc/pacman.conf")"
assert_eq 'every fetch is the fixed HTTPS host, no keyserver' '' \
    "$(sed 's/.* //' "$CALLS/curl" | grep -v '^https://pkgs\.oniomarchy\.com/' || true)"
assert_eq 'no fetch follows a redirect or allows plain HTTP' 5 "$(grep -c -- '--max-redirs 0 --proto =https --proto-redir =https' "$CALLS/curl")"
assert_eq 'the fetch order is key, database, signature, keyring, signature' \
    "curl https://pkgs.oniomarchy.com/oniomarchy.gpg|curl https://pkgs.oniomarchy.com/x86_64/oniomarchy.db|curl https://pkgs.oniomarchy.com/x86_64/oniomarchy.db.sig|gpg-verify oniomarchy.db|curl https://pkgs.oniomarchy.com/x86_64/oniomarchy-keyring-20260906-1-any.pkg.tar.gz|curl https://pkgs.oniomarchy.com/x86_64/oniomarchy-keyring-20260906-1-any.pkg.tar.gz.sig|gpg-verify oniomarchy-keyring-20260906-1-any.pkg.tar.gz" \
    "$(paste -sd'|' "$CALLS/order")"
assert_contains 'only the pinned primary is locally signed' "$(trust_ops)" "pacman-key --lsign-key $PIN"
assert_contains 'the audited keyring is populated explicitly' "$(trust_ops)" 'pacman-key --populate oniomarchy'
assert_contains 'the keyring is installed without scriptlets' "$(vapt_calls sudo)" '-U --noscriptlet'
assert_not_contains 'the keyring commit config names no repository' "$(vapt_calls commit-config)" '[oniomarchy]'
assert_contains 'the authority accepts the pin' "$(cat "$ROOT$SOURCES/oniomarchy.authority")" $'accepted\t'"$PIN"
vapt_api repo-status true
assert_contains 'the approved source is usable from recorded evidence' "$OUTPUT" '"state": "usable"'
assert_contains 'status never selects' "$OUTPUT" '"selected": false'
assert_contains 'the descriptor policy is strict' "$OUTPUT" '"descriptorPolicy": "Required DatabaseRequired"'
vapt_tools_untouched 'approval'

# Refresh: an opted-in operation re-verifies the database; no trust change.
: >"$CALLS/sudo"; : >"$CALLS/curl"
vapt_api install --yes --with-oniomarchy --groups automotive
assert_contains 'refresh re-fetches only the database' "$(cat "$CALLS/curl")" 'x86_64/oniomarchy.db.sig'
assert_not_contains 'refresh never refetches the key' "$(cat "$CALLS/curl")" 'oniomarchy.gpg'
assert_eq 'refresh changes no trust' '' "$(trust_ops)"
assert_contains 'refreshed source is usable' "$OUTPUT" $'# oniomarchy\tusable'
assert_contains 'can-utils resolves from the private source' "$(vapt_field can-utils 4)" 'oniomarchy/can-utils'

# Disable: only the unchanged descriptor; packages and keys stay.
installed_before="$(cat "$ROOT/var/lib/haseen/vapt/installed.json")"
: >"$CALLS/sudo"
vapt_api repo-disable --yes
assert_status 'disable completes' 0 "$STATUS"
assert_eq 'disable removes the descriptor' no "$(approved)"
assert_contains 'disable says keys and packages remain' "$OUTPUT" 'pacman keyring trust remain'
assert_eq 'disable removes no package' "$installed_before" "$(cat "$ROOT/var/lib/haseen/vapt/installed.json")"
assert_eq 'disable changes no key' '' "$(trust_ops)"
assert_eq 'the authority record is retained' yes "$([[ -f $ROOT$SOURCES/oniomarchy.authority ]] && echo yes || echo no)"
vapt_onio_seed
sed -i 's/DatabaseRequired/DatabaseOptional/' "$ROOT$SOURCES/oniomarchy.conf"
changed="$(cat "$ROOT$SOURCES/oniomarchy.conf")"
vapt_api repo-disable --yes
assert_status 'a changed descriptor is not removed' 1 "$STATUS"
assert_eq 'the changed descriptor is preserved' "$changed" "$(cat "$ROOT$SOURCES/oniomarchy.conf")"

# --- the fetched key ----------------------------------------------------------
for key in wrong extra revoked expired; do
    trust_case "vapt-onio-trust-key-$key" "key=$key"
    vapt_api repo-enable --yes
    no_trust_change "$key key"
    assert_eq "$key key: nothing fetched after the key" 1 "$(wc -l <"$CALLS/curl")"
done

# --- the database signature, before any filename is read ----------------------
for status in wrong expired revoked unknown multiple bad none; do
    trust_case "vapt-onio-trust-db-$status" "dbstatus=$status"
    vapt_api repo-enable --yes
    no_trust_change "database $status"
    assert_not_contains "database $status: no keyring archive fetched" "$(cat "$CALLS/curl")" 'oniomarchy-keyring'
done
trust_case vapt-onio-trust-no-keyring exclude=oniomarchy-keyring
vapt_api repo-enable --yes
no_trust_change 'database without a keyring record (name-only canary)'

# --- the keyring package: signature, digest, audit ----------------------------
for status in wrong expired none bad; do
    trust_case "vapt-onio-trust-pkg-$status" "pkgstatus=$status"
    vapt_api repo-enable --yes
    no_trust_change "keyring signature $status"
done
trust_case vapt-onio-trust-digest pkgdigest=bad
vapt_api repo-enable --yes
no_trust_change 'keyring bytes differ from the database digest'
for variant in hostile-scriptlet extra-member hook symlink missing-file; do
    trust_case "vapt-onio-trust-$variant" "variant=$variant"
    vapt_api repo-enable --yes
    no_trust_change "keyring layout $variant"
done
trust_case vapt-onio-trust-scriptlet variant=scriptlet
vapt_api repo-enable --yes
assert_status 'the population-only scriptlet is accepted' 0 "$STATUS"
assert_contains 'its population runs as an explicit step' "$(trust_ops)" 'pacman-key --populate oniomarchy'

# --- unsafe ancestry and redirected retained files ----------------------------
trust_case vapt-onio-trust-ancestry
mkdir -p "$SANDBOX/elsewhere" "$ROOT/var/lib/haseen/vapt"
ln -s "$SANDBOX/elsewhere" "$ROOT$SOURCES"
vapt_api repo-enable --yes
assert_status 'a redirected source directory is refused' 1 "$STATUS"
assert_eq 'nothing is written through it' '' "$(ls -A "$SANDBOX/elsewhere")"
assert_eq 'redirected directory: no trust change' '' "$(trust_ops)"
trust_case vapt-onio-trust-redirected
vapt_onio_seed
mv "$ROOT/usr/share/pacman/keyrings/oniomarchy-trusted" "$SANDBOX/trusted"
ln -s "$SANDBOX/trusted" "$ROOT/usr/share/pacman/keyrings/oniomarchy-trusted"
vapt_api repo-enable --yes
assert_status 'a redirected retained keyring file is refused' 1 "$STATUS"
assert_contains 'it needs manual review' "$OUTPUT" 'manual review'
assert_eq 'redirected keyring file: no trust change' '' "$(trust_ops)"

# --- rotation -----------------------------------------------------------------
while IFS=$'\t' read -r name itrusted irevoked via version trusted revoked signed expect; do
    [[ $irevoked != - ]] || irevoked=''
    [[ $revoked != - ]] || revoked=''
    trust_case vapt-onio-rotation "trusted=$itrusted" "revoked=$irevoked"
    vapt_api repo-enable --yes
    assert_status "$name: initial approval" 0 "$STATUS"
    if [[ $via != - ]]; then
        # An accepted intermediate keyring (VERSION/TRUSTED/REVOKED) first.
        IFS=/ read -r vversion vtrusted vrevoked <<<"$via"
        [[ $vrevoked != - ]] || vrevoked=''
        vapt_onio_serve "keyring=$vversion" "trusted=$vtrusted" "revoked=$vrevoked" pkgstatus=pinned
        vapt_api repo-enable --yes
        assert_status "$name: intermediate keyring accepted" 0 "$STATUS"
    fi
    vapt_onio_serve "keyring=$version" "trusted=$trusted" "revoked=$revoked" "pkgstatus=$signed"
    authority_before="$(cat "$ROOT$SOURCES/oniomarchy.authority")"
    : >"$CALLS/sudo"
    vapt_api repo-enable --yes
    if [[ $expect == accepted ]]; then
        assert_status "$name: accepted" 0 "$STATUS"
        assert_contains "$name: new accepted set" "$(cat "$ROOT$SOURCES/oniomarchy.authority")" "$ROT"
        assert_not_contains "$name: no second pin import" "$(trust_ops)" '--lsign-key'
    else
        assert_status "$name: refused" 1 "$STATUS"
        assert_eq "$name: authority unchanged" "$authority_before" "$(cat "$ROOT$SOURCES/oniomarchy.authority")"
        assert_eq "$name: no trust change" '' "$(trust_ops)"
    fi
done < <(python3 -c '
import json, sys
for c in json.load(open(sys.argv[1]))["cases"]:
    j = lambda v: ",".join(v) or "-"
    v = c.get("via")
    via = "/".join((v["version"], j(v["trusted"]), j(v["revoked"]))) if v else "-"
    print(c["name"], j(c["initialTrusted"]), j(c["initialRevoked"]), via, c["version"], j(c["trusted"]), j(c["revoked"]), c["signedBy"], c["expect"], sep="\t")
' "$ONIO_FX/trust/rotation.json")

# Raw-key replacement: after approval, a new key file and a database signed by
# its primary are refused; only the authority-accepted primaries count.
trust_case vapt-onio-rawkey
vapt_api repo-enable --yes
vapt_onio_serve key=wrong dbstatus=rotated
vapt_api repo-enable --yes
assert_status 'a raw key replacement is refused' 1 "$STATUS"
assert_not_contains 'the replaced key is never fetched' "$(tail -n 3 "$CALLS/curl")" 'oniomarchy.gpg'
assert_eq 'the pin is not replaced' "$PIN" "$(awk -F'\t' '$1 == "accepted" { print $2 }' "$ROOT$SOURCES/oniomarchy.authority")"

# --- dry-run and sysroot refusal (the real commands) --------------------------
trust_case vapt-onio-trust-dry
tree_before="$(vapt_tree)"
for command in repo-enable repo-disable repo-status; do
    args=(--dry-run oniomarchy)
    [[ $command != repo-status ]] || args=(--dry-run --json)
    vapt_cli "$command" "${args[@]}"
    assert_status "$command dry-run exit" 0 "$STATUS"
    assert_dry_pure "$command" "$OUTPUT"
    assert_eq "$command dry-run runs no stub" '' "$(ls -A "$CALLS")"
    assert_eq "$command dry-run writes nothing (no GPG home, state or lock)" "$tree_before" "$(vapt_tree)"
    assert_not_contains "$command claims no verification" "$OUTPUT" 'approved for dedicated'
done
vapt_cli repo-enable --dry-run oniomarchy
assert_contains 'enable dry-run shows the exact stanza' "$OUTPUT" '| Server = https://pkgs.oniomarchy.com/$arch'
assert_contains 'enable dry-run invents no filename' "$OUTPUT" '<filename-unknown-until-then>'
vapt_cli repo-enable oniomarchy
assert_status 'a fixture sysroot never drives a live approval' 2 "$STATUS"
assert_eq 'the refused approval ran nothing' '' "$(ls -A "$CALLS")"
vapt_cli repo-enable --dry-run bogus
assert_status 'an unknown source is a usage error' 2 "$STATUS"
vapt_cli repo-status --help
assert_contains 'status --help prints usage' "$OUTPUT" 'Usage: haseen vapt repo-status'
for f in repo-status repo-enable repo-disable; do
    assert_contains "haseen-vapt-$f has a summary" "$(cat "$REPO/bin/haseen-vapt-$f")" '# haseen:summary '
    assert_contains "haseen-vapt-$f takes --dry-run" "$(sed -n 's/^# haseen:args //p' "$REPO/bin/haseen-vapt-$f")" '--dry-run'
done
trust_case vapt-onio-trust-arch
vapt_onio_arch aarch64
vapt_api repo-enable --yes
assert_status 'an unsupported architecture is refused' 1 "$STATUS"
assert_eq 'unsupported architecture: nothing fetched' '' "$(vapt_calls curl)$(vapt_calls gpg)"
