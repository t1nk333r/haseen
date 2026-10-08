# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# VAPT layer (plan 007): group selection, source priority and identity, native
# adapters, closure policy, dry-run purity and the status contract. Every host
# is a fixture sysroot and every manager or tool a logging stub
# (tests/fixtures/vapt-lib.sh); nothing here runs a security tool.
# shellcheck source=tests/fixtures/vapt-lib.sh
source "$FIXTURES/vapt-lib.sh"

NETEXEC_SPEC="$(vapt_native_spec netexec)"
SHERLOCK_SPEC="$(vapt_native_spec sherlock)"
WHOIS="extra|whois|5.6.4-1|https://github.com/rfc1036/whois"

# --- selection is refused before anything runs (not a dry run) ---------------
vapt_sandbox vapt-select
vapt_root
vapt_repos "${VAPT_BASE[@]}" "$VAPT_BA_KEYRING" "$WHOIS"
before="$(vapt_tree)"
vapt_cli install --groups core,bogus
assert_status "unknown group refused" 2 "$STATUS"
assert_contains "the unknown group is named" "$OUTPUT" "bogus"
for args in "--groups Core" "--groups security/core" "--groups core," "--groups ,core" \
    "--groups core,,web" "--groups" "--all --groups core" "--groups core --all" \
    "--groups core --groups web" "--group core" ""; do
    read -r -a argv <<<"$args"
    vapt_cli install "${argv[@]}"
    assert_status "refused: '$args'" 2 "$STATUS"
    assert_not_contains "nothing planned or run: '$args'" "$OUTPUT" "DRYRUN:"
done
assert_eq "refusals change nothing on disk" "$before" "$(vapt_tree)"
assert_eq "refusals invoke no command" "" "$(ls -A "$CALLS")"
capture env HASEEN_SYSROOT="$ROOT" haseen layer apply vapt --dry-run </dev/null
assert_status "layer apply with no selection is refused (no default tools)" 2 "$STATUS"
assert_not_contains "no default tools are planned" "$OUTPUT" "DRYRUN:"
capture env HASEEN_SYSROOT="$ROOT" haseen layer apply vapt -- --groups web,bogus </dev/null
assert_status "layer apply validates the group list too" 2 "$STATUS"
assert_eq "layer refusal changes nothing on disk" "$before" "$(vapt_tree)"

# install.sh validates --vapt-groups before installing the tree; a fake
# installed CLI reports what each phase would receive.
stage="$SANDBOX/stage"
mkdir -p "$stage/bin" "$stage/share"
cp "$REPO/install.sh" "$stage/install.sh"
ln -s "$REPO/share/haseen" "$stage/share/haseen"
printf '#!/usr/bin/env bash\nprintf "HASEEN-CLI %%s\\n" "$*"\n' >"$stage/bin/haseen"
chmod +x "$stage/bin/haseen"
vapt_install_sh() {
    capture env HASEEN_SYSROOT="$FIXTURES/desk-cachyos-amd" \
        "$stage/install.sh" --dry-run --yes --prefix "$SANDBOX/prefix" "$@" </dev/null
}
vapt_install_sh --layers base --vapt-groups core,bogus
assert_status "installer refuses an unknown VAPT group" 2 "$STATUS"
assert_not_contains "installer refusal precedes the tree" "$OUTPUT" "DRYRUN:"
assert_not_contains "installer refusal precedes every layer" "$OUTPUT" "HASEEN-CLI"
vapt_install_sh --layers vapt
assert_status "installer: vapt without groups refused" 1 "$STATUS"
assert_not_contains "installer: nothing applied without groups" "$OUTPUT" "HASEEN-CLI"
vapt_install_sh --layers base,vapt --vapt-groups core,web
assert_status "installer with VAPT groups" 0 "$STATUS"
assert_contains "vapt is not applied as an ordinary layer" "$OUTPUT" "HASEEN-CLI layer apply base --dry-run --yes"$'\n'
assert_contains "the groups reach the vapt layer" "$OUTPUT" "HASEEN-CLI layer apply vapt --dry-run --yes -- --groups core,web"
vapt_install_sh --layers base --vapt-groups all
assert_contains "'all' selects every group explicitly" "$OUTPUT" "HASEEN-CLI layer apply vapt --dry-run --yes -- --all"
# The guided picker never offers vapt: applied bare it would refuse after the
# earlier layers, and a remembered choice would repeat that on every run.
capture env HASEEN_SYSROOT="$FIXTURES/desk-cachyos-amd" \
    "$stage/install.sh" --dry-run --pick --prefix "$SANDBOX/prefix" <<<""
assert_status "picker run without vapt succeeds" 0 "$STATUS"
assert_contains "the picker still lists optional layers" "$OUTPUT" "[ ] secureboot"
assert_not_contains "the picker does not offer vapt" "$OUTPUT" "] vapt"
assert_not_contains "a picked run never applies vapt" "$OUTPUT" "layer apply vapt"
mkdir -p "$HOME/.config/haseen"
printf 'layers = ["base", "vapt"]\nsetup = []\n' >"$HOME/.config/haseen/install.toml"
capture env HASEEN_SYSROOT="$FIXTURES/desk-cachyos-amd" \
    "$stage/install.sh" --dry-run --pick --prefix "$SANDBOX/prefix" <<<"y"
assert_status "a saved vapt choice does not abort the installer" 0 "$STATUS"
assert_contains "a saved vapt choice is dropped with a reason" "$OUTPUT" "layer 'vapt' needs its own arguments"
assert_contains "the rest of the saved choice is applied" "$OUTPUT" "HASEEN-CLI layer apply base --dry-run"$'\n'
assert_not_contains "a saved vapt choice is never applied bare" "$OUTPUT" "layer apply vapt"
rm -f "$HOME/.config/haseen/install.toml"

