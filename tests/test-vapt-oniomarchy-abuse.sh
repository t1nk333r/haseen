# shellcheck shell=bash
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# Independent hostile-input and ordering probes. All managers/network/keys use
# existing sysroot fixtures; FIFO barriers make concurrency deterministic.
source "$FIXTURES/vapt-lib.sh"

# Status and snapshot parse the signed cache through the production libarchive
# reader. In particular, the blank checkpoint line and enormous version probes
# require a usable reader; without one, "unverified"/an absent row are correct
# fail-closed outcomes, not evidence about either hostile-input assertion.
# gpg/curl/pacman/sudo remain stubs; bsdtar and openssl are not prerequisites.
if ! command -v python3 >/dev/null 2>&1; then
    echo "  (note: python3 is not installed; private-source abuse regressions were skipped)"
    return 0
fi
if ! PYTHONPATH="$VAPT_LAYER${PYTHONPATH:+:$PYTHONPATH}" python3 -c 'import metadata; metadata.libarchive()' >/dev/null 2>&1; then
    echo "  (note: libarchive reader is unavailable; private-source abuse regressions were skipped, including checkpoint-newline and enormous-version cases)"
    return 0
fi

ABUSE_SANDBOX=''
abuse_cleanup() {
    [[ -z $ABUSE_SANDBOX ]] || rm -rf -- "$ABUSE_SANDBOX"
}
trap 'abuse_cleanup; vapt_fixture_cleanup' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
ABUSE_CONF=$'[options]\nArchitecture = auto\nDownloadUser = alpm\nSigLevel = Required DatabaseOptional\n\n[core]\nServer = https://geo.mirror.pkgbuild.com/$repo/os/$arch\n\n[extra]\nServer = https://geo.mirror.pkgbuild.com/$repo/os/$arch'
abuse_case() {
    abuse_cleanup
    ABUSE_SANDBOX="$OUT/vapt-abuse-$1"
    vapt_sandbox "vapt-abuse-$1"
    vapt_root
    printf '%s\n' "$ABUSE_CONF" >"$ROOT/etc/pacman.conf"
    vapt_repos "${VAPT_BASE[@]}"
    vapt_installed
    vapt_onio_arch x86_64
    vapt_transactions
    vapt_onio_stubs
    vapt_onio_serve
    vapt_onio_seed
    SOURCE_DIR="$ROOT/var/lib/haseen/vapt/sources"
}
abuse_meta() { python3 "$VAPT_META" "$@" --root "$ROOT"; }
abuse_json() { python3 -c 'import json,sys; r=json.loads(sys.argv[1]); assert r["schemaVersion"]==1; print(r["repositories"][0][sys.argv[2]])' "$OUTPUT" "$1"; }

# Exercise the supervisor's failure paths, not just the successful race.
# Tiny test deadlines keep a broken partner from stalling these regressions.
abuse_cleanup
ABUSE_SANDBOX="$OUT/vapt-abuse-supervisor"
vapt_sandbox vapt-abuse-supervisor
cat >"$SANDBOX/fault-runner.sh" <<'SH'
case "$VAPT_ABUSE_FAULT:$1" in
    early:repo-enable) exit 7 ;;
    no-ready:repo-enable) sleep 60; exit 0 ;;
    challenger:repo-disable) sleep 60; exit 0 ;;
esac
if [ "$1" = repo-enable ]; then
    printf 'ready\n' >"$VAPT_SANDBOX/ready"
    read -r token <"$VAPT_SANDBOX/release"
    [ "$VAPT_ABUSE_FAULT" != post-release ] || sleep 60
fi
exit 0
SH
for fault in early no-ready challenger post-release; do
    case "$fault" in
        early) reason='partner exited before readiness handshake (exit 7)' ;;
        no-ready) reason='readiness handshake timed out' ;;
        challenger) reason='challenger timed out' ;;
        post-release) reason='first timed out' ;;
    esac
    capture env VAPT_ABUSE_FAULT="$fault" python3 "$FIXTURES/vapt-abuse-race.py" \
        "$SANDBOX" "$SANDBOX/fault-runner.sh" repo-disable \
        --handshake-timeout 0.3 --process-timeout 0.3
    assert_status "$fault: supervisor fails rather than hanging" 1 "$STATUS"
    assert_contains "$fault: supervisor explains failure" "$OUTPUT" "$reason"
    assert_eq "$fault: FIFOs cleaned on failure" '' "$(find "$SANDBOX" -maxdepth 1 -type p -print)"
