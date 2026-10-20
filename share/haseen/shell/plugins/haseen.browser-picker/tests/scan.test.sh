#!/bin/bash
# Adapted from test/test_scan.sh of the owner's fork t1nk33r.browser-picker of
# K53N0/omarchy-browser-picker (MIT, Copyright (c) 2026 K53N0); see ../LICENSE.
# haseen: runs bin/haseen-browser-scan, the seam is HASEEN_BROWSER_DESKTOP_DIRS,
# and the picker's own entries are haseen-browser-picker and the fork's.
# tests/test-browser-picker.sh runs it.
# Checks browser-picker-scan against a fake HOME and a fake desktop-entry tree,
# so the assertions do not depend on which browsers the machine running them
# happens to have.
#
#   bash test/test_scan.sh
#
# Discovery is desktop-entry driven (see bin/browser-picker-scan), so the
# fixture is two applications directories plus the config dirs the entries
# should be attributed to. HASEEN_BROWSER_DESKTOP_DIRS is the seam that keeps
# the host's own /usr/share/applications out of the run.

set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# BROWSER_PICKER_SCAN runs the same fixture against a different scanner, which
# is how the fork's new cases were shown to fail against the pre-fork one.
SCAN="${BROWSER_PICKER_SCAN:-$HERE/../../../../../../bin/haseen-browser-scan}"

passed=0
failed=0
# Soft failures exist for one purpose: running the whole suite against another
# scanner and seeing every case it misses at once, rather than the first.
fail() {
  echo "FAIL: $1"
  echo "      $2"
  failed=$((failed + 1))
  [[ -n ${BROWSER_PICKER_SOFT_FAIL:-} ]] || exit 1
}
ok() { passed=$((passed + 1)); }

fake=$(mktemp -d)
trap 'rm -rf "$fake"' EXIT

sys="$fake/usr/share/applications"
user="$fake/home/.local/share/applications"
mkdir -p "$sys" "$user" "$fake/bin"

entry() { # dir id body...
  local dir=$1 id=$2
  shift 2
  { echo "[Desktop Entry]"; echo "Type=Application"; printf '%s\n' "$@"; } >"$dir/$id.desktop"
}

stub() { # name
  printf '#!/bin/sh\nexit 0\n' >"$fake/bin/$1"
  chmod +x "$fake/bin/$1"
}

WEB="MimeType=text/html;x-scheme-handler/http;x-scheme-handler/https;"

# --- The fixture ------------------------------------------------------------

# A Local State with two identically-named profiles and one with no name at all,
# which is what Opera writes.
mkdir -p "$fake/home/.config/chromium"
cat >"$fake/home/.config/chromium/Local State" <<'JSON'
{"profile":{"info_cache":{
  "Default":   {"name":"acme-client"},
  "Profile 7": {"name":"acme-client"},
  "Profile 9": {"name":""},
  "Profile 3": {"name":"He said \"hi\""}
}}}
JSON
entry "$sys" chromium "Name=Chromium" "Exec=/usr/bin/chromium %U" "$WEB"
stub chromium
# The Exec is absolute in the entry, so the stub has to be reachable there too.
mkdir -p "$fake/usr/bin"
cp "$fake/bin/chromium" "$fake/usr/bin/chromium"
sed -i "s|Exec=/usr/bin/chromium|Exec=$fake/usr/bin/chromium|" "$sys/chromium.desktop"

# Helium: the binary is `helium-browser`, the config dir is `net.imput.helium`,
# and nothing about either name spells the other. This is the case upstream's
# allow-list could not express — its row wanted bin `helium` and dir `helium`.
mkdir -p "$fake/home/.config/net.imput.helium/Default"
echo '{"profile":{"info_cache":{"Default":{"name":"You"}}}}' \
  >"$fake/home/.config/net.imput.helium/Local State"
entry "$sys" helium "Name=Helium Browser" "Exec=helium-browser %U" "$WEB"
stub helium-browser

