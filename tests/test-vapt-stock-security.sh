# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# Independent adversarial regressions for SEC-STOCK-1, SEC-PROVENANCE-3,
# SEC-ARTIFACT-2, SEC-PATH-4 and recovery/umask boundaries (G1/G2).
# Archives contain original inert data and non-executable ELF metadata, mode 0644.
# No installer, hook, shared object, key, service, scanner or tool executes.
# Existing fixture helpers are read-only. Observable audit verdicts, installed
# state and bytes opened by the manager fake are the safety assertions.
# shellcheck source=tests/fixtures/vapt-lib.sh
source "$FIXTURES/vapt-lib.sh"

if ! command -v bsdtar >/dev/null 2>&1; then
    echo '  (note: bsdtar is not installed; stock security regressions were skipped)'
    return 0
fi

sec_case() {
    vapt_sandbox "$1"
    vapt_root
    export LC_ALL=C
    unset VAPT_SWAP_DOWNLOAD VAPT_SWAP_COMMIT VAPT_SUDO_PATH VAPT_COMMIT_PATH VAPT_MOCK_SIGNATURES
    unset SEC_PLAN
    vapt_repos "${VAPT_BASE[@]}" 'extra|nmap|7.99-1|https://nmap.org/'
    vapt_stock
}

# A static SONAME record with a read-only PT_LOAD: entry=0, no executable
# segment, code, symbols, interpreter, init arrays, constructors or dependencies.
# Only the audit byte parser reads it; no fixture bytes are linked or loaded.
sec_soname_data() {
    vapt_elf "$1" "soname=$2" "type=${3:-3}"
}

