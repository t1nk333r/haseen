# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# Public environment/layer APIs, real isolated files and fake managers only.
source "$FIXTURES/vapt-lib.sh"
COAE_PINS=(torch==2.14.1 transformers==5.18.0 modelscan==0.8.8 textattack==0.3.11)
WHOIS='extra|whois|5.6.4-1|https://github.com/rfc1036/whois'
env_case() {
    vapt_sandbox "$1"
    vapt_root
    vapt_home_in_root
    vapt_repos "${VAPT_BASE[@]}" "$VAPT_BA_KEYRING" "$WHOIS"
    LINK="$ROOT$VAPT_LINK" STATE="$ROOT$VAPT_STATE" TEST_HOME="$ROOT$HOME"
    COAE_DEST="$XDG_DATA_HOME/htb-coae" COAE="$ROOT$XDG_DATA_HOME/htb-coae"
    SESSION_DEST="$XDG_CONFIG_HOME/uwsm/env.d/70-haseen-vapt"
    SESSION="$ROOT$SESSION_DEST"
}
report() { cat "$STATE/report.tsv" 2>/dev/null || true; }
link_state() {
    if [[ -L $LINK ]]; then printf 'link %s\n' "$(readlink "$LINK")"
    elif [[ -f $LINK ]]; then printf 'file %s\n' "$(cat "$LINK")"
    else echo absent; fi
}
tree_of() { find "$1" -printf '%P %y %m %s %T@ %l\n' 2>/dev/null | LC_ALL=C sort; }
coae_env() {
    local dir="$1" py="$2" pin site
    shift 2
    site="$dir/lib/python3.12/site-packages"
    mkdir -p "$dir/bin" "$site"
    for pin in "$@"; do
        mkdir -p "$site/${pin%%==*}-${pin#*==}.dist-info"
        printf 'Name: %s\nVersion: %s\n' "${pin%%==*}" "${pin#*==}" >"$site/${pin%%==*}-${pin#*==}.dist-info/METADATA"
    done
    python3 "$VAPT_FIXTURE_DRIVER" runtime managed "$dir" "$py"
}
coae_own() { mkdir -p "$STATE"; printf 'v1\tcreated\t%s\n' "${1:-$COAE_DEST}" >"$STATE/coae.tsv"; }
env_install() { vapt_api install --groups "${1:-osint}"; }

# Creation/reapply/removal: no runtime execution; only unchanged owned links go.
env_case vapt-env-lifecycle
printf '# my bashrc\n' >"$TEST_HOME/.bashrc"
rc_before="$(cat "$TEST_HOME/.bashrc")"
env_install
assert_status 'missing binary sources are skips, not mutation failures' 0 "$STATUS"
assert_eq 'shell activation target' "$VAPT_FRAGMENT" "$(readlink "$LINK")"
assert_eq 'the user rc is never edited' "$rc_before" "$(cat "$TEST_HOME/.bashrc")"
assert_contains 'the missing activation is reported with the exact line' "$OUTPUT" \
    "add this line yourself: [ -r \"$VAPT_LINK\" ] && . \"$VAPT_LINK\""
assert_eq 'no zshrc invented' no "$([[ -e $TEST_HOME/.zshrc ]] && echo yes || echo no)"
assert_eq 'no uwsm directory invented' no "$([[ -e ${SESSION%/*} ]] && echo yes || echo no)"
assert_eq 'no COAE workspace invented for osint' no "$([[ -e $COAE ]] && echo yes || echo no)"
assert_contains 'environment report contract (a missing rc line does not degrade)' "$(report)" $'# environment\tok'
assert_eq 'transaction failure is reported per item' skipped "$(vapt_field whois 6)"
vapt_api status
assert_contains 'status names the line to add' "$OUTPUT" "haseen never edits rc files); to activate it, add: [ -r \"$VAPT_LINK\" ]"
env_install
assert_eq 'reapply still leaves the rc alone' "$rc_before" "$(cat "$TEST_HOME/.bashrc")"
coae_env "$COAE" 3.12.7 "${COAE_PINS[@]}"
mkdir -p "$ROOT$XDG_DATA_HOME/haseen/vapt/pipx/venvs/kept"
vapt_cli remove --dry-run --yes
assert_status 'CLI removal dry-run' 0 "$STATUS"
assert_dry_pure 'CLI removal' "$OUTPUT"
assert_eq 'dry removal leaves link' "$VAPT_FRAGMENT" "$(readlink "$LINK")"
vapt_api remove
assert_status 'removal' 0 "$STATUS"
assert_eq 'owned link removed' absent "$(link_state)"
assert_eq 'rc retained' "$rc_before" "$(cat "$TEST_HOME/.bashrc")"
assert_eq 'COAE retained' yes "$([[ -f $COAE/pyvenv.cfg ]] && echo yes || echo no)"
assert_eq 'native store retained' yes "$([[ -d $ROOT$XDG_DATA_HOME/haseen/vapt/pipx/venvs/kept ]] && echo yes || echo no)"
vapt_api status
assert_status 'removed state is missing, not healthy or degraded' 1 "$STATUS"
env_install
assert_eq 'reapply restores activation' "$VAPT_FRAGMENT" "$(readlink "$LINK")"
vapt_tools_untouched lifecycle