# A Flatpak export: file-forwarding markers, an app id that is not a binary,
# and a config dir under ~/.var/app.
mkdir -p "$fake/home/.var/app/com.brave.Browser/config/BraveSoftware/Brave-Browser"
echo '{"profile":{"info_cache":{"Default":{"name":"Personal"},"Profile 2":{"name":"Work"}}}}' \
  >"$fake/home/.var/app/com.brave.Browser/config/BraveSoftware/Brave-Browser/Local State"
entry "$user" com.brave.Browser "Name=Brave" \
  "Exec=$fake/bin/flatpak run --branch=stable --arch=x86_64 --command=brave --file-forwarding com.brave.Browser @@u %U @@" \
  "X-Flatpak=com.brave.Browser" "$WEB"
stub flatpak

# Firefox family: profiles.ini, and a dir the name cannot reach (`.mozilla`).
mkdir -p "$fake/home/.mozilla/firefox"
cat >"$fake/home/.mozilla/firefox/profiles.ini" <<'INI'
[Profile0]
Name=default-release
Path=abc.default-release

[Profile1]
Name=Testing
Path=xyz.testing

[General]
StartWithLastProfile=1
INI
entry "$sys" firefox "Name=Firefox" "Exec=firefox %u" "$WEB"
stub firefox

# An uncurated browser whose config dir name relates to nothing but its own
# reverse-DNS id: found by the marker scan, family read off `Profile *`.
mkdir -p "$fake/home/.config/org.example.quokka/Profile 4"
entry "$sys" quokka "Name=Quokka Browser" "Exec=quokka-browser %U" "$WEB"
stub quokka-browser

# A browser with no attributable config dir at all: still one plain row.
entry "$sys" nomad "Name=Nomad" "Exec=nomad-browser" "$WEB"
stub nomad-browser

# Two binaries, one config dir: only one of them may be listed.
entry "$sys" ungoogled-chromium "Name=Ungoogled Chromium" \
  "Exec=$fake/usr/bin/ungoogled-chromium %U" "$WEB"
cp "$fake/bin/chromium" "$fake/usr/bin/ungoogled-chromium"

# Must never appear: the picker itself, which is the registered default browser
# and therefore guaranteed to be in this tree.
entry "$user" browser-picker "Name=Browser Picker" \
  "Exec=$HERE/../bin/browser-picker %U" "$WEB"
entry "$user" t1nk33r-browser-picker "Name=Browser Picker (t1nk33r)" \
  "Exec=$HERE/../bin/browser-picker %U" "$WEB"
entry "$user" haseen-browser-picker "Name=Browser Picker" \
  "Exec=haseen-browser-picker %U" "$WEB"

# Hidden and NoDisplay entries are not browsers the user can pick.
entry "$sys" ghost "Name=Ghost" "Exec=ghost-browser %U" "NoDisplay=true" "$WEB"
stub ghost-browser
entry "$sys" spectre "Name=Spectre" "Exec=spectre-browser %U" "Hidden=true" "$WEB"
stub spectre-browser

# A broken TryExec means the install is gone even though the entry remains.
entry "$sys" stale "Name=Stale" "Exec=stale-browser %U" \
  "TryExec=$fake/nonexistent-browser" "$WEB"
stub stale-browser

# Not a browser: no http(s) scheme handler.
entry "$sys" notepad "Name=Notepad" "Exec=notepad %f" "MimeType=text/plain;"
stub notepad

# Duplicate desktop id in both directories: the user-local one wins, and it
# wins even by being NoDisplay — that is how a system entry gets hidden.
entry "$sys" dupe "Name=Dupe From System" "Exec=dupe-browser %U" "$WEB"
entry "$user" dupe "Name=Dupe From User" "Exec=dupe-browser %U" "NoDisplay=true" "$WEB"
stub dupe-browser

# An entry with no field code at all still launches.
entry "$sys" plainexec "Name=Plain Exec" "Exec=plain-browser" "$WEB"
stub plain-browser

