# shellcheck shell=bash
# haseen:covers share/haseen/default/vapt/** share/haseen/layers/vapt/**
# haseen:covers share/haseen/lib/packages.sh tests/fixtures/vapt-host/**
# haseen:covers tests/fixtures/vapt-oniomarchy/** tests/fixtures/vapt-driver.py
# haseen:covers tests/fixtures/vapt-lib.sh tests/fixtures/vapt-runner.sh
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# Plan 087 slice 1B: transactions with the private oniomarchy source keep
# Required DatabaseRequired in rendered, private and frozen configurations;
# closure admits only the fixed roles by exact name or reviewed alias; a full
# upgrade never carries the private source and no recovery record names it.
# Package manager, keys and network are hermetic fixture stubs.
# shellcheck source=tests/fixtures/vapt-lib.sh
source "$FIXTURES/vapt-lib.sh"

if ! command -v bsdtar >/dev/null 2>&1; then
    echo "  (note: bsdtar is not installed; transaction regressions were skipped)"
    return 0
fi

ONIO_FX="$FIXTURES/vapt-oniomarchy"
CONF=$'[options]\nArchitecture = auto\nDownloadUser = alpm\nSigLevel = Required DatabaseOptional\n\n[core]\nServer = https://geo.mirror.pkgbuild.com/$repo/os/$arch\n\n[extra]\nServer = https://geo.mirror.pkgbuild.com/$repo/os/$arch'
MARKER=var/lib/haseen/vapt/upgrade-pending

tx_case() { # NAME [extra repository rows...]
    vapt_sandbox "$1"
    shift
    vapt_root
    printf '%s\n' "$CONF" >"$ROOT/etc/pacman.conf"
    printf 'original system sync DB\n' >"$ROOT/var/lib/pacman/sync/extra.db"
    vapt_repos "$@"
    vapt_installed
    vapt_onio_arch x86_64
    vapt_transactions
    vapt_onio_stubs
    vapt_onio_serve
    vapt_onio_seed
    : >"$SANDBOX/plan.tsv"
    export VAPT_PLAN="$SANDBOX/plan.tsv" VAPT_ARCHIVES="$SANDBOX/archives" VAPT_MOCK_SIGNATURES=1
    mkdir -p "$SANDBOX/archives"
    CONF_BEFORE="$(cat "$ROOT/etc/pacman.conf")"
}
meta() { python3 "$VAPT_META" "$@" --root "$ROOT"; }
pending() { [[ -e $ROOT/$MARKER ]] && echo yes || echo no; }

# --- rendered configurations keep the strict policy ----------------------------
tx_case vapt-onio-tx-config
rendered="$(meta config --with-oniomarchy)"
assert_contains 'the private stanza is rendered with its strict policy' "$rendered" \
    $'[oniomarchy]\nSigLevel = Required DatabaseRequired\nServer = https://pkgs.oniomarchy.com/$arch\nUsage = Sync Search Install'
assert_eq 'the private source is the last section' '[oniomarchy]' "$(grep '^\[' <<<"$rendered" | tail -n1)"
assert_not_contains 'without the operation flag it is absent' "$(meta config)" 'oniomarchy'
frozen="$(meta config --with-oniomarchy --frozen /var/cache/haseen-vapt.x/reviewed)"
assert_contains 'the frozen configuration keeps DatabaseRequired' "$frozen" \
    $'[oniomarchy]\nSigLevel = Required DatabaseRequired\nServer = file:///var/cache/haseen-vapt.x/reviewed/oniomarchy'
vapt_conf_add $'[oniomarchy]\nSigLevel = Optional TrustAll\nServer = http://pkgs.oniomarchy.com/$arch'
assert_not_contains 'a host stanza is never rendered' "$(meta config --with-oniomarchy)" 'Optional TrustAll'
find "$VAPT_LAYER" -name __pycache__ -prune -exec rm -rf {} +