# --- Microsoft PyRIT versus the BlackArch WPA cracker; the COAE environment ---
vapt_sandbox vapt-pyrit
vapt_root
vapt_repos "${VAPT_BASE[@]}" "$VAPT_BA_KEYRING" "blackarch|pyrit|0.5.1-1|https://github.com/JPaulMora/Pyrit"
vapt_plan "htb-coae" --groups htb-coae
assert_eq "PyRIT comes from the pinned native adapter" native "$(vapt_field pyrit 3)"
assert_eq "PyRIT is the Microsoft release" "pyrit==1.1.0" "$(vapt_field pyrit 4)"
assert_not_contains "the BlackArch homonym is never resolved or planned" "$OUTPUT" "blackarch/pyrit"
pyrit_pipx="$(vapt_pipx_lines | grep -F 'pyrit==1.1.0' || true)"
assert_eq "PyRIT is planned exactly once" 1 "$(vapt_count "$pyrit_pipx" 'pyrit==1.1.0')"
assert_not_contains "PyRIT does not get the unconstrained system Python" "$pyrit_pipx" "--python /usr/bin/python "
coae_venv="$(grep -E '^DRYRUN: .*/uv venv ' <<<"$OUTPUT" || true)"
coae_pip="$(grep -E '^DRYRUN: .*/uv pip install ' <<<"$OUTPUT" || true)"
assert_contains "the COAE environment is CPython 3.12" "$coae_venv" "--python 3.12 $XDG_DATA_HOME/htb-coae"
for pin in torch==2.14.1 transformers==5.18.0 modelscan==0.8.8 textattack==0.3.11; do
    assert_contains "COAE pin $pin" "$coae_pip" " $pin"
done
assert_contains "COAE pins go into the COAE interpreter" "$coae_pip" "--python $XDG_DATA_HOME/htb-coae/bin/python "
assert_contains "the planned environment is recorded ok" "$OUTPUT" $'# environment\tok'

# --- provider identity: ProjectDiscovery tools are never Python homonyms -----
vapt_sandbox vapt-identity
vapt_root
vapt_repos "${VAPT_BASE[@]}" "$VAPT_BA_KEYRING" \
    "blackarch|katana-pd|1.0-1|https://github.com/JohnHammond/katana" \
    "extra|httpx|0.28.1-1|https://www.python-httpx.org/" \
    "extra|python-httpx|0.28.1-1|https://github.com/encode/httpx|httpx"
vapt_plan "identity" --groups htb-cwes
assert_eq "Python httpx under the exact name is refused" unavailable "$(vapt_field httpx 5)"
assert_eq "Python httpx is not planned" no "$(vapt_planned extra/httpx)"
assert_eq "a provider of the name is not planned" no "$(vapt_planned extra/python-httpx)"
assert_eq "katana-framework under katana-pd is refused" unavailable "$(vapt_field katana-pd 5)"
assert_eq "katana-framework is not planned" no "$(vapt_planned blackarch/katana-pd)"
vapt_repos "${VAPT_BASE[@]}" "$VAPT_BA_KEYRING" \
    "blackarch|httpx|1.7.1-1|https://github.com/projectdiscovery/httpx" \
    "blackarch|katana-pd|1.2.2-1|https://github.com/projectdiscovery/katana" \
    "extra|python-httpx|0.28.1-1|https://github.com/encode/httpx|httpx"
vapt_plan "identity confirmed" --groups htb-cwes
assert_eq "ProjectDiscovery httpx resolves (control)" blackarch/httpx "$(vapt_field httpx 4)"
assert_eq "ProjectDiscovery httpx is planned" yes "$(vapt_planned blackarch/httpx)"
assert_eq "ProjectDiscovery katana resolves (control)" blackarch/katana-pd "$(vapt_field katana-pd 4)"

# Membership lists (.pkgs) resolve names but prove neither identity nor
# closure safety: nothing is planned on them.
rm -f "$ROOT/var/lib/haseen/vapt/repositories.json"
mkdir -p "$ROOT/var/lib/pacman/sync"
printf 'blackarch-keyring\nhttpx\n' >"$ROOT/var/lib/pacman/sync/blackarch.pkgs"
printf 'nmap\n' >"$ROOT/var/lib/pacman/sync/extra.pkgs"
vapt_plan "membership only" --groups core,htb-cwes
assert_eq "membership cannot prove the httpx identity" unavailable "$(vapt_field httpx 5)"
assert_eq "membership still finds the pinned nmap" extra/nmap "$(vapt_field nmap 4)"
assert_eq "an unknown closure is skipped" skipped "$(vapt_field nmap 6)"
assert_eq "nothing is installed on membership alone" no "$(vapt_planned extra/nmap)"

# --- explicit repository pins come first; a missing pin falls through -------
vapt_sandbox vapt-pins
vapt_root
vapt_repos "${VAPT_BASE[@]}" "$VAPT_BA_KEYRING" \
    "extra|nmap|7.98-1|https://nmap.org/" "blackarch|nmap|7.99-1|https://nmap.org/"
