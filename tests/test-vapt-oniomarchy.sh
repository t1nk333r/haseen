# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# Plan 087 slice 1B: the private oniomarchy source is opt-in per operation,
# private to VAPT's own configuration, x86_64-only, strictly signed, the last
# tier and admitted only by exact reviewed names. Every fetch, key, package
# and tool command is a logging stub (tests/fixtures/vapt-lib.sh); signed
# artifacts come from tests/fixtures/vapt-oniomarchy through the hermetic
# driver. Nothing reaches a network, a keyring or a package manager.
# shellcheck source=tests/fixtures/vapt-lib.sh
source "$FIXTURES/vapt-lib.sh"

ONIO_FX="$FIXTURES/vapt-oniomarchy"
PIN=0F5F9214F312B067ECBF1DF125E2C00AA6340BD0
CONF=$'[options]\nArchitecture = auto\nDownloadUser = alpm\nSigLevel = Required DatabaseOptional\n\n[core]\nServer = https://geo.mirror.pkgbuild.com/$repo/os/$arch\n\n[extra]\nServer = https://geo.mirror.pkgbuild.com/$repo/os/$arch'
SOURCES=/var/lib/haseen/vapt/sources

onio_case() { # NAME — an x86_64 host whose fixture repository serves the signed source
    vapt_sandbox "$1"
    vapt_root
    printf '%s\n' "$CONF" >"$ROOT/etc/pacman.conf"
    vapt_repos "${VAPT_BASE[@]}"
    vapt_onio_arch x86_64
    vapt_onio_stubs
    vapt_onio_serve
}
approved_case() { # NAME — plus an approved, verified private source
    onio_case "$1"
    vapt_onio_seed
}
annotation() { awk -F'\t' '$1 == "# oniomarchy" { print $2; exit }' <<<"$OUTPUT"; }
json_field() { python3 -c 'import json, sys; print(json.loads(sys.stdin.read())["repositories"][0][sys.argv[1]])' "$1" <<<"$OUTPUT"; }

# --- no flag: no fetch, no import, no stanza, no candidate --------------------
approved_case vapt-onio-not-selected
CONF_BEFORE="$(cat "$ROOT/etc/pacman.conf")"
vapt_plan 'not selected' --groups sdr
assert_eq 'without the flag chirp stays unavailable' unavailable "$(vapt_field chirp 5)"
assert_contains 'the source tier is recorded as not selected' "$(vapt_field chirp 8)" 'oniomarchy:not-selected'
assert_not_contains 'nothing is planned from the private source' "$OUTPUT" 'oniomarchy/'
assert_eq 'the operation records its source choice' not-selected "$(annotation)"
vapt_plan '--all is not consent' --all
assert_not_contains '--all plans nothing from the private source' "$OUTPUT" 'oniomarchy/'
assert_contains '--all leaves the tier not selected' "$(vapt_field supersdr 8)" 'oniomarchy:not-selected'
assert_eq 'planning never touches pacman.conf' "$CONF_BEFORE" "$(cat "$ROOT/etc/pacman.conf")"
vapt_cli install --dry-run --with-oniomarchy
assert_status 'the flag alone selects no tool' 2 "$STATUS"
vapt_cli install --dry-run --with-oniomarchy --with-oniomarchy --groups sdr
assert_status 'a repeated flag is refused' 2 "$STATUS"

# --- opted in, approved and verified: the last tier, exact names only --------
approved_case vapt-onio-selected
TREE_BEFORE="$(vapt_tree)"
vapt_plan 'opted-in dry-run' --with-oniomarchy --groups sdr
assert_eq 'opted-in chirp resolves from the private source' oniomarchy "$(vapt_field chirp 3)"
assert_eq 'the reviewed alias keeps the published suffix' oniomarchy/chirp-next "$(vapt_field chirp 4)"
assert_eq 'supersdr resolves by its exact name' oniomarchy/supersdr "$(vapt_field supersdr 4)"
assert_contains 'the resolved tier is recorded last' "$(vapt_field supersdr 8)" 'multilib,oniomarchy'
assert_contains 'the reason says what the source is not' "$(vapt_field supersdr 7)" 'not independent provenance'
assert_eq 'the audited private package is planned' yes "$(vapt_planned oniomarchy/supersdr)"
assert_eq 'the source state is annotated' usable "$(annotation)"
assert_contains 'dry-run says it did not re-verify' "$OUTPUT" 'not re-verified'
assert_eq 'opted-in dry-run writes nothing' "$TREE_BEFORE" "$(vapt_tree)"
assert_eq 'opted-in dry-run fetches nothing' '' "$(vapt_calls curl)$(vapt_calls gpg)$(vapt_calls pacman-key)"
assert_contains 'official pins are still tried first' "$(vapt_field airspy 8)" 'pin:extra/airspy'
vapt_tools_untouched 'opted-in dry-run'