# Borrowed/foreign/dangling/modified links are not owned by matching content.
for kind in borrowed file foreign dangling; do
    env_case "vapt-env-$kind"
    mkdir -p "${LINK%/*}"
    case "$kind" in
    borrowed) ln -s "$VAPT_FRAGMENT" "$LINK" ;;
    file) printf 'export MINE=1\n' >"$LINK" ;;
    foreign) printf 'mine\n' >"$SANDBOX/mine"; ln -s "$SANDBOX/mine" "$LINK" ;;
    dangling) ln -s "$SANDBOX/gone" "$LINK" ;;
    esac
    before="$(link_state)"
    env_install
    assert_status "$kind apply" 0 "$STATUS"
    assert_eq "$kind preserved by apply" "$before" "$(link_state)"
    if [[ $kind != borrowed ]]; then
        assert_contains "$kind recorded degraded" "$(report)" $'# environment\tdegraded'
        vapt_api env-status
        assert_status "$kind status" 2 "$STATUS"
    fi
    vapt_api remove
    assert_eq "$kind preserved by remove" "$before" "$(link_state)"
done
env_case vapt-env-modified
env_install
rm "$LINK"
printf 'mine\n' >"$LINK"
vapt_api remove
assert_eq 'modified owned link preserved' 'file mine' "$(link_state)"

env_case vapt-env-retarget
old="$SANDBOX/old/share/haseen/default/vapt/shell.sh"
mkdir -p "${old%/*}" "${LINK%/*}" "$STATE"
cp "$VAPT_FRAGMENT" "$old"
ln -s "$old" "$LINK"
printf 'v1\tcreated\t%s\t%s\n' "$VAPT_LINK" "$old" >"$STATE/links.tsv"
env_install
assert_eq 'owned old-tree link retargeted' "$VAPT_FRAGMENT" "$(readlink "$LINK")"
vapt_api remove
assert_eq 'retargeted link removable' absent "$(link_state)"

# Reports/journals and every ancestor must be safe, on both apply and remove.
for journal in report.tsv links.tsv coae.tsv; do
    env_case "vapt-env-journal-$journal"
    mkdir -p "$STATE"
    printf 'private user content\n' >"$SANDBOX/victim"
    ln -s "$SANDBOX/victim" "$STATE/$journal"
    env_install htb-coae
    if [[ $journal == report.tsv ]]; then
        assert_status 'report conflict refuses mutation' 1 "$STATUS"
        assert_eq 'report conflict runs no manager' '' "$(ls -A "$CALLS")"
    else
        assert_status "$journal preserved conflict is a skip" 0 "$STATUS"
        assert_contains "$journal degraded" "$(report)" $'# environment\tdegraded'
    fi
    assert_eq "$journal target not truncated" 'private user content' "$(cat "$SANDBOX/victim")"
    assert_eq "$journal remains symlink" yes "$([[ -L $STATE/$journal ]] && echo yes || echo no)"
    vapt_tools_untouched "$journal"
done
for ancestor in state config data; do
    env_case "vapt-env-parent-$ancestor"
    mkdir -p "$ROOT/redirected"
    case "$ancestor" in
    state) parent="$ROOT$XDG_STATE_HOME/haseen" ;;
    config) parent="$ROOT$XDG_CONFIG_HOME/haseen" ;;
    data) parent="$ROOT$XDG_DATA_HOME" ;;
    esac
    mkdir -p "${parent%/*}"
    ln -s /redirected "$parent"
    vapt_api env-apply htb-coae
    assert_eq "$ancestor symlink target untouched" '' "$(ls -A "$ROOT/redirected")"
    assert_eq "$ancestor creates no COAE" no "$([[ -e $COAE/pyvenv.cfg ]] && echo yes || echo no)"