vapt_plan "pins" --groups core
assert_eq "pinned nmap comes from extra over BlackArch" extra/nmap "$(vapt_field nmap 4)"
assert_eq "pinned nmap is planned" yes "$(vapt_planned extra/nmap)"
assert_eq "BlackArch nmap is not planned" no "$(vapt_planned blackarch/nmap)"
vapt_repos "${VAPT_BASE[@]}" "$VAPT_BA_KEYRING" "blackarch|nmap|7.99-1|https://nmap.org/"
vapt_plan "pin missing" --groups core
assert_eq "a missing pin falls through to BlackArch" blackarch/nmap "$(vapt_field nmap 4)"
assert_contains "the missing pin is reported" "$(vapt_field nmap 7)" "pin missing"

# --- native adapters: one logical identity across groups --------------------
vapt_sandbox vapt-native
vapt_root
vapt_repos "${VAPT_BASE[@]}" "$VAPT_BA_KEYRING"
vapt_system_python
vapt_plan "htb-cpts,ad" --groups htb-cpts,ad
assert_eq "netexec is one report row" 1 "$(awk -F'\t' '$1 == "netexec"' <<<"$OUTPUT" | grep -c . || true)"
assert_eq "netexec lists both groups" "htb-cpts,ad" "$(vapt_field netexec 2)"
assert_eq "netexec falls back to its native adapter" native "$(vapt_field netexec 3)"
nx_pipx="$(vapt_pipx_lines | grep -F 'NetExec' || true)"
assert_eq "netexec is installed once" 1 "$(vapt_count "$nx_pipx" NetExec)"
assert_contains "netexec is pinned to the release commit" "$nx_pipx" \
    "git+https://github.com/Pennyw0rth/NetExec@c7dc286ba65daf10402cdc470e531b84e6d3d911"
assert_eq "impacket is installed once" 1 "$(vapt_count "$(vapt_pipx_lines)" 'impacket==')"
vapt_plan "htb-cpts alone" --groups htb-cpts
assert_eq "the adapter serves a group other than its own row's" native "$(vapt_field netexec 3)"
assert_eq "a group outside the selection is not recorded" htb-cpts "$(vapt_field netexec 2)"
vapt_plan "core twice" --groups core,core
assert_eq "a repeated group is one membership" core "$(vapt_field nmap 2)"
vapt_repos "${VAPT_BASE[@]}" "$VAPT_BA_KEYRING" "blackarch|netexec|1.4.0-1|https://github.com/Pennyw0rth/NetExec"
vapt_plan "BlackArch netexec" --groups ad
assert_eq "BlackArch precedes the native adapter" blackarch/netexec "$(vapt_field netexec 4)"
assert_eq "no pipx install when BlackArch provides it" "" "$(vapt_pipx_lines | grep -F NetExec || true)"

# --- native store ownership: conflicts are preserved, owned drift reinstalled -
native_case() {
    vapt_root
    vapt_repos "${VAPT_BASE[@]}" "$VAPT_BA_KEYRING" "$WHOIS"
    vapt_system_python
    STORE="$ROOT$XDG_DATA_HOME/haseen/vapt/pipx"
}
sherlock_pipx() { vapt_pipx_lines | grep -F -- "$SHERLOCK_SPEC" || true; }
vapt_sandbox vapt-native-store
native_case
vapt_plan "fresh store" --groups osint
assert_contains "a fresh adapter is planned" "$(sherlock_pipx)" " $SHERLOCK_SPEC"
assert_not_contains "a fresh adapter is not forced" "$(sherlock_pipx)" "--force"
native_case
mkdir -p "$STORE/bin"
printf '#!/bin/sh\n' >"$STORE/bin/sherlock"
vapt_plan "user executable" --groups osint
assert_eq "a user's executable in the store is preserved" "" "$(sherlock_pipx)"
assert_eq "the conflict is skipped, not failed" skipped "$(vapt_field sherlock 6)"
native_case
mkdir -p "$STORE/venvs/sherlock-project"
vapt_plan "unowned venv" --groups osint
assert_eq "an unowned environment is never reinstalled" "" "$(sherlock_pipx)"
native_case
vapt_native_env "$STORE" sherlock-project "$SHERLOCK_SPEC" sherlock 0.15.0
rm "$STORE/owned/sherlock"
ln -s "$SANDBOX/elsewhere" "$STORE/owned/sherlock"
vapt_plan "symlinked owner record" --groups osint
assert_eq "a symlinked ownership record proves nothing" "" "$(sherlock_pipx)"
native_case
vapt_native_env "$STORE" sherlock-project "$SHERLOCK_SPEC" sherlock 0.15.0
printf '%s\n' "$SHERLOCK_SPEC" >"$STORE/owned/sherlock"
vapt_plan "owned drift" --groups osint
assert_contains "owned drift is reinstalled at the pin" "$(sherlock_pipx)" "--force $SHERLOCK_SPEC"
native_case
vapt_native_env "$STORE" sherlock-project "$SHERLOCK_SPEC" sherlock "${SHERLOCK_SPEC#*==}"
printf '%s\n' "$SHERLOCK_SPEC" >"$STORE/owned/sherlock"
vapt_plan "exact" --groups osint
assert_eq "an exact adapter is already-exact" already-exact "$(vapt_field sherlock 6)"
assert_eq "an exact adapter is not reinstalled" "" "$(sherlock_pipx)"
native_case
mkdir -p "$SANDBOX/real-haseen" "$ROOT$XDG_DATA_HOME"
ln -s "$SANDBOX/real-haseen" "$ROOT$XDG_DATA_HOME/haseen"
vapt_plan "symlinked store" --groups osint
assert_eq "a symlinked store ancestor is preserved" "" "$(sherlock_pipx)"

