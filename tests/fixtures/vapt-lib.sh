# shellcheck shell=bash disable=SC2034  # ROOT/CALLS/VAPT_* are read by the test files
# tests/fixtures/vapt-lib.sh — shared builders for tests/test-vapt*.sh,
# sourced after tests/lib.sh.
#
# Every VAPT test is hermetic. The host is a sysroot built under $SANDBOX from
# tests/fixtures/vapt-host plus per-test repository metadata in the fixture
# protocol metadata.py reads (/var/lib/haseen/vapt/repositories.json and
# installed.json). Every package, runtime, trust and network command and
# every assessment tool or native presence probe the inventory names is a
# logging stub: an invocation leaves $CALLS/<command> behind instead of
# happening, and fails with 97.

VAPT_FX="$FIXTURES/vapt-host"
VAPT_LAYER="$HASEEN_PATH/layers/vapt"
VAPT_FRAGMENT="$HASEEN_PATH/default/vapt/shell.sh"
VAPT_META="$VAPT_LAYER/metadata.py"
VAPT_INCLUDE="$HASEEN_PATH/default/shell/init.sh"

# Repository rows (repo|name|version|url|provides|depends|install) every
# scenario starts from: the native and COAE build/runtime prerequisites.
VAPT_BASE=(
    "core|base-devel|1-2|https://archlinux.org/"
    "core|openssl|3.5.0-1|https://www.openssl.org"
    "core|libffi|3.5.1-1|https://github.com/libffi/libffi"
    "extra|python|3.14.0-1|https://www.python.org/||||usr/bin/python,usr/bin/python3.14,usr/include/python3.14/Python.h"
    "extra|python-pipx|1.8.0-1|https://github.com/pypa/pipx"
    "extra|uv|0.9.0-1|https://github.com/astral-sh/uv"
    "extra|git|2.51.0-1|https://git-scm.com/"
    "extra|rust|1:1.90.0-1|https://www.rust-lang.org/"
)
# The canary that makes an already-configured BlackArch usable.
VAPT_BA_KEYRING="blackarch|blackarch-keyring|20251001-1|https://www.blackarch.org/"

