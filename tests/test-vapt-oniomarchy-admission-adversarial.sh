# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# Plan 087 adversarial: the private source admits only its fixed 52 names in
# their reviewed roles, by exact name or reviewed alias, never through
# Provides, never as a dependency-only or unmapped root, never shadowing an
# earlier source, never with replaces/conflicts and only for x86_64/any. Each
# case republishes a signed fixture database (tests/fixtures/
# vapt-onio-adversarial.sh) and plans offline; nothing is fetched or run.
# shellcheck source=tests/fixtures/vapt-lib.sh
source "$FIXTURES/vapt-lib.sh"
# shellcheck source=tests/fixtures/vapt-onio-adversarial.sh
source "$FIXTURES/vapt-onio-adversarial.sh"

SUPERSDR='"name":"supersdr","version":"1.0-1","arch":"x86_64","url":"https://github.com/ka7oei/supersdr"'
CANUTILS='"name":"can-utils","version":"2025.01-1","url":"https://github.com/linux-can/can-utils"'

# --- control: a clean republished database is usable ------------------------
adv_approved vapt-adv-admit-control
adv_publish "[{$SUPERSDR},{$CANUTILS,\"arch\":\"x86_64\"}]"
assert_eq 'republished control database is usable' usable "$(adv_state)"
adv_closure oniomarchy/supersdr
assert_status 'control: an admitted candidate closes' 0 "$STATUS"

# --- unmapped candidates are not installable, even as dependencies ----------
# peass-ng, powershell-empire-git, eyewitness-git and android-apktool-bin are
# published candidates with no inventory mapping (logical "-"): a row for them
# "does not select or install it" (plan 087 admission contract).
for unmapped in peass-ng powershell-empire-git eyewitness-git android-apktool-bin; do
    adv_approved "vapt-adv-admit-unmapped-$unmapped"
    adv_publish "[{$SUPERSDR,\"depends\":[\"$unmapped\"]},{\"name\":\"$unmapped\",\"version\":\"1-1\",\"arch\":\"any\",\"url\":\"https://example.org/$unmapped\"}]"
    adv_closure oniomarchy/supersdr
    assert_status "unmapped candidate $unmapped pulled in as a dependency is refused" 1 "$STATUS"
    adv_closure "oniomarchy/$unmapped"
    assert_status "unmapped candidate $unmapped as a requested target is refused" 1 "$STATUS"
done
# The same through the reviewed-transaction path (the plan rows a real
# install audits): an unmapped candidate row is not an admitted dependency.
db="$ROOT/var/cache/haseen-vapt.review/db"
mkdir -p "$db/sync"
cp "$SANDBOX/onio/serve/oniomarchy.db" "$ROOT/var/lib/haseen/vapt/repositories.json" "$db/sync/"
printf 'oniomarchy\tsupersdr\t1.0-1\noniomarchy\tandroid-apktool-bin\t1-1\n' >"$SANDBOX/unmapped.tsv"
capture python3 "$VAPT_META" closure oniomarchy/supersdr "$SANDBOX/unmapped.tsv" --dbpath "$db" --root "$ROOT" --with-oniomarchy
assert_status 'a transaction plan carrying an unmapped candidate is refused' 1 "$STATUS"

# --- the 53rd name, the keyring and dependency-only roles --------------------
adv_approved vapt-adv-admit-53rd
adv_publish "[{$SUPERSDR,\"depends\":[\"evil-tool\"]},{\"name\":\"evil-tool\",\"version\":\"1-1\",\"arch\":\"x86_64\",\"url\":\"https://example.invalid/evil\"}]"
adv_closure oniomarchy/supersdr
assert_status 'a dependency on a 53rd published name is refused' 1 "$STATUS"
assert_not_contains 'the 53rd name is never a snapshot record' \
    "$(python3 "$VAPT_META" snapshot --root "$ROOT" --with-oniomarchy)" 'evil-tool'