# --- closure policy: no Omarchy, no service activation, allowlisted repos ----
vapt_sandbox vapt-closure
vapt_root
vapt_conf_add $'[omarchy]\nServer = https://pkgs.omarchy.org/$arch'
vapt_repos "${VAPT_BASE[@]}" "$VAPT_BA_KEYRING" \
    "extra|proxychains-ng|4.17-1|https://github.com/rofl0r/proxychains-ng" \
    "extra|libpcap|1.10.5-1|https://www.tcpdump.org/" \
    "extra|tcpdump|4.99.5-1|https://www.tcpdump.org/||omarchy-hooks" \
    "extra|socat|1.8.0.3-1|http://www.dest-unreach.org/socat/|||post_install() { systemctl enable --now socat.service; }" \
    "extra|metasploit|6.4.90-1|https://www.metasploit.com/|||post_install() { systemctl reenable metasploit.service; }" \
    "extra|wireshark-cli|4.4.9-1|https://www.wireshark.org/||libpcap" \
    "extra|openbsd-netcat|1.229-1|https://salsa.debian.org/debian/netcat-openbsd||libretls" \
    "omarchy|libretls|3.8.1-1|https://git.causal.agency/libretls/" \
    "omarchy|chisel|1.10.1-1|https://github.com/jpillora/chisel"
vapt_installed "omarchy-pcap|1-1|https://omarchy.org/|libpcap"
vapt_plan "closure" --groups core
assert_eq "a clean closure is planned (control)" yes "$(vapt_planned extra/proxychains-ng)"
for t in tcpdump wireshark-cli openbsd-netcat; do
    assert_eq "$t: unsafe closure skipped" skipped "$(vapt_field "$t" 6)"
    assert_eq "$t: unsafe closure not planned" no "$(vapt_planned "extra/$t")"
done
assert_eq "a non-allowlisted repository is never a source" unavailable "$(vapt_field chisel 5)"
assert_not_contains "nothing from the Omarchy repository" "$OUTPUT" "omarchy/"
assert_not_contains "no AUR helper" "$OUTPUT" "paru"
assert_not_contains "no AUR helper (yay)" "$OUTPUT" "yay "
assert_not_contains "no package build" "$OUTPUT" "makepkg"
assert_not_contains "no service is enabled" "$OUTPUT" "systemctl"

# An Omarchy package providing android-tools from Chaotic must neither be
# chosen nor shadow the genuine Arch package.
vapt_sandbox vapt-omarchy-provider
vapt_root
vapt_conf_add $'[chaotic-aur]\nServer = https://cdn-mirror.chaotic.cx/$repo/$arch'
vapt_repos "${VAPT_BASE[@]}" "$VAPT_BA_KEYRING" \
    "chaotic-aur|chaotic-keyring|20250101-1|https://aur.chaotic.cx/" \
    "chaotic-aur|omarchy-android-tools|1-1|https://github.com/basecamp/omarchy|android-tools" \
    "chaotic-aur|omarchy-apktool|1-1|https://github.com/basecamp/omarchy|android-apktool" \
    "extra|android-tools|35.0.2-1|https://developer.android.com/tools/releases/platform-tools"
vapt_plan "omarchy provider" --groups mobile
assert_not_contains "android-tools never resolves to an Omarchy package" "$(vapt_field android-tools 3) $(vapt_field android-tools 4)" "omarchy"
assert_eq "the genuine android-tools is planned" yes "$(vapt_planned extra/android-tools)"
# attempted_tiers may name the unselected oniomarchy tier; source and target may not.
assert_not_contains "android-apktool never resolves to an Omarchy package" "$(vapt_field android-apktool 3) $(vapt_field android-apktool 4)" "omarchy"

# Already-enabled Chaotic is a source only with its keyring canary.
vapt_sandbox vapt-chaotic
vapt_root
vapt_conf_add $'[chaotic-aur]\nServer = https://cdn-mirror.chaotic.cx/$repo/$arch'
vapt_repos "${VAPT_BASE[@]}" "$VAPT_BA_KEYRING" "chaotic-aur|ligolo-ng|0.8.2-1|https://github.com/nicocha30/ligolo-ng"
vapt_plan "chaotic without keyring" --groups core
assert_eq "unverified Chaotic is not a source" unavailable "$(vapt_field ligolo-ng 5)"
vapt_repos "${VAPT_BASE[@]}" "$VAPT_BA_KEYRING" "chaotic-aur|ligolo-ng|0.8.2-1|https://github.com/nicocha30/ligolo-ng" \
    "chaotic-aur|chaotic-keyring|20250101-1|https://aur.chaotic.cx/"
vapt_plan "chaotic with keyring" --groups core
assert_eq "enabled Chaotic with its keyring is a source (control)" chaotic-aur/ligolo-ng "$(vapt_field ligolo-ng 4)"

# --- missing, unknown or unsafe sources: report and continue -----------------
vapt_sandbox vapt-sources
vapt_root
printf '[options]\nArchitecture = auto\n\n[core]\nServer = https://geo.mirror.pkgbuild.com/$repo/os/$arch\n\n[extra]\nServer = https://geo.mirror.pkgbuild.com/$repo/os/$arch\n' \
    >"$ROOT/etc/pacman.conf"
vapt_repos "${VAPT_BASE[@]}" "$WHOIS"
vapt_plan "no BlackArch" --groups osint,network
assert_eq "an available tool resolves" yes "$(vapt_planned extra/whois)"
assert_eq "an unavailable tool is reported" unavailable "$(vapt_field masscan 5)"
assert_eq "an unavailable tool is skipped" skipped "$(vapt_field masscan 6)"
assert_contains "the report is still written" "$OUTPUT" "DRYRUN: write $XDG_STATE_HOME/haseen/vapt/report.tsv"

