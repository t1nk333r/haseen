# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# VAPT inventory (plan 083 slice 1A): the 25 fixed groups, the added group
# roots, dependency-only names, reviewed aliases, official pins, canonical URL
# identities and blocked identities. Every host is a fixture sysroot and every
# manager or tool a logging stub (tests/fixtures/vapt-lib.sh); expectations
# come from tests/fixtures/vapt-oniomarchy/inventory.json, results from the
# real planner's report. Nothing here runs a security tool or reaches a network.
# shellcheck source=tests/fixtures/vapt-lib.sh
source "$FIXTURES/vapt-lib.sh"

INVENTORY="$FIXTURES/vapt-oniomarchy/inventory.json"
inv() { python3 - "$INVENTORY" "$@" <<'EOF'
import json, sys
data = json.load(open(sys.argv[1]))
query = sys.argv[2]
if query == 'groups':
    print(' '.join(data['originalGroups'] + list(data['addedGroups'])))
elif query == 'added':
    print(' '.join(data['addedGroups'][sys.argv[3]]))
elif query == 'appended':
    for group, names in data['appendedRoots'].items():
        print(group, ' '.join(names))
elif query == 'roles':
    for name, role in sorted(data['sourcePackages'].items()):
        print(name, role)
elif query == 'dependencies':
    for name, consumer in data['dependencies'].items():
        print(name, consumer)
elif query == 'aliases':
    for row in data['aliases']:
        print(' '.join(row))
elif query == 'pins':
    for name, target in data['officialPins'].items():
        print(name, target)
else:
    value = data[query]
    print(' '.join(value) if isinstance(value, list) else value)
EOF
}
# report_logicals — the report's logical tools, one per line, in row order.
report_logicals() { awk -F'\t' 'NF == 8 && $1 !~ /^[# ]/ && $1 != "logical" { print $1 }' <<<"$OUTPUT"; }
# group_members GROUP — logical tools whose report memberships include GROUP.
group_members() {
    awk -F'\t' -v g="$1" 'NF == 8 && $1 !~ /^[# ]/ && $1 != "logical" && ("," $2 ",") ~ ("," g ",") { print $1 }' <<<"$OUTPUT"
}
# manifest_union — distinct manifest roots plus native adapter logicals.
manifest_union() {
    { sed -e 's/#.*//' -e 's/[[:space:]]//g' "$VAPT_LAYER"/packages/security/*.txt | grep -v '^$'
      awk -F'\t' '$1 !~ /^#/ && NF >= 6 { print $2 }' "$VAPT_LAYER/packages/security/native.tsv"; } | LC_ALL=C sort -u
}
# mutated_tree — a private copy of the installed tree to break deliberately.
mutated_tree() {
    tree="$SANDBOX/share"
    rm -rf "$tree"
    mkdir -p "$tree/layers"
    ln -s "$HASEEN_PATH/lib" "$tree/lib"
    ln -s "$HASEEN_PATH/default" "$tree/default"
    cp -R "$VAPT_LAYER" "$tree/layers/vapt"
    TREE_VAPT="$tree/layers/vapt"
}
tree_plan() { capture env HASEEN_PATH="$tree" HASEEN_SYSROOT="$ROOT" PATH="$SANDBOX/cli-stubs:$PATH" haseen vapt install --dry-run "$@" </dev/null; }

# --- the fixed group array: --all covers exactly the 25 groups ---------------
vapt_sandbox vapt-inventory-all
vapt_root
vapt_repos "${VAPT_BASE[@]}" "$VAPT_BA_KEYRING"
before="$(vapt_tree)"
vapt_plan '--all' --all
assert_eq '--all writes nothing anywhere' "$before" "$(vapt_tree)"
vapt_tools_untouched '--all'
ALL_OUTPUT="$OUTPUT"
expected_groups="$(inv groups | tr ' ' '\n' | LC_ALL=C sort)"
assert_eq 'there are 25 fixed groups' 25 "$(grep -c . <<<"$expected_groups")"
observed_groups="$(awk -F'\t' 'NF == 8 && $1 !~ /^[# ]/ && $1 != "logical" { print $2 }' <<<"$OUTPUT" | tr ',' '\n' | LC_ALL=C sort -u)"
assert_eq '--all selects exactly the fixed groups' "$expected_groups" "$observed_groups"
assert_eq 'no logical tool has two report rows' '' "$(report_logicals | LC_ALL=C sort | uniq -d)"

# The tool/data union is computed from the manifests and native rows, and the
# planner reports every member once; docs/vapt.md publishes that number.
union="$(manifest_union | grep -c .)"
assert_eq 'the --all report is the manifest/native union' "$(manifest_union)" "$(report_logicals | LC_ALL=C sort)"
assert_contains 'docs/vapt.md publishes the observed union' "$(tr '\n' ' ' <"$REPO/docs/vapt.md")" "**$union distinct tool names**"
original=''
for group in $(inv originalGroups); do original+="$(group_members "$group")"$'\n'; done
appended="$(inv appended | cut -d' ' -f2- | tr ' ' '\n')"
assert_eq 'the original fifteen groups keep their union' "$(inv originalUnion)" \
    "$(LC_ALL=C sort -u <<<"$original" | grep -vxF -f <(printf '%s\n' "$appended") | grep -c .)"

# Added group roots are the exact specified lists, in manifest order.
for group in sdr wireless privacy anonymity automotive social reporting ai exploitation services; do
    assert_eq "$group roots" "$(inv added "$group")" "$(group_members "$group" | tr '\n' ' ' | sed 's/ $//')"
done
while read -r group names; do
    in_group=" $(group_members "$group" | tr '\n' ' ')"
    for name in $names; do assert_contains "$group gains $name" "$in_group" " $name "; done
done < <(inv appended)
sorted_members() { group_members "$1" | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//'; }
assert_eq 'osint keeps its root and native-only injection' 'recon-ng sherlock theharvester whois' "$(sorted_members osint)"
assert_eq 'passwords keeps seclists distinct from wordlists' 'hashcat hydra john seclists wordlists' "$(sorted_members passwords)"
assert_eq 'native-only frida-tools stays in mobile' mobile "$(vapt_field frida-tools 2)"
assert_eq 'native-only sigma-cli stays in htb-cjca' htb-cjca "$(vapt_field sigma-cli 2)"

# Dependency-only packages and the source's infrastructure never become roots.
roots=" $(report_logicals | tr '\n' ' ')"
while read -r name consumer; do
    assert_not_contains "dependency $name is never a root" "$roots" " $name "
    [[ $consumer == '*' ]] || assert_contains "dependency $name names a real consumer ($consumer)" "$roots" " $consumer "
done < <(inv dependencies)
while read -r name role; do
    [[ $role == candidate ]] || assert_not_contains "$role package $name is never a root" "$roots" " $name "
done < <(inv roles)
assert_eq 'the source index fixture lists 52 packages' 52 "$(inv roles | grep -c .)"
assert_eq 'the source index fixture has one infrastructure package' 1 "$(inv roles | grep -c ' infrastructure$')"

# --- selection: unknown and deduplicated groups ------------------------------
vapt_cli install --dry-run --groups sdr,bogus
assert_status 'an unknown group beside a new group is refused' 2 "$STATUS"
assert_not_contains 'nothing planned for the refused selection' "$OUTPUT" 'DRYRUN:'
vapt_plan 'a repeated new group' --groups social,social
assert_eq 'a repeated group is one membership' social "$(vapt_field gophish 2)"
assert_eq 'a repeated group is one row' 1 "$(report_logicals | grep -cx gophish)"

# --- every group file and table is validated, even when not selected ---------
broken_case() { # LABEL EDIT-COMMAND...
    local label="$1"
    shift
    mutated_tree
    "$@"
    local before
    before="$(vapt_tree)"
    tree_plan --groups core
    assert_status "$label refuses the unrelated core selection" 2 "$STATUS"
    assert_not_contains "$label plans nothing" "$OUTPUT" 'DRYRUN:'
    assert_eq "$label writes nothing" "$before" "$(vapt_tree)"
    assert_eq "$label invokes nothing" '' "$(ls -A "$CALLS")"
}
vapt_sandbox vapt-inventory-validate
vapt_root
vapt_repos "${VAPT_BASE[@]}" "$VAPT_BA_KEYRING"
mutated_tree
tree_plan --groups core
assert_status 'the unmodified copied tree plans (control)' 0 "$STATUS"
broken_case 'a missing new group file' rm "$TREE_VAPT/packages/security/sdr.txt"
broken_case 'a malformed new group file' sh -c 'printf "bad/name\n" >>"$1"' _ "$TREE_VAPT/packages/security/services.txt"
for name in powershell-bin xorg-xhost jdk17-openjdk java17-openjfx sleuthkit-java jdk-openjdk python-wxpython; do
    broken_case "dependency $name as a root" sh -c 'printf "%s\n" "$2" >>"$1"' _ "$TREE_VAPT/packages/security/wireless.txt" "$name"
done
for table in aliases.tsv dependencies.tsv identity-policy.tsv; do
    broken_case "missing $table" rm "$TREE_VAPT/packages/$table"
done
broken_case 'an alias for an unknown repository' sh -c 'printf "chirp\tsomewhere\tchirp-next\n" >>"$1"' _ "$TREE_VAPT/packages/aliases.tsv"
broken_case 'an identity-preserving alias' sh -c 'printf "chirp\textra\tchirp\n" >>"$1"' _ "$TREE_VAPT/packages/aliases.tsv"
broken_case 'a BlackArch alias beside a native adapter' sh -c 'printf "netexec\tblackarch\tnetexec-git\n" >>"$1"' _ "$TREE_VAPT/packages/aliases.tsv"
broken_case 'an alias for a blocked identity' sh -c 'printf "metasploit-mcp\tblackarch\tmetasploit-mcp-git\n" >>"$1"' _ "$TREE_VAPT/packages/aliases.tsv"
broken_case 'a dependency whose package has no alias' sh -c 'printf "libfoo\t*\textra/libfoo-bin\tdependency\n" >>"$1"' _ "$TREE_VAPT/packages/dependencies.tsv"
broken_case 'a dependency with an unknown consumer' sh -c 'printf "libfoo\tnot-a-tool\textra/libfoo\tdependency\n" >>"$1"' _ "$TREE_VAPT/packages/dependencies.tsv"
broken_case 'a dependency with an explicit install reason' sh -c 'printf "libfoo\t*\textra/libfoo\texplicit\n" >>"$1"' _ "$TREE_VAPT/packages/dependencies.tsv"
broken_case 'an unknown identity policy' sh -c 'printf "gophish\ttrusted\tno reason\n" >>"$1"' _ "$TREE_VAPT/packages/identity-policy.tsv"
broken_case 'a pin for a name outside the inventory' sh -c 'printf "xorg-xhost\textra/xorg-xhost\n" >>"$1"' _ "$TREE_VAPT/packages/pins.tsv"
broken_case 'a pin on a fact-only source' sh -c 'printf "chirp\toniomarchy/chirp-next\n" >>"$1"' _ "$TREE_VAPT/packages/pins.tsv"
broken_case 'a substring identity' sed -i 's#\thttps://github.com/projectdiscovery/httpx\t#\tgithub.com/projectdiscovery/httpx\t#' "$TREE_VAPT/packages/identities.tsv"
broken_case 'a trailing-slash identity' sed -i 's#\thttps://www.maltego.com\t#\thttps://www.maltego.com/\t#' "$TREE_VAPT/packages/identities.tsv"
broken_case 'an identity with a port' sed -i 's#\thttps://www.maltego.com\t#\thttps://www.maltego.com:8443\t#' "$TREE_VAPT/packages/identities.tsv"
broken_case 'a required target on a fact-only source' sed -i 's#^maltego\trepository\t\*\t#maltego\trepository\toniomarchy/maltego\t#' "$TREE_VAPT/packages/identities.tsv"

# --- official pins and the concrete SET mapping -------------------------------
vapt_sandbox vapt-inventory-pins
vapt_root
vapt_repos "${VAPT_BASE[@]}" "$VAPT_BA_KEYRING" \
    'extra|gqrx|2.17.6-1|https://gqrx.dk/' 'blackarch|gqrx|2.99-1|https://example.org/another-gqrx' \
    'blackarch|urh|2.9.8-1|https://github.com/jopohl/urh' \
    'core|openssh|10.0p1-1|https://www.openssh.com/portable.html' 'blackarch|openssh|10.1p1-1|https://www.openssh.com/portable.html' \
    'extra|remmina|1:1.4.40-1|https://www.remmina.org/'
vapt_plan 'official pins' --groups sdr,services
assert_eq 'pinned gqrx comes from extra over a BlackArch homonym' extra/gqrx "$(vapt_field gqrx 4)"
assert_eq 'pinned gqrx is planned' yes "$(vapt_planned extra/gqrx)"
assert_eq 'the BlackArch gqrx homonym is not planned' no "$(vapt_planned blackarch/gqrx)"
assert_eq 'pinned openssh comes from core' core/openssh "$(vapt_field openssh 4)"
assert_eq 'pinned remmina comes from extra' extra/remmina "$(vapt_field remmina 4)"
assert_eq 'a missing official pin falls through to BlackArch' blackarch/urh "$(vapt_field urh 4)"
assert_contains 'the missing pin is reported' "$(vapt_field urh 7)" 'pin missing'
assert_eq 'an item missing everywhere is unavailable' unavailable "$(vapt_field chirp 5)"
assert_contains 'its attempts are observable' "$(vapt_field chirp 8)" 'blackarch,native,chaotic-aur'
assert_not_contains 'no service is enabled or started' "$OUTPUT" 'systemctl'
# Every official pin is the first attempted tier of its item.
while read -r name target; do
    assert_contains "$name is pinned to $target" "$(OUTPUT="$ALL_OUTPUT" vapt_field "$name" 8)" "pin:$target"
done < <(inv pins)

SET_URL=https://github.com/trustedsec/social-engineer-toolkit
vapt_repos "${VAPT_BASE[@]}" "$VAPT_BA_KEYRING" "blackarch|set|8.0.3-1|$SET_URL" \
    "blackarch|gophish|0.12.1-1|https://github.com/gophish/gophish"
vapt_plan 'SET mapping' --groups social
assert_eq 'social-engineer-toolkit is BlackArch set' blackarch/set "$(vapt_field social-engineer-toolkit 4)"
assert_eq 'blackarch/set is planned' yes "$(vapt_planned blackarch/set)"
assert_eq 'gophish resolves by name' blackarch/gophish "$(vapt_field gophish 4)"
vapt_repos "${VAPT_BASE[@]}" "$VAPT_BA_KEYRING" 'blackarch|set|1.0-1|https://example.org/set-theory' \
    "blackarch|set-fork|8.0.3-1|$SET_URL|set,social-engineer-toolkit"
vapt_plan 'SET homonym and providers' --groups social
assert_eq 'a set homonym from another upstream is refused' unavailable "$(vapt_field social-engineer-toolkit 5)"
assert_eq 'the set homonym is not planned' no "$(vapt_planned blackarch/set)"
assert_eq 'a BlackArch provider cannot replace the reviewed alias' no "$(vapt_planned blackarch/set-fork)"

# --- fact-only alias targets are never a tier --------------------------------
vapt_conf_add $'[oniomarchy]\nSigLevel = Required DatabaseRequired\nServer = https://pkgs.oniomarchy.com/$arch'
vapt_repos "${VAPT_BASE[@]}" "$VAPT_BA_KEYRING" \
    'oniomarchy|chirp-next|0.4.0-1|https://chirpmyradio.com/' 'oniomarchy|supersdr|1-1|https://github.com/ka7oei/supersdr' \
    'oniomarchy|powershell-bin|7.5.3-1|https://github.com/PowerShell/PowerShell'
vapt_plan 'fact-only source rows' --groups sdr
assert_eq 'chirp is not resolved from a fact-only source' unavailable "$(vapt_field chirp 5)"
assert_eq 'supersdr is not resolved from a fact-only source' unavailable "$(vapt_field supersdr 5)"
assert_not_contains 'nothing is planned from the fact-only source' "$OUTPUT" 'oniomarchy/'
assert_not_contains 'the host pacman.conf is never rewritten' "$OUTPUT" 'append to /etc/pacman.conf'

# --- canonical URL identities --------------------------------------------------
vapt_sandbox vapt-inventory-identity
vapt_root
BEEF=https://github.com/beefproject/beef
identity_case() { # LABEL URL EXPECTED(resolved|unavailable)
    vapt_repos "${VAPT_BASE[@]}" "$VAPT_BA_KEYRING" "blackarch|beef|0.5.4.0-1|$2"
    vapt_plan "beef identity: $1" --groups exploitation
    assert_eq "beef identity: $1" "$3" "$(vapt_field beef 5)"
}
identity_case 'canonical' "$BEEF" resolved
identity_case 'host and path case, trailing slash' https://GitHub.com/BeefProject/beef/ resolved
identity_case 'descendant path' "$BEEF/tree/master" resolved
identity_case 'sibling path prefix' "${BEEF}-fork" unavailable
identity_case 'identity embedded in another host path' "https://evil.example/github.com/beefproject/beef" unavailable
identity_case 'identity host as a subdomain prefix' "https://github.com.evil.example/beefproject/beef" unavailable
identity_case 'scheme downgrade' "http://github.com/beefproject/beef" unavailable
identity_case 'userinfo' "https://user@github.com/beefproject/beef" unavailable
identity_case 'port' "https://github.com:8443/beefproject/beef" unavailable
identity_case 'query' "$BEEF?ref=x" unavailable
identity_case 'dot segments' "https://github.com/beefproject/beef/../../other/beef" unavailable
identity_case 'missing URL' '' unavailable
vapt_repos "${VAPT_BASE[@]}" "$VAPT_BA_KEYRING" 'blackarch|armitage|1.4.11-1|https://www.fastandeasyhacking.com/' \
    'extra|routersploit|3.4.7-1|https://github.com/threat9/routersploit'
vapt_plan 'http identity accepts https' --groups exploitation
assert_eq 'armitage http identity accepts an https package URL' blackarch/armitage "$(vapt_field armitage 4)"
assert_eq 'routersploit uses its official pin' extra/routersploit "$(vapt_field routersploit 4)"

# Migrated ProjectDiscovery identities keep refusing the Python homonyms.
vapt_repos "${VAPT_BASE[@]}" "$VAPT_BA_KEYRING" \
    'extra|httpx|0.28.1-1|https://www.python-httpx.org/' \
    'extra|python-httpx|0.28.1-1|https://github.com/encode/httpx|httpx' \
    'blackarch|katana-pd|1.2.2-1|https://github.com/projectdiscovery/katana-framework'
vapt_plan 'ProjectDiscovery identities' --groups htb-cwes
assert_eq 'Python httpx is refused' unavailable "$(vapt_field httpx 5)"
assert_eq 'a katana path-prefix sibling is refused' unavailable "$(vapt_field katana-pd 5)"

# Required targets are enforced, not just parsed.
mutated_tree
sed -i 's#^beef\trepository\t\*\t#beef\trepository\tblackarch/beef\t#' "$TREE_VAPT/packages/identities.tsv"
vapt_repos "${VAPT_BASE[@]}" 'extra|beef|0.5.4.0-1|https://github.com/beefproject/beef'
tree_plan --groups exploitation
assert_status 'required target plan' 0 "$STATUS"
assert_eq 'an identity-matching package outside the required target is refused' unavailable "$(vapt_field beef 5)"
vapt_repos "${VAPT_BASE[@]}" "$VAPT_BA_KEYRING" 'blackarch|beef|0.5.4.0-1|https://github.com/beefproject/beef'
tree_plan --groups exploitation
assert_eq 'the required target resolves (control)' blackarch/beef "$(vapt_field beef 4)"

# --- Microsoft PyRIT, unavailable AI identities, the distinct wordlists -------
vapt_sandbox vapt-inventory-ai
vapt_root
vapt_repos "${VAPT_BASE[@]}" "$VAPT_BA_KEYRING" \
    'blackarch|metasploit-mcp|0.1-1|https://pypi.org/project/metasploit-mcp/' \
    'extra|metasploit-mcp|0.2-1|https://github.com/example/metasploit-mcp' \
    'blackarch|hexstrike-ai|6.0-1|https://example.org/hexstrike-ai'
vapt_plan 'AI identities' --groups ai
assert_eq 'metasploit-mcp is unavailable' unavailable "$(vapt_field metasploit-mcp 5)"
assert_eq 'metasploit-mcp is only identity-blocked' identity-blocked "$(vapt_field metasploit-mcp 8)"
assert_contains 'the blocked reason is reported' "$(vapt_field metasploit-mcp 7)" 'identity blocked'
assert_eq 'no metasploit-mcp package is planned' '' "$(grep -F 'metasploit-mcp>' <<<"$OUTPUT" || true)"
assert_eq 'hexstrike-ai from another upstream is refused' unavailable "$(vapt_field hexstrike-ai 5)"
assert_not_contains 'no MCP server or AI client is touched' "$OUTPUT" 'systemctl'
vapt_repos "${VAPT_BASE[@]}" "$VAPT_BA_KEYRING" 'blackarch|hexstrike-ai|6.0-1|https://github.com/0x4m4/hexstrike-ai'
vapt_plan 'a future acceptable hexstrike-ai source' --groups ai
assert_eq 'hexstrike-ai with its identity resolves (control)' blackarch/hexstrike-ai "$(vapt_field hexstrike-ai 4)"

vapt_repos "${VAPT_BASE[@]}" "$VAPT_BA_KEYRING" "blackarch|pyrit|0.5.1-1|https://github.com/JPaulMora/Pyrit"
vapt_plan 'PyRIT exclusion' --groups htb-coae
assert_eq 'PyRIT stays the Microsoft native release' native "$(vapt_field pyrit 3)"
assert_not_contains 'the BlackArch WPA pyrit is never planned' "$OUTPUT" 'blackarch/pyrit'

vapt_repos "${VAPT_BASE[@]}" "$VAPT_BA_KEYRING" \
    'blackarch|seclists|2025.3-1|https://github.com/danielmiessler/SecLists|wordlists' \
    'extra|wordlist-bundle|1-1|https://example.org/wordlists|wordlists'
vapt_plan 'wordlists providers' --groups passwords
assert_eq 'no provider substitutes for wordlists' unavailable "$(vapt_field wordlists 5)"
assert_eq 'seclists remains its own root' blackarch/seclists "$(vapt_field seclists 4)"
vapt_repos "${VAPT_BASE[@]}" "$VAPT_BA_KEYRING" 'blackarch|wordlists|1-1|https://example.org/wordlists'
vapt_plan 'wordlists exact name' --groups passwords
assert_eq 'an exact wordlists package resolves (control)' blackarch/wordlists "$(vapt_field wordlists 4)"
vapt_tools_untouched 'identity cases'

# --- a consumer's declared dependency is installed as a dependency ------------
if command -v bsdtar >/dev/null 2>&1; then
    vapt_sandbox vapt-inventory-reasons
    vapt_root
    printf '[options]\nArchitecture = auto\nDownloadUser = alpm\nSigLevel = Required DatabaseOptional\n\n[core]\nServer = https://geo.mirror.pkgbuild.com/$repo/os/$arch\n\n[extra]\nServer = https://geo.mirror.pkgbuild.com/$repo/os/$arch\n' \
        >"$ROOT/etc/pacman.conf"
    printf 'original system sync DB\n' >"$ROOT/var/lib/pacman/sync/extra.db"
    vapt_transactions
    export VAPT_PLAN="$SANDBOX/plan.tsv" VAPT_LIVE_PLAN="$SANDBOX/live.tsv" VAPT_ARCHIVES="$SANDBOX/archives" VAPT_MOCK_SIGNATURES=1
    vapt_repos 'extra|ghidra|11.4-1|https://github.com/NationalSecurityAgency/ghidra||jdk-openjdk' \
        'extra|jdk-openjdk|25-1|https://openjdk.org/'
    vapt_package ghidra 11.4-1
    vapt_package jdk-openjdk 25-1
    for name in 'ghidra 11.4-1' 'jdk-openjdk 25-1'; do
        read -r n v <<<"$name"
        printf 'extra\t%s\t%s\thttps://geo.mirror.pkgbuild.com/extra/os/x86_64/%s-%s-x86_64.pkg.tar.gz\n' "$n" "$v" "$n" "$v"
    done >"$VAPT_PLAN"
    cp "$VAPT_PLAN" "$VAPT_LIVE_PLAN"
    vapt_api pacman --yes extra/ghidra
    assert_status 'the consumer transaction commits' 0 "$STATUS"
    reason_of() {
        python3 - "$ROOT/var/lib/haseen/vapt/installed.json" "$1" <<'EOF'
import json, sys
print(next((p.get('reason', '') for p in json.load(open(sys.argv[1])) if p['name'] == sys.argv[2]), 'absent'))
EOF
    }
    assert_eq 'the consumer is explicit' explicit "$(reason_of ghidra)"
    assert_eq 'its declared runtime is a dependency' depend "$(reason_of jdk-openjdk)"
    vapt_tools_untouched 'dependency reasons'
else
    echo "  (note: bsdtar is not installed; the dependency-reason commit was skipped)"
fi
