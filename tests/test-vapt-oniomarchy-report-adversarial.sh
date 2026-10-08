# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# Plan 087 adversarial: the v1 report keeps its eight columns with the private
# source, memberships are a union, attempted_tiers says only what was tried,
# and `haseen vapt status` keeps 0 complete / 1 missing / 2 degraded when the
# private source's evidence or a recorded dependency goes away. Hermetic.
# shellcheck source=tests/fixtures/vapt-lib.sh
source "$FIXTURES/vapt-lib.sh"
# shellcheck source=tests/fixtures/vapt-onio-adversarial.sh
source "$FIXTURES/vapt-onio-adversarial.sh"

if ! command -v bsdtar >/dev/null 2>&1; then
    echo "  (note: bsdtar is not installed; private-source report regressions were skipped)"
    return 0
fi

HEADER=$'# haseen-vapt-report-v1\nlogical\tselected_groups\tselected_source\ttarget\tresolution_state\tapply_state\treason\tattempted_tiers'
report_shape() { # TEXT — "ok" when every row is v1-shaped, else the first bad line
    awk -F'\t' '
        NR <= 2 { next }
        /^# / { if ($1 !~ /^# (environment|source|mutation-failed|oniomarchy|infrastructure|dependency)$/) { print "annotation: " $0; exit 1 } next }
        NF != 8 { print "columns " NF ": " $0; exit 1 }
        $5 != "resolved" && $5 != "unavailable" { print "resolution: " $0; exit 1 }
        END { print "ok" }' <<<"$1" | tail -n1
}

# --- a real opted-in run writes a v1 report --------------------------------
adv_approved vapt-adv-report-schema
: >"$SANDBOX/plan.tsv"
export VAPT_PLAN="$SANDBOX/plan.tsv" VAPT_ARCHIVES="$SANDBOX/archives" VAPT_MOCK_SIGNATURES=1
mkdir -p "$SANDBOX/archives"
printf 'original system sync DB\n' >"$ROOT/var/lib/pacman/sync/extra.db"
vapt_package can-utils 2025.01-1
vapt_onio_serve
vapt_onio_seed
printf 'oniomarchy\tcan-utils\t2025.01-1\thttps://pkgs.oniomarchy.com/x86_64/can-utils-2025.01-1-x86_64.pkg.tar.gz\n' >"$VAPT_PLAN"
vapt_api install --yes --with-oniomarchy --groups automotive,ai
unset VAPT_PLAN VAPT_ARCHIVES VAPT_MOCK_SIGNATURES
written="$(cat "$ROOT$VAPT_STATE/report.tsv")"
assert_eq 'the report starts with the v1 header' "$HEADER" "$(head -n2 <<<"$written")"
assert_eq 'every written row is v1-shaped' ok "$(report_shape "$written")"
assert_eq 'the private source annotation appears once' 1 "$(grep -c $'^# oniomarchy\t' <<<"$written")"
assert_eq 'the private annotation has three fields' 3 "$(awk -F'\t' '$1 == "# oniomarchy" { print NF }' <<<"$written")"
assert_eq 'the printed report equals the written report' "$written" "$(sed -n '/^# haseen-vapt-report-v1$/,$p' <<<"$OUTPUT" | grep -v '^    | ')"
assert_eq 'the private target keeps its published name' oniomarchy/can-utils "$(vapt_field can-utils 4)"
assert_eq 'a blocked identity records no private tier' identity-blocked "$(vapt_field metasploit-mcp 8)"
assert_eq 'a blocked identity is never resolved' unavailable "$(vapt_field metasploit-mcp 5)"
assert_contains 'an unpublished AI item records the private tier it tried' "$(vapt_field hexstrike-ai 8)" 'oniomarchy:unavailable'

# A second run without the flag keeps the schema and the union of groups.
vapt_sudo_noop
vapt_api install --yes --groups automotive,anonymity
written="$(cat "$ROOT$VAPT_STATE/report.tsv")"
assert_eq 'a second run keeps every row v1-shaped' ok "$(report_shape "$written")"
assert_eq 'a second run keeps one private annotation' 1 "$(grep -c $'^# oniomarchy\t' <<<"$written")"
assert_eq 'the second run annotation is its own (not selected)' not-selected \
    "$(awk -F'\t' '$1 == "# oniomarchy" { print $2 }' <<<"$written")"
assert_eq 'earlier rows from other groups are kept' 1 "$(grep -c $'^metasploit-mcp\t' <<<"$written")"