done

# Corrupted retained state must never acquire new trust or repair itself.
for file in oniomarchy.conf oniomarchy.authority oniomarchy.database sync/oniomarchy.db sync/oniomarchy.db.sig; do
    for damage in truncate nonutf8 extra; do
        abuse_case "state-${file//\//-}-$damage"
        python3 - "$SOURCE_DIR/$file" "$damage" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); b=p.read_bytes()
p.write_bytes(b[:len(b)//2] if sys.argv[2]=='truncate' else b'\xff\xfe' if sys.argv[2]=='nonutf8' else b+b'\nforged\taccepted\n')
PY
        vapt_api repo-status true
        assert_status "$file $damage: status remains consumable" 0 "$STATUS"
        assert_not_contains "$file $damage: not ready" "$(abuse_json state)" usable
        if [[ $file == oniomarchy.conf || $file == oniomarchy.authority ]]; then
            before="$(sha256sum "$SOURCE_DIR/$file")"
            vapt_api repo-enable --yes
            assert_status "$file $damage: refuses approval" 1 "$STATUS"
            assert_eq "$file $damage: preserves conflict" "$before" "$(sha256sum "$SOURCE_DIR/$file")"
            assert_eq "$file $damage: no trust operation" '' "$(vapt_calls commit-config)"
        fi
    done
done
abuse_case note-extra-newline
printf '\n' >>"$SOURCE_DIR/oniomarchy.database"
vapt_api repo-status true
assert_eq 'extra trailing blank line does not change checkpoint meaning' verified "$(abuse_json databaseSignatureState)"

# Redirected/hardlinked cache records and oversized authority files fail closed.
for damage in hardlink symlink writable oversized; do
    abuse_case "ancestry-$damage"
    p="$SOURCE_DIR/oniomarchy.authority"
    case "$damage" in
        hardlink) ln "$p" "$SANDBOX/alias" ;;
        symlink) mv "$p" "$SANDBOX/original"; ln -s "$SANDBOX/original" "$p" ;;
        writable) chmod 0666 "$p" ;;
        oversized) truncate -s 70000 "$p" ;;
    esac
    vapt_api repo-status true
    assert_eq "$damage: authority mismatch" mismatch "$(abuse_json keyringAuthorityState)"
    vapt_api repo-enable --yes
    assert_status "$damage: approval refuses" 1 "$STATUS"
    assert_eq "$damage: no fetch" '' "$(vapt_calls curl)"
done

# Manifest data is tested on a sandbox copy, never by altering the checkout.
abuse_case manifests
cp -R "$VAPT_LAYER/packages" "$SANDBOX/packages"
original="$(cat "$SANDBOX/packages/security/automotive.txt")"
long_name="$(printf '%0300d' 0 | tr 0 a)"
for item in '/tmp/evil' '--overwrite' 'a;touch-pwned' 'can utils' 'cán-utils' "$long_name"; do
    printf '%s\n%s\n' "$original" "$item" >"$SANDBOX/packages/security/automotive.txt"
    capture bash -c 'source "$HASEEN_PATH/lib/common.sh"; source "$HASEEN_PATH/layers/vapt/provision.sh"; vapt_reset; VAPT_DIR="$1"; vapt_manifest_validate' _ "$SANDBOX"
    case "$item" in
        'can utils') assert_status 'manifest whitespace follows existing normalization' 0 "$STATUS" ;;
        "$long_name") assert_status '300-character manifest name has no documented length limit' 0 "$STATUS" ;;
        *) assert_status "hostile manifest [$item]: rejected" 2 "$STATUS" ;;
    esac
done