adv_publish "[{$SUPERSDR,\"provides\":[\"evil-tool\"]},{\"name\":\"evil-tool\",\"version\":\"1-1\",\"arch\":\"x86_64\",\"url\":\"https://example.invalid/evil\"}]"
adv_closure oniomarchy/evil-tool
assert_status 'a 53rd name is never a requested target' 1 "$STATUS"
adv_publish "[{$SUPERSDR,\"depends\":[\"oniomarchy-keyring\"]}]"
adv_closure oniomarchy/supersdr
assert_status 'the keyring is never a dependency' 1 "$STATUS"
assert_contains 'a self-reference is refused for review, not labelled Omarchy' "$OUTPUT" 'oniomarchy self-reference requires review: supersdr depends on oniomarchy-keyring'
adv_publish "[{$SUPERSDR,\"depends\":[\"omarchy-settings\"]}]"
adv_closure oniomarchy/supersdr
assert_status 'an Omarchy dependency is refused' 1 "$STATUS"
assert_contains 'and labelled Omarchy' "$OUTPUT" 'forbidden Omarchy: supersdr depends on omarchy-settings'
adv_publish "[{$SUPERSDR,\"depends\":[\"oniomarchy-keyring\"]}]"
adv_closure oniomarchy/oniomarchy-keyring
assert_status 'the keyring is never a requested target' 1 "$STATUS"
adv_publish '[{"name":"powershell-bin","version":"7.5.3-1","arch":"x86_64","url":"https://github.com/PowerShell/PowerShell"},{"name":"python-yattag","version":"1.16-1","arch":"any","url":"https://www.yattag.org"}]'
for dependency in powershell-bin python-yattag; do
    adv_closure "oniomarchy/$dependency"
    assert_status "dependency-only $dependency is never a requested target" 1 "$STATUS"
done

# --- Provides never stands in for an item -----------------------------------
adv_approved vapt-adv-admit-provides
adv_publish '[{"name":"seclists","version":"1-1","arch":"any","url":"https://github.com/danielmiessler/SecLists","provides":["wordlists"]}]'
vapt_plan 'exact-name item with a private provider' --with-oniomarchy --groups passwords
assert_eq 'wordlists is not substituted by a private Provides' none "$(vapt_field wordlists 3)"
assert_contains 'wordlists records the private tier as unavailable' "$(vapt_field wordlists 8)" 'oniomarchy:unavailable'
adv_publish "[{$SUPERSDR,\"provides\":[\"can-utils\",\"chirp\"]}]"
vapt_plan 'items with only a private provider' --with-oniomarchy --groups automotive,sdr
assert_eq 'can-utils is not satisfied by a private Provides' none "$(vapt_field can-utils 3)"
assert_eq 'chirp is not satisfied by a private Provides' none "$(vapt_field chirp 3)"
adv_publish "[{$SUPERSDR,\"depends\":[\"libsdrvirtual\"]},{\"name\":\"python-yattag\",\"version\":\"1-1\",\"arch\":\"any\",\"url\":\"https://www.yattag.org\",\"provides\":[\"libsdrvirtual\"]}]"
adv_closure oniomarchy/supersdr
assert_status 'a private dependency Provides never satisfies a dependency' 1 "$STATUS"

# --- architecture -------------------------------------------------------------
adv_approved vapt-adv-admit-arch
for arch in aarch64 i686 armv7h; do
    adv_publish "[{$CANUTILS,\"arch\":\"$arch\"}]"
    vapt_plan "can-utils published for $arch" --with-oniomarchy --groups automotive
    assert_eq "$arch record is never admitted" none "$(vapt_field can-utils 3)"
done
adv_publish "[{$CANUTILS,\"arch\":\"any\"}]"
vapt_plan 'can-utils published for any' --with-oniomarchy --groups automotive
assert_eq 'an architecture-independent record is admitted' oniomarchy/can-utils "$(vapt_field can-utils 4)"