done
env_case vapt-env-remove-parent
env_install
journal_before="$(cat "$STATE/links.tsv")"
mv "${LINK%/*}" "$ROOT/redirected"
ln -s /redirected "${LINK%/*}"
vapt_api env-remove
assert_eq 'remove never traverses changed parent' "$VAPT_FRAGMENT" "$(readlink "$ROOT/redirected/shell.sh")"
assert_eq 'changed parent retains authority record' "$journal_before" "$(cat "$STATE/links.tsv")"

# The layer consumer must not convert a safely preserved owned activation into
# a successful removed marker, or let status short-circuit its retained journal.
vapt_api remove
assert_status 'changed owned activation makes layer removal incomplete' 2 "$STATUS"
assert_eq 'incomplete removal never records removed state' no "$([[ -e $STATE/removed ]] && echo yes || echo no)"
assert_eq 'incomplete removal preserves reachable activation' "$VAPT_FRAGMENT" "$(readlink "$ROOT/redirected/shell.sh")"
vapt_api status
assert_status 'retained activation status is degraded, not removed' 2 "$STATUS"
assert_not_contains 'retained owned activation cannot claim removed' "$OUTPUT" 'activation removed'

# A real EEXIST from a concurrent same-target link must preserve the winner.
# The fixture creates that link just before real ln; it does not echo a return.
env_case vapt-env-concurrent-link
export VAPT_LN_RACE="$VAPT_LINK"
vapt_api env-apply osint
assert_status 'lost activation creation race is a mutation failure' 1 "$STATUS"
assert_eq 'EEXIST winner remains a matching borrowed link' "$VAPT_FRAGMENT" "$(readlink "$LINK")"
unset VAPT_LN_RACE
vapt_api remove
assert_status 'borrowed concurrent link is not an owned-removal failure' 0 "$STATUS"
assert_eq 'removal preserves concurrently supplied borrowed link' "$VAPT_FRAGMENT" "$(readlink "$LINK")"
vapt_tools_untouched 'concurrent borrowed activation'

# Real durable-write failures: before mutation, and after creating a link/env.
for nth in 1 2; do
    env_case "vapt-env-write-link-$nth"
    export VAPT_FAIL_WRITE="$nth"
    vapt_api env-apply osint
    assert_status "link durable write $nth fails" 1 "$STATUS"
    assert_eq "link durable write $nth leaves no unjournaled link" absent "$(link_state)"
done
for nth in 1 2; do
    env_case "vapt-env-write-coae-$nth"
    mkdir -p "$ROOT/usr/bin"
    _vapt_stub_log "$ROOT/usr/bin/uv" uv
    vapt_installed 'uv|0.9.0-1|https://github.com/astral-sh/uv'
    export VAPT_FAIL_WRITE="$nth" VAPT_FAKE_UV=true
    vapt_api env-apply htb-coae
    assert_status "COAE durable write $nth fails" 1 "$STATUS"
    if [[ $nth == 1 ]]; then
        assert_eq 'no uv before pending journal durable' '' "$(vapt_calls uv)"
        assert_eq 'no environment before pending journal durable' no "$([[ -e $COAE ]] && echo yes || echo no)"
    else
        assert_contains 'post-creation failure retains pending evidence' "$(cat "$STATE/coae.tsv")" $'v1\tpending\t'
        assert_eq 'post-creation env retained for recovery' yes "$([[ -f $COAE/pyvenv.cfg ]] && echo yes || echo no)"
    fi
done