printf '[options]\nArchitecture = auto\n\n[core]\nInclude = /etc/pacman.d/mirrorlist\n\n[extra]\nInclude = /etc/pacman.d/mirrorlist\n' \
    >"$ROOT/etc/pacman.conf"
vapt_api install --groups osint
assert_status "unreadable source configuration refuses before mutation" 1 "$STATUS"
assert_eq "unreadable sources invoke no manager" "" "$(ls -A "$CALLS")"

vapt_root
vapt_repos "${VAPT_BASE[@]}" "$WHOIS" "blackarch|masscan|1.3.2-1|https://github.com/robertdavidgraham/masscan"
vapt_plan "unverified BlackArch stanza" --groups network
assert_eq "an existing stanza without its keyring is not a source" unavailable "$(vapt_field masscan 5)"
assert_not_contains "an existing stanza is not re-bootstrapped" "$OUTPUT" "blackarch.org"
assert_not_contains "an existing stanza is not rewritten" "$OUTPUT" "append to /etc/pacman.conf"

vapt_root
printf '[options]\nArchitecture = auto\n\n[core]\nServer = https://geo.mirror.pkgbuild.com/$repo/os/$arch\n\n[extra]\nSigLevel = Optional TrustAll\nServer = https://geo.mirror.pkgbuild.com/$repo/os/$arch\n\n[blackarch]\nServer = https://blackarch.org/blackarch/$repo/os/$arch\n' \
    >"$ROOT/etc/pacman.conf"
vapt_repos "${VAPT_BASE[@]}" "$VAPT_BA_KEYRING" "extra|nmap|7.98-1|https://nmap.org/" "blackarch|nmap|7.99-1|https://nmap.org/"
vapt_plan "unsigned extra" --groups core
assert_eq "an unsigned repository is not a source, even pinned" blackarch/nmap "$(vapt_field nmap 4)"
assert_eq "nothing from the unsigned repository" no "$(vapt_planned extra/nmap)"

# --- the full plan: write-free, offline, one row and one install per identity -
vapt_sandbox vapt-all
vapt_root
vapt_repos "${VAPT_BASE[@]}" "$VAPT_BA_KEYRING" "$WHOIS" \
    "extra|nmap|7.98-1|https://nmap.org/" "extra|jq|1.8.1-1|https://jqlang.github.io/jq/" \
    "blackarch|masscan|1.3.2-1|https://github.com/robertdavidgraham/masscan"
before="$(vapt_tree)"
vapt_plan "--all" --all
assert_eq "--all writes nothing anywhere" "$before" "$(vapt_tree)"
vapt_tools_untouched "--all"
assert_eq "no logical tool has two report rows" "" \
    "$(awk -F'\t' 'NF == 8 && $1 !~ /^[# ]/ && $1 != "logical" { print $1 }' <<<"$OUTPUT" | LC_ALL=C sort | uniq -d)"
assert_eq "no adapter is installed twice" "" "$(vapt_pipx_lines | awk '{ print $NF }' | LC_ALL=C sort | uniq -d)"
assert_eq "a shared prerequisite is installed once" 1 "$(vapt_count "$OUTPUT" ' <audited-archives-of:extra/python-pipx>')"
assert_not_contains "no service is enabled or started" "$OUTPUT" "systemctl"
assert_not_contains "no AUR helper" "$OUTPUT" "paru"
capture env HASEEN_SYSROOT="$ROOT" haseen layer apply vapt --dry-run -- --groups osint </dev/null
assert_status "the layer interface takes the same selection" 0 "$STATUS"
assert_eq "the layer interface resolves the same way" extra/whois "$(vapt_field whois 4)"

# --- status: the recorded state, re-verified against metadata ---------------
vapt_sandbox vapt-status
vapt_root
vapt_repos "${VAPT_BASE[@]}" "$VAPT_BA_KEYRING" "$WHOIS" "blackarch|masscan|1.3.2-1|https://github.com/robertdavidgraham/masscan"
vapt_installed "whois|5.6.4-1|https://github.com/rfc1036/whois" \
    "masscan|1.3.2-1|https://github.com/robertdavidgraham/masscan"
STATUS_LINK="$ROOT$VAPT_LINK"
mkdir -p "${STATUS_LINK%/*}"
ln -s "$VAPT_FRAGMENT" "$STATUS_LINK"
ROW_WHOIS=$'whois\tosint\textra\textra/whois\tresolved\tinstalled\texplicit repository pin\tblackarch,native,chaotic-aur,core,extra'
TAIL=$'# environment\tok\n# source\tobserved\n# mutation-failed\t0'

vapt_cli status
assert_status "status before any apply: not applied" 1 "$STATUS"
vapt_tools_untouched "status"

vapt_report_put "$ROW_WHOIS"$'\n'"$TAIL"
vapt_cli status
assert_status "healthy recorded state is ok" 0 "$STATUS"

vapt_report_put "$ROW_WHOIS"$'\n'"${TAIL/$'mutation-failed\t0'/$'mutation-failed\t1'}"
vapt_cli status
assert_status "a recorded mutation failure is degraded" 2 "$STATUS"
vapt_report_put "$ROW_WHOIS"$'\n'"${TAIL/$'environment\tok'/$'environment\tdegraded'}"
vapt_cli status
assert_status "a degraded environment is degraded" 2 "$STATUS"
vapt_report_put "$ROW_WHOIS"$'\n'"$TAIL"$'\n# infrastructure\tpython-pipx\textra/python-pipx\tfailed'
vapt_cli status
assert_status "a failed prerequisite is degraded" 2 "$STATUS"
vapt_report_put $'masscan\tnetwork\tnone\t-\tunavailable\tskipped\tno source\tblackarch'$'\n'"$ROW_WHOIS"$'\n'"$TAIL"
vapt_cli status
assert_status "an unavailable item is not success" 2 "$STATUS"
assert_contains "the unavailable item is listed" "$OUTPUT" "masscan"