# Signed publisher metadata is still hostile input. Mutate the cached tar and
# renew the fixture checkpoint; this models bytes signed by an accepted key.
abuse_db() {
    python3 - "$SOURCE_DIR" "$1" <<'PY'
import io,tarfile,hashlib,sys
from pathlib import Path
root=Path(sys.argv[1]); mode=sys.argv[2]; db=root/'sync/oniomarchy.db'
with tarfile.open(db) as t:
    entries=[(m,t.extractfile(m).read() if m.isfile() else None) for m in t]
out=io.BytesIO()
with tarfile.open(fileobj=out,mode='w:gz') as t:
    for m,b in entries:
        if b is not None and m.name.endswith('/desc') and b'%NAME%\ncan-utils\n' in b:
            if mode=='huge': b=b.replace(b'%VERSION%\n2025.01-1\n',b'%VERSION%\n'+b'9'*100000+b'-1\n')
            elif mode=='suffix': b=b.replace(b'%NAME%\ncan-utils\n',b'%NAME%\ncan-utils-evil\n')
            elif mode=='tab': b=b.replace(b'%VERSION%\n2025.01-1\n',b'%VERSION%\n1\tforged\n')
            elif mode=='escape': b=b.replace(b'%URL%\nhttps://github.com/linux-can/can-utils\n',b'%URL%\nhttps://github.com/linux-can/can-utils\x1b[2J\n')
            elif mode=='duplicate':
                duplicate=tarfile.TarInfo('duplicate/desc'); duplicate.size=len(b); t.addfile(duplicate,io.BytesIO(b))
        if b is not None: m.size=len(b)
        t.addfile(m,io.BytesIO(b) if b is not None else None)
data=out.getvalue(); db.write_bytes(data)
sig=root/'sync/oniomarchy.db.sig'
pin='0F5F9214F312B067ECBF1DF125E2C00AA6340BD0'
(root/'oniomarchy.database').write_text('haseen-vapt-oniomarchy-database-v1\ndb\t'+hashlib.sha256(data).hexdigest()+'\nsig\t'+hashlib.sha256(sig.read_bytes()).hexdigest()+'\nsigner\t'+pin+'\n')
PY
}
for mode in huge suffix tab escape duplicate; do
    abuse_case "db-$mode"
    abuse_db "$mode"
    vapt_api repo-status true
    assert_status "$mode: status JSON decodes" 0 "$STATUS"
    if [[ $mode == duplicate ]]; then
        assert_eq 'same package twice: database unusable' unverified "$(abuse_json databaseSignatureState)"
    else
        capture abuse_meta snapshot --with-oniomarchy --offline
        if [[ $mode == suffix ]]; then
            assert_not_contains '53rd name via suffix has no admission' "$OUTPUT" 'can-utils-evil'
        elif [[ $mode == tab ]]; then
            assert_not_contains 'tab in version cannot corrupt snapshot columns' "$OUTPUT" $'1\tforged'
        elif [[ $mode == escape ]]; then
            assert_not_contains 'terminal control in URL cannot reach snapshot' "$OUTPUT" $'\x1b[2J'
        else
            assert_contains 'enormous version is returned unchanged (no documented version bound)' "$OUTPUT" "$(printf '%01000d' 0 | tr 0 9)"
        fi
    fi
done

# JSON escapes hostile fields. Text/report consumers must not be injected.
abuse_case output
vapt_onio_arch $'odd\tarchitecture\nforged\x1b[2J'
vapt_cli repo-status --json
assert_status 'hostile architecture: CLI JSON succeeds' 0 "$STATUS"
assert_eq 'JSON preserves one object with fixed source id' oniomarchy "$(abuse_json name)"
assert_not_contains 'JSON stdout contains no raw terminal escape' "$OUTPUT" $'\x1b'
vapt_cli repo-status
assert_not_contains 'human status contains no terminal control' "$OUTPUT" $'\x1b'
vapt_api install --dry-run --with-oniomarchy --groups automotive
assert_not_contains 'report has no terminal control from architecture' "$OUTPUT" $'\x1b'

# Sysroot and state environment cannot drive live trust. Hostile HOME/XDG
# values stay inside this fixture; all external commands remain logging stubs.
abuse_case environment
for command in repo-enable repo-disable; do
    vapt_cli "$command" --yes oniomarchy
    assert_status "$command: live sysroot mutation refused" 2 "$STATUS"
    assert_eq "$command: no stub invoked" '' "$(vapt_calls sudo)$(vapt_calls curl)$(vapt_calls gpg)$(vapt_calls pacman)"