# --- Run --------------------------------------------------------------------
# The PATH is replaced rather than prepended: keeping the real one would let
# every browser actually installed on this machine into the results, and the
# assertions below are about what the scanner does with the fixture, not with
# the host.
ln -s "$(command -v jq)" "$fake/bin/jq"

run_scan() {
  HOME="$fake/home" PATH="$fake/bin" \
    XDG_DATA_HOME="$fake/home/.local/share" XDG_DATA_DIRS="$fake/usr/share" \
    HASEEN_BROWSER_DESKTOP_DIRS="$user:$sys" \
    "$SCAN"
}

out=$(run_scan) || fail "scan exited non-zero" "$out"
jq -e . >/dev/null 2>&1 <<<"$out" || fail "output is not valid JSON" "$out"
ok

labels=$(jq -r '.entries[].label' <<<"$out")
ids=$(jq -r '.entries[].id' <<<"$out")

has_id() { jq -e --arg id "$1" '[.entries[].id] | index($id) != null' >/dev/null <<<"$out"; }
no_id() { jq -e --arg id "$1" '[.entries[].id] | index($id) == null' >/dev/null <<<"$out"; }

# --- Upstream's assertions, kept --------------------------------------------

# Duplicate display names must still be distinguishable.
dupes=$(sort <<<"$labels" | uniq -d)
[[ -z $dupes ]] || fail "duplicate labels survived" "$dupes"
ok

count=$(grep -c 'acme-client' <<<"$labels")
[[ $count -eq 2 ]] || fail "expected both acme-client profiles" "found $count"
ok

# An empty profile name falls back to the directory, never a dangling dash.
grep -q 'Profile 9' <<<"$labels" \
  || fail "empty profile name did not fall back to its directory" "$labels"
grep -qE '— *$' <<<"$labels" && fail "a label ends in a dangling dash" "$labels"
ok

# Ids are keyed on the directory, so renaming a profile never breaks a rule.
has_id "chromium:Profile 7" || fail "id is not <key>:<profile-dir>" "$ids"
ok

# A quote in a profile name must not produce a payload the QML side cannot read.
jq -e '[.entries[].label] | map(select(test("He said"))) | length == 1' \
  >/dev/null <<<"$out" || fail "a quoted profile name was mangled" "$out"
ok

# Nothing that is not installed may appear.
no_id "stale:" || fail "an entry with a broken TryExec was listed" "$ids"
ok

# --- Discovery: which entries are emitted -----------------------------------

# Helium, by evidence: binary helium-browser, config dir net.imput.helium.
has_id "helium:Default" || fail "Helium was not discovered" "$ids"
jq -e '[.entries[] | select(.id == "helium:Default")
        | select(.family == "chromium") | select(.icon == "🎈")] | length == 1' \
  >/dev/null <<<"$out" || fail "Helium was misclassified" "$out"
ok

# The Flatpak: profiles read from ~/.var/app, argv kept whole, markers gone.
has_id "com.brave.Browser:Profile 2" || fail "Flatpak profiles were not read" "$ids"
jq -e --arg fake "$fake" '[.entries[] | select(.id == "com.brave.Browser:Default")][0]
  | (.exec == [($fake + "/bin/flatpak"), "run", "--branch=stable", "--arch=x86_64",
               "--command=brave", "--file-forwarding", "com.brave.Browser"])
    and (.bin == ($fake + "/bin/flatpak"))
    and (.family == "chromium")
    and (.label | test("Flatpak"))' \
  >/dev/null <<<"$out" || fail "Flatpak argv or labelling is wrong" \
  "$(jq -c '.entries[] | select(.id == "com.brave.Browser:Default")' <<<"$out")"
ok

# Firefox family from profiles.ini: keyed on the profile *directory* (a name is
# renameable, a directory is not), launched by profile name.
has_id "firefox:abc.default-release" || fail "profiles.ini was not read" "$ids"
has_id "firefox:xyz.testing" || fail "second Firefox profile missing" "$ids"
jq -e '[.entries[] | select(.id == "firefox:xyz.testing")][0] | .profile == "Testing"' \
  >/dev/null <<<"$out" || fail "a firefox row does not carry its name for -P" \
  "$(jq -c '.entries[] | select(.id == "firefox:xyz.testing")' <<<"$out")"