vapt_report_put "$ROW_WHOIS"$'\n'"$TAIL"
vapt_installed "whois|5.6.3-1|https://github.com/rfc1036/whois"
vapt_cli status
assert_status "an installed version that drifted from the repository is degraded" 2 "$STATUS"
vapt_installed "whois|5.6.4-1|https://example.org/another-whois"
vapt_cli status
assert_status "an installed homonym from another upstream is degraded" 2 "$STATUS"

vapt_installed "masscan|1.3.2-1|https://github.com/robertdavidgraham/masscan"
vapt_repos "${VAPT_BASE[@]}" "blackarch|masscan|1.3.2-1|https://github.com/robertdavidgraham/masscan"
vapt_report_put $'masscan\tnetwork\tblackarch\tblackarch/masscan\tresolved\tinstalled\tok\tblackarch'$'\n'"$TAIL"
vapt_cli status
assert_status "a source that lost its keyring canary is degraded" 2 "$STATUS"

vapt_repos "${VAPT_BASE[@]}" "$VAPT_BA_KEYRING" "$WHOIS"
vapt_installed "whois|5.6.4-1|https://github.com/rfc1036/whois"
vapt_report_put "$ROW_WHOIS"$'\n'"$TAIL"
rm -f "$STATUS_LINK"
vapt_cli status
assert_status "a missing activation link is degraded" 2 "$STATUS"
ln -s "$VAPT_FRAGMENT" "$STATUS_LINK"

# Native rows are re-read from pipx metadata: version, VCS commit, recorded
# specification, the executable path and ownership of the environment.
STORE="$ROOT$XDG_DATA_HOME/haseen/vapt/pipx"
nx_status() { # LABEL EXPECTED_EXIT [REPORT_TARGET]
    vapt_report_put "netexec"$'\tad\tnative\t'"${3:-$NETEXEC_SPEC}"$'\tresolved\tinstalled\texact\tblackarch,native\n'"$TAIL"
    vapt_cli status
    assert_status "native status: $1" "$2" "$STATUS"
    if [[ $2 == 0 ]]; then
        assert_not_contains "native status: $1 (no netexec warning)" "$OUTPUT" "warn: netexec"
    else
        assert_contains "native status: $1 (netexec warned)" "$OUTPUT" "warn: netexec"
    fi
    vapt_tools_untouched "native status: $1"
}
vapt_native_env "$STORE" netexec "$NETEXEC_SPEC" netexec 1.4.0
nx_status "exact pinned commit" 0
nx_status "report records a superseded pin" 2 "git+https://github.com/Pennyw0rth/NetExec@0123456789abcdef0123456789abcdef01234567"
rm -rf "$STORE"
vapt_native_env "$STORE" netexec "$NETEXEC_SPEC" netexec 1.4.0 \
    "git+https://github.com/Pennyw0rth/NetExec@0123456789abcdef0123456789abcdef01234567"
nx_status "installed from another commit" 2
rm -rf "$STORE"
vapt_native_env "$STORE" netexec "netexec" netexec 1.4.0 "$NETEXEC_SPEC"
nx_status "pipx recorded an unpinned spec" 2
rm -rf "$STORE"
vapt_native_env "$STORE" netexec "$NETEXEC_SPEC" netexec 1.4.0
mkdir -p "$STORE/venvs/netexec/lib/python3.14/site-packages/netexec-1.3.0.dist-info"
printf 'Metadata-Version: 2.1\nName: NetExec\nVersion: 1.3.0\n\n' \
    >"$STORE/venvs/netexec/lib/python3.14/site-packages/netexec-1.3.0.dist-info/METADATA"
nx_status "two distributions claim the name" 2
rm -rf "$STORE"
vapt_native_env "$STORE" netexec "$NETEXEC_SPEC" netexec 1.4.0
mkdir -p "$STORE/venvs/other/bin"
_vapt_stub_log "$STORE/venvs/other/bin/netexec" native-other
ln -sfn ../venvs/other/bin/netexec "$STORE/bin/netexec"
nx_status "the executable belongs to another environment" 2
rm -rf "$STORE"
vapt_native_env "$STORE" netexec "$NETEXEC_SPEC" netexec 1.4.0
mv "$STORE/venvs/netexec" "$SANDBOX/netexec-elsewhere"
ln -s "$SANDBOX/netexec-elsewhere" "$STORE/venvs/netexec"
nx_status "the environment is a symlink" 2
rm -rf "$STORE"
vapt_native_env "$STORE" sherlock-project "$SHERLOCK_SPEC" sherlock 0.15.0
vapt_report_put "sherlock"$'\tosint\tnative\t'"$SHERLOCK_SPEC"$'\tresolved\tinstalled\texact\tblackarch,native\n'"$TAIL"
vapt_cli status
assert_status "native status: version drift" 2 "$STATUS"
assert_contains "native status: version drift warned" "$OUTPUT" "warn: sherlock"