# --- closure admission (exact roles, no Provides, no shadowing) ----------------
while IFS=$'\t' read -r name target plan extra expect; do
    [[ $plan != - ]] || plan=''
    [[ $extra != - ]] || extra=''
    rows=()
    [[ -z $extra ]] || IFS=';' read -r -a rows <<<"$extra"
    tx_case vapt-onio-tx-closure "${rows[@]}"
    db="$ROOT/var/cache/haseen-vapt.review/db"
    mkdir -p "$db/sync"
    cp "$SANDBOX/onio/serve/oniomarchy.db" "$db/sync/"
    cp "$ROOT/var/lib/haseen/vapt/repositories.json" "$db/sync/"
    if [[ -n $plan ]]; then
        tr ';' '\n' <<<"$plan" | tr ',' '\t' >"$SANDBOX/closure.tsv"
        capture meta closure "$target" "$SANDBOX/closure.tsv" --dbpath "$db" --with-oniomarchy
    else
        capture meta closure "$target" --dbpath "$db" --with-oniomarchy
    fi
    if [[ $expect == safe ]]; then
        assert_status "$name: admitted" 0 "$STATUS"
    else
        assert_status "$name: refused" 1 "$STATUS"
        assert_contains "$name: reason" "$OUTPUT" "$expect"
    fi