# --- replaces / conflicts ------------------------------------------------------
# A replacement is always refused. A declared conflict removes nothing unless
# the conflicting package is installed (reject_removals refuses that), so the
# usual -git/-bin records declaring conflicts=(base) provides=(base) close.
adv_approved vapt-adv-admit-replaces
adv_publish "[{$CANUTILS,\"arch\":\"x86_64\",\"replaces\":[\"can-utils-legacy\"]}]"
vapt_plan 'candidate declaring replaces' --with-oniomarchy --groups automotive
assert_eq 'a candidate declaring replaces is not planned' no "$(vapt_planned oniomarchy/can-utils)"
assert_eq 'a candidate declaring replaces is never applied' skipped "$(vapt_field can-utils 6)"
assert_contains 'the replaces refusal is reported' "$(vapt_field can-utils 7)" 'replacement/conflict'
adv_publish "[{$SUPERSDR,\"depends\":[\"python-yattag\"]},{\"name\":\"python-yattag\",\"version\":\"1-1\",\"arch\":\"any\",\"url\":\"https://www.yattag.org\",\"replaces\":[\"python-yattag-old\"]}]"
adv_closure oniomarchy/supersdr
assert_status 'a private dependency declaring replaces is refused' 1 "$STATUS"
adv_publish '[{"name":"chirp-next","version":"20260101-1","arch":"any","url":"https://github.com/kk7ds/chirp","conflicts":["chirp"],"provides":["chirp"]}]'
adv_closure oniomarchy/chirp-next
assert_status 'a -git/-bin style alias declaring conflicts=(base) provides=(base) closes' 0 "$STATUS"
adv_publish '[{"name":"autopsy","version":"4.22-1","arch":"x86_64","url":"https://www.autopsy.com","depends":["java17-openjfx"]},{"name":"java17-openjfx-bin","version":"17-1","arch":"x86_64","url":"https://openjfx.io","conflicts":["java17-openjfx"],"provides":["java17-openjfx"]}]'
adv_closure oniomarchy/autopsy
assert_status 'autopsy closes through a conflicting -bin dependency alias' 0 "$STATUS"
adv_approved vapt-adv-admit-conflict-installed
python3 - "$ROOT/var/lib/haseen/vapt/installed.json" <<'EOF'
import json, sys
path = sys.argv[1]
data = json.load(open(path))
data.append({"name": "chirp", "version": "1-1", "url": "https://example.org/chirp"})
json.dump(data, open(path, "w"))
EOF
adv_publish '[{"name":"chirp-next","version":"20260101-1","arch":"any","url":"https://github.com/kk7ds/chirp","conflicts":["chirp"],"provides":["chirp"]}]'
adv_closure oniomarchy/chirp-next
assert_status 'a declared conflict with an installed package is refused' 1 "$STATUS"
assert_contains 'the removal refusal is reported' "$OUTPUT" 'replacement/conflict removal'

# --- a duplicated record makes the source unusable, not ambiguous ------------
adv_approved vapt-adv-admit-duplicate
adv_publish "[{$CANUTILS,\"arch\":\"x86_64\"},{\"name\":\"can-utils\",\"version\":\"2099-1\",\"arch\":\"x86_64\",\"url\":\"https://github.com/linux-can/can-utils\",\"dir\":\"can-utils-shadow\"}]"
assert_eq 'a duplicated record leaves the source unverified' unverified "$(adv_state)"
vapt_plan 'duplicated record' --with-oniomarchy --groups automotive
assert_eq 'a duplicated record resolves nothing' none "$(vapt_field can-utils 3)"

# --- identity: host, path boundary, scheme ------------------------------------
adv_approved vapt-adv-admit-identity
while IFS='|' read -r label url; do
    adv_publish "[{\"name\":\"can-utils\",\"version\":\"1-1\",\"arch\":\"x86_64\",\"url\":\"$url\"}]"
    vapt_plan "identity $label" --with-oniomarchy --groups automotive
    assert_eq "identity $label is refused" none "$(vapt_field can-utils 3)"
    assert_contains "identity $label records identity-rejected" "$(vapt_field can-utils 8)" 'oniomarchy:identity-rejected'
done <<'EOF'
lookalike host|https://github.com.evil.example/linux-can/can-utils
path prefix without boundary|https://github.com/linux-can/can-utils-fork
parent path|https://github.com/linux-can
http downgrade of an https identity|http://github.com/linux-can/can-utils
userinfo|https://user@github.com/linux-can/can-utils
port|https://github.com:8443/linux-can/can-utils
dot segment|https://github.com/linux-can/x/../can-utils
empty url|
EOF
adv_publish '[{"name":"can-utils","version":"1-1","arch":"x86_64","url":"https://GitHub.com/linux-can/can-utils/tree/master"}]'
vapt_plan 'identity case-folded descendant' --with-oniomarchy --groups automotive
assert_eq 'a case-folded descendant path keeps the identity' oniomarchy/can-utils "$(vapt_field can-utils 4)"