ok

# An uncurated browser: named by its own desktop entry, neutral icon, and the
# family still read off a `Profile *` directory whose name (org.example.quokka)
# matches nothing about the binary. No `Local State`, so there are no profile
# names to list — a plain row with the right family is the correct answer.
jq -e '[.entries[] | select(.id == "quokka-browser:")
        | select(.browser == "Quokka Browser") | select(.family == "chromium")
        | select(.icon == "🧭") | select(.generic == true)] | length == 1' \
  >/dev/null <<<"$out" || fail "uncurated browser was not handled by evidence" \
  "$(jq -c '.entries[] | select(.bin | test("quokka"))' <<<"$out")"
ok

# No attributable config dir: exactly one plain row, and no private-window
# guess to make later.
jq -e '[.entries[] | select(.bin | test("nomad"))] | length == 1' \
  >/dev/null <<<"$out" || fail "browser with no config dir did not fall back to one row" \
  "$(jq -c '.entries[] | select(.bin | test("nomad"))' <<<"$out")"
jq -e '[.entries[] | select(.bin | test("nomad"))][0]
  | (.profile == "") and (.generic == true) and (.family == "other")' \
  >/dev/null <<<"$out" || fail "the plain fallback row is malformed" "$out"
ok

# The picker itself, under either desktop id, must never be offered.
grep -q 'Browser Picker' <<<"$labels" && fail "the picker listed itself" "$labels"
ok

# Two binaries, one config dir: the second one is dropped, not duplicated.
jq -e '[.entries[] | select(.bin | test("ungoogled"))] | length == 0' \
  >/dev/null <<<"$out" || fail "two binaries sharing a config dir were both listed" "$ids"
ok

# NoDisplay and Hidden are honoured.
grep -qE 'Ghost|Spectre' <<<"$labels" && fail "a hidden entry was listed" "$labels"
ok

# Not a handler of http(s): not a browser.
grep -q 'Notepad' <<<"$labels" && fail "a non-browser was listed" "$labels"
ok

# XDG precedence: the user-local entry owns the id, and it hides the system one.
grep -q 'Dupe From System' <<<"$labels" \
  && fail "a system entry shadowed by a user-local one was listed" "$labels"
grep -q 'Dupe From User' <<<"$labels" \
  && fail "a NoDisplay user-local entry was listed" "$labels"
ok

# An Exec with no field code is launched exactly as written.
jq -e '[.entries[] | select(.bin == "plain-browser")][0] | .exec == ["plain-browser"]' \
  >/dev/null <<<"$out" || fail "an Exec with no field code was mangled" "$out"
# ... and one with %U keeps nothing of it.
jq -e '[.entries[] | select(.id == "helium:Default")][0] | .exec == ["helium-browser"]' \
  >/dev/null <<<"$out" || fail "a field code survived into argv" "$out"
ok

# Emission order is discovery order: user-local directory first.
first_id=$(jq -r '.entries[0].id' <<<"$out")
[[ $first_id == com.brave.Browser:* ]] \
  || fail "user-local entries are not emitted first" "$first_id"
ok

# Deterministic: two runs of the same tree agree exactly.
again=$(run_scan)
[[ $again == "$out" ]] || fail "two runs disagree" "$(diff <(echo "$out") <(echo "$again"))"
ok

# --- Firefox default resolution ---------------------------------------------
# A Firefox-family store records which profile it actually opens in one of
# three places, and the modern two disagree with the legacy one on this host:
# `Default=1` sits on a profile the owner never opens. Each case below is its
# own fake HOME, because the answer is a property of one store.
stub zen-browser