# --- approval planned, never fabricated ---------------------------------------
onio_case vapt-onio-absent
vapt_plan 'unapproved source' --with-oniomarchy --groups sdr
assert_eq 'an unapproved source is reported absent' absent "$(annotation)"
assert_contains 'the item records the unavailable tier' "$(vapt_field chirp 8)" 'oniomarchy:unavailable'
assert_contains 'the plan names the fixed HTTPS key URL' "$OUTPUT" 'https://pkgs.oniomarchy.com/oniomarchy.gpg'
assert_contains 'the plan names the reviewed primary' "$OUTPUT" "$PIN"
assert_contains 'the plan shows the exact private stanza' "$OUTPUT" '| SigLevel = Required DatabaseRequired'
assert_contains 'the plan discloses the global keyring change' "$OUTPUT" 'shared pacman keyring'
assert_not_contains 'no keyring filename is invented' "$OUTPUT" 'oniomarchy-keyring-20260906-1'
assert_not_contains 'no verification is claimed' "$OUTPUT" 'signature verified'
assert_eq 'no private state is created' no "$([[ -e $ROOT$SOURCES ]] && echo yes || echo no)"

# --- architecture: report and skip before any trust mutation ------------------
while read -r arch expected; do
    approved_case "vapt-onio-arch-$arch"
    vapt_onio_arch "$arch"
    vapt_plan "arch $arch" --with-oniomarchy --groups automotive
    assert_eq "arch $arch state" "$expected" "$(annotation)"
    if [[ $expected != usable ]]; then
        assert_contains "arch $arch tier" "$(vapt_field can-utils 8)" 'oniomarchy:unsupported-architecture'
        vapt_sudo_noop
        vapt_api install --with-oniomarchy --groups automotive
        assert_eq "arch $arch: nothing fetched before the refusal" '' "$(vapt_calls curl)$(vapt_calls gpg)"
        assert_not_contains "arch $arch: no key import" "$(vapt_calls sudo)" 'pacman-key'
        assert_contains "arch $arch: real run reports it" "$OUTPUT" $'# oniomarchy\tunsupported-architecture'
    else
        assert_eq "arch $arch resolves" oniomarchy/can-utils "$(vapt_field can-utils 4)"
    fi
done < <(python3 -c 'import json, sys; [print(k, v) for k, v in json.load(open(sys.argv[1]))["cases"].items()]' "$ONIO_FX/architecture.json")