# Ownership, pin/version ambiguity and interpreter availability are metadata-only.
for kind in unmanaged-exact unmanaged-drift owned-exact owned-drift wrong-python foreign-owner ambiguous broken-python; do
    env_case "vapt-coae-$kind"
    pins=("${COAE_PINS[@]}") py=3.12.7
    case "$kind" in *drift) pins[0]=torch==2.13.0 ;; wrong-python) py=3.13.1 ;; ambiguous) pins+=(torch==2.13.0) ;; esac
    coae_env "$COAE" "$py" "${pins[@]}"
    case "$kind" in owned-*|wrong-python|ambiguous|broken-python) coae_own ;; foreign-owner) coae_own "$SANDBOX/other" ;; esac
    [[ $kind != broken-python ]] || rm "$COAE/bin/python3.12"
    before="$(tree_of "$COAE")"
    env_install htb-coae
    assert_status "$kind unavailable uv remains a skip" 0 "$STATUS"
    assert_eq "$kind metadata observation does not mutate environment" "$before" "$(tree_of "$COAE")"
    if [[ $kind == unmanaged-exact ]]; then
        vapt_api env-status
        assert_status 'unmanaged exact shared runtime is healthy without ownership' 0 "$STATUS"
        assert_eq 'observing unmanaged exact runtime does not grant ownership' no "$([[ -e $STATE/coae.tsv ]] && echo yes || echo no)"
    elif [[ $kind == owned-exact ]]; then
        assert_contains "$kind is healthy" "$(report)" $'# environment\tok'
    elif [[ $kind != foreign-owner ]]; then
        assert_contains "$kind is degraded" "$(report)" $'# environment\tdegraded'
    fi
    if [[ $kind == owned-drift ]]; then
        assert_contains 'owned drift attempts signed uv provisioning' "$(vapt_calls pacman)" 'extra/uv'
    else
        assert_eq "$kind invokes no uv reconciliation" '' "$(vapt_calls uv)"
    fi
    vapt_tools_untouched "$kind"
done

# Even usable uv cannot reconcile ambiguous/unknown distribution evidence.
# Real metadata ambiguity, not a canned manager response, is the boundary.
for kind in ambiguous unknown; do
    env_case "vapt-coae-usable-uv-$kind"
    coae_env "$COAE" 3.12.7 "${COAE_PINS[@]}"
    if [[ $kind == ambiguous ]]; then
        mkdir -p "$COAE/lib/python3.12/site-packages/torch-2.13.0.dist-info"
        printf 'Name: torch\nVersion: 2.13.0\n' >"$COAE/lib/python3.12/site-packages/torch-2.13.0.dist-info/METADATA"
    else
        rm "$COAE/lib/python3.12/site-packages/torch-2.14.1.dist-info/METADATA"
    fi
    coae_own
    vapt_installed 'uv|0.9.0-1|https://github.com/astral-sh/uv'
    mkdir -p "$ROOT/usr/bin"
    _vapt_stub_log "$ROOT/usr/bin/uv" uv
    export VAPT_FAKE_UV=true
    before="$(tree_of "$COAE")"
    journal_before="$(cat "$STATE/coae.tsv")"
    vapt_api env-apply htb-coae
    assert_status "$kind pins are preserved as unavailable, not mutation failure" 0 "$STATUS"
    assert_eq "$kind pins never reach usable uv" '' "$(vapt_calls uv)"
    assert_eq "$kind pins never reach fake uv backend" '' "$(vapt_calls uv-fake)"
    assert_eq "$kind environment remains untouched" "$before" "$(tree_of "$COAE")"
    assert_eq "$kind ownership authority remains unchanged" "$journal_before" "$(cat "$STATE/coae.tsv")"
    vapt_api env-status
    assert_status "$kind preserved metadata cannot claim healthy status" 2 "$STATUS"
    vapt_tools_untouched "$kind usable uv"
done

# An exact unmanaged shared environment is observable, not native authority.
# No allowed system Python exists until the explicit independent control.
env_case vapt-coae-unmanaged-native-authority
coae_env "$COAE" 3.12.7 "${COAE_PINS[@]}"
before="$(tree_of "$COAE")"
vapt_api env-apply htb-coae
assert_status 'exact unmanaged shared runtime can activate passively' 0 "$STATUS"
vapt_api env-status
assert_status 'exact unmanaged shared runtime is observable as healthy' 0 "$STATUS"
vapt_tools_untouched 'unmanaged observation before planning'
# The passive activation above is fixture work, not part of either dry-run.
rm -f -- "$CALLS/ln" "$CALLS/mkdir"
vapt_plan 'unmanaged COAE cannot authorize PyRIT' --groups htb-coae
assert_eq 'unmanaged shared interpreter does not satisfy native PyRIT' skipped "$(vapt_field pyrit 6)"
assert_eq 'PyRIT without independent system proof has no manager plan' '' "$(vapt_pipx_lines | grep -F pyrit== || true)"
vapt_system_python
vapt_plan 'independently proven system Python for unmanaged COAE' --groups htb-coae
pyrit_plan="$(vapt_pipx_lines | grep -F pyrit== || true)"
assert_contains 'independent system interpreter authorizes PyRIT' "$pyrit_plan" '--python /usr/bin/python '
assert_not_contains 'healthy unmanaged COAE still cannot supply PyRIT interpreter' "$pyrit_plan" "$COAE_DEST/bin/python"
assert_eq 'shared unmanaged environment never mutated or reconciled' "$before" "$(tree_of "$COAE")"
assert_eq 'observation and planning never take shared environment ownership' no "$([[ -e $STATE/coae.tsv ]] && echo yes || echo no)"
vapt_tools_untouched 'unmanaged native authority'