ff_store() { # case-name -> prints a fresh fixture root, profiles.ini from stdin
  local root="$fake/ff/$1"
  mkdir -p "$root/home/.config/zen" "$root/applications"
  { echo "[Desktop Entry]"; echo "Type=Application"; echo "Name=Zen"
    echo "Exec=zen-browser %U"; echo "$WEB"; } >"$root/applications/zen.desktop"
  cat >"$root/home/.config/zen/profiles.ini"
  printf '%s' "$root"
}

ff_scan() { # fixture-root
  HOME="$1/home" PATH="$fake/bin" \
    XDG_DATA_HOME="$1/home/.local/share" XDG_DATA_DIRS="$1/usr/share" \
    HASEEN_BROWSER_DESKTOP_DIRS="$1/applications" \
    "$SCAN"
}

ff_flagged() { # json -> ids of every row flagged default, comma-joined
  jq -r '[.entries[] | select(.default) | .id] | join(",")' <<<"$1"
}

ff_rows() { # json -> every row's id, comma-joined
  jq -r '[.entries[].id] | join(",")' <<<"$1"
}

# (a) An `[Install*]` section in profiles.ini decides, even against `Default=1`
# on another profile: this is the shape the owner's own ~/.config/zen has.
root=$(ff_store install <<'INI'
[General]
StartWithLastProfile=1

[Profile0]
Name=Default (release)
IsRelative=1
Path=t1ig2skk.Default (release)

[Install15B76BAA26BA15E7]
Default=2z0zn07a.Default Profile
Locked=1

[Profile1]
Name=Default Profile
IsRelative=1
Path=2z0zn07a.Default Profile
Default=1
INI
)
ff_out=$(ff_scan "$root")
flagged=$(ff_flagged "$ff_out")
# The Install section names Profile1 here, so the flag has to be on Profile1
# and nowhere else — a scanner that trusted `Default=1` would agree by accident
# on this fixture only because the two were made to point the same way.
[[ $flagged == "zen-browser:2z0zn07a.Default Profile" ]] \
  || fail "[Install*] Default did not decide the default profile" "$flagged"
# The id is the profile directory, and the launch flag is still the name.
jq -e '[.entries[] | select(.id == "zen-browser:t1ig2skk.Default (release)")][0]
  | (.profile == "Default (release)") and (.default == false)' \
  >/dev/null <<<"$ff_out" || fail "a firefox row is keyed or flagged wrongly" \
  "$(jq -c '.entries[] | select(.family == "firefox")' <<<"$ff_out")"
ok

# (a) beats (b): profiles.ini's own Install section wins over installs.ini.
root=$(ff_store install-over-installs <<'INI'
[Profile0]
Name=Default (release)
IsRelative=1
Path=t1ig2skk.Default (release)

[Profile1]
Name=Default Profile
IsRelative=1
Path=2z0zn07a.Default Profile

[Install15B76BAA26BA15E7]
Default=t1ig2skk.Default (release)
INI
)
cat >"$root/home/.config/zen/installs.ini" <<'INI'
[15B76BAA26BA15E7]
Default=2z0zn07a.Default Profile
INI
flagged=$(ff_flagged "$(ff_scan "$root")")
[[ $flagged == "zen-browser:t1ig2skk.Default (release)" ]] \
  || fail "installs.ini overrode profiles.ini's own Install section" "$flagged"
ok

# (b) beats (c): with no Install section in profiles.ini, the sibling
# installs.ini decides — matched on the Path, which is what it stores.
root=$(ff_store installs-ini <<'INI'
[Profile0]
Name=Default (release)
IsRelative=1
Path=t1ig2skk.Default (release)

[Profile1]
Name=Default Profile
IsRelative=1
Path=2z0zn07a.Default Profile
Default=1
INI
)
cat >"$root/home/.config/zen/installs.ini" <<'INI'
[15B76BAA26BA15E7]
Default=t1ig2skk.Default (release)
Locked=1
INI
flagged=$(ff_flagged "$(ff_scan "$root")")
[[ $flagged == "zen-browser:t1ig2skk.Default (release)" ]] \
  || fail "installs.ini was not consulted for the default profile" "$flagged"