# --- offline canary: every recorded-evidence state, never silently repaired ---
onio_mutate() { # MUTATION — break one piece of the approved evidence
    # The keyring package is never installed; its evidence is the audited
    # archive kept in the private root state.
    local archive="$ROOT$SOURCES/oniomarchy-keyring.pkg"
    case "$1" in
    none) ;;
    remove-descriptor) rm "$ROOT$SOURCES/oniomarchy.conf" ;;
    weaken-descriptor) sed -i 's/DatabaseRequired/DatabaseOptional/' "$ROOT$SOURCES/oniomarchy.conf" ;;
    symlink-descriptor)
        mv "$ROOT$SOURCES/oniomarchy.conf" "$ROOT$SOURCES/real.conf"
        ln -s real.conf "$ROOT$SOURCES/oniomarchy.conf" ;;
    host-stanza) vapt_conf_add $'[oniomarchy]\nSigLevel = Required DatabaseRequired\nServer = https://pkgs.oniomarchy.com/$arch' ;;
    tamper-database) printf 'x' >>"$ROOT$SOURCES/sync/oniomarchy.db" ;;
    remove-signature) rm "$ROOT$SOURCES/sync/oniomarchy.db.sig" ;;
    no-keyring-record) vapt_onio_serve exclude=oniomarchy-keyring && vapt_onio_seed ;;
    tamper-keyring-file) printf 'x' >>"$archive" ;;
    symlink-keyring-file)
        cp "$archive" "$SANDBOX/elsewhere"
        rm "$archive"
        ln -s "$SANDBOX/elsewhere" "$archive" ;;
    drift-keyring-version) sed -i 's/^version\t20260906-1$/version\t20260101-1/' "$ROOT$SOURCES/oniomarchy.authority" ;;
    remove-authority) rm "$ROOT$SOURCES/oniomarchy.authority" ;;
    arch-aarch64) vapt_onio_arch aarch64 ;;
    *) return 97 ;;
    esac
}
while IFS=$'\t' read -r name mutation state; do
    approved_case vapt-onio-state
    onio_mutate "$mutation"
    descriptor_before="$(cat "$ROOT$SOURCES/oniomarchy.conf" 2>/dev/null || true)"
    conf_before="$(cat "$ROOT/etc/pacman.conf")"
    vapt_cli repo-status oniomarchy
    assert_status "$name: status inspects" 0 "$STATUS"
    assert_contains "$name: status state" "$OUTPUT" "oniomarchy: $state"
    assert_contains "$name: status never selects" "$OUTPUT" 'selected: no'
    vapt_cli repo-status --json
    assert_eq "$name: json state" "$state" "$(json_field state)"
    vapt_plan "$name" --with-oniomarchy --groups sdr
    assert_eq "$name: opted-in operation reports the same state" "$state" "$(annotation)"
    if [[ $state == usable ]]; then
        assert_eq "$name: resolves" oniomarchy/supersdr "$(vapt_field supersdr 4)"
    else
        assert_eq "$name: nothing resolves" unavailable "$(vapt_field supersdr 5)"
    fi
    assert_eq "$name: descriptor preserved" "$descriptor_before" "$(cat "$ROOT$SOURCES/oniomarchy.conf" 2>/dev/null || true)"
    assert_eq "$name: host configuration preserved" "$conf_before" "$(cat "$ROOT/etc/pacman.conf")"
done < <(python3 -c 'import json, sys; [print(c["name"], c["mutation"], c["state"], sep="\t") for c in json.load(open(sys.argv[1]))["cases"]]' "$ONIO_FX/source-states.json")

# --- resolution order, shadowing and exact admission --------------------------
while IFS=$'\t' read -r name group logical extra exclude source tiers; do
    [[ $extra != - ]] || extra=''
    [[ $exclude != - ]] || exclude=''
    approved_case vapt-onio-shadow
    if [[ -n $extra ]]; then
        IFS=';' read -r -a rows <<<"$extra"
        vapt_repos "${VAPT_BASE[@]}" "${rows[@]}"
    fi
    vapt_onio_serve ${exclude:+"exclude=$exclude"}
    vapt_onio_seed
    vapt_plan "$name" --with-oniomarchy --groups "$group"
    assert_eq "$name: source" "$source" "$(vapt_field "$logical" 3)"
    assert_contains "$name: tiers" "$(vapt_field "$logical" 8)" "$tiers"