# Provider uniqueness and exact-name precedence are consumer resolution rules.
vapt_sandbox vapt-provider-boundaries
vapt_root
vapt_repos "${VAPT_BASE[@]}" "$VAPT_BA_KEYRING" \
    'core|ligolo-compat|1-1|https://github.com/nicocha30/ligolo-ng|ligolo-ng' \
    'extra|ligolo-ng|0.8.2-1|https://github.com/nicocha30/ligolo-ng'
vapt_plan 'Arch exact beats earlier-tier provider' --groups core
assert_eq 'extra exact wins over core provider' extra/ligolo-ng "$(vapt_field ligolo-ng 4)"
vapt_repos "${VAPT_BASE[@]}" "$VAPT_BA_KEYRING" \
    'extra|ligolo-one|1-1|https://github.com/nicocha30/ligolo-ng|ligolo-ng' \
    'extra|ligolo-two|1-1|https://github.com/nicocha30/ligolo-ng|ligolo-ng'
vapt_plan 'ambiguous providers' --groups core
assert_eq 'two providers never picked arbitrarily' unavailable "$(vapt_field ligolo-ng 5)"
vapt_repos "${VAPT_BASE[@]}" "$VAPT_BA_KEYRING" \
    'extra|ligolo-one|1-1|https://github.com/nicocha30/ligolo-ng|ligolo-ng'
vapt_plan 'one provider' --groups core
assert_eq 'unique binary provider resolves' extra/ligolo-one "$(vapt_field ligolo-ng 4)"
vapt_conf_add $'[cachyos-extra-v3]\nServer = https://mirror.cachyos.org/repo/$arch/$repo'
vapt_repos "${VAPT_BASE[@]}" "$VAPT_BA_KEYRING" \
    'cachyos-extra-v3|ligolo-ng|0.8.2-1|https://github.com/nicocha30/ligolo-ng' \
    'extra|ligolo-ng|0.8.2-1|https://github.com/nicocha30/ligolo-ng' \
    'cachyos-extra-v3|sherlock-project|0.16.0-1|https://github.com/sherlock-project/sherlock'
vapt_plan 'CachyOS binary tier' --groups core,osint
assert_eq 'enabled CachyOS precedes Arch' cachyos-extra-v3/ligolo-ng "$(vapt_field ligolo-ng 4)"
assert_eq 'global native fallback precedes CachyOS' native "$(vapt_field sherlock 3)"

# Exact metadata cannot approve an executable outside the owned environment,
# a dangling base interpreter, or absent authority. Never run either payload.
vapt_sandbox vapt-native-containment
vapt_root
vapt_repos "${VAPT_BASE[@]}" "$VAPT_BA_KEYRING"
STORE="$ROOT$XDG_DATA_HOME/haseen/vapt/pipx"
NATIVE_SPEC="$(vapt_native_spec sherlock)"
native_observed() {
    capture python3 "$VAPT_META" native "$STORE" sherlock "$NATIVE_SPEC" sherlock --root "$ROOT"
}
vapt_native_env "$STORE" sherlock-project "$NATIVE_SPEC" sherlock "${NATIVE_SPEC#*==}"
native_observed
assert_eq 'exact metadata, authority and executable control' exact "$OUTPUT"
rm "$STORE/venvs/sherlock-project/bin/sherlock"
_vapt_stub_log "$ROOT/outside" native-outside
ln -s /outside "$STORE/venvs/sherlock-project/bin/sherlock"
native_observed
assert_eq 'outside executable rejected' drifted "$OUTPUT"
vapt_plan 'outside executable is not exact' --groups osint
assert_eq 'outside executable remains conflict, not already-exact' skipped "$(vapt_field sherlock 6)"
rm -rf "$STORE"
vapt_native_env "$STORE" sherlock-project "$NATIVE_SPEC" sherlock "${NATIVE_SPEC#*==}"
mkdir -p "$ROOT${VAPT_LINK%/*}"
ln -s "$VAPT_FRAGMENT" "$ROOT$VAPT_LINK"
vapt_report_put "sherlock"$'\tosint\tnative\t'"$NATIVE_SPEC"$'\tresolved\talready-exact\texact\tblackarch,native\n# environment\tok\n# mutation-failed\t0'
vapt_cli status
assert_status 'complete native interpreter supports healthy consumer status' 0 "$STATUS"
rm "$STORE/venvs/sherlock-project/bin/python"
ln -s /missing-python "$STORE/venvs/sherlock-project/bin/python"
vapt_cli status
assert_status 'missing base interpreter cannot claim healthy consumer status' 2 "$STATUS"
assert_contains 'missing base interpreter is diagnosed for the native tool' "$OUTPUT" 'warn: sherlock'
before="$(find "$STORE" -printf '%P %y %m %s %T@ %l\n' | LC_ALL=C sort)"
vapt_plan 'missing base interpreter is preserved without manager execution' --groups osint
assert_eq 'missing base interpreter is not accepted as already-exact' skipped "$(vapt_field sherlock 6)"
assert_eq 'missing base interpreter invokes no native install' '' "$(sherlock_pipx)"
assert_eq 'missing base interpreter environment remains unchanged' "$before" \
    "$(find "$STORE" -printf '%P %y %m %s %T@ %l\n' | LC_ALL=C sort)"
rm -rf "$STORE"
vapt_native_env "$STORE" sherlock-project "$NATIVE_SPEC" sherlock "${NATIVE_SPEC#*==}"
rm "$STORE/owned/sherlock"
native_observed
assert_eq 'unowned exact distribution does not become managed' unknown "$OUTPUT"
vapt_tools_untouched containment