ok

# (c) The legacy flag, and only when nothing modern says otherwise.
root=$(ff_store legacy <<'INI'
[Profile0]
Name=Default (release)
IsRelative=1
Path=t1ig2skk.Default (release)

[Profile1]
Name=Default Profile
IsRelative=1
Path=2z0zn07a.Default Profile
Default=1
INI
)
flagged=$(ff_flagged "$(ff_scan "$root")")
[[ $flagged == "zen-browser:2z0zn07a.Default Profile" ]] \
  || fail "Default=1 was not the fallback when no install section exists" "$flagged"
ok

# A store with no default recorded anywhere flags nothing rather than guessing
# at the first section.
root=$(ff_store nodefault <<'INI'
[Profile0]
Name=Default (release)
IsRelative=1
Path=t1ig2skk.Default (release)

[Profile1]
Name=Default Profile
IsRelative=1
Path=2z0zn07a.Default Profile
INI
)
flagged=$(ff_flagged "$(ff_scan "$root")")
[[ -z $flagged ]] || fail "a store with no recorded default flagged a row" "$flagged"
ok

# Not everything shaped like a profile is one: Zen keeps a `Profile Groups`
# directory next to the profiles and writes sections that are not profiles.
# Only `[Profile<digits>]` counts, and the directory listing is never read.
root=$(ff_store groups <<'INI'
[Profile Groups]
Path=Profile Groups/abc
Name=Group One

[Profile0]
Name=Default (release)
IsRelative=1
Path=t1ig2skk.Default (release)

[Install15B76BAA26BA15E7]
Default=t1ig2skk.Default (release)

[Profile1]
Name=Default Profile
IsRelative=1
Path=2z0zn07a.Default Profile
Default=1
INI
)
mkdir -p "$root/home/.config/zen/Profile Groups/abc" \
         "$root/home/.config/zen/t1ig2skk.Default (release)" \
         "$root/home/.config/zen/2z0zn07a.Default Profile" \
         "$root/home/.config/zen/xxxxxxxx.Never Listed"
ff_out=$(ff_scan "$root")
rows=$(ff_rows "$ff_out")
[[ $rows == "zen-browser:t1ig2skk.Default (release),zen-browser:2z0zn07a.Default Profile" ]] \
  || fail "profile rows came from something other than [ProfileN] sections" "$rows"
flagged=$(ff_flagged "$ff_out")
[[ $flagged == "zen-browser:t1ig2skk.Default (release)" ]] \
  || fail "the [Profile Groups] section disturbed default resolution" "$flagged"
ok

# Chromium symmetry: profile.last_used names the default, and the `Default`
# directory is the fallback when it does not.
root=$(ff_store chromium-last-used </dev/null)
rm -r "$root/home/.config/zen"
mkdir -p "$root/home/.config/chromium"
echo '{"profile":{"last_used":"Profile 7","info_cache":{
  "Default":{"name":"Personal"},"Profile 7":{"name":"Work"}}}}' \
  >"$root/home/.config/chromium/Local State"
{ echo "[Desktop Entry]"; echo "Type=Application"; echo "Name=Chromium"
  echo "Exec=chromium %U"; echo "$WEB"; } >"$root/applications/zen.desktop"
flagged=$(ff_flagged "$(ff_scan "$root")")
[[ $flagged == "chromium:Profile 7" ]] \
  || fail "profile.last_used did not decide the Chromium default" "$flagged"

echo '{"profile":{"last_used":"Profile 404","info_cache":{
  "Default":{"name":"Personal"},"Profile 7":{"name":"Work"}}}}' \
  >"$root/home/.config/chromium/Local State"
flagged=$(ff_flagged "$(ff_scan "$root")")
[[ $flagged == "chromium:Default" ]] \
  || fail "a stale last_used did not fall back to the Default directory" "$flagged"
ok

if (( failed )); then
  echo "$failed failed, $((passed - failed)) passed"
  exit 1
fi
echo "$passed passed"