# --- membership union inside one opted-in plan -------------------------------
adv_approved vapt-adv-report-union
adv_publish '[{"name":"wfuzz","version":"3.1.0-1","arch":"any","url":"https://github.com/xmendez/wfuzz"}]'
vapt_plan 'wfuzz in two groups' --with-oniomarchy --groups htb-cwes,web,htb-cwes
assert_eq 'wfuzz carries both groups once each' 'htb-cwes,web' "$(vapt_field wfuzz 2)"
assert_eq 'wfuzz appears in one row' 1 "$(grep -c $'^wfuzz\t' <<<"$OUTPUT")"
assert_eq 'every planned row is v1-shaped' ok "$(report_shape "$(sed -n '/^# haseen-vapt-report-v1$/,$p' <<<"$OUTPUT" | grep -v '^    | ' | grep -v '^\[\*\]\|^DRYRUN')")"

# --- attempted_tiers says only what happened ---------------------------------
adv_approved vapt-adv-report-tiers "extra|airspy|1.0-1|https://github.com/airspy/airspyone_host" "extra|cubicsdr|0.2.7-1|https://cubicsdr.com"
vapt_onio_serve
vapt_onio_seed
vapt_plan 'tiers' --with-oniomarchy --groups sdr
assert_eq 'a satisfied pin stops at the pin' 'pin:extra/airspy' "$(vapt_field airspy 8)"
assert_not_contains 'an earlier-tier resolution never claims the private tier' "$(vapt_field cubicsdr 8)" 'oniomarchy'
assert_eq 'an earlier-tier resolution names its source' extra "$(vapt_field cubicsdr 3)"
assert_contains 'a private resolution ends with the bare private tier' "$(vapt_field supersdr 8)" ',oniomarchy'
assert_not_contains 'a private resolution carries no failure suffix' "$(vapt_field supersdr 8)" 'oniomarchy:'
assert_contains 'an unpublished item records the private tier as unavailable' "$(vapt_field gqrx 8)" 'oniomarchy:unavailable'
while read -r arch tier; do
    adv_approved "vapt-adv-report-tier-$arch"
    vapt_onio_arch "$arch"
    vapt_plan "tier on $arch" --with-oniomarchy --groups automotive
    assert_contains "tier on $arch" "$(vapt_field can-utils 8)" "oniomarchy:$tier"
done <<'EOF'
aarch64 unsupported-architecture
riscv64 unsupported-architecture
EOF

# --- status: 0 complete / 1 missing / 2 degraded -------------------------------
status_case() { # NAME — approved source; supersdr installed from it with its recorded dependency
    adv_approved "$1"
    python3 - "$ROOT/var/lib/haseen/vapt/installed.json" <<'EOF'
import json, sys
path = sys.argv[1]
records = json.load(open(path))
records += [{'name': 'supersdr', 'version': '1.0-1', 'url': 'https://github.com/ka7oei/supersdr',
             'depends': ['python-yattag'], 'files': ['usr/bin/supersdr'], 'reason': 'explicit'},
            {'name': 'python-yattag', 'version': '1.16-1', 'url': 'https://www.yattag.org',
             'files': ['usr/lib/python3/yattag.py'], 'reason': 'depend'}]
json.dump(records, open(path, 'w'))
EOF
    vapt_report_put $'supersdr\tsdr\toniomarchy\toniomarchy/supersdr\tresolved\tinstalled\tconcrete allowed repository identity\tblackarch,native,chaotic-aur,core,extra,multilib,oniomarchy\n# environment\tok\n# mutation-failed\t0\n# oniomarchy\tusable\tsigned database verified for this operation\n# dependency\tpython-yattag\toniomarchy/supersdr\tdependency'
    vapt_api env-apply sdr
}
status_case vapt-adv-report-status-control
vapt_api status
assert_status 'control: recorded private provisioning is complete' 0 "$STATUS"
assert_contains 'control: status says complete' "$OUTPUT" 'ok: recorded VAPT provisioning complete'
while IFS='|' read -r label expected; do
    status_case "vapt-adv-report-status"
    case "$label" in
    'host stanza declared') vapt_conf_add "$HOST_STANZA" ;;
    'source disabled') rm "$ROOT$SOURCES/oniomarchy.conf" ;;
    'stored keyring archive changed') printf 'x' >>"$ROOT$SOURCES/oniomarchy-keyring.pkg" ;;
    'cached database changed') printf 'x' >>"$ROOT$SOURCES/sync/oniomarchy.db" ;;
    'installed version drifted') sed -i 's/"1.0-1"/"0.9-1"/' "$ROOT/var/lib/haseen/vapt/installed.json" ;;
    'unsupported architecture') vapt_onio_arch aarch64 ;;
    'recorded dependency removed')
        python3 - "$ROOT/var/lib/haseen/vapt/installed.json" <<'EOF'