# Fixture state wins over contradictory live sandbox decoys, including ownership.
env_case vapt-env-isolation
coae_env "$COAE" 3.12.7 torch==2.13.0 transformers==5.18.0 modelscan==0.8.8 textattack==0.3.11
mkdir -p "$VAPT_STATE" "${VAPT_LINK%/*}"
printf 'v1\tcreated\t%s\n' "$COAE_DEST" >"$VAPT_STATE/coae.tsv"
printf 'host conflict\n' >"$VAPT_LINK"
vapt_api install --dry-run --groups htb-coae
assert_status 'fixture plan ignores host ownership' 0 "$STATUS"
assert_not_contains 'host ownership cannot authorize reconciliation' "$OUTPUT" '/usr/bin/uv pip install'
assert_contains 'fixture link absence plans activation despite host conflict' "$OUTPUT" "ln -s -- $VAPT_FRAGMENT $VAPT_LINK"
assert_eq 'host decoy unchanged' 'host conflict' "$(cat "$VAPT_LINK")"
coae_own
vapt_api install --dry-run --groups htb-coae
assert_contains 'fixture ownership authorizes drift reconciliation' "$OUTPUT" "/usr/bin/uv pip install --python $COAE_DEST/bin/python"
assert_not_contains 'reconciliation does not recreate owned env' "$OUTPUT" '/usr/bin/uv venv'

# Optional session link shares ownership/removal rules, never invents a desktop.
env_case vapt-env-session
mkdir -p "${SESSION%/*}"
env_install
assert_eq 'existing uwsm env.d activated' "$VAPT_FRAGMENT" "$(readlink "$SESSION")"
vapt_api remove
assert_eq 'owned session link removed' no "$([[ -L $SESSION ]] && echo yes || echo no)"
env_case vapt-env-session-borrowed
mkdir -p "${SESSION%/*}"
ln -s "$VAPT_FRAGMENT" "$SESSION"
env_install
vapt_api remove
assert_eq 'borrowed session link retained' "$VAPT_FRAGMENT" "$(readlink "$SESSION")"

env_case vapt-env-shadow
store="$ROOT$XDG_DATA_HOME/haseen/vapt/pipx/bin"
mkdir -p "$store" "$ROOT$SANDBOX/stubs"
_vapt_stub_log "$store/sherlock" native-sherlock
_vapt_stub_log "$ROOT$SANDBOX/stubs/sherlock" sherlock
vapt_api env-apply osint
assert_status 'shadow conflict is preserved, not mutation failure' 0 "$STATUS"
vapt_api env-status
assert_status 'PATH shadow degrades status' 2 "$STATUS"
vapt_tools_untouched shadow

# The fragment appends actual existing bins only, has no aliases/functions,
# does not create workspaces, and never executes an installed tool/interpreter.
vapt_sandbox vapt-fragment
store="$XDG_DATA_HOME/haseen/vapt/pipx/bin"
mkdir -p "$store" "$HOME/.local/bin" "$XDG_DATA_HOME/uv/bin"
capture env -i HOME="$HOME" PATH=/usr/bin:/bin /bin/sh -c '
    before=$(alias); . "$0"; first=$PATH; . "$0"
    [ "$first" = "$PATH" ] || exit 3
    [ "$before" = "$(alias)" ] || exit 4
    printf "%s\n" "$PATH"