# PATH=TEXT, PATH=@ELF, PATH=@SONAME:NAME, PATH@>LINK. All bytes are original
# inert data; @ELF is incomplete and @SONAME is the non-executable layout above.
sec_archive() {
    local name="$1" version="$2" dir="$SANDBOX/sec-packages/$1-$2" item path value kind
    local spec='^([A-Za-z0-9._/+-]+)(=|@>)(.*)$'
    local -A tops=([usr]=1)
    shift 2
    rm -rf "$dir"
    mkdir -p "$dir/usr/bin" "$SANDBOX/archives"
    printf 'pkgname = %s\npkgver = %s\narch = x86_64\n' "$name" "$version" >"$dir/.PKGINFO"
    printf 'inert fixture inventory item, never executed\n' >"$dir/usr/bin/$name"
    for item in "$@"; do
        [[ $item =~ $spec ]] || return 1
        path="${BASH_REMATCH[1]}" kind="${BASH_REMATCH[2]}" value="${BASH_REMATCH[3]}"
        mkdir -p "$dir/$(dirname "$path")"
        if [[ $kind == '@>' ]]; then
            ln -s "$value" "$dir/$path"
        elif [[ $value == @ELF ]]; then
            printf '\177ELF\002\001\001incomplete-security-decoy %s\n' "$path" >"$dir/$path"
        elif [[ $value == @SONAME:* ]]; then
            sec_soname_data "$dir/$path" "${value#@SONAME:}"
        elif [[ $value == @SONAME-NONE:* ]]; then
            sec_soname_data "$dir/$path" "${value#@SONAME-NONE:}" 0
        else
            printf '%s\n' "$value" >"$dir/$path"
        fi
        [[ -L $dir/$path ]] || chmod 0644 "$dir/$path"
        tops[${path%%/*}]=1
    done
    SEC_ARCHIVE="$SANDBOX/archives/$name-$version-x86_64.pkg.tar.gz"
    tar -czf "$SEC_ARCHIVE" -C "$dir" .PKGINFO "${!tops[@]}"
    _vapt_digests
}

sec_plan() {
    SEC_PLAN="$SANDBOX/sec-plan.tsv"
    : >"$SEC_PLAN"
    while (($# >= 3)); do
        printf '%s\t%s\t%s\thttps://mirror.example/%s-%s-x86_64.pkg.tar.gz\n' \
            "$1" "$2" "$3" "$2" "$3" >>"$SEC_PLAN"
        shift 3
    done
}
sec_review() {
    local label="$1" expected="$2" plan=()
    shift 2
    [[ -z ${SEC_PLAN:-} ]] || plan=(--plan "$SEC_PLAN")
    capture python3 "$VAPT_META" audit "$@" "${plan[@]}" --root "$ROOT"
    assert_status "$label" "$expected" "$STATUS"
    assert_eq "$label: no fixture command executes during audit" '' "$(find "$CALLS" -type f -printf '%f\n')"
}
sec_digest() { sha256sum "$1" | cut -d ' ' -f 1; }
sec_no_commit() {
    assert_eq "$1: no opened commit artifacts" '' "$(vapt_calls commit-digests)"
}
sec_sealed_ancestry() {
    local label="$1" result
    result="$(python3 - "$CALLS/commit-ancestry" "${2:-integrity}" <<'PY'
import sys
from pathlib import Path
path = Path(sys.argv[1])
lines = path.read_text().splitlines() if path.is_file() else []
errors = []
if not lines:
    errors.append('no opened-file ancestry observed')
for line in lines:
    fields = line.split()
    if len(fields) < 2:
        errors.append('missing ancestry: ' + line)
    for field in fields[1:]:
        directory, mode = field.rsplit('=', 1)
        if '@link' in mode or int(mode.split('@', 1)[0], 8) & 0o022:
            errors.append('replaceable ancestor: ' + field)
        # DownloadUser must traverse the outer root stage regardless of the
        # caller's umask. The sealed leaf itself is not a download destination.
        if (sys.argv[2] == 'download-reader'
                and Path(directory).name.startswith('haseen-vapt.')
                and not int(mode.split('@', 1)[0], 8) & 0o001):
            errors.append('DownloadUser cannot traverse root stage: ' + field)
print('\n'.join(errors))
PY
)"
    assert_eq "$label: no writable or symlinked commit ancestor" '' "$result"
}
sec_installed() {
    python3 - "$ROOT/var/lib/haseen/vapt/installed.json" "$1" <<'PY'
import json, sys
from pathlib import Path
path = Path(sys.argv[1])
records = json.loads(path.read_text()) if path.is_file() else []
print(next((p['version'] for p in records if p['name'] == sys.argv[2]), 'absent'))
PY
}
sec_transaction() {
    sec_case "$1"
    printf '[options]\nArchitecture = auto\nDownloadUser = alpm\nSigLevel = Required DatabaseOptional\n[core]\nServer = https://geo.mirror.pkgbuild.com/$repo/os/$arch\n[extra]\nServer = https://geo.mirror.pkgbuild.com/$repo/os/$arch\n' >"$ROOT/etc/pacman.conf"
    printf 'unchanged live fixture database\n' >"$ROOT/var/lib/pacman/sync/extra.db"
    vapt_transactions
    export VAPT_PLAN="$SANDBOX/plan.tsv" VAPT_ARCHIVES="$SANDBOX/archives"
    export VAPT_MOCK_SIGNATURES=1
    printf 'extra\tnmap\t7.99-1\thttps://geo.mirror.pkgbuild.com/extra/os/x86_64/nmap-7.99-1-x86_64.pkg.tar.gz\n' >"$VAPT_PLAN"
}

# --- Loader/dependency input is executable influence, not harmless data. ---
# Positive control prohibits a blanket ban on all unknown private libraries.
sec_case vapt-sec-private-library-control
sec_archive nmap 7.99-1 'usr/lib/nmap/libnmap.so.1=@ELF'
sec_review 'SEC-STOCK-1 unrelated private library remains allowed' 0 "$SEC_ARCHIVE"

for route in preload cache conf hwcaps soname redirect; do
    sec_case "vapt-sec-loader-$route"
    case "$route" in
    preload) sec_archive nmap 7.99-1 'etc/ld.so.preload=/usr/lib/nmap/preload.so' 'usr/lib/nmap/preload.so=@ELF' ;;
    cache) sec_archive nmap 7.99-1 'etc/ld.so.cache=inert malformed loader cache, never consumed' ;;
    conf) sec_archive nmap 7.99-1 'etc/ld.so.conf.d/nmap.conf=/opt/vendor/lib' 'opt/vendor/lib/libc.so.6=@ELF' ;;
    hwcaps) sec_archive nmap 7.99-1 'usr/lib/glibc-hwcaps/x86-64-v3/libc.so.6=@ELF' ;;
    soname) sec_archive nmap 7.99-1 'usr/lib/libc.so.6=@ELF' ;;
    redirect) sec_archive nmap 7.99-1 'usr/lib/libc.so.6@>../../opt/vendor/lib/libc.so.6' 'opt/vendor/lib/libc.so.6=@ELF' ;;
    esac
    sec_review "SEC-STOCK-1 $route cannot borrow trusted maintenance execution" 1 "$SEC_ARCHIVE"
done

sec_case vapt-sec-fresh-soname
sec_archive nmap 7.99-1 'usr/lib/libnmap.so.9=@SONAME:libnmap.so.9'
sec_review 'SEC-STOCK-1 noncolliding loader-directory SONAME remains allowed' 0 "$SEC_ARCHIVE"
sec_archive nmap 7.99-1 'usr/lib/libnmap.so.9=@SONAME:libreadline.so.8'
sec_review 'SEC-STOCK-1 bogus SONAME cannot redirect a retained helper dependency under an innocent filename' 1 "$SEC_ARCHIVE"
sec_archive nmap 7.99-1 'usr/lib/libnmap.so.9=@SONAME-NONE:libnmap.so.9'
sec_review 'SEC-STOCK-1 structurally bounded but invalid ELF type fails closed in a loader directory' 1 "$SEC_ARCHIVE"

sec_case vapt-sec-incoming-loader-directory
sec_archive nmap 7.99-1 'etc/ld.so.conf.d/nmap.conf=/opt/nmap/lib' \
    'opt/nmap/lib/libnmap.so.9=@SONAME:libnmap.so.9'
sec_review 'SEC-STOCK-1 new loader directory with a fresh SONAME remains allowed' 0 "$SEC_ARCHIVE"
sec_archive nmap 7.99-1 'etc/ld.so.conf.d/nmap.conf=/opt/nmap/lib' \
    'opt/nmap/lib/libnmap.so.9=@SONAME:libreadline.so.8'
sec_review 'SEC-STOCK-1 incoming conf cannot hide a colliding SONAME outside usr/lib' 1 "$SEC_ARCHIVE"

# A retained preload is just as influential as an incoming one. The same
# ordinary archive must pass before introducing that loader input.
sec_case vapt-sec-retained-preload
sec_archive nmap 7.99-1
sec_review 'SEC-STOCK-1 clean retained runtime control' 0 "$SEC_ARCHIVE"
printf '/usr/lib/nmap/preload.so\n' >"$ROOT/etc/ld.so.preload"
mkdir -p "$ROOT/usr/lib/nmap"
printf 'inert retained loader dependency, never loaded\n' >"$ROOT/usr/lib/nmap/preload.so"
sec_review 'SEC-STOCK-1 retained preload cannot bypass future-view checks' 1 "$SEC_ARCHIVE"

# --- Identity plus the package's own MTREE cannot authenticate origin. ---
for owner in glibc bash; do
    sec_case "vapt-sec-self-attested-$owner"
    if [[ $owner == glibc ]]; then
        sec_archive nmap 7.99-1 'etc/ld.so.conf.d/nmap.conf=/usr/lib/nmap'
        SEC_PATH=usr/bin/ldconfig
        SEC_ENTRY=glibc-2.44-1
    else
        sec_archive nmap 7.99-1
        SEC_PATH=usr/bin/bash
        SEC_ENTRY=bash-5.3.3-2
    fi
    sec_review "SEC-PROVENANCE-3 authentic retained $owner control" 0 "$SEC_ARCHIVE"
    python3 - "$ROOT" "$SEC_ENTRY" "$SEC_PATH" <<'PY'
import gzip, hashlib, sys
from pathlib import Path
root, entry, rel = Path(sys.argv[1]), sys.argv[2], sys.argv[3]
# Keep name, version and legitimate upstream URL unchanged. Only the owner
# bytes and its own statement about them change, modelling a retained homonym.
(root / rel).write_bytes(b'\x7fELF\x02\x01\x01self-attested foreign fixture bytes\n')
mtree = root / 'var/lib/pacman/local' / entry / 'mtree'
lines = gzip.open(mtree, 'rt').read().splitlines()
digest = hashlib.sha256((root / rel).read_bytes()).hexdigest()
lines = [('./' + rel + ' type=file mode=644 sha256digest=' + digest)
         if line.startswith('./' + rel + ' ') else line for line in lines]
with gzip.open(mtree, 'wt') as stream:
    stream.write('\n'.join(lines) + '\n')
PY
    sec_review "SEC-PROVENANCE-3 $owner homonym with matching identity and self-MTREE refused" 1 "$SEC_ARCHIVE"
done

# Missing/corrupted/non-base references must not fall back to local claims.
# The fixture caches carry pre-tamper bytes authenticated by the fixture's
# explicit base signer protocol; no host keyring or crypto command is used.
for reference_failure in missing hash signer; do
    sec_case "vapt-sec-reference-$reference_failure"
    sec_archive nmap 7.99-1 'etc/ld.so.conf.d/nmap.conf=/usr/lib/nmap'
    sec_review "SEC-PROVENANCE-3 intact reference $reference_failure control" 0 "$SEC_ARCHIVE"
    SEC_REFERENCE="$ROOT/var/cache/pacman/pkg/glibc-2.44-1-x86_64.pkg.tar.gz"
    SEC_SIGNATURES="$ROOT/var/lib/haseen/vapt/fixture-signatures.tsv"
    if [[ ! -f $SEC_REFERENCE || ! -f $SEC_SIGNATURES ]]; then
        _fail "SEC-PROVENANCE-3 $reference_failure: authenticated reference fixture unavailable"
        continue
    fi
    case "$reference_failure" in
    missing) rm -- "$SEC_REFERENCE" ;;
    hash) printf 'inert reference drift\n' >>"$SEC_REFERENCE" ;;
    signer)
        python3 - "$SEC_SIGNATURES" "$(sec_digest "$SEC_REFERENCE")" <<'PY'
import sys
from pathlib import Path
path, digest = Path(sys.argv[1]), sys.argv[2]
rows = path.read_text().splitlines()
path.write_text('\n'.join(digest + '\t' + 'E' * 40 if row.split('\t', 1)[0] == digest else row
                          for row in rows) + '\n')
PY
        ;;
    esac
    sec_review "SEC-PROVENANCE-3 $reference_failure reference never falls back to self-MTREE" 1 "$SEC_ARCHIVE"
done

sec_case vapt-sec-core-label-wrong-bytes
sec_archive nmap 7.99-1 'etc/ld.so.conf.d/nmap.conf=/usr/lib/nmap'
SEC_NMAP="$SEC_ARCHIVE"
SEC_GENUINE="$(vapt_stock_archive glibc 2.44-2)"
sec_plan core glibc 2.44-2 extra nmap 7.99-1
sec_review 'SEC-PROVENANCE-3 exact reviewed core artifact control' 0 "$SEC_GENUINE" "$SEC_NMAP"
SEC_FOREIGN="$(python3 "$VAPT_FIXTURE_DRIVER" stock-archive glibc 2.44-2 "$SANDBOX/foreign" usr/bin/ldconfig unregistered)"
sec_review 'SEC-PROVENANCE-3 legitimate core label never authenticates a different same-identity artifact' 1 "$SEC_FOREIGN" "$SEC_NMAP"
SEC_NONBASE="$(vapt_stock_archive glibc 2.44-2 '' nonbase-signed)"
sec_review 'SEC-PROVENANCE-3 metadata-matching core artifact signed by a non-base key is refused' 1 "$SEC_NONBASE" "$SEC_NMAP"

# --- Both signed alternatives are valid to the mock signature verifier. ---
# The driver signs downloaded/swapped inert bytes and reopens the actual files
# to verify that detached fixture signature. Argument logs are not byte proof.
for timing in download commit; do
    sec_transaction "vapt-sec-signed-cache-swap-$timing"
    sec_archive nmap 7.99-1 'usr/share/nmap/reviewed.txt=reviewed original data'
    mkdir -p "$SANDBOX/replacement"
    sec_archive nmap 7.99-1 'usr/share/nmap/reviewed.txt=signed but unreviewed replacement'
    SEC_BAD_SHA="$(sec_digest "$SEC_ARCHIVE")"
    cp "$SEC_ARCHIVE" "$SANDBOX/replacement/$(basename "$SEC_ARCHIVE")"
    # Restore and register the exact reviewed bytes, leaving the other archive
    # outside the published-artifact fixture directory.
    sec_archive nmap 7.99-1 'usr/share/nmap/reviewed.txt=reviewed original data'
    # gzip timestamps may change across builds: bind the DB to this exact copy.
    SEC_GOOD_SHA="$(sec_digest "$SEC_ARCHIVE")"
    python3 "$VAPT_FIXTURE_DRIVER" digests "$SANDBOX/archives"
    if [[ $timing == download ]]; then
        export VAPT_SWAP_DOWNLOAD="$SANDBOX/replacement"
    else
        export VAPT_SWAP_COMMIT="$SANDBOX/replacement"
    fi
    vapt_api pacman --yes extra/nmap
    if [[ $timing == download ]]; then
        assert_status 'SEC-ARTIFACT-2 validly signed pre-seal substitution fails metadata binding' 2 "$STATUS"
        sec_no_commit 'SEC-ARTIFACT-2 pre-seal substitution'
        assert_eq 'SEC-ARTIFACT-2 pre-seal replacement is never installed' absent "$(sec_installed nmap)"
    else
        assert_status 'SEC-ARTIFACT-2 cache substitution after audit leaves the sealed transaction usable' 0 "$STATUS"
        assert_eq 'SEC-ARTIFACT-2 committed identity is reviewed' 7.99-1 "$(sec_installed nmap)"
        assert_eq 'SEC-ARTIFACT-2 root opens reviewed bytes, not the signed replacement' \
            "$(basename "$SEC_ARCHIVE") $SEC_GOOD_SHA" "$(vapt_calls commit-digests)"
        assert_not_contains 'SEC-ARTIFACT-2 replacement digest is never committed' "$(vapt_calls commit-digests)" "$SEC_BAD_SHA"
        assert_eq 'SEC-ARTIFACT-2 detached signature accompanies the sealed bytes' \
            "$(basename "$SEC_ARCHIVE") valid" "$(vapt_calls commit-signatures)"
        assert_not_contains 'SEC-ARTIFACT-2 downloader-writable directory is never committed' "$(vapt_calls commit-dirs)" '/packages '
        sec_sealed_ancestry 'SEC-ARTIFACT-2 exact sealed artifacts'
    fi
    vapt_tools_untouched "SEC-ARTIFACT-2 $timing substitution"
done

# --- An earlier nonstandard PATH entry must not be the helper consumer. ---
sec_transaction vapt-sec-nonstandard-path
sec_archive nmap 7.99-1 'opt/vendor/bin/touch=inert PATH shadow, never executed'
python3 "$VAPT_FIXTURE_DRIVER" digests "$SANDBOX/archives"
mkdir -p "$ROOT/opt/vendor/bin"
printf 'inert existing PATH shadow, never executed\n' >"$ROOT/opt/vendor/bin/touch"
# Deliberately model hostile inherited PATH without putting the fixture's
# nonexecuted payload directory on the real test process's PATH.
export VAPT_SUDO_PATH=/opt/vendor/bin:/usr/local/bin:/usr/bin
vapt_api pacman --yes extra/nmap
assert_status 'SEC-PATH-4 canonical root PATH permits a benign transaction with irrelevant shadows' 0 "$STATUS"
assert_eq 'SEC-PATH-4 helper resolves the canonical consumer, never the earlier vendor shadow' \
    'touch /usr/bin/touch' "$(vapt_calls commit-resolutions)"
unset VAPT_SUDO_PATH
vapt_tools_untouched 'SEC-PATH-4 canonical helper resolution'

# --- Recovery records are an exact protocol, not a substring or best effort. ---
sec_transaction vapt-sec-recovery-valid-control
sec_archive nmap 7.99-1
SEC_MARKER="$ROOT/var/lib/haseen/vapt/upgrade-pending"
printf 'reviewed-full-upgrade-commit-pending\n' >"$SEC_MARKER"
vapt_api recover
assert_status 'G1 exact pending record remains recoverable (positive control)' 0 "$STATUS"
assert_eq 'G1 valid recovery commits the reviewed archive' 7.99-1 "$(sec_installed nmap)"
assert_eq 'G1 successful recovery clears only its completed marker' no "$([[ -e $SEC_MARKER ]] && echo yes || echo no)"
vapt_tools_untouched 'G1 exact pending recovery'

for malformed in empty truncated nonutf8 prefix tag-suffix extra-line nul unreadable; do
    sec_transaction "vapt-sec-recovery-$malformed"
    sec_archive nmap 7.99-1
    python3 "$VAPT_FIXTURE_DRIVER" digests "$SANDBOX/archives"
    SEC_MARKER="$ROOT/var/lib/haseen/vapt/upgrade-pending"
    case "$malformed" in
    empty) : >"$SEC_MARKER" ;;
    truncated) printf 'reviewed-full-upgrade-commit-' >"$SEC_MARKER" ;;
    nonutf8) printf 'reviewed-full-upgrade-commit-pending\t\377\n' >"$SEC_MARKER" ;;
    prefix) printf 'reviewed-full-upgrade-commit-pending-foreign\n' >"$SEC_MARKER" ;;
    tag-suffix) printf 'reviewed-full-upgrade-commit-pending\tblackarch-staged-foreign\n' >"$SEC_MARKER" ;;
    extra-line) printf 'reviewed-full-upgrade-commit-pending\nforeign second record\n' >"$SEC_MARKER" ;;
    nul) printf 'reviewed-full-upgrade-commit-pending\000\n' >"$SEC_MARKER" ;;
    unreadable) mkdir "$SEC_MARKER"; printf 'retain directory sentinel\n' >"$SEC_MARKER/sentinel" ;;
    esac
    SEC_SENTINEL="$SEC_MARKER"
    [[ $malformed != unreadable ]] || SEC_SENTINEL="$SEC_MARKER/sentinel"
    SEC_MARKER_SHA="$(sec_digest "$SEC_SENTINEL")"
    SEC_CONF_BEFORE="$(sec_digest "$ROOT/etc/pacman.conf")"
    vapt_api recover
    assert_status "G1 $malformed recovery record is refused" 2 "$STATUS"
    sec_no_commit "G1 $malformed recovery"
    if [[ -f $SEC_SENTINEL ]]; then
        assert_eq "G1 $malformed preserves exact recovery evidence" "$SEC_MARKER_SHA" "$(sec_digest "$SEC_SENTINEL")"
    else
        _fail "G1 $malformed recovery evidence was removed"
    fi
    assert_eq "G1 $malformed does not activate a repository" "$SEC_CONF_BEFORE" "$(sec_digest "$ROOT/etc/pacman.conf")"
    assert_eq "G1 $malformed leaves live sync metadata unchanged" 'unchanged live fixture database' "$(cat "$ROOT/var/lib/pacman/sync/extra.db")"
    vapt_tools_untouched "G1 $malformed recovery"
done

# --- Explicit permissions must not accidentally depend on caller umask. ---
sec_case vapt-sec-umask-state
SEC_STATE="$ROOT/var/lib/haseen/vapt/private-state"
SEC_MASK="$(umask)"
umask 077
capture python3 "$VAPT_META" state-write "$SEC_STATE" <<'EOF'
original safe fixture metadata
EOF
umask "$SEC_MASK"
assert_status 'G2 state metadata writes under umask077' 0 "$STATUS"
SEC_EXPECTED_MODE=600
[[ $(id -u) != 0 ]] || SEC_EXPECTED_MODE=644
assert_eq 'G2 state metadata has the explicit reader-contract mode' "$SEC_EXPECTED_MODE" "$(stat -c %a "$SEC_STATE")"
capture python3 "$VAPT_META" state-read "$SEC_STATE"
assert_status 'G2 safely written metadata remains readable' 0 "$STATUS"
assert_eq 'G2 metadata read preserves the payload' 'original safe fixture metadata' "$OUTPUT"

sec_transaction vapt-sec-umask-cache
sec_archive nmap 7.99-1 'usr/share/nmap/safe.txt=inert cache read control'
python3 "$VAPT_FIXTURE_DRIVER" digests "$SANDBOX/archives"
SEC_MASK="$(umask)"
umask 077
vapt_api pacman --yes extra/nmap
umask "$SEC_MASK"
assert_status 'G2 DownloadUser cache and audited archive remain usable under umask077' 0 "$STATUS"
assert_eq 'G2 cache read semantics reach the consumer without a live manager' 7.99-1 "$(sec_installed nmap)"
assert_eq 'G2 restrictive umask never alters committed bytes' \
    "$(basename "$SEC_ARCHIVE") $(sec_digest "$SEC_ARCHIVE")" "$(vapt_calls commit-digests)"
sec_sealed_ancestry 'G2 restrictive umask' download-reader
vapt_tools_untouched 'G2 restrictive umask'

# --- A1: consumer-level current/future dependency closure and candidates. ---
# These helpers only alter scratch package metadata and original inert bytes.
# They never execute the helper, interpreter or library represented by an ELF.

# Replace/add one member of an authenticated fixture archive. "retained"
# also installs exactly those bytes/link into the scratch tree and local DB.
# Publication/signature are re-bound to the rewritten archive, so failures
# cannot be explained by stale fixture checksums or self-MTREE alone.
sec_a1_member() {
    local archive="$1" owner="$2" version="$3" rel="$4" source="$5" view="$6"
    python3 - "$ROOT" "$archive" "$owner" "$version" "$rel" "$source" "$view" <<'PY'
import gzip, hashlib, io, os, sys, tarfile
from pathlib import Path
root, archive = Path(sys.argv[1]), Path(sys.argv[2])
owner, version, rel, source, view = sys.argv[3:]
link = source.removeprefix('link:') if source.startswith('link:') else None
data = None if link is not None else Path(source).read_bytes()
result = io.BytesIO()
with tarfile.open(archive, 'r:*') as old, tarfile.open(fileobj=result, mode='w:gz') as new:
    for member in old:
        if member.name.removeprefix('./').rstrip('/') == rel:
            continue
        new.addfile(member, old.extractfile(member) if member.isfile() else None)
    member = tarfile.TarInfo(rel)
    member.mode = 0o644
    if link is not None:
        member.type, member.linkname = tarfile.SYMTYPE, link
        new.addfile(member)
    else:
        member.size = len(data)
        new.addfile(member, io.BytesIO(data))
archive.write_bytes(result.getvalue())
if view == 'retained':
    target = root / rel
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.is_symlink():
        target.unlink()
    if link is not None:
        target.unlink(missing_ok=True)
        target.symlink_to(link)
        mtree_line = './' + rel + ' type=link link=' + link
    else:
        target.write_bytes(data)
        target.chmod(0o644)
        mtree_line = './' + rel + ' type=file mode=644 sha256digest=' + hashlib.sha256(data).hexdigest()
    entry = root / 'var/lib/pacman/local' / (owner + '-' + version)
    files = entry / 'files'
    rows = files.read_text().splitlines()
    if rel not in rows:
        files.write_text('%FILES%\n' + '\n'.join(row for row in rows if row and row != '%FILES%') + '\n' + rel + '\n\n')
    mtree = entry / 'mtree'
    rows = gzip.open(mtree, 'rt').read().splitlines()
    rows = [row for row in rows if not row.startswith('./' + rel + ' ')]
    with gzip.open(mtree, 'wt') as stream:
        stream.write('\n'.join(rows + [mtree_line]) + '\n')
PY
    python3 "$VAPT_FIXTURE_DRIVER" digests "$(dirname "$archive")"
    printf 'fixture-sha256 %s\n' "$(sec_digest "$archive")" >"$archive.sig"
}

# Add a genuine lower-tier installed owner, preserving the stock local DB.
# Both versions remain inspected metadata; only the new one is planned.
sec_a1_lower_owner() {
    local name="$1" rel="$2" source="$3"
    vapt_conf_add $'[chaotic-aur]\nServer = https://mirror.example/chaotic-aur/$arch'
    python3 - "$ROOT" "$name" "$rel" "$source" <<'PY'
import gzip, hashlib, json, sys
from pathlib import Path
root, name, rel, source = Path(sys.argv[1]), sys.argv[2], sys.argv[3], Path(sys.argv[4])
url = 'https://example.org/' + name
target = root / rel
target.parent.mkdir(parents=True, exist_ok=True)
target.write_bytes(source.read_bytes())
target.chmod(0o644)
entry = root / 'var/lib/pacman/local' / (name + '-1-1')
entry.mkdir()
(entry / 'desc').write_text('%NAME%\n' + name + '\n\n%VERSION%\n1-1\n\n%URL%\n' + url + '\n\n')
(entry / 'files').write_text('%FILES%\n' + rel + '\n\n')
(entry / 'depends').write_text('%DEPENDS%\n\n%PROVIDES%\n\n%CONFLICTS%\n\n%REPLACES%\n\n')
with gzip.open(entry / 'mtree', 'wt') as stream:
    stream.write('#mtree\n./' + rel + ' type=file mode=644 sha256digest=' + hashlib.sha256(target.read_bytes()).hexdigest() + '\n')
path = root / 'var/lib/haseen/vapt/repositories.json'
repos = json.loads(path.read_text())
repos.setdefault('chaotic-aur', []).append(
    {'name': name, 'version': '2-1', 'url': url, 'provides': [], 'depends': [],
     'conflicts': [], 'replaces': []})
path.write_text(json.dumps(repos))
PY
}

# A sync repository publishes one current version per package name. Older
# installed/reference archives remain local evidence, not duplicate solver rows.
sec_sync_version() {
    python3 - "$ROOT/var/lib/haseen/vapt/repositories.json" "$1" "$2" "$3" <<'PY'
import json, sys
from pathlib import Path
path, repo, name, version = Path(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4]
records = json.loads(path.read_text())
records[repo] = [record for record in records[repo]
                 if record['name'] != name or record.get('version') == version]
path.write_text(json.dumps(records))
PY
}

sec_a1_bash_reference() {
    sec_a1_member "$ROOT/var/cache/pacman/pkg/bash-5.3.3-2-x86_64.pkg.tar.gz" \
        bash 5.3.3-2 usr/bin/bash "$1" retained
}
sec_a1_base_library() {
    sec_a1_member "$ROOT/var/cache/pacman/pkg/glibc-2.44-1-x86_64.pkg.tar.gz" \
        glibc 2.44-1 "$1" "$2" retained
}
sec_a1_installed_version() {
    python3 - "$ROOT" "$1" <<'PY'
import json, sys
from pathlib import Path
root, name = Path(sys.argv[1]), sys.argv[2]
installed = root / 'var/lib/haseen/vapt/installed.json'
if installed.is_file():
    records = json.loads(installed.read_text())
else:
    records = []
    for desc in (root / 'var/lib/pacman/local').glob('*/desc'):
        fields, key = {}, None
        for row in desc.read_text().splitlines():
            if row.startswith('%') and row.endswith('%'):
                key = row.strip('%').lower()
            elif row and key:
                fields.setdefault(key, row)
        records.append(fields)
print(next((record['version'] for record in records if record.get('name') == name), 'absent'))
PY
}
sec_a1_verdict() {
    local name="$1" expected="$2" target="${3:-extra/nmap}" before version
    before="$(sec_a1_installed_version "${target#*/}")"
    case "$target" in
    core/bash) version=5.3.3-3 ;;
    chaotic-aur/vapt-runtime) version=2-1 ;;
    *) version=7.99-1 ;;
    esac
    vapt_api pacman --yes "$target"
    assert_status "A1 $name: consumer verdict" "$expected" "$STATUS"
    if [[ $expected == 0 ]]; then
        assert_contains "A1 $name: reviewed transaction remains usable" "$OUTPUT" 'STATE=installed'
        assert_eq "A1 $name: consumer installs the planned version" \
            "$version" "$(sec_a1_installed_version "${target#*/}")"
        [[ -n $(vapt_calls commit-digests) ]] || _fail "A1 $name: no archive reached the consumer"
    else
        sec_no_commit "A1 $name"
        assert_eq "A1 $name: refusal preserves the installed package version" \
            "$before" "$(sec_a1_installed_version "${target#*/}")"
    fi
    vapt_tools_untouched "A1 $name"
}
sec_a1_plain() { sec_archive nmap 7.99-1; }

# Self-upgrade exemptions are legitimate only when the library cannot enter a
# trusted helper's dependency closure. The two consumers differ only in NEEDED.
for needed in nonneeded needed; do
    sec_transaction "vapt-a1-own-library-$needed"
    vapt_elf "$SANDBOX/library-old" soname=libvaptfix.so.1 tag=old-data
    sec_a1_lower_owner vapt-runtime usr/lib/libvaptfix.so.1 "$SANDBOX/library-old"
    if [[ $needed == needed ]]; then
        vapt_elf "$SANDBOX/base-bash" type=2 interp=/usr/lib64/ld-linux-x86-64.so.2 \
            needed=libreadline.so.8,libc.so.6,libvaptfix.so.1
        sec_a1_bash_reference "$SANDBOX/base-bash"
    fi
    sec_archive vapt-runtime 2-1
    vapt_elf "$SANDBOX/library-new" soname=libvaptfix.so.1 tag=new-data
    sec_a1_member "$SEC_ARCHIVE" vapt-runtime 2-1 usr/lib/libvaptfix.so.1 "$SANDBOX/library-new" incoming
    printf 'chaotic-aur\tvapt-runtime\t2-1\thttps://mirror.example/vapt-runtime-2-1-x86_64.pkg.tar.gz\n' >"$VAPT_PLAN"
    SEC_EXPECTED=0
    [[ $needed != needed ]] || SEC_EXPECTED=2
    sec_a1_verdict "own-library-$needed" "$SEC_EXPECTED" chaotic-aur/vapt-runtime
done

# An authenticated owner upgrade may introduce a new dependency only when its
# current/future providers have authenticated base provenance too.
for provider in lower base; do
    sec_transaction "vapt-a1-base-upgrade-needed-$provider"
    vapt_elf "$SANDBOX/new-library" soname=libvaptfix.so.1
    if [[ $provider == lower ]]; then
        sec_a1_lower_owner vapt-runtime usr/lib/libvaptfix.so.1 "$SANDBOX/new-library"
    else
        sec_a1_base_library usr/lib/libvaptfix.so.1 "$SANDBOX/new-library"
    fi
    SEC_BASH_ARCHIVE="$(vapt_stock_archive bash 5.3.3-3)"
    vapt_elf "$SANDBOX/new-bash" type=2 interp=/usr/lib64/ld-linux-x86-64.so.2 \
        needed=libreadline.so.8,libc.so.6,libvaptfix.so.1
    sec_a1_member "$SEC_BASH_ARCHIVE" bash 5.3.3-3 usr/bin/bash "$SANDBOX/new-bash" incoming
    sec_sync_version core bash 5.3.3-3
    printf 'core\tbash\t5.3.3-3\thttps://mirror.example/bash-5.3.3-3-x86_64.pkg.tar.gz\n' >"$VAPT_PLAN"
    SEC_EXPECTED=0
    [[ $provider != lower ]] || SEC_EXPECTED=2
    sec_a1_verdict "base-upgrade-needed-$provider" "$SEC_EXPECTED" core/bash
done

# Multiple local owners are ambiguous even if both claim exactly the same bytes.
sec_transaction vapt-a1-duplicate-needed-owner
sec_a1_plain
vapt_elf "$SANDBOX/duplicate-library" soname=libvaptfix.so.1
sec_a1_base_library usr/lib/libvaptfix.so.1 "$SANDBOX/duplicate-library"
sec_a1_lower_owner vapt-shadow usr/lib/libvaptfix.so.1 "$SANDBOX/duplicate-library"
vapt_elf "$SANDBOX/needed-bash" type=2 interp=/usr/lib64/ld-linux-x86-64.so.2 \
    needed=libreadline.so.8,libc.so.6,libvaptfix.so.1
sec_a1_bash_reference "$SANDBOX/needed-bash"
sec_a1_verdict duplicate-needed-owner 2

# Both the needed library's link and its destination require reference proof.
for link_state in canonical retargeted; do
    sec_transaction "vapt-a1-needed-link-$link_state"
    sec_a1_plain
    vapt_elf "$SANDBOX/link-library" soname=libvaptfix.so.1
    sec_a1_base_library usr/lib/libvaptfix-real.so.1 "$SANDBOX/link-library"
    sec_a1_base_library usr/lib/libvaptfix.so.1 link:libvaptfix-real.so.1
    vapt_elf "$SANDBOX/link-bash" type=2 interp=/usr/lib64/ld-linux-x86-64.so.2 \
        needed=libreadline.so.8,libc.so.6,libvaptfix.so.1
    sec_a1_bash_reference "$SANDBOX/link-bash"
    SEC_EXPECTED=0
    if [[ $link_state == retargeted ]]; then
        mkdir -p "$ROOT/opt/vendor/lib"
        cp "$SANDBOX/link-library" "$ROOT/opt/vendor/lib/libvaptfix.so.1"
        rm "$ROOT/usr/lib/libvaptfix.so.1"
        ln -s /opt/vendor/lib/libvaptfix.so.1 "$ROOT/usr/lib/libvaptfix.so.1"
        SEC_EXPECTED=2
    fi
    sec_a1_verdict "needed-link-$link_state" "$SEC_EXPECTED"
done

# Authenticated bytes do not make unsupported loader semantics reviewable.
for unsupported in origin interpreter; do
    sec_transaction "vapt-a1-unsupported-$unsupported"
    sec_a1_plain
    if [[ $unsupported == origin ]]; then
        vapt_elf "$SANDBOX/unsupported-bash" type=2 interp=/usr/lib64/ld-linux-x86-64.so.2 \
            needed=libreadline.so.8,libc.so.6 'runpath=$ORIGIN/../bad'
    else
        vapt_elf "$SANDBOX/unsupported-bash" type=2 interp=/opt/vendor/ld-linux-x86-64.so.2 \
            needed=libreadline.so.8,libc.so.6
    fi
    sec_a1_bash_reference "$SANDBOX/unsupported-bash"
    sec_a1_verdict "unsupported-$unsupported" 2
done

# A trusted ordinary candidate does not excuse another effective cache
# candidate with the same needed name, even if its bytes are identical.
for cache_state in absent unowned; do
    sec_transaction "vapt-a1-cache-candidate-$cache_state"
    sec_a1_plain
    vapt_elf "$SANDBOX/cache-library" soname=libvaptfix.so.1
    sec_a1_base_library usr/lib/libvaptfix.so.1 "$SANDBOX/cache-library"
    vapt_elf "$SANDBOX/cache-bash" type=2 interp=/usr/lib64/ld-linux-x86-64.so.2 \
        needed=libreadline.so.8,libc.so.6,libvaptfix.so.1
    sec_a1_bash_reference "$SANDBOX/cache-bash"
    SEC_EXPECTED=0
    if [[ $cache_state == unowned ]]; then
        mkdir -p "$ROOT/opt/vendor/lib"
        cp "$SANDBOX/cache-library" "$ROOT/opt/vendor/lib/libvaptfix.so.1"
        vapt_ldcache "$ROOT/etc/ld.so.cache" libvaptfix.so.1=/opt/vendor/lib/libvaptfix.so.1
        SEC_EXPECTED=2
    fi
    sec_a1_verdict "cache-candidate-$cache_state" "$SEC_EXPECTED"
done

# Closure is recursive, and declared FDO dlopen notes are dependencies rather
# than harmless strings. Both cases use authentic roots and an untrusted leaf.
for edge in transitive dlopen; do
    sec_transaction "vapt-a1-$edge-lower-leaf"
    sec_a1_plain
    vapt_elf "$SANDBOX/lower-leaf" soname=libvaptleaf.so.1
    sec_a1_lower_owner vapt-runtime usr/lib/libvaptleaf.so.1 "$SANDBOX/lower-leaf"
    if [[ $edge == transitive ]]; then
        vapt_elf "$SANDBOX/base-middle" soname=libvaptfix.so.1 needed=libvaptleaf.so.1
        sec_a1_base_library usr/lib/libvaptfix.so.1 "$SANDBOX/base-middle"
        vapt_elf "$SANDBOX/recursive-bash" type=2 interp=/usr/lib64/ld-linux-x86-64.so.2 \
            needed=libreadline.so.8,libc.so.6,libvaptfix.so.1
    else
        vapt_elf "$SANDBOX/recursive-bash" type=2 interp=/usr/lib64/ld-linux-x86-64.so.2 \
            needed=libreadline.so.8,libc.so.6 dlopen=libvaptleaf.so.1
    fi
    sec_a1_bash_reference "$SANDBOX/recursive-bash"
    sec_a1_verdict "$edge-lower-leaf" 2
done

# --- A2: gconv registry/cache targets, exact ORIGIN, and NSS candidates. ---
# The shared decoder fixture builders write original static cache fields and
# read-only inert ELF metadata, never iconvconfig output or upstream code.
sec_a2_lower_request() {
    sec_archive vapt-runtime 2-1
    sec_a1_member "$SEC_ARCHIVE" vapt-runtime 2-1 "$1" "$2" incoming
    printf 'chaotic-aur\tvapt-runtime\t2-1\thttps://mirror.example/vapt-runtime-2-1-x86_64.pkg.tar.gz\n' >"$VAPT_PLAN"
}
sec_a2_verdict() {
    local name="$1" expected="$2" target="${3:-extra/nmap}" tag="${4:-A2}" before version
    before="$(sec_a1_installed_version "${target#*/}")"
    version=7.99-1
    [[ $target != chaotic-aur/vapt-runtime ]] || version=2-1
    vapt_api pacman --yes "$target"
    assert_status "$tag $name: consumer verdict" "$expected" "$STATUS"
    if [[ $expected == 0 ]]; then
        assert_contains "$tag $name: reviewed transaction remains usable" "$OUTPUT" 'STATE=installed'
        assert_eq "$tag $name: consumer installs the planned version" \
            "$version" "$(sec_a1_installed_version "${target#*/}")"
        [[ -n $(vapt_calls commit-digests) ]] || _fail "$tag $name: no archive reached the consumer"
    else
        sec_no_commit "$tag $name"
        assert_eq "$tag $name: refusal preserves installed version" \
            "$before" "$(sec_a1_installed_version "${target#*/}")"
    fi
    vapt_tools_untouched "$tag $name"
}

# A retained absolute registration can name an object supplied later, outside
# the usual loader dirs. Unsupported absolute forms may instead fail closed.
for future_target in unrelated registered; do
    sec_transaction "vapt-a2-absolute-registry-$future_target"
    printf 'old inert runtime inventory data\n' >"$SANDBOX/runtime-old"
    sec_a1_lower_owner vapt-runtime usr/share/vapt-runtime/old.txt "$SANDBOX/runtime-old"
    mkdir -p "$ROOT/usr/lib/gconv"
    printf 'module VAPTFIX// INTERNAL vapt_unrelated 1\n' >"$ROOT/usr/lib/gconv/gconv-modules"
    vapt_elf "$SANDBOX/conversion-module" soname=convert.so needed=libc.so.6
    SEC_GCONV_DEST=opt/vendor/unrelated.so
    SEC_EXPECTED=0
    if [[ $future_target == registered ]]; then
        printf 'module VAPTFIX// INTERNAL /opt/vendor/convert 1\n' >"$ROOT/usr/lib/gconv/gconv-modules"
        SEC_GCONV_DEST=opt/vendor/convert.so
        SEC_EXPECTED=2
    fi
    sec_a2_lower_request "$SEC_GCONV_DEST" "$SANDBOX/conversion-module"
    sec_a2_verdict "absolute-registry-$future_target" "$SEC_EXPECTED" chaotic-aur/vapt-runtime
done

# A generated cache takes effect even when the adjacent text is benign.
# Without that cache the same retained lower-tier object is unrelated.
for registry_form in text cache; do
    sec_transaction "vapt-a2-generated-$registry_form-foreign-module"
    sec_a1_plain
    vapt_elf "$SANDBOX/foreign-conversion-module" soname=convert.so needed=libc.so.6
    sec_a1_lower_owner vapt-runtime opt/vendor/convert.so "$SANDBOX/foreign-conversion-module"
    mkdir -p "$ROOT/usr/lib/gconv"
    printf '# original inert alias fixture\nalias VAPTFIX// INTERNAL\n' >"$ROOT/usr/lib/gconv/gconv-modules"
    SEC_EXPECTED=0
    if [[ $registry_form == cache ]]; then
        vapt_gconv_cache "$ROOT/usr/lib/gconv/gconv-modules.cache" /opt/vendor/convert.so
        SEC_EXPECTED=2
    fi
    sec_a2_verdict "generated-$registry_form-foreign-module" "$SEC_EXPECTED"
done

# Prove each link and final object, whether discovered in text or in a cache.
for registration in text cache; do
    for link_state in canonical retargeted; do
        sec_transaction "vapt-a2-$registration-target-link-$link_state"
        sec_a1_plain
        vapt_elf "$SANDBOX/auth-conversion-module" soname=vapt_convert.so needed=libc.so.6
        sec_a1_base_library usr/lib/gconv/vapt_real.so "$SANDBOX/auth-conversion-module"
        sec_a1_base_library usr/lib/gconv/vapt_convert.so link:vapt_real.so
        if [[ $registration == text ]]; then
            printf 'module VAPTFIX// INTERNAL vapt_convert 1\n' >"$SANDBOX/auth-registry"
            sec_a1_base_library usr/lib/gconv/gconv-modules "$SANDBOX/auth-registry"
        else
            vapt_gconv_cache "$SANDBOX/auth-cache" /usr/lib/gconv/vapt_convert.so
            sec_a1_base_library usr/lib/gconv/gconv-modules.cache "$SANDBOX/auth-cache"
        fi
        SEC_EXPECTED=0
        if [[ $link_state == retargeted ]]; then
            mkdir -p "$ROOT/opt/vendor"
            cp "$SANDBOX/auth-conversion-module" "$ROOT/opt/vendor/convert.so"
            rm "$ROOT/usr/lib/gconv/vapt_convert.so"
            ln -s /opt/vendor/convert.so "$ROOT/usr/lib/gconv/vapt_convert.so"
            SEC_EXPECTED=2
        fi
        sec_a2_verdict "$registration-target-link-$link_state" "$SEC_EXPECTED"
    done
done

# Exact $ORIGIN is a supported per-object search directory, not a reason to
# reject all gconv. Its target module AND its origin-local dependency are
# authenticated, and the registry plus generated cache are ordinary base data.
sec_transaction vapt-a2-authenticated-gconv-exact-origin
sec_a1_plain
vapt_elf "$SANDBOX/origin-helper" soname=libvaptgconvhelper.so.1 needed=libc.so.6
sec_a1_base_library usr/lib/gconv/libvaptgconvhelper.so.1 "$SANDBOX/origin-helper"
vapt_elf "$SANDBOX/origin-conversion-module" soname=vapt_convert.so \
    needed=libvaptgconvhelper.so.1 'runpath=$ORIGIN'
sec_a1_base_library usr/lib/gconv/vapt_convert.so "$SANDBOX/origin-conversion-module"
printf '# original fixture conversion data\nalias VAPTFIX-ALIAS// VAPTFIX//\nmodule VAPTFIX// INTERNAL vapt_convert 1\n' >"$SANDBOX/origin-registry"
sec_a1_base_library usr/lib/gconv/gconv-modules "$SANDBOX/origin-registry"
vapt_gconv_cache "$SANDBOX/origin-cache" /usr/lib/gconv/vapt_convert.so
sec_a1_base_library usr/lib/gconv/gconv-modules.cache "$SANDBOX/origin-cache"
sec_a2_verdict authenticated-gconv-exact-origin 0

# Unrelated loader-directory libraries are still allowed; A2 is not a blanket
# non-base shared-object prohibition.
sec_transaction vapt-a2-unrelated-shared-object
printf 'old inert runtime inventory data\n' >"$SANDBOX/runtime-old"
sec_a1_lower_owner vapt-runtime usr/share/vapt-runtime/old.txt "$SANDBOX/runtime-old"
vapt_elf "$SANDBOX/unrelated-library" soname=libvapt_unrelated.so.1 needed=libc.so.6
sec_a2_lower_request usr/lib/libvapt_unrelated.so.1 "$SANDBOX/unrelated-library"
sec_a2_verdict unrelated-shared-object 0 chaotic-aur/vapt-runtime

# The same incoming NSS module is optional data without the retained service,
# but an executable candidate with it. No NSS call/module is actually made.
for service in absent configured; do
    sec_transaction "vapt-a2-nss-service-$service"
    printf 'old inert runtime inventory data\n' >"$SANDBOX/runtime-old"
    sec_a1_lower_owner vapt-runtime usr/share/vapt-runtime/old.txt "$SANDBOX/runtime-old"
    printf 'hosts: files\n' >"$ROOT/etc/nsswitch.conf"
    SEC_EXPECTED=0
    if [[ $service == configured ]]; then
        printf 'hosts: files vaptfix\n' >"$ROOT/etc/nsswitch.conf"
        SEC_EXPECTED=2
    fi
    vapt_elf "$SANDBOX/nss-module" soname=libnss_vaptfix.so.2 needed=libc.so.6
    sec_a2_lower_request usr/lib/libnss_vaptfix.so.2 "$SANDBOX/nss-module"
    sec_a2_verdict "nss-service-$service" "$SEC_EXPECTED" chaotic-aur/vapt-runtime
done

# C-locale gconv filenames do not split at Unicode NBSP. The apparent ASCII
# target is base-authenticated; the actual NBSP-containing target is supplied
# by the lower tier. Unsupported non-ASCII/absolute syntax must fail closed,
# never silently audit only the apparent ASCII prefix. Comments are ignored.
for record in comment active; do
    sec_transaction "vapt-a2-nbsp-filename-$record"
    printf 'old inert runtime inventory data\n' >"$SANDBOX/runtime-old"
    sec_a1_lower_owner vapt-runtime usr/share/vapt-runtime/old.txt "$SANDBOX/runtime-old"
    vapt_elf "$SANDBOX/nbsp-module" soname=vapt_convert.so needed=libc.so.6
    sec_a1_base_library opt/vapt-module.so "$SANDBOX/nbsp-module"
    SEC_NBSP_NAME=$'opt/vapt-module\302\240suffix.so'
    sec_a2_lower_request "$SEC_NBSP_NAME" "$SANDBOX/nbsp-module"
    mkdir -p "$ROOT/usr/lib/gconv"
    SEC_EXPECTED=0
    if [[ $record == active ]]; then
        printf 'module VAPT// INTERNAL /opt/vapt-module\302\240suffix\n' >"$ROOT/usr/lib/gconv/gconv-modules"
        SEC_EXPECTED=2
    else
        printf '# module VAPT// INTERNAL /opt/vapt-module\302\240suffix\n' >"$ROOT/usr/lib/gconv/gconv-modules"
    fi
    sec_a2_verdict "nbsp-filename-$record" "$SEC_EXPECTED" chaotic-aur/vapt-runtime
done

# Cache names are literal: selecting "convert" must never be changed into the
# different, safe "convert.so". Both bytesets are inert; only one is proven.
for provider in base lower; do
    sec_transaction "vapt-a2-cache-literal-no-suffix-$provider"
    printf 'old inert runtime inventory data\n' >"$SANDBOX/runtime-old"
    sec_a1_lower_owner vapt-runtime usr/share/vapt-runtime/old.txt "$SANDBOX/runtime-old"
    vapt_elf "$SANDBOX/literal-module" soname=vapt_convert.so needed=libc.so.6
    sec_a1_base_library opt/vendor/convert.so "$SANDBOX/literal-module"
    SEC_LITERAL_DEST=opt/vendor/unrelated
    SEC_EXPECTED=0
    if [[ $provider == base ]]; then
        sec_a1_base_library opt/vendor/convert "$SANDBOX/literal-module"
    else
        SEC_LITERAL_DEST=opt/vendor/convert
        SEC_EXPECTED=2
    fi
    sec_a2_lower_request "$SEC_LITERAL_DEST" "$SANDBOX/literal-module"
    vapt_gconv_cache "$ROOT/usr/lib/gconv/gconv-modules.cache" /opt/vendor/convert
    sec_a2_verdict "cache-literal-no-suffix-$provider" "$SEC_EXPECTED" chaotic-aur/vapt-runtime
done

# The '[' delimiter belongs to the NSS action syntax even without whitespace.
# Both forms name the same actual foreign module and must be refused.
for bracket in spaced adjacent; do
    sec_transaction "vapt-a2-nss-action-$bracket"
    printf 'old inert runtime inventory data\n' >"$SANDBOX/runtime-old"
    sec_a1_lower_owner vapt-runtime usr/share/vapt-runtime/old.txt "$SANDBOX/runtime-old"
    vapt_elf "$SANDBOX/action-nss-module" soname=libnss_vaptfix.so.2 needed=libc.so.6
    sec_a2_lower_request usr/lib/libnss_vaptfix.so.2 "$SANDBOX/action-nss-module"
    if [[ $bracket == spaced ]]; then
        printf 'hosts: files vaptfix [NOTFOUND=return]\n' >"$ROOT/etc/nsswitch.conf"
    else
        printf 'hosts: files vaptfix[NOTFOUND=return]\n' >"$ROOT/etc/nsswitch.conf"
    fi
    sec_a2_verdict "nss-action-$bracket" 2 chaotic-aur/vapt-runtime
done

# Unsupported source names must not disappear from the model. Their comments
# are inert, but active dotted/slashed tokens cannot be silently skipped.
for token in dotted slashed; do
    for record in comment active; do
        sec_transaction "vapt-a2-nss-$token-$record"
        printf 'old inert runtime inventory data\n' >"$SANDBOX/runtime-old"
        sec_a1_lower_owner vapt-runtime usr/share/vapt-runtime/old.txt "$SANDBOX/runtime-old"
        vapt_elf "$SANDBOX/unsupported-nss-module" soname=libnss_vaptfix.so.2 needed=libc.so.6
        SEC_NSS_SERVICE=vapt.fix
        SEC_NSS_DEST=usr/lib/libnss_vapt.fix.so.2
        if [[ $token == slashed ]]; then
            SEC_NSS_SERVICE=vapt/unsafe
            SEC_NSS_DEST=libnss_vapt/unsafe.so.2
        fi
        sec_a2_lower_request "$SEC_NSS_DEST" "$SANDBOX/unsupported-nss-module"
        SEC_EXPECTED=0
        if [[ $record == active ]]; then
            printf 'hosts: files %s\n' "$SEC_NSS_SERVICE" >"$ROOT/etc/nsswitch.conf"
            SEC_EXPECTED=2
        else
            printf 'hosts: files # %s\n' "$SEC_NSS_SERVICE" >"$ROOT/etc/nsswitch.conf"
        fi
        sec_a2_verdict "nss-$token-$record" "$SEC_EXPECTED" chaotic-aur/vapt-runtime
    done
done

# Absolute text filenames and iconvconfig's dir+filename cache construction
# can address different objects. Enumerate both or refuse the absolute form.
for form in relative absolute; do
    sec_transaction "vapt-a2-text-future-cache-$form"
    sec_a1_plain
    vapt_elf "$SANDBOX/future-cache-module" soname=vapt_convert.so needed=libc.so.6
    sec_a1_base_library opt/vendor/convert.so "$SANDBOX/future-cache-module"
    sec_a1_base_library usr/lib/gconv/vapt_safe.so "$SANDBOX/future-cache-module"
    sec_a1_lower_owner vapt-runtime usr/lib/gconv/opt/vendor/convert.so "$SANDBOX/future-cache-module"
    SEC_EXPECTED=0
    if [[ $form == absolute ]]; then
        printf 'module VAPT// INTERNAL /opt/vendor/convert.so 1\n' >"$ROOT/usr/lib/gconv/gconv-modules"
        SEC_EXPECTED=2
    else
        printf 'module VAPT// INTERNAL vapt_safe 1\n' >"$ROOT/usr/lib/gconv/gconv-modules"
    fi
    sec_a2_verdict "text-future-cache-$form" "$SEC_EXPECTED"
done

# Reachable cache boundaries: INTERNAL is module 0; VAPT// and U// resolve to
# nonzero modules 1/2. Seven-slot hash first positions are 2/5 respectively
# under PJW hashing, without a collision. The control selects a genuine extra
# record through its bias-1 pointer; corrupted records are never executed.
sec_a2_boundary_cache() {
    python3 - "$1" "$2" <<'PY'
import struct, sys
from pathlib import Path
destination, variant = Path(sys.argv[1]), sys.argv[2]
strings = bytearray(b'\0')
def string(value):
    offset = len(strings)
    strings.extend(value.encode('ascii') + b'\0')
    return offset
source = string('VAPT//')
target = string('U//')
safe_dir = string('/opt/vapt-safe/')
safe_name = string('convert.so')
foreign_dir = string('/opt/vapt-foreign/')
foreign_name = string('convert')
if len(strings) % 2:
    strings.extend(b'\0')
hashes = [(0, 0)] * 7
hashes[2] = (source, 3 if variant == 'hash-hidden-module' else 1)
hashes[5] = (target, 2)
extra = struct.pack('<4H', 1, 2, safe_dir, safe_name) + struct.pack('<H', 0)
extra_pointer = 1
if variant == 'hash-hidden-module':
    extra_pointer = 0
    # This fourth record is wholly in the file but beyond the declared
    # three-entry module table. Native hash selection can address it.
    extra = struct.pack('<6H', source, foreign_dir, foreign_name, 0, 0, 0)
elif variant == 'extra-pointer-eof':
    extra_pointer = len(extra) + 1
elif variant == 'extra-intermediate-outname':
    # Destination 2 matches the last step, so the record is selected; the
    # earlier step's outname 3 is nevertheless outside the declared table.
    extra = struct.pack('<7H', 2, 3, safe_dir, safe_name, 2, safe_dir, safe_name) + struct.pack('<H', 0)
elif variant == 'extra-unterminated':
    # Nonmatching destination forces the native reader to seek another
    # record, but no zero-count terminator follows this complete record.
    extra = struct.pack('<4H', 1, 1, safe_dir, safe_name)
module_table = (
    struct.pack('<6H', 0, 0, 0, 0, 0, 0)
    + struct.pack('<6H', source, safe_dir, safe_name, 0, 0, extra_pointer)
    + struct.pack('<6H', target, 0, 0, safe_dir, safe_name, 0))
string_offset = 16
hash_offset = string_offset + len(strings)
module_offset = hash_offset + 4 * len(hashes)
other_offset = module_offset + len(module_table)
header = struct.pack('<IHHHHH', 0x20010324, string_offset, hash_offset,
                     len(hashes), module_offset, other_offset) + b'\0\0'
destination.parent.mkdir(parents=True, exist_ok=True)
destination.write_bytes(header + strings + b''.join(struct.pack('<2H', *row) for row in hashes) + module_table + extra)
destination.chmod(0o644)
PY
}
for cache_boundary in extra-valid hash-hidden-module extra-pointer-eof extra-intermediate-outname extra-unterminated; do
    sec_transaction "vapt-a2-cache-$cache_boundary"
    sec_a1_plain
    vapt_elf "$SANDBOX/cache-boundary-module" soname=vapt_convert.so needed=libc.so.6
    sec_a1_base_library opt/vapt-safe/convert.so "$SANDBOX/cache-boundary-module"
    sec_a1_lower_owner vapt-runtime opt/vapt-foreign/convert "$SANDBOX/cache-boundary-module"
    sec_a2_boundary_cache "$ROOT/usr/lib/gconv/gconv-modules.cache" "$cache_boundary"
    SEC_EXPECTED=2
    [[ $cache_boundary != extra-valid ]] || SEC_EXPECTED=0
    sec_a2_verdict "cache-$cache_boundary" "$SEC_EXPECTED"
done

# --- Independent public-consumer deltas for SEC-L1..L7. ---------------------
# The owner file covers audit-level cases. These drive the hermetic transaction
# and its observable package state, without letting a real manager run.
sec_l_raw_member() {
    python3 - "$1" "$2" "$3" <<'PY'
import io, sys, tarfile
from pathlib import Path
archive, rel, source = Path(sys.argv[1]), sys.argv[2], Path(sys.argv[3])
data, result = source.read_bytes(), io.BytesIO()
with tarfile.open(archive, 'r:*') as old, tarfile.open(fileobj=result, mode='w:gz') as new:
    for member in old:
        if member.name.removeprefix('./').rstrip('/') != rel:
            new.addfile(member, old.extractfile(member) if member.isfile() else None)
    member = tarfile.TarInfo(rel)
    member.mode, member.size = 0o644, len(data)
    new.addfile(member, io.BytesIO(data))
archive.write_bytes(result.getvalue())
PY
}

for shell in retained nonbase; do
    sec_transaction "vapt-l1-scriptlet-consumer-$shell"
    rm -f "$ROOT"/usr/share/libalpm/hooks/*.hook
    if [[ $shell == retained ]]; then
        sec_archive nmap 7.99-1 $'.INSTALL=post_install() {\n echo "original fixture notice"\n return 0\n}'
        sec_a2_verdict "SEC-L1/scriptlet-consumer-$shell" 0
    else
        SEC_SHELL_ARCHIVE="$(vapt_stock_archive bash 5.3.3-3)"
        vapt_elf "$SANDBOX/nonbase-shell" type=2 interp=/usr/lib64/ld-linux-x86-64.so.2 \
            needed=libreadline.so.8,libc.so.6 tag=nonbase-shell-bytes
        sec_a1_member "$SEC_SHELL_ARCHIVE" bash 5.3.3-3 usr/bin/bash "$SANDBOX/nonbase-shell" incoming
        printf 'post_upgrade() {\n return 0\n}\n' >"$SANDBOX/builtin-install"
        sec_l_raw_member "$SEC_SHELL_ARCHIVE" .INSTALL "$SANDBOX/builtin-install"
        vapt_conf_add $'[chaotic-aur]\nServer = https://mirror.example/chaotic-aur/$arch'
        python3 - "$ROOT/var/lib/haseen/vapt/repositories.json" <<'PY'
import json, sys
from pathlib import Path
path = Path(sys.argv[1])
repos = json.loads(path.read_text())
record = next(record for record in repos['core'] if record['name'] == 'bash' and record['version'] == '5.3.3-3')
repos['core'] = [record for record in repos['core'] if not (record['name'] == 'bash' and record['version'] == '5.3.3-3')]
repos['chaotic-aur'] = [record]
path.write_text(json.dumps(repos))
PY
        python3 "$VAPT_FIXTURE_DRIVER" digests "$VAPT_ARCHIVES"
        printf 'chaotic-aur\tbash\t5.3.3-3\thttps://mirror.example/bash-5.3.3-3-x86_64.pkg.tar.gz\n' >"$VAPT_PLAN"
        sec_a2_verdict "SEC-L1/scriptlet-consumer-$shell" 2 chaotic-aur/bash
    fi
done

# A full upgrade reaches the privileged postcommit Python startup. Its runtime
# remains base-proven, while both incoming extensions have the same NON-base
# origin. None are imported, loaded or executed by the test's manager fake.
for import_path in site-packages stdlib-abi-init; do
    sec_transaction "vapt-l2-python-consumer-$import_path"
    vapt_stock_python
    rm -f "$ROOT"/usr/share/libalpm/hooks/*.hook
    printf 'old inert runtime inventory data\n' >"$SANDBOX/runtime-old"
    sec_a1_lower_owner vapt-runtime usr/share/vapt-runtime/old.txt "$SANDBOX/runtime-old"
    vapt_elf "$SANDBOX/python-shadow" needed=libc.so.6
    SEC_PYTHON_MEMBER=usr/lib/python3.14/site-packages/ctypes/__init__.cpython-314-x86_64-linux-gnu.so
    SEC_EXPECTED=0
    if [[ $import_path == stdlib-abi-init ]]; then
        SEC_PYTHON_MEMBER=usr/lib/python3.14/ctypes/__init__.cpython-314-x86_64-linux-gnu.so
        SEC_EXPECTED=2
    fi
    sec_a2_lower_request "$SEC_PYTHON_MEMBER" "$SANDBOX/python-shadow"
    vapt_api upgrade
    assert_status "SEC-L2 $import_path full-upgrade consumer" "$SEC_EXPECTED" "$STATUS"
    if [[ $SEC_EXPECTED == 0 ]]; then
        assert_eq 'SEC-L2 isolated non-base site-packages does not break the reviewed upgrade' 2-1 "$(sec_a1_installed_version vapt-runtime)"
    else
        sec_no_commit 'SEC-L2 ABI package-extension shadow'
        assert_eq 'SEC-L2 rejected non-base import shadow preserves the installed package' 1-1 "$(sec_a1_installed_version vapt-runtime)"
    fi
    vapt_tools_untouched "SEC-L2 $import_path"
done

for retained_name in novel colliding; do
    sec_transaction "vapt-l3-retained-soname-consumer-$retained_name"
    SEC_SONAME=libvapt_retained.so.99
    SEC_EXPECTED=0
    if [[ $retained_name == colliding ]]; then
        SEC_SONAME=libreadline.so.8
        SEC_EXPECTED=2
    fi
    vapt_elf "$ROOT/usr/lib/libvapt_retained.so.99" "soname=$SEC_SONAME" needed=libc.so.6
    sec_archive nmap 7.99-1 'etc/ld.so.conf.d/vapt-trigger.conf=/usr/lib'
    # The stock fixture has no current cache: only future ldconfig enumeration
    # can reveal the retained collider under its different filename.
    sec_a2_verdict "SEC-L3/retained-soname-$retained_name" "$SEC_EXPECTED"
done

# The actual include/opendir root follows this absolute selector symlink. The
# incoming child is at its PHYSICAL target, not at the logical selector path.
for selector in loader gconv; do
    sec_transaction "vapt-l4-physical-selector-consumer-$selector"
    printf 'old inert runtime inventory data\n' >"$SANDBOX/runtime-old"
    sec_a1_lower_owner vapt-runtime usr/share/vapt-runtime/old.txt "$SANDBOX/runtime-old"
    mkdir -p "$ROOT/opt/selectors"
    if [[ $selector == loader ]]; then
        rm -rf "$ROOT/etc/ld.so.conf.d"
        ln -s /opt/selectors "$ROOT/etc/ld.so.conf.d"
        printf 'include /etc/ld.so.conf.d/*.conf\n' >"$ROOT/etc/ld.so.conf"
        printf '/opt/vendor/lib\n' >"$SANDBOX/selector-conf"
        vapt_elf "$SANDBOX/selector-module" soname=libreadline.so.8 needed=libc.so.6
        SEC_SELECTOR_MEMBER=opt/vendor/lib/libvapt_selector.so.1
    else
        mkdir -p "$ROOT/usr/lib/gconv"
        ln -s /opt/selectors "$ROOT/usr/lib/gconv/gconv-modules.d"
        printf 'module VAPT// INTERNAL /opt/vendor/convert 1\n' >"$SANDBOX/selector-conf"
        vapt_elf "$SANDBOX/selector-module" soname=convert.so needed=libc.so.6
        SEC_SELECTOR_MEMBER=opt/vendor/convert.so
    fi
    sec_a2_lower_request opt/selectors/vapt.conf "$SANDBOX/selector-conf"
    sec_a1_member "$SEC_ARCHIVE" vapt-runtime 2-1 "$SEC_SELECTOR_MEMBER" "$SANDBOX/selector-module" incoming
    sec_a2_verdict "SEC-L4/physical-selector-$selector" 2 chaotic-aur/vapt-runtime
done

# Permission changes are real scratch inode modes, not simulated UID claims.
# An authenticated writable cache snapshot is acceptable, but changed bytes
# must never authenticate a matching self-attested retained shell. A genuine
# old reference remains available to the fake downloader, preventing a vacuous
# "download unavailable" rejection.
for snapshot in authentic substituted; do
    sec_transaction "vapt-l5-writable-reference-$snapshot"
    sec_a1_plain
    SEC_REFERENCE="$ROOT/var/cache/pacman/pkg/bash-5.3.3-2-x86_64.pkg.tar.gz"
    cp "$SEC_REFERENCE" "$VAPT_ARCHIVES/"
    chmod 0777 "$ROOT/var/cache/pacman/pkg"
    chmod 0666 "$SEC_REFERENCE"
    SEC_EXPECTED=0
    if [[ $snapshot == substituted ]]; then
        vapt_elf "$SANDBOX/substituted-shell" type=2 interp=/usr/lib64/ld-linux-x86-64.so.2 \
            needed=libreadline.so.8,libc.so.6 tag=signed-but-unreviewed-reference
        sec_l_raw_member "$SEC_REFERENCE" usr/bin/bash "$SANDBOX/substituted-shell"
        cp "$SANDBOX/substituted-shell" "$ROOT/usr/bin/bash"
        python3 - "$ROOT" "$SEC_REFERENCE" <<'PY'
import gzip, hashlib, sys
from pathlib import Path
root, archive = Path(sys.argv[1]), Path(sys.argv[2])
digest = hashlib.sha256(archive.read_bytes()).hexdigest()
Path(str(archive) + '.sig').write_text('fixture-sha256 ' + digest + '\n')
fpr = (root / 'var/lib/haseen/vapt/fixture-base-signers').read_text().splitlines()[0]
with (root / 'var/lib/haseen/vapt/fixture-signatures.tsv').open('a') as stream:
    stream.write(digest + '\t' + fpr + '\n')
mtree = root / 'var/lib/pacman/local/bash-5.3.3-2/mtree'
rows = gzip.open(mtree, 'rt').read().splitlines()
file_digest = hashlib.sha256((root / 'usr/bin/bash').read_bytes()).hexdigest()
with gzip.open(mtree, 'wt') as stream:
    stream.write('\n'.join('./usr/bin/bash type=file mode=644 sha256digest=' + file_digest
                           if row.startswith('./usr/bin/bash ') else row for row in rows) + '\n')
PY
        SEC_EXPECTED=2
    fi
    sec_a2_verdict "SEC-L5/writable-reference-$snapshot" "$SEC_EXPECTED"
    chmod 0755 "$ROOT/var/cache/pacman/pkg"
done

for ancestry in safe group-writable; do
    sec_transaction "vapt-l5-sealed-ancestor-$ancestry"
    sec_a1_plain
    export VAPT_SEALED_ANCESTOR_MODE=0755
    SEC_EXPECTED=0
    if [[ $ancestry == group-writable ]]; then
        export VAPT_SEALED_ANCESTOR_MODE=0775
        SEC_EXPECTED=2
    fi
    sec_a2_verdict "SEC-L5/sealed-ancestor-$ancestry" "$SEC_EXPECTED"
    unset VAPT_SEALED_ANCESTOR_MODE
done

# The actual PKGINFO dependency can name a forbidden retained virtual provider
# even though the reviewed DB closure is empty. Legitimate matching metadata
# and unambiguous identity remain usable.
for metadata in matching-provider forbidden-provider duplicate-version; do
    sec_transaction "vapt-l6-actual-metadata-$metadata"
    sec_archive nmap 7.99-1
    SEC_PROVIDER=vapt-safe-provider
    SEC_DEPENDENCY=vapt-safe-virtual
    if [[ $metadata == forbidden-provider ]]; then
        SEC_PROVIDER=omarchy-shadow
        SEC_DEPENDENCY=vapt-secret-virtual
    fi
    python3 - "$ROOT" "$SEC_PROVIDER" "$SEC_DEPENDENCY" "$metadata" <<'PY'
import json, sys
from pathlib import Path
root, name, provided, variant = Path(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4]
url = 'https://example.org/' + name
entry = root / 'var/lib/pacman/local' / (name + '-1-1')
entry.mkdir()
(entry / 'desc').write_text('%NAME%\n' + name + '\n\n%VERSION%\n1-1\n\n%URL%\n' + url + '\n\n')
(entry / 'depends').write_text('%DEPENDS%\n\n%PROVIDES%\n' + provided + '\n\n%CONFLICTS%\n\n%REPLACES%\n\n')
(entry / 'files').write_text('%FILES%\n\n')
path = root / 'var/lib/haseen/vapt/repositories.json'
repos = json.loads(path.read_text())
repos['extra'].append({'name': name, 'version': '1-1', 'url': url, 'depends': [],
                       'provides': [provided], 'conflicts': [], 'replaces': []})
for record in repos['extra']:
    if record['name'] == 'nmap':
        record['depends'] = [provided] if variant == 'matching-provider' else []
path.write_text(json.dumps(repos))
PY
    printf 'pkgname = nmap\npkgver = 7.99-1\narch = x86_64\n' >"$SANDBOX/actual-pkginfo"
    if [[ $metadata == duplicate-version ]]; then
        printf 'pkgver = 99-1\n' >>"$SANDBOX/actual-pkginfo"
    else
        printf 'depend = %s\n' "$SEC_DEPENDENCY" >>"$SANDBOX/actual-pkginfo"
    fi
    sec_l_raw_member "$SEC_ARCHIVE" .PKGINFO "$SANDBOX/actual-pkginfo"
    # Publish the exact planned filename/hash regardless of the malformed
    # identity fields. A checksum mismatch must not stand in for L6 review.
    python3 - "$ROOT" "$SEC_ARCHIVE" <<'PY'
import hashlib, json, sys
from pathlib import Path
root, archive = Path(sys.argv[1]), Path(sys.argv[2])
path = root / 'var/lib/haseen/vapt/repositories.json'
repos = json.loads(path.read_text())
digest = hashlib.sha256(archive.read_bytes()).hexdigest()
for record in repos['extra']:
    if record['name'] == 'nmap':
        record['filename'], record['sha256sum'] = archive.name, digest
path.write_text(json.dumps(repos))
Path(str(archive) + '.sig').write_text('fixture-sha256 ' + digest + '\n')
fpr = (root / 'var/lib/haseen/vapt/fixture-base-signers').read_text().splitlines()[0]
table = root / 'var/lib/haseen/vapt/fixture-signatures.tsv'
rows = [row for row in table.read_text().splitlines() if not row.startswith(digest + '\t')]
table.write_text('\n'.join(rows + [digest + '\t' + fpr]) + '\n')
PY
    SEC_EXPECTED=2
    [[ $metadata != matching-provider ]] || SEC_EXPECTED=0
    sec_a2_verdict "SEC-L6/actual-metadata-$metadata" "$SEC_EXPECTED"
done

# Public entrypoints are NOT the hermetic mutator. A sysroot must be refused
# before any manager, trust/config action or user state write, not merely before
# sudo commits. The stubs remain fail-only; no live command can be delegated.
for public_verb in install remove; do
    sec_case "vapt-l7-public-$public_verb-no-actions"
    SEC_TREE_BEFORE="$(vapt_tree)"
    if [[ $public_verb == install ]]; then
        vapt_cli install --yes --groups osint
    else
        vapt_cli remove --yes
    fi
    assert_status "SEC-L7 public $public_verb refuses sysroot mutation" 2 "$STATUS"
    assert_eq "SEC-L7 public $public_verb invokes no manager/key/config command" '' "$(find "$CALLS" -type f -printf '%f\n')"
    assert_eq "SEC-L7 public $public_verb preserves the entire observed state" "$SEC_TREE_BEFORE" "$(vapt_tree)"
done
sec_case vapt-l7-public-readonly-controls
SEC_TREE_BEFORE="$(vapt_tree)"
vapt_cli install --dry-run --groups osint
assert_status 'SEC-L7 public sysroot dry-run planning remains available' 0 "$STATUS"
vapt_cli status
assert_status 'SEC-L7 public sysroot status reports not-applied without a provisioning report' 1 "$STATUS"
assert_contains 'SEC-L7 not-applied status explains its missing report' "$OUTPUT" 'missing: no per-user VAPT provisioning report'
assert_eq 'SEC-L7 readonly inspection invokes no manager/key/config command' '' "$(find "$CALLS" -type f -printf '%f\n')"
assert_eq 'SEC-L7 readonly inspection preserves the observed state' "$SEC_TREE_BEFORE" "$(vapt_tree)"

# --- A3: post-commit sudo selects PAM/sudo runtime inputs. ------------------
# Retained PAM/sudo configuration is existing admin state. Every stack, sudoers
# record, environment file and ELF below is original static text or inert ELF
# metadata; no PAM module, helper, plugin or sudo is loaded or executed. The
# selection probes use /usr/lib/vapt/* so only the selector graph, never a
# blanket PAM/sudo tree rule, can explain a refusal. A lower-tier vapt-runtime
# (chaotic-aur, non-base signer) is installed in every case.
sec_a3_case() {
    local rel="${2:-usr/share/vapt-runtime/old.txt}" source="${3:-}"
    sec_transaction "$1"
    if [[ -z $source ]]; then
        printf 'old inert runtime inventory data\n' >"$SANDBOX/runtime-old"
        source="$SANDBOX/runtime-old"
    fi
    sec_a1_lower_owner vapt-runtime "$rel" "$source"
    mkdir -p "$ROOT/etc/pam.d" "$ROOT/usr/lib/pam.d" "$ROOT/usr/lib/sudo"
    sec_a3_pam etc/pam.d/sudo $'auth include system-auth\naccount include system-auth\nsession include system-auth'
    sec_a3_pam etc/pam.d/system-auth $'auth required pam_unix.so\naccount required pam_unix.so\nsession required pam_unix.so'
    vapt_elf "$ROOT/usr/bin/sudo" type=2 interp=/usr/lib64/ld-linux-x86-64.so.2 needed=libc.so.6
}
# sec_a3_pam REL TEXT — a retained, unowned configuration file in the sysroot.
sec_a3_pam() {
    mkdir -p "$ROOT/$(dirname "$1")"
    printf '%s\n' "$2" >"$ROOT/$1"
    chmod 0644 "$ROOT/$1"
}
# sec_a3_text NAME TEXT — scratch payload bytes outside the sysroot; prints it.
sec_a3_text() {
    printf '%s\n' "$2" >"$SANDBOX/a3-$1"
    printf '%s\n' "$SANDBOX/a3-$1"
}
# sec_a3_incoming REL SOURCE [REL SOURCE]... — plan the lower-tier upgrade
# vapt-runtime 2-1 carrying exactly these members.
sec_a3_incoming() {
    sec_a2_lower_request "$1" "$2"
    shift 2
    while (($# >= 2)); do
        sec_a1_member "$SEC_ARCHIVE" vapt-runtime 2-1 "$1" "$2" incoming
        shift 2
    done
}
sec_a3_verdict() { sec_a2_verdict "$1" "$2" "${3:-chaotic-aur/vapt-runtime}" A3; }

# pam_env's conffile=/envfile= arguments select files outside /etc/security.
# The identical incoming file is inert data while unselected; a selected but
# absent and unchanged file is not a refusal reason.
for selection in unselected absent-unchanged conffile envfile; do
    sec_a3_case "vapt-a3-pam-env-$selection"
    SEC_EXPECTED=0
    case "$selection" in
    unselected) SEC_PAM_ENV='session required pam_env.so' ;;
    absent-unchanged | conffile) SEC_PAM_ENV='session required pam_env.so conffile=/etc/vapt/pam_env.conf' ;;
    envfile) SEC_PAM_ENV='session required pam_env.so readenv=1 envfile=/etc/vapt/environment' ;;
    esac
    sec_a3_pam etc/pam.d/system-auth $'auth required pam_unix.so\naccount required pam_unix.so\nsession required pam_unix.so\n'"$SEC_PAM_ENV"
    case "$selection" in
    unselected) sec_a3_incoming etc/vapt/pam_env.conf "$(sec_a3_text env 'VAPT_NOTE DEFAULT=fixture')" ;;
    absent-unchanged) sec_a3_incoming usr/share/vapt-runtime/new.txt "$(sec_a3_text env 'unrelated inert data')" ;;
    conffile) sec_a3_incoming etc/vapt/pam_env.conf "$(sec_a3_text env 'VAPT_NOTE DEFAULT=fixture')"; SEC_EXPECTED=2 ;;
    envfile) sec_a3_incoming etc/vapt/environment "$(sec_a3_text env 'VAPT_NOTE=fixture')"; SEC_EXPECTED=2 ;;
    esac
    sec_a3_verdict "pam-env-$selection" "$SEC_EXPECTED"
done

# Loader overrides in current or future pam_env inputs are refused even when
# the incoming package is base-signed (extra/nmap); benign variables are not.
# `export` is accepted pam_env syntax and must not hide the variable name.
for environment in current-benign current-preload future-benign future-pam-env-conf future-export; do
    sec_a3_case "vapt-a3-loader-environment-$environment"
    sec_a3_pam etc/pam.d/system-auth $'auth required pam_unix.so\naccount required pam_unix.so\nsession required pam_unix.so\nsession required pam_env.so'
    SEC_EXPECTED=2
    case "$environment" in
    current-benign) sec_a3_pam etc/environment 'EDITOR=nano'; sec_a1_plain; SEC_EXPECTED=0 ;;
    current-preload) sec_a3_pam etc/environment 'LD_PRELOAD=/usr/lib/libc.so.6'; sec_a1_plain ;;
    future-benign) sec_archive nmap 7.99-1 'etc/environment=EDITOR=nano'; SEC_EXPECTED=0 ;;
    future-pam-env-conf) sec_archive nmap 7.99-1 'etc/security/pam_env.conf=LD_LIBRARY_PATH DEFAULT=/opt/nmap/lib' ;;
    future-export) sec_archive nmap 7.99-1 'etc/environment=export LD_AUDIT=/opt/nmap/audit.so' ;;
    esac
    sec_a3_verdict "loader-environment-$environment" "$SEC_EXPECTED" extra/nmap
done

# pam_exec: an absolute command is a guarded executable (base coreutils touch
# is proven; a lower-tier incoming command is not). A relative command has no
# reviewable resolution and must be a manual refusal.
for command in absolute-base absolute-incoming relative; do
    sec_a3_case "vapt-a3-pam-exec-$command"
    case "$command" in
    absolute-base) SEC_EXEC=/usr/bin/touch ;;
    absolute-incoming) SEC_EXEC=/usr/lib/vapt/notify ;;
    relative) SEC_EXEC=vapt-notify ;;
    esac
    sec_a3_pam etc/pam.d/system-auth $'auth optional pam_exec.so quiet '"$SEC_EXEC"$'\nauth required pam_unix.so\naccount required pam_unix.so\nsession required pam_unix.so'
    if [[ $command == absolute-incoming ]]; then
        sec_a3_incoming usr/lib/vapt/notify "$(sec_a3_text notify 'inert fixture command, never executed')"
        sec_a3_verdict "pam-exec-$command" 2
    else
        sec_a1_plain
        SEC_EXPECTED=2
        [[ $command != absolute-base ]] || SEC_EXPECTED=0
        sec_a3_verdict "pam-exec-$command" "$SEC_EXPECTED" extra/nmap
    fi
done

# Vendor PAM files: without /etc/pam.d/sudo the vendor service and its
# vendor-only include are live. The approved policy guards every present
# candidate in /etc/pam.d and usr/lib/pam.d (no precedence is modelled), so
# a referencing vendor file still selects the module beside /etc/pam.d/sudo.
# The retained fallback stack, and an incoming module no present file names,
# are legitimate.
for vendor in fallback-retained fallback-selected both-present unreferenced; do
    sec_a3_case "vapt-a3-pam-vendor-$vendor"
    sec_a3_pam usr/lib/pam.d/sudo $'auth include vapt-auth\naccount include system-auth\nsession include system-auth'
    if [[ $vendor == unreferenced ]]; then
        sec_a3_pam usr/lib/pam.d/vapt-auth 'auth include system-auth'
    else
        sec_a3_pam usr/lib/pam.d/vapt-auth $'auth optional /usr/lib/vapt/pam_x.so\nauth include system-auth'
    fi
    [[ $vendor == both-present || $vendor == unreferenced ]] || rm "$ROOT/etc/pam.d/sudo"
    vapt_elf "$SANDBOX/pam-x" soname=pam_x.so needed=libc.so.6
    if [[ $vendor == fallback-retained ]]; then
        sec_a1_plain
        sec_a3_verdict "pam-vendor-$vendor" 0 extra/nmap
    else
        sec_a3_incoming usr/lib/vapt/pam_x.so "$SANDBOX/pam-x"
        SEC_EXPECTED=2
        [[ $vendor != unreferenced ]] || SEC_EXPECTED=0
        sec_a3_verdict "pam-vendor-$vendor" "$SEC_EXPECTED"
    fi
done

# A shared include reached twice (diamond) with -type and bracket controls is
# legitimate. A substack/include cycle must terminate and still guard the
# dash-type bracket module reached only inside the cycle.
for graph in diamond cycle; do
    sec_a3_case "vapt-a3-pam-graph-$graph"
    vapt_elf "$SANDBOX/pam-x" soname=pam_x.so needed=libc.so.6
    if [[ $graph == diamond ]]; then
        sec_a3_pam etc/pam.d/sudo $'auth include system-auth\naccount substack vapt-account\nsession include system-auth'
        sec_a3_pam etc/pam.d/vapt-account $'-account [success=ok new_authtok_reqd=ok default=ignore] pam_permit.so\naccount include system-auth'
        sec_a3_incoming usr/lib/vapt/pam_other.so "$SANDBOX/pam-x"
        sec_a3_verdict "pam-graph-$graph" 0
    else
        sec_a3_pam etc/pam.d/sudo $'auth include vapt-loop-a\naccount include system-auth\nsession include system-auth'
        sec_a3_pam etc/pam.d/vapt-loop-a $'auth substack vapt-loop-b\nauth include system-auth'
        sec_a3_pam etc/pam.d/vapt-loop-b $'-auth [success=ok default=ignore] /usr/lib/vapt/pam_x.so\nauth include vapt-loop-a'
        sec_a3_incoming usr/lib/vapt/pam_x.so "$SANDBOX/pam-x"
        sec_a3_verdict "pam-graph-$graph" 2
    fi
done

# Removal is a change too: dropping a referenced lower-tier module alters the
# stack even for a dash-type rule. Keeping it, or dropping an unreferenced
# one, is not a refusal reason.
for removal in kept removed-referenced removed-unreferenced; do
    vapt_elf "$SANDBOX/pam-vapt-$removal" soname=pam_vapt.so needed=libc.so.6
    sec_a3_case "vapt-a3-pam-removal-$removal" usr/lib/vapt/pam_vapt.so "$SANDBOX/pam-vapt-$removal"
    if [[ $removal != removed-unreferenced ]]; then
        sec_a3_pam etc/pam.d/system-auth $'-auth [success=1 default=ignore] /usr/lib/vapt/pam_vapt.so\nauth required pam_unix.so\naccount required pam_unix.so\nsession required pam_unix.so'
    fi
    if [[ $removal == kept ]]; then
        sec_a1_plain
        sec_a3_verdict "pam-removal-$removal" 0 extra/nmap
    else
        sec_a3_incoming usr/share/vapt-runtime/new.txt "$(sec_a3_text removal 'replacement inert data')"
        SEC_EXPECTED=2
        [[ $removal != removed-unreferenced ]] || SEC_EXPECTED=0
        sec_a3_verdict "pam-removal-$removal" "$SEC_EXPECTED"
    fi
done

# pam_unix runs its helper; a lower-tier helper executable cannot be added.
sec_a3_case vapt-a3-pam-unix-helper
sec_a3_incoming usr/bin/unix_chkpwd "$(sec_a3_text helper 'inert fixture helper, never executed')"
sec_a3_verdict pam-unix-helper 2

# Literal RUNPATH /usr/lib/sudo with a base-proven dependency reached through
# a symlink hop is legitimate; a lower-tier later candidate for the same
# NEEDED name is still a guarded candidate.
for candidate in control later; do
    sec_a3_case "vapt-a3-sudo-runpath-$candidate"
    vapt_elf "$ROOT/usr/bin/sudo" type=2 interp=/usr/lib64/ld-linux-x86-64.so.2 \
        needed=libsudo_util.so.0,libc.so.6 runpath=/usr/lib/sudo
    vapt_elf "$SANDBOX/sudo-util" soname=libsudo_util.so.0 needed=libc.so.6
    sec_a1_base_library usr/lib/sudo/libsudo_util.so.0.0.0 "$SANDBOX/sudo-util"
    sec_a1_base_library usr/lib/sudo/libsudo_util.so.0 link:libsudo_util.so.0.0.0
    if [[ $candidate == control ]]; then
        sec_a3_incoming usr/share/vapt-runtime/new.txt "$(sec_a3_text runpath 'unrelated inert data')"
        sec_a3_verdict "sudo-runpath-$candidate" 0
    else
        sec_a3_incoming usr/lib/libsudo_util.so.0 "$SANDBOX/sudo-util"
        sec_a3_verdict "sudo-runpath-$candidate" 2
    fi
done

# The root-side producer reads sudoers: the same incoming lower-tier object is
# inert until a group_plugin record selects it.
for plugin in none selected; do
    sec_a3_case "vapt-a3-sudoers-group-plugin-$plugin"
    SEC_SUDOERS='root ALL=(ALL:ALL) ALL'
    [[ $plugin == none ]] || SEC_SUDOERS=$'Defaults group_plugin="/usr/lib/vapt/group_vapt.so /etc/group"\n'"$SEC_SUDOERS"
    sec_a3_pam etc/sudoers "$SEC_SUDOERS"
    chmod 0440 "$ROOT/etc/sudoers"
    vapt_elf "$SANDBOX/group-plugin" soname=group_vapt.so needed=libc.so.6
    sec_a3_incoming usr/lib/vapt/group_vapt.so "$SANDBOX/group-plugin"
    SEC_EXPECTED=0
    [[ $plugin == none ]] || SEC_EXPECTED=2
    sec_a3_verdict "sudoers-group-plugin-$plugin" "$SEC_EXPECTED"
done

# The producer's facts are consumed, not just a refusal switch: a retained,
# base-proven selected group_plugin beside an unrelated change is legitimate.
# Without real root-produced facts reaching the audit, this and the `none`
# control above cannot pass.
sec_a3_case vapt-a3-sudoers-group-plugin-selected-unchanged
sec_a3_pam etc/sudoers $'Defaults group_plugin="/usr/lib/vapt/group_vapt.so /etc/group"\nroot ALL=(ALL:ALL) ALL'
chmod 0440 "$ROOT/etc/sudoers"
vapt_elf "$SANDBOX/group-plugin" soname=group_vapt.so needed=libc.so.6
sec_a1_base_library usr/lib/vapt/group_vapt.so "$SANDBOX/group-plugin"
sec_a3_incoming usr/share/vapt-runtime/new.txt "$(sec_a3_text unchanged 'unrelated inert data')"
sec_a3_verdict sudoers-group-plugin-selected-unchanged 0

# sudoers includes: a literal include is followed. Quoted and backslash-escaped
# include paths either resolve to the same included file or refuse; they must
# never silently drop the group_plugin record inside it.
for include in literal-unselected literal-selected quoted escaped; do
    sec_a3_case "vapt-a3-sudoers-include-$include"
    SEC_INCLUDED=/etc/vapt-sudoers
    SEC_INCLUDED_TEXT='Defaults group_plugin="/usr/lib/vapt/group_vapt.so /etc/group"'
    case "$include" in
    literal-unselected) SEC_DIRECTIVE='@include /etc/vapt-sudoers' SEC_INCLUDED_TEXT='Defaults env_reset' ;;
    literal-selected) SEC_DIRECTIVE='@include /etc/vapt-sudoers' ;;
    quoted) SEC_DIRECTIVE='@include "/etc/vapt-sudoers"' ;;
    escaped) SEC_INCLUDED='/etc/vapt sudoers' SEC_DIRECTIVE='@include /etc/vapt\ sudoers' ;;
    esac
    sec_a3_pam etc/sudoers "$SEC_DIRECTIVE"$'\nroot ALL=(ALL:ALL) ALL'
    sec_a3_pam "${SEC_INCLUDED#/}" "$SEC_INCLUDED_TEXT"
    chmod 0440 "$ROOT/etc/sudoers" "$ROOT$SEC_INCLUDED"
    vapt_elf "$SANDBOX/group-plugin" soname=group_vapt.so needed=libc.so.6
    sec_a3_incoming usr/lib/vapt/group_vapt.so "$SANDBOX/group-plugin"
    SEC_EXPECTED=2
    [[ $include != literal-unselected ]] || SEC_EXPECTED=0
    sec_a3_verdict "sudoers-include-$include" "$SEC_EXPECTED"
done

# sudoers plugin backend arguments name the policy source the plugin loads.
# The same lower-tier file is inert without the argument; with it, it is
# either guarded or a manual refusal, never ignored.
for argument in none sudoers_file ldap_conf; do
    sec_a3_case "vapt-a3-sudo-plugin-argument-$argument"
    SEC_PLUGIN='Plugin sudoers_policy sudoers.so'
    [[ $argument == none ]] || SEC_PLUGIN+=" $argument=/etc/vapt/sudo-backend"
    sec_a3_pam etc/sudo.conf "$SEC_PLUGIN"
    sec_a3_incoming etc/vapt/sudo-backend "$(sec_a3_text backend 'root ALL=(ALL:ALL) ALL')"
    SEC_EXPECTED=2
    [[ $argument != none ]] || SEC_EXPECTED=0
    sec_a3_verdict "sudo-plugin-argument-$argument" "$SEC_EXPECTED"
done

# A nondefault sudoers pam_service/pam_login_service selects another stack.
# An ordinary Defaults line leaves that stack unreachable and its changed
# module inert.
for setting in env_reset pam_service pam_login_service; do
    sec_a3_case "vapt-a3-sudoers-$setting"
    SEC_DEFAULTS="Defaults $setting=vapt-auth"
    [[ $setting != env_reset ]] || SEC_DEFAULTS='Defaults env_reset'
    sec_a3_pam etc/sudoers "$SEC_DEFAULTS"$'\nroot ALL=(ALL:ALL) ALL'
    chmod 0440 "$ROOT/etc/sudoers"
    sec_a3_pam etc/pam.d/vapt-auth $'auth optional /usr/lib/vapt/pam_x.so\nauth include system-auth'
    vapt_elf "$SANDBOX/pam-x" soname=pam_x.so needed=libc.so.6
    sec_a3_incoming usr/lib/vapt/pam_x.so "$SANDBOX/pam-x"
    SEC_EXPECTED=2
    [[ $setting != env_reset ]] || SEC_EXPECTED=0
    sec_a3_verdict "sudoers-$setting" "$SEC_EXPECTED"
done

# A nondefault sudo.conf plugin_dir moves where the default sudoers.so is
# loaded from; the same lower-tier object elsewhere is unrelated.
for plugin_dir in absent nondefault; do
    sec_a3_case "vapt-a3-sudo-plugin-dir-$plugin_dir"
    [[ $plugin_dir == absent ]] || sec_a3_pam etc/sudo.conf 'Path plugin_dir /usr/lib/vapt-sudo'
    vapt_elf "$SANDBOX/sudoers-plugin" soname=sudoers.so needed=libc.so.6
    sec_a3_incoming usr/lib/vapt-sudo/sudoers.so "$SANDBOX/sudoers-plugin"
    SEC_EXPECTED=2
    [[ $plugin_dir != absent ]] || SEC_EXPECTED=0
    sec_a3_verdict "sudo-plugin-dir-$plugin_dir" "$SEC_EXPECTED"
done

# A base-proven PAM module's NEEDED library is in the guarded closure: an
# incoming lower-tier library under an innocent filename that ldconfig would
# index as the same SONAME is a candidate; a distinct SONAME is not.
for alias in unrelated colliding; do
    sec_a3_case "vapt-a3-pam-dependency-alias-$alias"
    vapt_elf "$SANDBOX/pam-dependency" soname=libvaptpam.so.1 needed=libc.so.6
    sec_a1_base_library usr/lib/libvaptpam.so.1 "$SANDBOX/pam-dependency"
    vapt_elf "$SANDBOX/pam-module" soname=pam_vaptdep.so needed=libvaptpam.so.1,libc.so.6
    sec_a1_base_library usr/lib/security/pam_vaptdep.so "$SANDBOX/pam-module"
    sec_a3_pam etc/pam.d/system-auth $'auth optional pam_vaptdep.so\nauth required pam_unix.so\naccount required pam_unix.so\nsession required pam_unix.so'
    SEC_SONAME=libvaptinnocent.so.1
    [[ $alias == unrelated ]] || SEC_SONAME=libvaptpam.so.1
    vapt_elf "$SANDBOX/alias-library" "soname=$SEC_SONAME" needed=libc.so.6
    sec_a3_incoming usr/lib/libvaptinnocent.so.1 "$SANDBOX/alias-library"
    SEC_EXPECTED=2
    [[ $alias == colliding ]] || SEC_EXPECTED=0
    sec_a3_verdict "pam-dependency-alias-$alias" "$SEC_EXPECTED"
done

# --sudo-plugins FILE records are root-produced facts, supplied explicitly
# whenever the sudo graph is active. Under a fixture --root the caller may own
# the record, but it and every ancestor must be a real, singly-linked, non
# group/other-writable path holding absolute literal records.
sec_a3_selector_case() {
    sec_case "$1"
    mkdir -p "$ROOT/etc/pam.d"
    sec_a3_pam etc/pam.d/sudo $'auth include system-auth\naccount include system-auth\nsession include system-auth'
    sec_a3_pam etc/pam.d/system-auth $'auth required pam_unix.so\naccount required pam_unix.so\nsession required pam_unix.so'
    vapt_elf "$ROOT/usr/bin/sudo" type=2 interp=/usr/lib64/ld-linux-x86-64.so.2 needed=libc.so.6
    SEC_SELECTORS_DIR="$(cd "$SANDBOX" && pwd -P)/sudo-selectors"
    SEC_SELECTORS="$SEC_SELECTORS_DIR/sudo-plugins"
    mkdir -p "$SEC_SELECTORS_DIR"
    chmod 0755 "$SEC_SELECTORS_DIR"
    printf '%s\n' "${2-/usr/lib/vapt/group_vapt.so}" >"$SEC_SELECTORS"
    chmod 0644 "$SEC_SELECTORS"
}
# A lower-tier archive carrying the selectable object, planned from chaotic-aur.
sec_a3_selected_archive() {
    printf 'old inert runtime inventory data\n' >"$SANDBOX/runtime-old"
    sec_a1_lower_owner vapt-runtime usr/share/vapt-runtime/old.txt "$SANDBOX/runtime-old"
    vapt_elf "$SANDBOX/group-plugin" soname=group_vapt.so needed=libc.so.6
    sec_archive vapt-runtime 2-1
    sec_a1_member "$SEC_ARCHIVE" vapt-runtime 2-1 usr/lib/vapt/group_vapt.so "$SANDBOX/group-plugin" incoming
    sec_plan chaotic-aur vapt-runtime 2-1
}

sec_a3_selector_case vapt-a3-selectors-control
sec_archive nmap 7.99-1
sec_review 'A3 safe caller-owned selector record under a fixture root (control)' 0 "$SEC_ARCHIVE" --sudo-plugins "$SEC_SELECTORS"

sec_a3_selector_case vapt-a3-selectors-selected-change
sec_a3_selected_archive
sec_review 'A3 selector record makes the lower-tier group_plugin object guarded' 1 "$SEC_ARCHIVE" --sudo-plugins "$SEC_SELECTORS"

sec_a3_selector_case vapt-a3-selectors-empty-change ''
: >"$SEC_SELECTORS"
sec_a3_selected_archive
sec_review 'A3 empty selector record leaves the same unselected object inert' 0 "$SEC_ARCHIVE" --sudo-plugins "$SEC_SELECTORS"

for unsafe in group-writable symlink-file symlink-ancestor hardlink absent relative-record dotdot-record; do
    sec_a3_selector_case "vapt-a3-selectors-$unsafe"
    SEC_SELECTOR_ARG="$SEC_SELECTORS"
    case "$unsafe" in
    group-writable) chmod 0664 "$SEC_SELECTORS" ;;
    symlink-file)
        mv "$SEC_SELECTORS" "$SEC_SELECTORS.real"
        ln -s sudo-plugins.real "$SEC_SELECTORS"
        ;;
    symlink-ancestor)
        mv "$SEC_SELECTORS_DIR" "$SEC_SELECTORS_DIR.real"
        ln -s sudo-selectors.real "$SEC_SELECTORS_DIR"
        ;;
    hardlink) ln "$SEC_SELECTORS" "$SEC_SELECTORS_DIR/second-name" ;;
    absent) rm "$SEC_SELECTORS" ;;
    relative-record) printf 'group_vapt.so\n' >"$SEC_SELECTORS" ;;
    dotdot-record) printf '/usr/lib/vapt/../vapt/group_vapt.so\n' >"$SEC_SELECTORS" ;;
    esac
    sec_archive nmap 7.99-1
    sec_review "A3 unsafe selector record ($unsafe) fails closed" 1 "$SEC_ARCHIVE" --sudo-plugins "$SEC_SELECTOR_ARG"
done

# Production (empty root) accepts only uid-0 records and ancestry. The same
# safe caller-owned record a fixture root accepts is refused there. This reads
# metadata of the scratch file's ancestors only; it never audits a host
# package. Positive uid-0 acceptance needs real root and is not claimed.
if (($(id -u) != 0)); then
    sec_a3_selector_case vapt-a3-selectors-production-ownership
    capture python3 - "$VAPT_META" "$SEC_SELECTORS" "$ROOT" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location('vapt_metadata', sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
for label, root in (('fixture', sys.argv[3]), ('production', '')):
    try:
        module.read_sudo_plugins(sys.argv[2], root)
        print(label, 'accepted')
    except ValueError:
        print(label, 'refused')
PY
    assert_status 'A3 selector record ownership probe completes' 0 "$STATUS"
    assert_eq 'A3 caller-owned record: fixture root accepts, production refuses' \
        $'fixture accepted\nproduction refused' "$OUTPUT"
    assert_eq 'A3 ownership probe executes no fixture command' '' "$(find "$CALLS" -type f -printf '%f\n')"
fi