# vapt_tool_names — every inventory name and native presence probe.
vapt_tool_names() {
    sed -e 's/#.*//' -e 's/[[:space:]]//g' "$VAPT_LAYER"/packages/security/*.txt | grep -v '^$' || true
    awk -F'\t' '$1 !~ /^#/ && NF >= 6 { print $6 }' "$VAPT_LAYER/packages/security/native.tsv"
    printf 'smbserver.py\n'
}

# vapt_native_spec LOGICAL — the pinned specification native.tsv declares.
vapt_native_spec() { awk -F'\t' -v l="$1" '$2 == l { print $5 }' "$VAPT_LAYER/packages/security/native.tsv"; }

# _vapt_stub_log FILE NAME — a script that records its argv in $CALLS/NAME,
# says STUB-CALLED and fails. Never does anything else.
_vapt_stub_log() {
    cat >"$1" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >>'$CALLS/$2'
echo "STUB-CALLED: $2 \$*" >&2
exit 97
EOF
    chmod +x "$1"
}

# vapt_sandbox NAME — sandbox() with logging stubs for the standard mutators,
# trust/runtime managers and every assessment tool; sets CALLS, VAPT_LINK
# (the activation link) and VAPT_STATE (the per-user VAPT state dir).
vapt_sandbox() {
    sandbox "$1"
    CALLS="$SANDBOX/calls"
    mkdir -p "$CALLS"
    VAPT_LINK="$XDG_CONFIG_HOME/haseen/vapt/shell.sh"
    VAPT_STATE="$XDG_STATE_HOME/haseen/vapt"
    export VAPT_SANDBOX="$SANDBOX" VAPT_CALLS="$CALLS"
    export VAPT_FIXTURE_DRIVER="$FIXTURES/vapt-driver.py"
    unset VAPT_PLAN VAPT_ARCHIVES VAPT_PACMAN_FAIL VAPT_FAIL_WRITE VAPT_FAKE_UV VAPT_LN_RACE VAPT_LIVE_PLAN VAPT_FAKE_TRUST \
        VAPT_MOCK_SIGNATURES VAPT_SWAP_COMMIT VAPT_SWAP_DOWNLOAD VAPT_SUDO_PATH VAPT_COMMIT_PATH \
        VAPT_FAIL_ROOT_OP VAPT_SEALED_ANCESTOR_MODE
    local c
    # shellcheck disable=SC2046  # one name per word
    for c in "${STUBBED_CMDS[@]}" gpg gpg2 pacman-key pip pip3 pipx uv uvx npm npx cargo gem \
        $(vapt_tool_names); do
        _vapt_stub_log "$SANDBOX/stubs/$c" "$c"
    done
    # Real CLI user mutations need the same fixture-root mapping as vapt_api.
    # Keep these wrappers off the parent PATH so test setup remains physical.
    mkdir -p "$SANDBOX/cli-stubs"
    for c in mkdir ln rm mktemp; do
        printf '#!/bin/sh\nexec /usr/bin/python3 "$VAPT_FIXTURE_DRIVER" user %s "$@"\n' "$c" \
            >"$SANDBOX/cli-stubs/$c"
        chmod +x "$SANDBOX/cli-stubs/$c"
    done
    cat >"$SANDBOX/stubs/bsdtar" <<'EOF'
#!/bin/sh
exec /usr/bin/python3 "$VAPT_FIXTURE_DRIVER" bsdtar "$@"
EOF
    chmod +x "$SANDBOX/stubs/bsdtar"
}

# vapt_sudo_noop — sudo that records the privileged request and succeeds
# WITHOUT performing it (so non-dry runs reach their later steps). Never
# executes its arguments; drains stdin for tee so writers see no SIGPIPE.
vapt_sudo_noop() {
    cat >"$SANDBOX/stubs/sudo" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >>'$CALLS/sudo'
case "\$*" in
    'mktemp -d /var/cache/haseen-vapt.XXXXXXXX') printf '/var/cache/haseen-vapt.noop\n' ;;
    # The shared transaction lock is real (inside the fixture sysroot) so
    # the privileged-transaction mutex itself is exercised, not skipped.
    *'metadata.py shared-lock-prepare '*) shift 3; exec /usr/bin/python3 "\$@" ;;
esac
[ "\$1" != tee ] || cat >/dev/null
exit 0
EOF
    chmod +x "$SANDBOX/stubs/sudo"
}

# vapt_calls NAME — every recorded invocation of NAME (empty if none).
vapt_calls() { cat "$CALLS/$1" 2>/dev/null || true; }

# vapt_tools_untouched LABEL — no assessment tool, native probe, pipx/uv or
# AUR helper was invoked.
vapt_tools_untouched() {
    local name hit='' f
    # shellcheck disable=SC2046
    for name in $(vapt_tool_names) pipx pip pip3 uv uvx paru yay makepkg; do
        [[ ! -e $CALLS/$name ]] || hit+=" $name"
    done
    for f in "$CALLS"/native-* "$CALLS"/coae-*; do
        [[ ! -e $f ]] || hit+=" ${f##*/}"
    done
    assert_eq "$1: no assessment tool, runtime manager or AUR helper ran" "" "$hit"
}

# vapt_root — fresh sysroot copied from the static fixture; sets ROOT. The
# prefix is a physical path so symlink-ancestor checks see only what a test
# put there.
vapt_root() {
    ROOT="$(cd "$SANDBOX" && pwd -P)/root"
    rm -rf "$ROOT"
    mkdir -p "$ROOT/var/lib/haseen/vapt" "$ROOT/var/lib/pacman/local" "$ROOT/var/lib/pacman/sync"
    cp -R "$VAPT_FX/." "$ROOT/"
    export HASEEN_SYSROOT="$ROOT"
}

# Allowed installed Python, package interpreter link and headers are evidence
# for fresh native provisioning; all executable bytes are nonexecuted decoys.
vapt_system_python() { python3 "$VAPT_FIXTURE_DRIVER" runtime base; }

# vapt_conf_add TEXT — append sections to the fixture pacman.conf.
vapt_conf_add() { printf '\n%s\n' "$1" >>"$ROOT/etc/pacman.conf"; }