' "$VAPT_FRAGMENT"
assert_status 'fragment is idempotent and introduces no aliases' 0 "$STATUS"
assert_contains 'system path keeps precedence' "$OUTPUT" '/usr/bin:/bin:'
assert_contains 'owned bin exposed' "$OUTPUT" "$store"
assert_not_contains 'COAE interpreter never exposed on PATH' "$OUTPUT" htb-coae
mkdir -p "$SANDBOX/custom-uv"
capture env -i HOME="$HOME" PATH=/usr/bin:/bin UV_TOOL_BIN_DIR="$SANDBOX/custom-uv" /bin/sh -c '. "$0"; printf "%s\n" "$PATH"' "$VAPT_FRAGMENT"
assert_contains 'explicit user uv bin honored' "$OUTPUT" "$SANDBOX/custom-uv"
assert_not_contains 'explicit user uv bin replaces default' "$OUTPUT" "$XDG_DATA_HOME/uv/bin"
vapt_tools_untouched fragment

# Activation is read-only: an rc (even a symlinked one) that already sources
# the link, or the optional shell-rc layer's init.sh, counts; otherwise the
# exact line is reported. No rc is ever written or invented.
for included in yes init no; do
    env_case "vapt-env-rc-link-$included"
    printf '# managed elsewhere\n' >"$ROOT/managed.rc"
    case "$included" in
    yes) printf '[ -r "%s" ] && . "%s"\n' "$VAPT_LINK" "$VAPT_LINK" >>"$ROOT/managed.rc" ;;
    init) printf '. "%s"\n' "$VAPT_INCLUDE" >>"$ROOT/managed.rc" ;;
    esac
    ln -s /managed.rc "$TEST_HOME/.bashrc"
    before="$(cat "$ROOT/managed.rc")"
    env_install
    assert_status "$included rc include apply" 0 "$STATUS"
    assert_eq "$included symlinked rc unchanged" "$before" "$(cat "$ROOT/managed.rc")"
    assert_eq "$included rc still a link" /managed.rc "$(readlink "$TEST_HOME/.bashrc")"
    assert_contains "$included rc include environment state" "$(report)" $'# environment\tok'
    if [[ $included == no ]]; then
        assert_contains 'an unincluded rc gets the line reported' "$OUTPUT" 'add this line yourself'
    else
        assert_not_contains "$included: an existing include is reused, nothing reported" "$OUTPUT" 'add this line yourself'
    fi
done
env_case vapt-env-existing-zsh
printf '# zsh mine\n' >"$TEST_HOME/.zshrc"
env_install
env_install
assert_eq 'existing zshrc never edited' '# zsh mine' "$(cat "$TEST_HOME/.zshrc")"
assert_eq 'no bashrc invented' no "$([[ -e $TEST_HOME/.bashrc ]] && echo yes || echo no)"

env_case vapt-env-session-parent
mkdir -p "$ROOT/session-elsewhere" "$ROOT$XDG_CONFIG_HOME"
ln -s /session-elsewhere "$ROOT$XDG_CONFIG_HOME/uwsm"
vapt_api env-apply osint
assert_eq 'symlinked session parent not traversed' '' "$(ls -A "$ROOT/session-elsewhere")"
vapt_api env-status
assert_status 'optional session conflict still degraded' 2 "$STATUS"

# Report reads are isolated as well: contradictory host report cannot mask
# the healthy fixture report, nor make an unapplied fixture look provisioned.
env_case vapt-env-report-isolation
mkdir -p "${LINK%/*}" "$VAPT_STATE"
ln -s "$VAPT_FRAGMENT" "$LINK"
vapt_report_put $'# environment\tok\n# mutation-failed\t0'
printf '# mutation-failed\t1\n' >"$VAPT_STATE/report.tsv"
vapt_api status
assert_status 'status reads healthy fixture report, not degraded host decoy' 0 "$STATUS"
rm "$STATE/report.tsv"
vapt_api status
assert_status 'host report cannot turn absent fixture report into applied' 1 "$STATUS"