done < <(python3 -c '
import json, sys
for c in json.load(open(sys.argv[1]))["cases"]:
    print(c["name"], c["group"], c["logical"], ";".join(c["extra"]) or "-", ",".join(c["exclude"]) or "-", c["source"], c["tiers"], sep="\t")
' "$ONIO_FX/transactions/shadowing.json")

approved_case vapt-onio-snapshot
snapshot="$(python3 "$VAPT_META" snapshot --root "$ROOT" --with-oniomarchy)"
assert_contains 'the admitted candidate is a snapshot record' "$snapshot" $'package\toniomarchy\tsupersdr\t'
assert_contains 'the keyring canary is a snapshot record' "$snapshot" $'package\toniomarchy\toniomarchy-keyring\t'
assert_not_contains 'a 53rd published name is never a record' "$snapshot" 'evil-tool'
assert_not_contains 'a wrong-architecture record is never admitted' "$snapshot" $'oniomarchy\tairgeddon'
assert_not_contains 'the private source is never offered without the flag' \
    "$(python3 "$VAPT_META" snapshot --root "$ROOT")" 'oniomarchy'
vapt_conf_add $'[oniomarchy]\nSigLevel = Never\nServer = http://pkgs.oniomarchy.com/$arch'
assert_not_contains 'a host stanza is never a VAPT repository' "$(python3 "$VAPT_META" snapshot --root "$ROOT")" 'oniomarchy'

# --- the admission table and validator ---------------------------------------
mutated_tree() {
    tree="$SANDBOX/share"
    rm -rf "$tree"
    mkdir -p "$tree/layers"
    cp -R "$HASEEN_PATH/lib" "$tree/lib"
    cp -R "$HASEEN_PATH/default" "$tree/default"
    cp -R "$VAPT_LAYER" "$tree/layers/vapt"
    TREE_VAPT="$tree/layers/vapt"
}
tree_plan() { capture env HASEEN_PATH="$tree" HASEEN_SYSROOT="$ROOT" PATH="$SANDBOX/cli-stubs:$PATH" haseen vapt install --dry-run "$@" </dev/null; }
broken_case() { # LABEL EDIT-COMMAND...
    local label="$1"
    shift
    mutated_tree
    "$@"
    tree_plan --groups core
    assert_status "$label refuses an unrelated selection" 2 "$STATUS"
    assert_not_contains "$label plans nothing" "$OUTPUT" 'DRYRUN:'
}
onio_case vapt-onio-admission
admitted="$(grep -vc '^#' "$VAPT_LAYER/packages/oniomarchy.tsv")"
assert_eq 'the admission table holds exactly the reviewed 52 names' 52 "$admitted"
assert_eq 'the table equals the reviewed inventory roles' \
    "$(python3 -c 'import json, sys; [print(k, v, sep="\t") for k, v in sorted(json.load(open(sys.argv[1]))["sourcePackages"].items())]' "$ONIO_FX/inventory.json")" \
    "$(grep -v '^#' "$VAPT_LAYER/packages/oniomarchy.tsv" | cut -f1,2 | LC_ALL=C sort)"
mutated_tree
tree_plan --groups core
assert_status 'the copied tree plans (control)' 0 "$STATUS"
broken_case 'a 53rd admitted name' sh -c 'printf "evil-tool\tcandidate\t-\n" >>"$1"' _ "$TREE_VAPT/packages/oniomarchy.tsv"
broken_case 'a missing admission table' rm "$TREE_VAPT/packages/oniomarchy.tsv"
broken_case 'a candidate mapped to a non-inventory name' sed -i 's/^peass-ng\tcandidate\t-$/peass-ng\tcandidate\tpeass/' "$TREE_VAPT/packages/oniomarchy.tsv"
broken_case 'a suffix-stripped mapping without an alias' sed -i 's/^eyewitness-git\tcandidate\t-$/eyewitness-git\tcandidate\teyewitness/' "$TREE_VAPT/packages/oniomarchy.tsv"
broken_case 'a dependency promoted to a candidate' sed -i 's/^powershell-bin\tdependency\tpowershell-bin$/powershell-bin\tcandidate\tpowershell-bin/' "$TREE_VAPT/packages/oniomarchy.tsv"
broken_case 'a second infrastructure package' sed -i 's/^libsoup\tdependency\t-$/libsoup\tinfrastructure\t-/' "$TREE_VAPT/packages/oniomarchy.tsv"
broken_case 'a candidate for a blocked identity' sh -c 'sed -i "/^evil/d" "$1"; sed -i "s/^peass-ng\tcandidate\t-$/peass-ng\tcandidate\tmetasploit-mcp/" "$1"' _ "$TREE_VAPT/packages/oniomarchy.tsv"
broken_case 'a pin on the private source' sh -c 'printf "chirp\toniomarchy/chirp-next\n" >>"$1"' _ "$TREE_VAPT/packages/pins.tsv"
broken_case 'a required target on the private source' sed -i 's#^maltego\trepository\t\*\t#maltego\trepository\toniomarchy/maltego\t#' "$TREE_VAPT/packages/identities.tsv"
broken_case 'a dependency-only package as a root' sh -c 'printf "sleuthkit-java\n" >>"$1"' _ "$TREE_VAPT/packages/security/sdr.txt"
assert_eq 'the dependency alias row is a dependency' 'java17-openjfx-bin	dependency	java17-openjfx' \
    "$(grep '^java17-openjfx-bin	' "$VAPT_LAYER/packages/oniomarchy.tsv")"

# --- mirror and policy validation (one validator for every path) -------------
mirror_cases="$(python3 - "$VAPT_LAYER" <<'EOF'
import sys
sys.path.insert(0, sys.argv[1])
import metadata as m
cases = [
    ('oniomarchy', 'https://pkgs.oniomarchy.com/$arch', True),
    ('oniomarchy', 'https://pkgs.oniomarchy.com/x86_64', True),
    ('oniomarchy', 'http://pkgs.oniomarchy.com/$arch', False),
    ('oniomarchy', 'https://pkgs.oniomarchy.com.example.net/$arch', False),
    ('oniomarchy', 'https://example.net/pkgs.oniomarchy.com/$arch', False),
    ('oniomarchy', 'https://user@pkgs.oniomarchy.com/$arch', False),
    ('oniomarchy', 'https://pkgs.oniomarchy.com:8443/$arch', False),
    ('oniomarchy', 'https://pkgs.oniomarchy.com/$arch?mirror=1', False),
    ('oniomarchy', 'https://pkgs.oniomarchy.com/$arch#x', False),
    ('oniomarchy', 'https://pkgs.oniomarchy.com/$repo/os/$arch', False),
    ('oniomarchy', 'file:///srv/oniomarchy/$arch', False),
    ('extra', 'https://pkgs.oniomarchy.com/$arch', False),
    ('extra', 'https://mirror.example.org/omarchy/$arch', False),
    ('extra', 'https://geo.mirror.pkgbuild.com/$repo/os/$arch', True),
    ('blackarch', 'http://blackarch.org/blackarch/$repo/os/$arch', False),
]
for repo, url, expected in cases:
    print('mirror', repo, url, 'ok' if m.repository_mirror_safe(repo, url) == expected else 'WRONG', sep='\t')
policies = [
    (['SigLevel = Required DatabaseRequired', 'Server = https://pkgs.oniomarchy.com/$arch'], True),
    (['SigLevel = Required DatabaseOptional', 'Server = https://pkgs.oniomarchy.com/$arch'], False),
    (['Server = https://pkgs.oniomarchy.com/$arch'], False),
    (['SigLevel = Required DatabaseRequired TrustAll', 'Server = https://pkgs.oniomarchy.com/$arch'], False),
    (['SigLevel = Required DatabaseRequired', 'SigLevel = Optional', 'Server = https://pkgs.oniomarchy.com/$arch'], False),
    (['SigLevel = Never', 'Server = https://pkgs.oniomarchy.com/$arch'], False),
    (['SigLevel = Required DatabaseRequired', 'Server = https://pkgs.oniomarchy.com/$arch', 'Include = /etc/x'], False),
    (['SigLevel = Required DatabaseRequired', 'Server = https://pkgs.oniomarchy.com/$arch', 'Usage = All'], False),
]
for lines, expected in policies:
    print('policy', ' | '.join(lines), str(expected), 'ok' if m.repository_policy_safe('oniomarchy', lines) == expected else 'WRONG', sep='\t')
print('vendor', 'oniomarchy is never a base vendor', 'ok' if not m.BASE_VENDOR.fullmatch('oniomarchy') else 'WRONG', sep='\t')
EOF
)"
while IFS=$'\t' read -r kind subject detail verdict; do
    [[ $kind == vendor ]] && { verdict="$detail"; detail=''; }
    assert_eq "$kind: $subject ${detail}" ok "$verdict"