# vapt_home_in_root — real fixture directories, never symlink the fixture to
# host HOME: that would defeat the very ancestor isolation being tested.
vapt_home_in_root() {
    mkdir -p "$ROOT$HOME"
}

_vapt_json_list() { # CSV -> JSON array of strings
    local IFS=, item out=''
    for item in $1; do out+="${out:+,}\"$item\""; done
    printf '[%s]' "$out"
}
_vapt_json_record() { # name|version|url|provides|depends|install|files|reason
    local name version url provides depends install files reason
    IFS='|' read -r name version url provides depends install files reason <<<"$1"
    printf '{"name":"%s","version":"%s","url":"%s","provides":%s,"depends":%s,"install":"%s"' \
        "$name" "${version:-1.0-1}" "$url" "$(_vapt_json_list "$provides")" \
        "$(_vapt_json_list "$depends")" "$install"
    # ? deliberately represents unavailable old file metadata, not an empty list.
    [[ $files == '?' ]] || printf ',"files":%s' "$(_vapt_json_list "${files:-usr/bin/$name}")"
    [[ -z $reason ]] || printf ',"reason":"%s"' "$reason"
    printf '}'
}

# vapt_repos ROW... — the sync metadata; ROW is
# repo|name|version|url|provides,csv|depends,csv|install-script.
vapt_repos() {
    local row repo out='' r
    local -A body=()
    local order=()
    for row in "$@"; do
        repo="${row%%|*}"
        [[ -n ${body[$repo]+x} ]] || order+=("$repo")
        body[$repo]+="${body[$repo]:+,}$(_vapt_json_record "${row#*|}")"
    done
    for r in "${order[@]}"; do out+="${out:+,}\"$r\":[${body[$r]}]"; done
    printf '{%s}\n' "$out" >"$ROOT/var/lib/haseen/vapt/repositories.json"
    _vapt_digests
}

# _vapt_digests — every built archive in $SANDBOX/archives is the published
# repository artifact of its name/version: record it as that sync record's
# %SHA256SUM% (sha256sum). Archives built elsewhere are never registered.
_vapt_digests() {
    [[ -n ${ROOT:-} && ${HASEEN_SYSROOT:-} == "$ROOT" && -f $ROOT/var/lib/haseen/vapt/repositories.json
        && $ROOT == "$(cd "$SANDBOX" && pwd -P)"/* && -d $SANDBOX/archives ]] || return 0
    python3 "$VAPT_FIXTURE_DRIVER" digests "$SANDBOX/archives"
}

# vapt_installed ROW... — the local package database; ROW is
# name|version|url|provides|depends|install|files,csv (? omits old file metadata).
vapt_installed() {
    local row out=''
    for row in "$@"; do out+="${out:+,}$(_vapt_json_record "$row")"; done
    printf '[%s]\n' "$out" >"$ROOT/var/lib/haseen/vapt/installed.json"
}

# vapt_cli VERB ARGS... — the real `haseen vapt VERB` against $ROOT. stdin is
# closed, so a confirmation prompt is declined rather than answered.
vapt_cli() { capture env HASEEN_SYSROOT="$ROOT" PATH="$SANDBOX/cli-stubs:$PATH" haseen vapt "$@" </dev/null; }

# Public APIs with fixture-only wrappers; no absolute runtime manager executes.
vapt_api() {
    capture env HASEEN_SYSROOT="$ROOT" bash "$FIXTURES/vapt-runner.sh" "$@" </dev/null
}

# Deterministic package solver/download/commit, never a real manager.
vapt_transactions() {
    cat >"$SANDBOX/stubs/pacman" <<'EOF'
#!/bin/sh
exec /usr/bin/python3 "$VAPT_FIXTURE_DRIVER" pacman "$@"
EOF
    cat >"$SANDBOX/stubs/sudo" <<'EOF'
#!/bin/sh
exec /usr/bin/python3 "$VAPT_FIXTURE_DRIVER" root "$@"
EOF
    chmod +x "$SANDBOX/stubs/pacman" "$SANDBOX/stubs/sudo"
}

# vapt_plan LABEL ARGS... — `haseen vapt install --dry-run ARGS`, which must
# succeed and run nothing.
vapt_plan() {
    local label="$1"
    shift
    vapt_cli install --dry-run "$@"
    assert_status "$label: dry-run exit" 0 "$STATUS"
    assert_dry_pure "$label" "$OUTPUT"
    assert_eq "$label: dry-run invokes no stub" "" "$(ls -A "$CALLS")"
}

# vapt_row LOGICAL / vapt_field LOGICAL N — the report row (fields: 1 logical,
# 2 groups, 3 source, 4 target, 5 resolution, 6 apply state, 7 reason,
# 8 tiers) as printed by the last run. The dry-run write echo is indented, so
# only the printed report matches.
vapt_row() { awk -F'\t' -v l="$1" '$1 == l { print; exit }' <<<"$OUTPUT"; }
vapt_field() { vapt_row "$1" | awk -F'\t' -v n="$2" '{ print $n }'; }

# vapt_planned TARGET — "yes" when the plan commits TARGET's audited archives.
vapt_planned() {
    local line
    while IFS= read -r line; do
        if [[ $line == "DRYRUN: sudo "*"env "*" pacman "* && $line == *" -U "* && $line == *" <audited-archives-of:$1>" ]]; then
            echo yes
            return 0
        fi
    done <<<"$OUTPUT"
    echo no
}

# vapt_pipx_lines — the planned pipx installs.
vapt_pipx_lines() { grep -F '/usr/bin/pipx install' <<<"$OUTPUT" || true; }

# vapt_count TEXT NEEDLE — lines of TEXT containing NEEDLE.
vapt_count() { grep -cF -- "$2" <<<"$1" || true; }

# vapt_tree — every path under the sandbox with type, mode, size, mtime and
# link target; the stub call log is excluded.
vapt_tree() { find "$SANDBOX" -path "$CALLS" -prune -o -printf '%P %y %m %s %T@ %l\n' | LC_ALL=C sort; }

# vapt_report_put BODY — a v1 report in the fixture observation tree only.
# Host decoys are explicitly created by isolation cases, never synchronized.
vapt_report_put() {
    local f="$ROOT$VAPT_STATE/report.tsv"
    mkdir -p "${f%/*}"
    printf '# haseen-vapt-report-v1\nlogical\tselected_groups\tselected_source\ttarget\tresolution_state\tapply_state\treason\tattempted_tiers\n%s\n' "$1" >"$f"
}

# vapt_native_env STORE DIST SPEC PROBE VERSION [DIRECT_SPEC] — a pipx venv as
# pipx writes it (pipx_metadata.json, one dist-info, direct_url.json for VCS
# specs taken from DIRECT_SPEC, default SPEC) and the store's bin link to the
# probe. The probe itself is a logging stub: it must never run.
vapt_native_env() {
    local store="$1" dist="$2" spec="$3" probe="$4" version="$5" direct="${6:-$3}"
    local venv="$store/venvs/$2" info url commit
    info="$venv/lib/python3.14/site-packages/${dist//-/_}-$version.dist-info"
    mkdir -p "$info" "$venv/bin" "$store/bin" "$store/owned"
    printf '{"main_package": {"package": "%s", "package_or_url": "%s"}}\n' "$dist" "$spec" >"$venv/pipx_metadata.json"
    printf 'Metadata-Version: 2.1\nName: %s\nVersion: %s\n\n' "$dist" "$version" >"$info/METADATA"
    if [[ $direct == git+* ]]; then
        url="${direct#git+}"
        commit="${url##*@}"
        url="${url%@*}"
        printf '{"url": "%s", "vcs_info": {"vcs": "git", "commit_id": "%s"}}\n' "$url" "$commit" >"$info/direct_url.json"
    fi
    local logical="$dist"
    [[ $dist != sherlock-project ]] || logical=sherlock
    printf '%s\n' "$spec" >"$store/owned/$logical"
    python3 "$VAPT_FIXTURE_DRIVER" runtime system "$venv"
    _vapt_stub_log "$venv/bin/$probe" "native-$probe"
    ln -sfn "../venvs/$dist/bin/$probe" "$store/bin/$probe"
}

# Build real package bytes for the read-only archive audit, never makepkg.
vapt_package() {
    local name="$1" version="$2" dir="$SANDBOX/packages/$1" members=(.PKGINFO usr)
    mkdir -p "$dir/usr/bin" "$SANDBOX/archives"
    printf 'pkgname = %s\npkgver = %s\narch = x86_64\n' "$name" "$version" >"$dir/.PKGINFO"
    # A published artifact's .PKGINFO agrees with its signed sync record:
    # copy depends/provides/conflicts/replaces of the matching record.
    if [[ -n ${ROOT:-} && -f $ROOT/var/lib/haseen/vapt/repositories.json ]]; then
        python3 - "$ROOT/var/lib/haseen/vapt/repositories.json" "$name" "$version" >>"$dir/.PKGINFO" <<'EOF'
import json, sys
repos = json.load(open(sys.argv[1]))
record = next((p for records in repos.values() for p in records
               if p.get('name') == sys.argv[2] and p.get('version') == sys.argv[3]), {})
for field, key in (('depends', 'depend'), ('provides', 'provides'), ('conflicts', 'conflict'), ('replaces', 'replaces')):
    for value in record.get(field, []):
        print(key + ' = ' + value)
EOF
    fi
    _vapt_stub_log "$dir/usr/bin/$name" "$name"
    if [[ -n ${3:-} ]]; then
        printf '%s\n' "$3" >"$dir/.INSTALL"
        members+=(.INSTALL)
    fi
    tar -czf "$SANDBOX/archives/$name-$version-x86_64.pkg.tar.gz" -C "$dir" "${members[@]}"
    _vapt_digests
}

# vapt_stock — stock-equivalent Arch maintenance hooks/helpers, their owning
# allowed-source packages in a libalpm-shaped local DB (desc/files/mtree) and
# repository rows. Call after vapt_repos/vapt_installed: earlier installed rows
# move into the local DB. Helper and ELF bytes are inert, nonexecuted decoys.
vapt_stock() { python3 "$VAPT_FIXTURE_DRIVER" stock; }

# vapt_stock_archive NAME VERSION [CHANGED-PATH] [unregistered] — an upgrade
# archive of a stock owner with the same files, optionally one changed payload;
# prints it. By default it is the base repository's published artifact.
vapt_stock_archive() {
    mkdir -p "$SANDBOX/archives"
    python3 "$VAPT_FIXTURE_DRIVER" stock-archive "$1" "$2" "$SANDBOX/archives" "${3:-}" "${4:-register}"
}

# vapt_stock_python — opt-in base 'python' owner (extra 3.14.0-1): inert
# ET_EXEC usr/bin/python3.14 (PT_INTERP, NEEDED libc.so.6), usr/bin/python3
# link, inert stdlib ctypes/__init__.py and lib-dynload _ctypes extension
# (ET_DYN, NEEDED libc.so.6), local DB entry and base-signed host-cache
# reference. Call after vapt_stock; nothing is ever imported or executed.
vapt_stock_python() { python3 "$VAPT_FIXTURE_DRIVER" stock-python; }

# vapt_elf OUT [needed=a,b] [soname=X] [interp=P] [runpath=D] [rpath=D]
#     [dlopen=a,b] [type=N] [class=N] [machine=N] [tag=T] — inert static ELF
# metadata (read-only PT_LOAD, PT_DYNAMIC, optional PT_INTERP/FDO dlopen note;
# entry 0, no code). Defaults: type=3 (ET_DYN), class=2 (64-bit), machine=62.
vapt_elf() { python3 "$VAPT_FIXTURE_DRIVER" elf "$@"; }

# vapt_ldcache OUT SONAME=/ABS/PATH... — a glibc-ld.so.cache1.1 file
# (little endian, entries flagged x86-64 libc6, no extension directory).
vapt_ldcache() { python3 "$VAPT_FIXTURE_DRIVER" ldcache "$@"; }

# vapt_gconv_cache OUT /ABS/MODULE.so... — a gconv-modules.cache (magic
# 0x20010324, 5×u16 offsets, 6×u16 module entries; dir + name per module).
vapt_gconv_cache() { python3 "$VAPT_FIXTURE_DRIVER" gconvcache "$@"; }

# vapt_bootstrap_fixture — curl serves a fixture BlackArch DB/keyring/signature
# and signer keys; gpg replays an approved detached-signature status; root
# pacman-key and global config appends are recorded/confined by the driver.
vapt_bootstrap_fixture() {
    local kr="$SANDBOX/kr" file=blackarch-keyring-20251001-1-any.pkg.tar.zst primary signing
    primary="$(grep -m1 -E '^[A-F0-9]{40}$' "$VAPT_LAYER/files/blackarch-signers.txt")"
    signing=0123456789ABCDEF0123456789ABCDEF01234567
    mkdir -p "$kr/db/blackarch-keyring-20251001-1" "$kr/pkg/usr/share/pacman/keyrings"
    printf 'pkgname = blackarch-keyring\npkgver = 20251001-1\narch = any\n' >"$kr/pkg/.PKGINFO"
    printf 'fixture keyring\n' >"$kr/pkg/usr/share/pacman/keyrings/blackarch.gpg"
    tar -czf "$kr/keyring.pkg" -C "$kr/pkg" .PKGINFO usr
    # Like the real BlackArch DB, the record binds the artifact's digest.
    printf '%%FILENAME%%\n%s\n\n%%NAME%%\nblackarch-keyring\n\n%%VERSION%%\n20251001-1\n\n%%SHA256SUM%%\n%s\n\n' \
        "$file" "$(sha256sum "$kr/keyring.pkg" | cut -d' ' -f1)" >"$kr/db/blackarch-keyring-20251001-1/desc"
    tar -czf "$kr/blackarch.db" -C "$kr/db" blackarch-keyring-20251001-1
    printf '[GNUPG:] NEWSIG\n[GNUPG:] GOODSIG %s BlackArch signer\n[GNUPG:] VALIDSIG %s 2026-10-01 1790812800 0 4 0 22 10 00 %s\n' \
        "${primary:24}" "$signing" "$primary" >"$kr/vector"
    cat >"$SANDBOX/stubs/curl" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >>'$CALLS/curl'
out='' url=''
while [ \$# -gt 0 ]; do
    case "\$1" in
    --output) out="\$2"; shift ;;
    --proto | --proto-redir) shift ;;
    *) url="\$1" ;;
    esac
    shift
done
case "\$url" in
*keyserver*) printf 'public key\n' >"\$out" ;;
*.sig) printf 'detached signature\n' >"\$out" ;;
*.db) cp '$kr/blackarch.db' "\$out" ;;
*.pkg.tar.zst) cp '$kr/keyring.pkg' "\$out" ;;
*) exit 22 ;;
esac
EOF
    cat >"$SANDBOX/stubs/gpg" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >>'$CALLS/gpg'
status='' file='' verify=false showonly=false
while [ \$# -gt 0 ]; do
    case "\$1" in
    --status-file) status="\$2"; shift ;;
    --verify) verify=true ;;
    --import-options) [ "\$2" != show-only ] || showonly=true; shift ;;
    --homedir | --output | --export) shift ;;
    -*) ;;
    *) file="\$1" ;;
    esac
    shift
done
if \$verify; then cp '$kr/vector' "\$status"; exit 0; fi
if \$showonly; then
    fpr=\$(basename "\$file" .asc)
    printf 'pub:-:255:22:%s:1700000000:::-:::scESC::::::::0:\nfpr:::::::::%s:\n' "\$fpr" "\$fpr"
fi
exit 0
EOF
    chmod +x "$SANDBOX/stubs/curl" "$SANDBOX/stubs/gpg"
    export VAPT_FAKE_TRUST=1
}

# --- private oniomarchy source (plan 087 slice 1B) -------------------------------
# vapt_onio_arch ARCH — the fixture host architecture metadata.py reports.
vapt_onio_arch() { printf '%s\n' "$1" >"$ROOT/var/lib/haseen/vapt/fixture-architecture"; }

# vapt_onio_serve [key=value...] — publish the fixture repository the curl stub
# serves (keyring=VERSION trusted=PIN,ROT revoked=OLD variant=plain|scriptlet|
# hostile-scriptlet|extra-member|hook|symlink|missing-file exclude=NAME,...
# dbstatus/pkgstatus=pinned|rotated|wrong|expired|revoked|unknown|multiple|
# bad|none key=pinned|wrong|extra|revoked|expired pkgdigest=bad). Call after
# vapt_repos: its records join the fixture JSON production ignores.
vapt_onio_serve() { python3 "$VAPT_FIXTURE_DRIVER" onio-serve "$@"; }

# vapt_onio_seed — the approved, verified state a completed approval leaves.
vapt_onio_seed() { python3 "$VAPT_FIXTURE_DRIVER" onio-seed; }

# vapt_onio_stubs — curl serves only https://pkgs.oniomarchy.com/ artifacts of
# the fixture repository (anything else fails like an unreachable host); gpg
# lists the fixture key and replays the status recorded for exactly the
# verified bytes. Both log argv in $CALLS/<name> and their order in
# $CALLS/order. Nothing cryptographic or networked happens.
vapt_onio_stubs() {
    local onio="$SANDBOX/onio"
    cat >"$SANDBOX/stubs/curl" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >>'$CALLS/curl'
out='' url=''
while [ \$# -gt 0 ]; do
    case "\$1" in
    --output) out="\$2"; shift ;;
    --proto | --proto-redir | --max-redirs) shift ;;
    -*) ;;
    *) url="\$1" ;;
    esac
    shift
done
printf 'curl %s\n' "\$url" >>'$CALLS/order'
case "\$url" in
https://pkgs.oniomarchy.com/*) ;;
*) exit 6 ;;
esac
name="\${url##*/}"
[ -f '$onio/serve/'"\$name" ] || exit 22
cp '$onio/serve/'"\$name" "\$out"
EOF
    cat >"$SANDBOX/stubs/gpg" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >>'$CALLS/gpg'
status='' verify=false showonly=false export=false output='' last='' previous='' exported=''
while [ \$# -gt 0 ]; do
    case "\$1" in
    --status-file) status="\$2"; shift ;;
    --verify) verify=true ;;
    --import-options) [ "\$2" != show-only ] || showonly=true; shift ;;
    --output) output="\$2"; shift ;;
    --homedir) shift ;;
    --export) export=true ;;
    -*) ;;
    *) previous="\$last"; last="\$1"; ! \$export || exported="\$exported \$1" ;;
    esac
    shift