# A retained htb-coae row is a runtime requirement, not merely the previous
# apply's aggregate environment annotation. All other rows are exact so their
# failures cannot conceal a missing environment at the status boundary.
env_case vapt-env-cumulative-coae
infra=(
    'extra|openldap|2.6.10-1|https://www.openldap.org/'
    'extra|perl-image-exiftool|13.36-1|https://exiftool.org/'
)
# osint's plan 087 roots resolve and are installed too, so osint is complete.
osint_roots=(
    'blackarch|recon-ng|5.1.2-1|https://github.com/lanmaster53/recon-ng'
    'blackarch|theharvester|4.8.0-1|https://github.com/laramies/theHarvester'
)
vapt_repos "${VAPT_BASE[@]}" "$VAPT_BA_KEYRING" "$WHOIS" "${infra[@]}" "${osint_roots[@]}"
vapt_installed 'whois|5.6.4-1|https://github.com/rfc1036/whois' \
    'openldap|2.6.10-1|https://www.openldap.org/' \
    'perl-image-exiftool|13.36-1|https://exiftool.org/' \
    'python-pipx|1.8.0-1|https://github.com/pypa/pipx' \
    "${osint_roots[@]#blackarch|}"
store="$ROOT$XDG_DATA_HOME/haseen/vapt/pipx"
sherlock_spec="$(vapt_native_spec sherlock)"
vapt_native_env "$store" sherlock-project "$sherlock_spec" sherlock "${sherlock_spec#*==}"
pyrit_spec="$(vapt_native_spec pyrit)"
vapt_native_env "$store" pyrit "$pyrit_spec" pyrit_shell "${pyrit_spec#*==}"
env_install osint
vapt_api status
assert_status 'all non-COAE provisioning exact positive control' 0 "$STATUS"
# Seed the legitimate previous-apply result: the selected pinned tool exists
# using supported system Python, but uv could not create its shared runtime.
vapt_report_put "pyrit"$'\thtb-coae\tnative\t'"$pyrit_spec"$'\tresolved\talready-exact\texact\tblackarch,native\n# environment\tdegraded\n# mutation-failed\t0'
env_install osint
assert_status 'later group handles unavailable retained runtime as source skip' 0 "$STATUS"
assert_contains 'later apply retains prior COAE membership' "$(report)" $'pyrit\thtb-coae\t'
assert_eq 'later osint apply does not pretend missing COAE was created' no "$([[ -e $COAE ]] && echo yes || echo no)"
vapt_api status
assert_status 'cumulative status cannot erase absent required COAE runtime' 2 "$STATUS"
assert_contains 'status identifies actual absent runtime' "$OUTPUT" 'required htb-coae environment'
vapt_tools_untouched 'cumulative COAE runtime'

# A genuine uv-managed chain passes; executable outside targets and nested
# metadata decoys do not. No Python payload or installed library is imported.
for kind in external-python lib python-dir site-packages dist-info METADATA; do
    env_case "vapt-coae-followup-$kind"
    coae_env "$COAE" 3.12.7 "${COAE_PINS[@]}"
    coae_own
    vapt_api env-apply htb-coae
    vapt_api env-status
    assert_status "$kind genuine uv chain exact control" 0 "$STATUS"
    if [[ $kind == external-python ]]; then
        mkdir -p "$ROOT/other/runtime"
        _vapt_stub_log "$ROOT/other/runtime/python3.12" coae-impostor
        rm "$COAE/bin/python"
        ln -s /other/runtime/python3.12 "$COAE/bin/python"
    else
        case "$kind" in
        lib) component=lib ;;
        python-dir) component=lib/python3.12 ;;
        site-packages) component=lib/python3.12/site-packages ;;
        dist-info) component=lib/python3.12/site-packages/torch-2.14.1.dist-info ;;
        METADATA) component=lib/python3.12/site-packages/torch-2.14.1.dist-info/METADATA ;;
        esac
        decoy="$SANDBOX/host-coae-metadata"
        mv "$COAE/$component" "$decoy"
        ln -s "$decoy" "$COAE/$component"
        decoy_before="$(tree_of "$decoy")"
    fi
    vapt_api env-status
    assert_status "$kind cannot supply healthy COAE runtime" 2 "$STATUS"
    if [[ $kind != external-python ]]; then
        assert_eq "$kind host metadata stays untouched" "$decoy_before" "$(tree_of "$decoy")"
    else
        # Exercise the PyRIT consumer of the owned-runtime borrowing gate.
        vapt_api install --dry-run --groups htb-coae
        assert_not_contains 'external COAE interpreter never borrowed for PyRIT' "$(vapt_pipx_lines)" "--python $COAE_DEST/bin/python"
    fi
    vapt_tools_untouched "COAE $kind"
done