done <<<"$mirror_cases"
find "$VAPT_LAYER" -name __pycache__ -prune -exec rm -rf {} +

# --- declined source: reported, never degrading on its own --------------------
onio_case vapt-onio-declined
vapt_sudo_noop
vapt_api install --with-oniomarchy --groups automotive
assert_status 'a declined source is not a failed run' 0 "$STATUS"
assert_eq 'the closed prompt declines the source' declined "$(annotation)"
assert_contains 'the item records the declined tier' "$(vapt_field can-utils 8)" 'oniomarchy:declined'
assert_contains 'a decline is not a mutation failure' "$OUTPUT" $'# mutation-failed\t0'
assert_eq 'a decline fetches nothing' '' "$(vapt_calls curl)$(vapt_calls gpg)"
assert_eq 'a decline writes no private state' no "$([[ -e $ROOT$SOURCES ]] && echo yes || echo no)"
vapt_api status
with_annotation="$STATUS:$OUTPUT"
report="$ROOT$XDG_STATE_HOME/haseen/vapt/report.tsv"
grep -v '^# oniomarchy' "$report" >"$report.new" && mv "$report.new" "$report"
vapt_api status
assert_eq 'the declined annotation alone never changes status' "$with_annotation" "$STATUS:$OUTPUT"
vapt_tools_untouched 'declined source'