done
if \$verify; then
    sum=\$(sha256sum "\$last" | cut -d' ' -f1)
    printf 'gpg-verify %s\n' "\${last##*/}" >>'$CALLS/order'
    if [ -f '$onio/status/'"\$sum" ] && [ "\$(cat "\$previous")" = "fixture-sig \$sum" ]; then
        cp '$onio/status/'"\$sum" "\$status"
        exit 0
    fi
    printf '[GNUPG:] BADSIG 0000000000000000 fixture\n' >"\$status"
    exit 1
fi
# An exported key file names the primaries it holds (VAPT_GPG_EXPORT_DROP
# models a key the archive's key file lacks); show-only lists exactly those.
if \$showonly; then
    if read -r first <"\$last" && [ "\${first#fixture exported key}" != "\$first" ]; then
        for fpr in \${first#fixture exported key}; do
            printf 'pub:-:255:22:%s:1700000000:::-:::scESC::::::23::0:\nfpr:::::::::%s:\n' "\$fpr" "\$fpr"
        done
        exit 0
    fi
    cat '$onio/key.colons'; exit 0
fi
if [ -n "\$output" ]; then
    kept=''
    for fpr in \$exported; do [ "\$fpr" = "\${VAPT_GPG_EXPORT_DROP:-}" ] || kept="\$kept \$fpr"; done
    printf 'fixture exported key%s\n' "\$kept" >"\$output"
fi
exit 0
EOF
    chmod +x "$SANDBOX/stubs/curl" "$SANDBOX/stubs/gpg"
    export VAPT_FAKE_TRUST=1
}