# --- earlier homonyms ----------------------------------------------------------
# The same package name published by an earlier usable source: the private
# package never shadows it, whichever identity it carries.
adv_approved vapt-adv-admit-homonym-alias-name "extra|beef-xss|1-1|https://example.org/other"
adv_publish '[{"name":"beef-xss","version":"1-1","arch":"any","url":"https://github.com/beefproject/beef"}]'
vapt_plan 'aliased package name in an earlier tier' --with-oniomarchy --groups exploitation
assert_eq 'an earlier beef-xss refuses the private beef-xss' none "$(vapt_field beef 3)"
assert_contains 'the refusal is identity-rejected' "$(vapt_field beef 8)" 'oniomarchy:identity-rejected'
# The logical name itself published earlier with another identity: the
# reviewed shadowing contract (shadowing.json: "earlier homonym with another
# identity refuses the private package", recon-ng) must not depend on whether
# the private package happens to carry a -git/-xss suffix.
adv_approved vapt-adv-admit-homonym-exact "extra|recon-ng|5.1.2-1|https://example.org/recon-ng"
adv_publish '[{"name":"recon-ng","version":"5.1.2-1","arch":"any","url":"https://github.com/lanmaster53/recon-ng"}]'
vapt_plan 'exact homonym control' --with-oniomarchy --groups osint
assert_eq 'control: an earlier recon-ng homonym refuses the private recon-ng' none "$(vapt_field recon-ng 3)"
adv_approved vapt-adv-admit-homonym-logical "extra|beef|1-1|https://example.org/beef"
adv_publish '[{"name":"beef-xss","version":"1-1","arch":"any","url":"https://github.com/beefproject/beef"}]'
vapt_plan 'logical homonym through an alias' --with-oniomarchy --groups exploitation
assert_eq 'an earlier beef homonym also refuses the private beef-xss' none "$(vapt_field beef 3)"
# A homonym of a dependency in an earlier source: the private one never wins.
adv_approved vapt-adv-admit-homonym-dependency "extra|python-yattag|1.16-1|https://www.yattag.org"
adv_publish "[{$SUPERSDR,\"depends\":[\"python-yattag\"]},{\"name\":\"python-yattag\",\"version\":\"9-1\",\"arch\":\"any\",\"url\":\"https://www.yattag.org\"}]"
printf 'oniomarchy\tsupersdr\t1.0-1\nextra\tpython-yattag\t1.16-1\n' >"$SANDBOX/ok.tsv"
printf 'oniomarchy\tsupersdr\t1.0-1\noniomarchy\tpython-yattag\t9-1\n' >"$SANDBOX/shadow.tsv"
db="$ROOT/var/cache/haseen-vapt.review/db"
mkdir -p "$db/sync"
cp "$SANDBOX/onio/serve/oniomarchy.db" "$db/sync/"
cp "$ROOT/var/lib/haseen/vapt/repositories.json" "$db/sync/"
capture python3 "$VAPT_META" closure oniomarchy/supersdr "$SANDBOX/shadow.tsv" --dbpath "$db" --root "$ROOT" --with-oniomarchy
assert_status 'a planned private dependency shadowing an earlier one is refused' 1 "$STATUS"
assert_contains 'the shadowing refusal is explicit' "$OUTPUT" 'shadows a package of an earlier source'
# An earlier provider under another name (versioned Provides) also precedes a
# private dependency, in the reviewed transaction exactly as in the dry run.
adv_approved vapt-adv-admit-earlier-provider "extra|yattag-compat|1.16-1|https://www.yattag.org|python-yattag=1.16"
adv_publish "[{$SUPERSDR,\"depends\":[\"python-yattag\"]},{\"name\":\"python-yattag\",\"version\":\"1.16-1\",\"arch\":\"any\",\"url\":\"https://www.yattag.org\"}]"
adv_closure oniomarchy/supersdr
assert_status 'offline: the earlier provider closes the private target' 0 "$STATUS"
db="$ROOT/var/cache/haseen-vapt.review/db"
mkdir -p "$db/sync"
cp "$SANDBOX/onio/serve/oniomarchy.db" "$ROOT/var/lib/haseen/vapt/repositories.json" "$db/sync/"
printf 'oniomarchy\tsupersdr\t1.0-1\noniomarchy\tpython-yattag\t1.16-1\n' >"$SANDBOX/private-dep.tsv"
capture python3 "$VAPT_META" closure oniomarchy/supersdr "$SANDBOX/private-dep.tsv" --dbpath "$db" --root "$ROOT" --with-oniomarchy
assert_status 'transaction: a private dependency over an earlier provider is refused' 1 "$STATUS"
assert_contains 'and the earlier provider is named' "$OUTPUT" 'would win over the earlier provider extra/yattag-compat of python-yattag'
printf 'oniomarchy\tsupersdr\t1.0-1\nextra\tyattag-compat\t1.16-1\n' >"$SANDBOX/earlier-dep.tsv"
capture python3 "$VAPT_META" closure oniomarchy/supersdr "$SANDBOX/earlier-dep.tsv" --dbpath "$db" --root "$ROOT" --with-oniomarchy
assert_status 'transaction: the earlier provider closes' 0 "$STATUS"
adv_approved vapt-adv-admit-earlier-provider-version "extra|yattag-compat|1.16-1|https://www.yattag.org|python-yattag=1.16"
adv_publish "[{$SUPERSDR,\"depends\":[\"python-yattag>=2\"]},{\"name\":\"python-yattag\",\"version\":\"2.0-1\",\"arch\":\"any\",\"url\":\"https://www.yattag.org\"}]"
db="$ROOT/var/cache/haseen-vapt.review/db"
mkdir -p "$db/sync"
cp "$SANDBOX/onio/serve/oniomarchy.db" "$ROOT/var/lib/haseen/vapt/repositories.json" "$db/sync/"
printf 'oniomarchy\tsupersdr\t1.0-1\noniomarchy\tpython-yattag\t2.0-1\n' >"$SANDBOX/private-dep.tsv"
capture python3 "$VAPT_META" closure oniomarchy/supersdr "$SANDBOX/private-dep.tsv" --dbpath "$db" --root "$ROOT" --with-oniomarchy
assert_status 'an earlier provider of too old a version does not block the private dependency' 0 "$STATUS"
adv_closure oniomarchy/supersdr
assert_status 'offline agrees: the private dependency closes' 0 "$STATUS"