done < <(python3 -c '
import json, sys
for c in json.load(open(sys.argv[1]))["cases"]:
    plan = ";".join(",".join(row) for row in c["plan"]) or "-"
    print(c["name"], c["target"], plan, ";".join(c["extra"]) or "-", c["expect"], sep="\t")
' "$ONIO_FX/transactions/closure.json")
find "$VAPT_LAYER" -name __pycache__ -prune -exec rm -rf {} +

# --- an opted-in install commits the exact audited private package ------------
tx_case vapt-onio-tx-install
vapt_package can-utils 2025.01-1
vapt_onio_serve
vapt_onio_seed
printf 'oniomarchy\tcan-utils\t2025.01-1\thttps://pkgs.oniomarchy.com/x86_64/can-utils-2025.01-1-x86_64.pkg.tar.gz\n' >"$VAPT_PLAN"
vapt_api install --yes --with-oniomarchy --groups automotive
assert_eq 'the private package resolves' oniomarchy/can-utils "$(vapt_field can-utils 4)"
assert_eq 'the audited private package is installed' installed "$(vapt_field can-utils 6)"
assert_contains 'the source field names the private source (what the narrowed test-vapt.sh check rejects)' \
    "$(vapt_field can-utils 3) $(vapt_field can-utils 4)" omarchy
assert_contains 'the commit used a repository-free configuration' "$(vapt_calls commit-config)" 'LocalFileSigLevel = Required TrustedOnly'
assert_eq 'pacman.conf is never changed by a private install' "$CONF_BEFORE" "$(cat "$ROOT/etc/pacman.conf")"
vapt_tools_untouched 'private install'

# --- a private package may place nothing in pacman's trust configuration -------
# In pacman's GPGDir gpg reads gpg.conf-2 before gpg.conf, so one dropped file
# can name another keyring and a trusted-key that is then ultimately trusted
# for every repository. The keyrings directory feeds pacman-key --populate.
tx_case vapt-onio-tx-gpgdir-payload
vapt_package can-utils 2025.01-1
mkdir -p "$SANDBOX/packages/can-utils/etc/pacman.d/gnupg"
printf 'keyring /usr/share/can-utils/k.gpg\ntrusted-key D0D0D0D0D0D0D0D0D0D0D0D0D0D0D0D0D0D0D0D0\n' \
    >"$SANDBOX/packages/can-utils/etc/pacman.d/gnupg/gpg.conf-2"
tar -czf "$SANDBOX/archives/can-utils-2025.01-1-x86_64.pkg.tar.gz" -C "$SANDBOX/packages/can-utils" .PKGINFO usr etc
vapt_onio_serve
vapt_onio_seed
printf 'oniomarchy\tcan-utils\t2025.01-1\thttps://pkgs.oniomarchy.com/x86_64/can-utils-2025.01-1-x86_64.pkg.tar.gz\n' >"$VAPT_PLAN"
vapt_api install --yes --with-oniomarchy --groups automotive
assert_eq 'a private package with a GPGDir payload still resolves' oniomarchy/can-utils "$(vapt_field can-utils 4)"
assert_not_contains 'but it is never installed' "$(vapt_field can-utils 6)" installed
assert_contains 'the audit names the payload and why' "$(vapt_field can-utils 7)" \
    "places /etc/pacman.d/gnupg/gpg.conf-2 inside pacman's trust configuration"
assert_eq 'nothing lands in the GPGDir' '' "$(compgen -G "$ROOT/etc/pacman.d/gnupg/*" || true)"

# The same rule through the audit directly, for each protected path, however
# the member is spelt and through links. MEMBER is kind:path[=content|target].
tx_case vapt-onio-tx-pacman-trust
vapt_package can-utils 2025.01-1
vapt_onio_serve
vapt_onio_seed
printf 'oniomarchy\tcan-utils\t2025.01-1\n' >"$SANDBOX/trust-plan.tsv"
private_audit() { # MEMBER... — audit can-utils carrying these extra members
    python3 - "$SANDBOX/archives/can-utils-2025.01-1-x86_64.pkg.tar.gz" "$@" <<'EOF'
import io, sys, tarfile
out, *members = sys.argv[1:]
with tarfile.open(out, 'w:gz') as archive:
    def add(name, kind, data=b'', target=''):
        info = tarfile.TarInfo(name)
        info.type, info.linkname, info.size = kind, target, len(data)
        info.mode = 0o755 if kind == tarfile.DIRTYPE else 0o644
        archive.addfile(info, io.BytesIO(data))
    add('.PKGINFO', tarfile.REGTYPE, b'pkgname = can-utils\npkgver = 2025.01-1\narch = x86_64\n')
    add('usr', tarfile.DIRTYPE)
    add('usr/bin', tarfile.DIRTYPE)
    add('usr/bin/can-utils', tarfile.REGTYPE, b'#!/bin/sh\nexit 97\n')
    for member in members:
        kind, _, rest = member.partition(':')
        name, _, value = rest.partition('=')
        if kind == 'dir':
            add(name, tarfile.DIRTYPE)
        elif kind == 'link':
            add(name, tarfile.SYMTYPE, target=value)
        else:
            add(name, tarfile.REGTYPE, value.encode())
EOF
    capture meta audit "$SANDBOX/archives/can-utils-2025.01-1-x86_64.pkg.tar.gz" --plan "$SANDBOX/trust-plan.tsv" --with-oniomarchy
}
refused_payload() { # LABEL MEMBER...
    local label="$1"
    shift
    private_audit "$@"
    assert_status "$label: refused" 1 "$STATUS"
    assert_contains "$label: as pacman trust configuration" "$OUTPUT" "inside pacman's trust configuration"
}
private_audit
assert_status 'a plain private package passes the audit (control)' 0 "$STATUS"
private_audit file:etc/can-utils.conf=x dir:etc dir:etc/pacman.d dir:usr/share/pacman/keyrings
assert_status 'an ordinary /etc file and headers of the protected directories themselves pass (control)' 0 "$STATUS"
while IFS='|' read -r label members; do
    read -r -a list <<<"$members"
    refused_payload "$label" "${list[@]}"
done <<'EOF'
gpg.conf-2 in the default GPGDir|file:etc/pacman.d/gnupg/gpg.conf-2=trusted-key
gpg.conf in the default GPGDir|file:etc/pacman.d/gnupg/gpg.conf=trusted-key
a mirrorlist under /etc/pacman.d|file:etc/pacman.d/mirrorlist=x
a hook under /etc/pacman.d|file:etc/pacman.d/hooks/x.hook=x
/etc/pacman.conf|file:etc/pacman.conf=x
/etc/pacman.conf.pacnew|file:etc/pacman.conf.pacnew=x
a /etc/pacman.conf.d directory|dir:etc/pacman.conf.d
a keyrings list|file:usr/share/pacman/keyrings/evil-trusted=D0D0D0D0D0D0D0D0D0D0D0D0D0D0D0D0D0D0D0D0:128:
a link replacing the keyrings directory|link:usr/share/pacman/keyrings=/tmp
a ./-prefixed member|file:./etc/pacman.d/gnupg/gpg.conf-2=x
a member spelt with // and /./|file:etc//pacman.d/./gnupg/gpg.conf-2=x
a case-changed member|file:ETC/Pacman.D/gnupg/gpg.conf-2=x
an absolute link to the GPGDir|link:usr/share/can-utils/conf=/etc/pacman.d/gnupg
a file written through an incoming link|link:usr/share/can-utils/conf=/etc/pacman.d/gnupg file:usr/share/can-utils/conf/gpg.conf-2=x
a relative link to /etc/pacman.conf|link:usr/share/can-utils/pacman.conf=../../../etc/pacman.conf
EOF
mkdir -p "$ROOT/usr/share"
ln -s /etc/pacman.d "$ROOT/usr/share/can-utils-data"
refused_payload 'a file written through a retained host link' file:usr/share/can-utils-data/gnupg/gpg.conf-2=x
rm "$ROOT/usr/share/can-utils-data"
# A non-default GPGDir is protected wherever pacman.conf puts it.
private_audit file:var/lib/fixture-gnupg/gpg.conf-2=x
assert_status 'an unrelated directory passes while GPGDir is the default (control)' 0 "$STATUS"
sed -i 's|^DownloadUser = alpm$|&\nGPGDir = /var/lib/fixture-gnupg/|' "$ROOT/etc/pacman.conf"
refused_payload 'gpg.conf-2 in a configured GPGDir' file:var/lib/fixture-gnupg/gpg.conf-2=x
refused_payload 'a nested member of a configured GPGDir' file:var/lib//fixture-gnupg/sub/x=x
refused_payload '/etc/pacman.d stays protected with another GPGDir' file:etc/pacman.d/gnupg/gpg.conf-2=x
sed -i 's|^GPGDir = .*$|GPGDir = /etc/pacman.d/gnupg|' "$ROOT/etc/pacman.conf"
mkdir -p "$ROOT/etc/pacman.d" "$ROOT/var/lib/real-gnupg"
ln -s /var/lib/real-gnupg "$ROOT/etc/pacman.d/gnupg"
refused_payload 'the physical directory behind a linked GPGDir' file:var/lib/real-gnupg/gpg.conf-2=x

# --- a full upgrade never carries the private source ---------------------------
# The source's Usage excludes Upgrade and its prelude runs after any full
# upgrade, so an approved source is never reviewed, frozen or recorded.
tx_case vapt-onio-tx-upgrade
vapt_api upgrade
assert_status 'a full upgrade with an approved private source commits' 0 "$STATUS"
assert_not_contains 'the review never syncs the private source' "$(vapt_calls review-repos)" 'oniomarchy'
assert_not_contains 'the commit configuration never names it' "$(vapt_calls commit-config)" '[oniomarchy]'
assert_eq 'the recovery record is cleared' no "$(pending)"
assert_eq 'pacman.conf untouched by the upgrade' "$CONF_BEFORE" "$(cat "$ROOT/etc/pacman.conf")"
# The invariant is enforced, not assumed: a scope set before a full upgrade
# refuses it before any review.
tx_case vapt-onio-tx-upgrade-scope
capture bash -c '
runner="$1"
set -- repo-status true
source "$runner"
ASSUME_YES=true
vapt_snapshot || exit $?
VAPT_ONIOMARCHY_SCOPE=1
vapt_pacman_upgrade; rc=$?
printf "REASON=%s\n" "${VAPT_APPLY_REASON:-}"
exit "$rc"
' _ "$FIXTURES/vapt-runner.sh"
assert_status 'a full upgrade under the private scope is refused' 2 "$STATUS"
assert_contains 'the refusal names the invariant' "$OUTPUT" 'never joins a full upgrade'
assert_eq 'the refused upgrade reviewed nothing' '' "$(vapt_calls review-repos)"

# A failed reviewed commit records only the generic record.
tx_case vapt-onio-tx-record
export VAPT_PACMAN_FAIL=commit
vapt_api upgrade
unset VAPT_PACMAN_FAIL
assert_eq 'the recovery record never names the private source' 'reviewed-full-upgrade-commit-pending' "$(cat "$ROOT/$MARKER")"

# --- recovery records ------------------------------------------------------------
while IFS=$'\t' read -r expect record; do
    [[ -n $expect && $expect != \#* ]] || continue
    tx_case vapt-onio-tx-recover
    printf '%b' "$record" >"$ROOT/$MARKER"
    vapt_api recover
    if [[ $expect == accept ]]; then
        assert_status "recovery $record: resumes" 0 "$STATUS"
        assert_eq "recovery $record: record cleared" no "$(pending)"
        assert_not_contains "recovery $record: no private scope" "$(vapt_calls review-repos)" 'oniomarchy'
    else
        assert_status "recovery $record: refused" 2 "$STATUS"
        assert_eq "recovery $record: record preserved" yes "$(pending)"
        assert_eq "recovery $record: nothing reviewed" '' "$(vapt_calls review-repos)"
    fi
done <"$ONIO_FX/transactions/recovery-records.txt"
vapt_tools_untouched 'recovery'