# The PyPI impacket adapter exposes upstream smbserver.py, not distro aliases.
vapt_sandbox vapt-impacket-probe
vapt_root
vapt_repos "${VAPT_BASE[@]}" "$VAPT_BA_KEYRING"
STORE="$ROOT$XDG_DATA_HOME/haseen/vapt/pipx"
IMPACKET_SPEC="$(vapt_native_spec impacket)"
vapt_native_env "$STORE" impacket "$IMPACKET_SPEC" smbserver.py "${IMPACKET_SPEC#*==}"
vapt_plan 'upstream impacket script' --groups htb-cpts
assert_eq 'upstream script satisfies adapter' already-exact "$(vapt_field impacket 6)"
assert_eq 'exact impacket not reinstalled' '' "$(vapt_pipx_lines | grep -F "$IMPACKET_SPEC" || true)"
rm "$STORE/bin/smbserver.py"
ln -s ../venvs/impacket/bin/smbserver.py "$STORE/bin/impacket-smbserver"
vapt_plan 'distro-only impacket alias' --groups htb-cpts
assert_not_contains 'distro alias does not falsely satisfy native probe' "$(vapt_row impacket)" $'\talready-exact\t'
vapt_tools_untouched impacket

# Actual CLI owns errexit: refusing unsafe reports cannot write layer markers.
vapt_sandbox vapt-cli-report-failure
vapt_root
vapt_repos "${VAPT_BASE[@]}" "$VAPT_BA_KEYRING"
mkdir -p "$ROOT$VAPT_STATE"
printf 'keep me\n' >"$SANDBOX/private"
ln -s "$SANDBOX/private" "$ROOT$VAPT_STATE/report.tsv"
vapt_api install --groups osint
assert_status 'actual CLI report refusal propagates' 1 "$STATUS"
assert_eq 'actual CLI report refusal preserves victim' 'keep me' "$(cat "$SANDBOX/private")"
assert_eq 'actual CLI failed layer invokes no mutator/marker writer' '' "$(ls -A "$CALLS")"

# Malformed inventory/native pin refusal happens before any layer mutation.
for kind in manifest native; do
    vapt_sandbox "vapt-precheck-$kind"
    vapt_root
    tree="$SANDBOX/share"
    mkdir -p "$tree/layers"
    ln -s "$HASEEN_PATH/lib" "$tree/lib"
    ln -s "$HASEEN_PATH/default" "$tree/default"
    cp -R "$VAPT_LAYER" "$tree/layers/vapt"
    case "$kind" in
    manifest) printf 'bad/package\n' >>"$tree/layers/vapt/packages/security/core.txt" ;;
    native) printf 'security/ad\tnetexec\tnetexec\tpipx\tgit+https://github.com/Pennyw0rth/NetExec@main\tnetexec\n' \
        >>"$tree/layers/vapt/packages/security/native.tsv" ;;
    esac
    before="$(vapt_tree)"
    capture env HASEEN_PATH="$tree" HASEEN_SYSROOT="$ROOT" haseen vapt install --groups core </dev/null
    assert_status "$kind malformed precheck" 2 "$STATUS"
    assert_eq "$kind refusal writes nothing" "$before" "$(vapt_tree)"
    assert_eq "$kind refusal invokes no mutator" '' "$(ls -A "$CALLS")"
done

# A compatible allowed system interpreter keeps Microsoft PyRIT independent
# of an unmanaged COAE environment; metadata alone decides, never --version.
vapt_sandbox vapt-pyrit-system-interpreter
vapt_root
vapt_repos "${VAPT_BASE[@]}" "$VAPT_BA_KEYRING"
coae="$ROOT$XDG_DATA_HOME/htb-coae"
mkdir -p "$coae/bin" "$ROOT/usr/bin"
printf 'version_info = 3.13.1\n' >"$coae/pyvenv.cfg"
_vapt_stub_log "$coae/bin/python" coae-python
_vapt_stub_log "$ROOT/usr/bin/python3.14" native-system-python
ln -s python3.14 "$ROOT/usr/bin/python"
vapt_plan 'no allowed interpreter evidence' --groups htb-coae
assert_eq 'unmanaged incompatible COAE cannot authorize PyRIT' skipped "$(vapt_field pyrit 6)"
assert_eq 'no PyRIT manager command without interpreter evidence' '' "$(vapt_pipx_lines | grep -F pyrit== || true)"
vapt_installed 'python|3.14.0-1|https://www.python.org/'
vapt_plan 'allowed compatible system Python' --groups htb-coae
assert_contains 'PyRIT independently uses system interpreter' "$(vapt_pipx_lines | grep -F pyrit== || true)" '--python /usr/bin/python'
assert_not_contains 'PyRIT never borrows unmanaged COAE' "$(vapt_pipx_lines | grep -F pyrit== || true)" 'htb-coae/bin/python'
vapt_installed 'python|3.14.0-1|https://example.org/custom-python'
vapt_plan 'custom interpreter provenance' --groups htb-coae
assert_eq 'compatible custom interpreter still refused' skipped "$(vapt_field pyrit 6)"
vapt_tools_untouched 'PyRIT interpreter gate'

vapt_sandbox vapt-source-malformed-json
vapt_root
printf '{ malformed\n' >"$ROOT/var/lib/haseen/vapt/repositories.json"
before="$(vapt_tree)"
vapt_api install --groups core
assert_status 'malformed source metadata refuses before mutation' 1 "$STATUS"
assert_eq 'malformed source metadata writes nothing' "$before" "$(vapt_tree)"
assert_eq 'malformed source metadata invokes no manager' '' "$(ls -A "$CALLS")"