# --- a reviewed dependency alias is usable ------------------------------------
# dependencies.tsv/aliases.tsv review java17-openjfx -> oniomarchy/java17-openjfx-bin
# as autopsy's dependency; a private autopsy declaring that dependency name
# must close through the reviewed alias (never through an arbitrary Provides).
adv_approved vapt-adv-admit-dependency-alias
adv_publish '[{"name":"autopsy","version":"4.22-1","arch":"x86_64","url":"https://www.autopsy.com","depends":["java17-openjfx"]},{"name":"java17-openjfx-bin","version":"17-1","arch":"x86_64","url":"https://openjfx.io","provides":["java17-openjfx"]}]'
adv_closure oniomarchy/autopsy
assert_status 'the reviewed java17-openjfx alias satisfies autopsy' 0 "$STATUS"

# --- dependencies.tsv consumer and role (closure enforces them) ---------------
# A mapped candidate is admitted only as the requested target.
adv_approved vapt-adv-admit-candidate-as-dependency
adv_publish "[{$SUPERSDR,\"depends\":[\"can-utils\"]},{$CANUTILS,\"arch\":\"x86_64\"}]"
adv_closure oniomarchy/supersdr
assert_status 'a mapped candidate pulled in as a dependency is refused' 1 "$STATUS"
assert_contains 'and the refusal names the role rule' "$OUTPUT" 'admitted only as the requested target'
adv_closure oniomarchy/can-utils
assert_status 'control: the same candidate as the requested target closes' 0 "$STATUS"
# java17-openjfx-bin and sleuthkit-java serve only autopsy; powershell-bin (*) anyone.
adv_approved vapt-adv-admit-dependency-consumer
adv_publish "[{$SUPERSDR,\"depends\":[\"java17-openjfx\",\"sleuthkit-java\"]},{\"name\":\"java17-openjfx-bin\",\"version\":\"17-1\",\"arch\":\"x86_64\",\"url\":\"https://openjfx.io\",\"provides\":[\"java17-openjfx\"]},{\"name\":\"sleuthkit-java\",\"version\":\"4.14-1\",\"arch\":\"x86_64\",\"url\":\"https://www.sleuthkit.org\"}]"
adv_closure oniomarchy/supersdr
assert_status "another consumer's private dependency is refused" 1 "$STATUS"
assert_contains 'and the refusal names the recorded consumer rule' "$OUTPUT" 'serves only its recorded consumer'
adv_publish "[{$SUPERSDR,\"depends\":[\"powershell-bin\"]},{\"name\":\"powershell-bin\",\"version\":\"7.5.3-1\",\"arch\":\"x86_64\",\"url\":\"https://github.com/PowerShell/PowerShell\"}]"
adv_closure oniomarchy/supersdr
assert_status 'a private dependency recorded for any consumer (*) closes' 0 "$STATUS"