import json, sys
path = sys.argv[1]
json.dump([r for r in json.load(open(path)) if r['name'] != 'python-yattag'], open(path, 'w'))
EOF
        ;;
    'removal marker') mkdir -p "$ROOT$VAPT_STATE"; printf 'owned-activation-removed\n' >"$ROOT$VAPT_STATE/removed" ;;
    'report missing') rm "$ROOT$VAPT_STATE/report.tsv" ;;
    esac
    vapt_api status
    assert_status "status with $label" "$expected" "$STATUS"
    if [[ $expected != 0 ]]; then
        assert_not_contains "status with $label claims no completion" "$OUTPUT" 'provisioning complete'
    fi
done <<'EOF'
host stanza declared|2
source disabled|2
stored keyring archive changed|2
cached database changed|2
installed version drifted|2
unsupported architecture|2
recorded dependency removed|2
removal marker|1
report missing|1
EOF

# --- status says why: a disabled source is not drift ---------------------------
status_case vapt-adv-report-status-why
rm "$ROOT$SOURCES/oniomarchy.conf"
vapt_api status
assert_contains 'disabled source: provenance unverifiable' "$OUTPUT" 'supersdr: oniomarchy source disabled or unverified (absent:'
assert_contains 'disabled source: the package is retained' "$OUTPUT" 'installed package retained, provenance unverifiable'
assert_not_contains 'disabled source: not reported as drift' "$OUTPUT" 'drifted'
status_case vapt-adv-report-status-why
sed -i 's/"1.0-1"/"0.9-1"/' "$ROOT/var/lib/haseen/vapt/installed.json"
vapt_api status
assert_contains 'drift is reported as drift' "$OUTPUT" 'supersdr package drifted from its recorded source metadata'
status_case vapt-adv-report-status-why
python3 - "$ROOT/var/lib/haseen/vapt/installed.json" <<'EOF'
import json, sys
path = sys.argv[1]
json.dump([r for r in json.load(open(path)) if r['name'] != 'python-yattag'], open(path, 'w'))
EOF
vapt_api status
assert_contains 'a removed recorded dependency is named' "$OUTPUT" 'dependency python-yattag (installed for oniomarchy/supersdr) is no longer installed'

# --- retained private packages still prove themselves after repo-disable ------
status_case vapt-adv-report-retained-proof
rm "$ROOT$SOURCES/oniomarchy.conf"
python3 - "$ROOT/var/lib/haseen/vapt/repositories.json" <<'EOF'
import json, sys
path = sys.argv[1]
repos = json.load(open(path))
repos['extra'].append({'name': 'yattag-user', 'version': '1-1', 'url': 'https://example.org/yattag-user',
                       'depends': ['python-yattag']})
json.dump(repos, open(path, 'w'))
EOF
capture python3 "$VAPT_META" closure extra/yattag-user --root "$ROOT"
assert_status 'a retained private dependency is proven by the verified cache after disable' 0 "$STATUS"
capture python3 "$VAPT_META" closure oniomarchy/supersdr --root "$ROOT"
assert_status 'the cache never authorises a private target without opt-in' 1 "$STATUS"
printf 'x' >>"$ROOT$SOURCES/sync/oniomarchy.db"
capture python3 "$VAPT_META" closure extra/yattag-user --root "$ROOT"
assert_status 'an unverified cache proves nothing' 1 "$STATUS"

# --- a later run that cannot use the source keeps the installed row -----------
status_case vapt-adv-report-retained-row
find "$CALLS" -mindepth 1 -delete # env-apply's own stub calls, not the plan's
vapt_plan 'later run without --with-oniomarchy' --groups sdr
assert_eq 'the earlier private row is kept' oniomarchy/supersdr "$(vapt_field supersdr 4)"
assert_eq 'its apply state is kept' installed "$(vapt_field supersdr 6)"
assert_contains 'and annotated' "$(vapt_field supersdr 7)" 'source not selected this run (oniomarchy:not-selected); installed package retained'
report="$SANDBOX/merge.tsv"
printf '# haseen-vapt-report-v1\nlogical\tselected_groups\tselected_source\ttarget\tresolution_state\tapply_state\treason\tattempted_tiers\n%s\n' \
    "$(vapt_row supersdr)" >"$report"
merged="$(printf 'supersdr\tsdr\tnone\t-\tunavailable\tskipped\tno acceptable source\tcore,extra,oniomarchy:declined\n' |
    python3 "$VAPT_META" report-merge "$report")"
assert_contains 'a repeated annotation replaces the previous one' "$merged" \
    $'concrete allowed repository identity; source declined this run (oniomarchy:declined); installed package retained\t'
merged="$(printf 'supersdr\tsdr\tnone\t-\tunavailable\tskipped\tno acceptable source\tcore,extra,oniomarchy:identity-rejected\n' |
    python3 "$VAPT_META" report-merge "$report")"
assert_contains 'an earlier homonym replaces the retained row' "$merged" $'supersdr\tsdr\tnone\t-\tunavailable'
vapt_tools_untouched 'report adversarial'