done
capture env HASEEN_STATE_DIR="$SANDBOX/foreign-state" bash "$FIXTURES/vapt-runner.sh" repo-enable --yes
assert_status 'root-state override: approval refused' 1 "$STATUS"
assert_eq 'root-state override: no fetch' '' "$(vapt_calls curl)"
capture env HOME="$SANDBOX/home space;hostile" XDG_STATE_HOME="$SANDBOX/state space" XDG_CONFIG_HOME="$SANDBOX/config space" XDG_DATA_HOME="$SANDBOX/data space" bash "$FIXTURES/vapt-runner.sh" repo-status true
assert_status 'hostile HOME/XDG status remains read only' 0 "$STATUS"
assert_eq 'hostile HOME/XDG preserves source id' oniomarchy "$(abuse_json name)"

# Busy commands fail immediately rather than interleave trust. Persistent lock
# files alone must not count as a held lock. FIFOs avoid timing-based sleeps.
for operation in repo-disable repo-enable; do
    abuse_case "race-$operation"
    # Gate the first fetch only, delegating later calls without a barrier.
    mv "$SANDBOX/stubs/curl" "$SANDBOX/stubs/curl.delegate"
    # The supervisor owns nonblocking FIFO opens, deadlines, process groups,
    # file-backed stdio, reaping and FIFO cleanup (also on errors/signals).
    printf '#!/bin/sh\nif [ ! -f "%s/gated" ]; then\n touch "%s/gated"\n printf "ready\\n" >"%s/ready"\n read -r token <"%s/release"\nfi\nexec "%s/stubs/curl.delegate" "$@"\n' "$SANDBOX" "$SANDBOX" "$SANDBOX" "$SANDBOX" "$SANDBOX" >"$SANDBOX/stubs/curl"
    chmod +x "$SANDBOX/stubs/curl"
    capture python3 "$FIXTURES/vapt-abuse-race.py" "$SANDBOX" "$FIXTURES/vapt-runner.sh" "$operation"
    if [[ $STATUS != 0 ]]; then
        _fail "$operation race: barrier/partner failed" "$OUTPUT"
        return 1
    fi
    OUTPUT="$(cat "$SANDBOX/challenger.out")"
    assert_status "$operation during approval: rejected under mutex" 1 "$(cat "$SANDBOX/challenger.status")"
    assert_contains "$operation during approval: truthful busy reason" "$OUTPUT" busy
    assert_status "$operation race: original completes" 0 "$(cat "$SANDBOX/first.status")"
    vapt_api repo-disable --yes
    assert_status "$operation race: leftover lock inode does not block later disable" 0 "$STATUS"
done

# The private source never joins a full upgrade: a record naming it is not
# part of the recovery protocol, and changed checkpoint bytes are not adopted.
abuse_case recovery
scope="$(printf 'stale' | sha256sum | cut -d' ' -f1)"
marker="$ROOT/var/lib/haseen/vapt/upgrade-pending"
printf 'reviewed-full-upgrade-commit-pending\toniomarchy-private\t%s\n' "$scope" >"$marker"
vapt_api recover
assert_status 'private-scope recovery record: refuses' 2 "$STATUS"
assert_eq 'private-scope recovery record: no review' '' "$(vapt_calls review-repos)"
assert_contains 'private-scope recovery record: marker preserved' "$(cat "$marker")" "$scope"
for bytes in 'reviewed-full-upgrade-commit-pending' $'reviewed-full-upgrade-commit-pending\toniomarchy-private\tbad\n' $'reviewed-full-upgrade-commit-pending\nchanged\n'; do
    printf '%s' "$bytes" >"$marker"
    vapt_api recover
    assert_status 'changed/truncated recovery checkpoint refused' 2 "$STATUS"
    assert_eq 'changed/truncated checkpoint preserved verbatim' "${bytes%$'\n'}" "$(python3 -c 'import pathlib,sys; print(pathlib.Path(sys.argv[1]).read_text(),end="")' "$marker")"
done
vapt_tools_untouched 'all abuse paths'