# --- an earlier configured source unreadable this run is recorded ------------
adv_approved vapt-adv-admit-earlier-unseen
printf '\n[chaotic-aur]\nServer = https://cdn-mirror.chaotic.cx/$repo/$arch\n' >>"$ROOT/etc/pacman.conf"
adv_publish "[{$SUPERSDR}]"
vapt_plan 'earlier source unavailable' --with-oniomarchy --groups sdr
assert_eq 'the private source still resolves supersdr' oniomarchy/supersdr "$(vapt_field supersdr 4)"
assert_contains 'the reason records the unread earlier source' "$(vapt_field supersdr 7)" \
    'earlier source unavailable this run (chaotic-aur); not proof this is the inventory tool'
adv_approved vapt-adv-admit-earlier-seen
adv_publish "[{$SUPERSDR}]"
vapt_plan 'every earlier source read' --with-oniomarchy --groups sdr
assert_not_contains 'control: no uncertainty when every earlier source was read' "$(vapt_field supersdr 7)" 'earlier source unavailable'

# --- alias / admission table tampering ----------------------------------------
adv_approved vapt-adv-admit-tables
adv_mutated_tree
adv_tree_plan --groups core
assert_status 'copied tree plans (control)' 0 "$STATUS"
while IFS='|' read -r label table row; do
    adv_mutated_tree
    printf '%b\n' "$row" >>"$ADV_TREE_VAPT/packages/$table"
    adv_tree_plan --with-oniomarchy --groups core
    assert_status "tampered $label is refused" 2 "$STATUS"
    assert_not_contains "tampered $label plans nothing" "$OUTPUT" 'DRYRUN:'
done <<'EOF'
alias to the 53rd name|aliases.tsv|nuclei\toniomarchy\tevil-tool
alias to the keyring|aliases.tsv|steghide\toniomarchy\toniomarchy-keyring
alias to a dependency-only package|aliases.tsv|steghide\toniomarchy\tpowershell-bin
alias to another item's candidate|aliases.tsv|seclists\toniomarchy\twordlists
alias to an unmapped candidate|aliases.tsv|steghide\toniomarchy\tpeass-ng
alias for a blocked identity|aliases.tsv|metasploit-mcp\toniomarchy\tsliver
second alias for one item|aliases.tsv|chirp\toniomarchy\tchirp
dependency routed to a candidate|dependencies.tsv|libsoup\t*\toniomarchy/sliver\tdependency
admission row for the 53rd name|oniomarchy.tsv|evil-tool\tcandidate\t-
duplicate admission row|oniomarchy.tsv|peass-ng\tcandidate\t-
EOF
adv_mutated_tree
sed -i 's/^peass-ng\tcandidate\t-$/peass-ng\tinfrastructure\t-/' "$ADV_TREE_VAPT/packages/oniomarchy.tsv"
assert_contains 'the infrastructure edit applied' "$(cat "$ADV_TREE_VAPT/packages/oniomarchy.tsv")" $'peass-ng\tinfrastructure'
adv_tree_plan --groups core
assert_status 'a second infrastructure role is refused' 2 "$STATUS"
vapt_tools_untouched 'admission adversarial'
