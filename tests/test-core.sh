# shellcheck shell=bash
# haseen:scans bin/** share/**
# haseen:covers tests/fixtures/{arch-bios,arch-sdboot-sb-enabled,cachyos-grub-plain}/**
# haseen:covers tests/fixtures/{cachyos-limine-luks-dualboot,nixos,omarchy-limine-host}/**
# haseen:covers tests/fixtures/{sb-grub-setup,sb-limine-setup-windows,sb-sdboot-enabled}/**
# haseen:covers tests/fixtures/sb-sdboot-setup-tpm/** tests/fixtures/*/expected.preflight
# haseen:covers tests/test-*.sh install.sh
# bin/** and share/** are a scan, not a claim: the owner-plugin grep below reads
# every file there, and the tests that exercise a file claim it (plan 201).
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# Core: preflight detection, CLI router, layer runner, installer dry-run.

# --- inherited session state never selects a live launch path -----------------
export UWSM_FINALIZE_VARNAMES=fixture-finalize UWSM_WAIT_VARNAMES=fixture-wait
sandbox session-isolation
assert_eq "sandbox clears inherited uwsm finalize markers" "" "${UWSM_FINALIZE_VARNAMES+set}"
assert_eq "sandbox clears inherited uwsm wait markers" "" "${UWSM_WAIT_VARNAMES+set}"

# --- preflight against every fixture ---------------------------------------
for fx in "$FIXTURES"/*/; do
    fx="${fx%/}"
    [[ -r $fx/expected.preflight ]] || continue
    sandbox "preflight-${fx##*/}"
    capture env HASEEN_SYSROOT="$fx" bash -c 'source "$HASEEN_PATH/lib/preflight.sh"; preflight_all; preflight_report'
    assert_eq "preflight ${fx##*/}" "$(<"$fx/expected.preflight")" "$OUTPUT"
done

# --- router ----------------------------------------------------------------
sandbox router
capture haseen commands
assert_contains "router lists layer apply" "$OUTPUT" "haseen layer apply"
capture haseen layer
assert_contains "group listing" "$OUTPUT" "haseen layer list"
capture haseen no-such-thing
assert_status "unknown command exits 2" 2 "$STATUS"
capture haseen version
assert_eq "version" "$(<"$REPO/share/haseen/VERSION")" "$OUTPUT"

# --- layer runner on a synthetic layer tree --------------------------------
sandbox layers
L="$SANDBOX/layers"
mklayer() { # NAME REQUIRES CONFLICTS
    mkdir -p "$L/$1"
    cat >"$L/$1/layer.sh" <<EOF
LAYER_SUMMARY="test layer $1"
LAYER_REQUIRES=($2)
LAYER_CONFLICTS=($3)
LAYER_DISTROS=(cachyos arch)
layer_status() { echo "missing: $1"; return 1; }
layer_apply() { run_root touch "/etc/haseen-test-$1" "\$@"; }
EOF
}
mklayer a "" ""
mklayer b "a" ""
mklayer c "b a" ""
mklayer x "" "c"
mklayer loop1 "loop2" ""
mklayer loop2 "loop1" ""
printf 'ripgrep\naur:paru-bin  # helper\n' >"$L/b/packages.txt"
export HASEEN_LAYERS_DIR="$L"
fx="$FIXTURES/cachyos-limine-luks-dualboot"

capture env HASEEN_SYSROOT="$fx" bash -c 'source "$HASEEN_PATH/lib/layers.sh"; resolve_layers c'
assert_eq "resolve order" $'a\nb\nc' "$OUTPUT"
capture env HASEEN_SYSROOT="$fx" bash -c 'source "$HASEEN_PATH/lib/layers.sh"; resolve_layers loop1'
assert_contains "cycle detected" "$OUTPUT" "dependency cycle"
capture env HASEEN_SYSROOT="$fx" haseen layer apply c x --dry-run
assert_contains "conflict refused" "$OUTPUT" "conflicts with c"

capture env HASEEN_SYSROOT="$fx" haseen layer apply c --dry-run -- --flag
assert_status "dry-run apply exit" 0 "$STATUS"
assert_dry_pure "layer apply" "$OUTPUT"
assert_contains "repo package planned" "$OUTPUT" "DRYRUN: sudo pacman -S --needed ripgrep"
assert_contains "aur package via paru" "$OUTPUT" "DRYRUN: paru -S --needed paru-bin"
assert_contains "layer args reach last layer only" "$OUTPUT" "touch /etc/haseen-test-c --flag"
assert_contains "dependency applied without args" "$OUTPUT" "touch /etc/haseen-test-a"$'\n'
assert_contains "marker written" "$OUTPUT" "write /var/lib/haseen/layers/c"
assert_contains "the layer-applied hooks run for each layer applied (plan 200)" "$OUTPUT" \
    "DRYRUN: $REPO/bin/haseen-hook run layer-applied a"$'\n'
assert_contains "the last one with its own name" "$OUTPUT" "DRYRUN: $REPO/bin/haseen-hook run layer-applied c"
assert_eq "after the layer is applied" "marker" \
    "$(awk '/write \/var\/lib\/haseen\/layers\/c/ { m = 1 } /run layer-applied c/ { print (m ? "marker" : "first") }' <<<"$OUTPUT")"

capture env HASEEN_SYSROOT="$FIXTURES/nixos" haseen layer apply a --dry-run
assert_contains "distro gate" "$OUTPUT" "does not support distro 'nixos'"
assert_not_contains "a layer that was not applied fires no hook" "$OUTPUT" "layer-applied"

# Every event haseen hook install accepts is one haseen fires: a hook
# installed for it runs (plan 200).
for ev in $(sed -n 's/^HOOK_EVENTS=(\(.*\))$/\1/p' "$REPO/bin/haseen-hook"); do
    assert_contains "hook event $ev has a caller" \
        "$(grep -rlE "(^|[^a-z-])run $ev([^a-z-]|$)" "$REPO/bin" "$REPO/share" --exclude=haseen-hook --exclude='*.md' | head -n1)" "/"
done

printf 'Bad Name\n' >"$L/a/packages.txt"
capture env HASEEN_SYSROOT="$fx" haseen layer apply a --dry-run
assert_contains "manifest validation" "$OUTPUT" "invalid package name"
assert_dry_pure "bad manifest" "$OUTPUT"

capture env HASEEN_SYSROOT="$fx" haseen layer status a
assert_status "status propagates missing" 1 "$STATUS"
unset HASEEN_LAYERS_DIR

# --- installer -------------------------------------------------------------
sandbox installer
capture env HASEEN_SYSROOT="$FIXTURES/cachyos-grub-plain" "$REPO/install.sh" --dry-run --tree-only
assert_status "install tree dry-run" 0 "$STATUS"
assert_dry_pure "install.sh" "$OUTPUT"
assert_contains "installs router" "$OUTPUT" "install -Dm0755 $REPO/bin/haseen /usr/local/bin/haseen"
capture env HASEEN_SYSROOT="$FIXTURES/nixos" "$REPO/install.sh" --dry-run
assert_status "nixos refused" 1 "$STATUS"
assert_contains "nixos refused as unsupported" "$OUTPUT" "NixOS is not supported"

# --- the owner's Omarchy/DMS plugins are read-only (AGENTS.md) ---------------
# Static: no line naming those dirs (literally or via the variables that hold
# them) may also delete, move or write.
assert_eq "no destructive op on ~/.config/omarchy|DankMaterialShell/plugins" "" \
    "$(grep -rnE '(omarchy|DankMaterialShell)/plugins|PLUGIN_(OMARCHY|DMS)_DIR|omarchyPlugins|dmsPlugins' \
        "$REPO/bin" "$REPO/share" "$REPO/install.sh" |
        grep -E '(\brm\b|\bmv\b|rmdir|unlink|ln -s|>[^&|=]*(plugins|_DIR)|write_user_file|seed_user_file|removeFile|\.remove\()' || true)"
# --- sudo runs only in common.sh's helpers (CLAUDE.md, plan 185) --------------
# Static: a shell line outside common.sh with sudo in command position. Quoted
# text, comments and heredocs (messages, usage) are left out first.
sudo_files=()
while IFS= read -r f; do
    [[ $f != "$REPO/share/haseen/lib/common.sh" ]] || continue
    head -n1 -- "$f" | grep -qE '^#!.*\b(ba)?sh\b|^# shellcheck shell=(ba)?sh' && sudo_files+=("$f")
done < <(find "$REPO/bin" "$REPO/share" "$REPO/install.sh" -type f)
assert_eq "no sudo outside common.sh's helpers" "" "$(awk '
    FNR == 1 { hd = "" }
    hd != "" { if ($0 ~ "^[[:space:]]*" hd "[[:space:]]*$") hd = ""; next }
    /^[[:space:]]*#/ { next }
    {
        line = $0
        if (match(line, /<<-?[[:space:]]*["\047]?[A-Za-z_]+/)) {
            t = substr(line, RSTART, RLENGTH); sub(/^<<-?[[:space:]]*["\047]?/, "", t); hd = t
        }
        gsub(/"([^"\\]|\\.)*"/, "\"\"", line)
        gsub(/\047[^\047]*\047/, "", line)
        sub(/[[:space:]]#.*/, "", line)
        if (line ~ /(^|[;&|({]|then|do|else|\$\()[[:space:]]*sudo[[:space:]]/) print FILENAME ":" FNR ": " $0
    }' "${sudo_files[@]}")"
unset sudo_files

# Behaviour: every plugin command run against an Omarchy and a DMS plugin
# leaves both source trees byte-identical.
sandbox plugin-preserve
mkdir -p "$HOME/.config/omarchy/plugins/me.keep" "$HOME/.config/DankMaterialShell/plugins/dmsKeep"
printf '{"id":"me.keep","name":"Keep","version":"1","kind":"bar-widget","entry":"Widget.qml"}\n' >"$HOME/.config/omarchy/plugins/me.keep/manifest.json"
printf 'import QtQuick\nItem {}\n' >"$HOME/.config/omarchy/plugins/me.keep/Widget.qml"
printf '{"id":"dmsKeep","name":"Keep","version":"1","type":"widget","component":"./W.qml"}\n' >"$HOME/.config/DankMaterialShell/plugins/dmsKeep/plugin.json"
printf 'import QtQuick\nItem {}\n' >"$HOME/.config/DankMaterialShell/plugins/dmsKeep/W.qml"
tree_sum() { (cd "$HOME/.config" && find omarchy DankMaterialShell -type f -exec sha256sum {} + | sort); }
before="$(tree_sum)"
for id in me.keep dmsKeep; do
    for verb in info validate enable disable; do
        haseen plugin "$verb" "$id" >/dev/null 2>&1 || true
    done
    for verb in $(cd "$REPO/bin" && ls haseen-plugin-* | sed 's/^haseen-plugin-//' | grep -vE '^(info|validate|enable|disable|list|new)$'); do
        haseen plugin "$verb" "$id" --yes >/dev/null 2>&1 </dev/null || true
    done
done
assert_eq "plugin commands never change Omarchy/DMS plugin trees" "$before" "$(tree_sum)"

# --- DRY_RUN and ASSUME_YES from the environment (plan 185) -------------------
# The helpers run them as commands (`if $DRY_RUN`): DRY_RUN=1 once ran `1`,
# failed the test and mutated for real. The usual spellings are read once.
sandbox dry-run-env
capture env DRY_RUN=1 bash -Eeuo pipefail -c 'source "$HASEEN_PATH/lib/common.sh"; run touch "$HOME/mutated"'
assert_status "DRY_RUN=1 is a dry run" 0 "$STATUS"
assert_contains "DRY_RUN=1 plans" "$OUTPUT" "DRYRUN: touch $HOME/mutated"
[[ ! -e $HOME/mutated ]] && _pass || _fail "DRY_RUN=1 changes nothing"
capture env DRY_RUN=maybe bash -Eeuo pipefail -c 'source "$HASEEN_PATH/lib/common.sh"; run touch "$HOME/mutated"'
assert_status "an unknown DRY_RUN stops" 1 "$STATUS"
assert_contains "an unknown DRY_RUN is named" "$OUTPUT" "DRY_RUN=maybe is neither true nor false"
[[ ! -e $HOME/mutated ]] && _pass || _fail "an unknown DRY_RUN changes nothing"
capture env DRY_RUN=0 ASSUME_YES=yes bash -c 'source "$HASEEN_PATH/lib/common.sh"; echo "$DRY_RUN $ASSUME_YES"'
assert_eq "0 and yes read as false and true" "false true" "$OUTPUT"

# --- write_root_file leaves an existing parent's mode alone (plan 185) --------
# install -d -m 0755 chmods a directory that exists: /etc/sudoers.d is 0750.
sandbox write-root-mode
stub sudo 'exec "$@"'
mkdir -m 0750 "$SANDBOX/sudoers.d"
capture env DRY_RUN=false bash -c 'source "$HASEEN_PATH/lib/common.sh"; printf "x\n" | write_root_file "$1" 0440; printf "y\n" | write_root_file "$2"' \
    _ "$SANDBOX/sudoers.d/90-test" "$SANDBOX/new/dir/file"
assert_status "write_root_file wrote" 0 "$STATUS"
assert_eq "existing parent keeps its mode" 750 "$(stat -c %a "$SANDBOX/sudoers.d")"
assert_eq "file gets its mode" 440 "$(stat -c %a "$SANDBOX/sudoers.d/90-test")"
assert_eq "missing parents are created" y "$(cat "$SANDBOX/new/dir/file")"

# --- aur: entries: official repo, then Chaotic-AUR, AUR last (owner) --------
sandbox pkg-source
fx="$SANDBOX/fx"
cp -a "$FIXTURES/cachyos-limine-luks-dualboot/." "$fx/"
mkdir -p "$fx/var/lib/pacman/sync"
printf '[options]\nArchitecture = auto\n[cachyos]\nInclude = x\n[core]\nInclude = x\n[extra]\nInclude = x\n[chaotic-aur]\nInclude = /etc/pacman.d/chaotic-mirrorlist\n' >"$fx/etc/pacman.conf"
printf 'lib32-nvidia-580xx-utils\n' >"$fx/var/lib/pacman/sync/cachyos.pkgs"
printf 'chaotic-mirrorlist\nxpadneo-dkms\nparu\n' >"$fx/var/lib/pacman/sync/chaotic-aur.pkgs"
src() { capture env HASEEN_SYSROOT="$fx" DRY_RUN=true bash -c 'source "$HASEEN_PATH/lib/packages.sh"; pkg_install_aur "$@"' _ "$@"; }
src lib32-nvidia-580xx-utils
assert_contains "aur: entry found in an official repo installs from it" "$OUTPUT" "DRYRUN: sudo pacman -S --needed lib32-nvidia-580xx-utils"
assert_not_contains "repo hit never builds" "$OUTPUT" "paru -S"
src xpadneo-dkms
assert_contains "Chaotic-AUR preferred over the AUR" "$OUTPUT" "DRYRUN: sudo pacman -S --needed chaotic-aur/xpadneo-dkms"
assert_not_contains "chaotic hit never builds" "$OUTPUT" "paru -S"
src ttfx
assert_contains "AUR only as the last resort" "$OUTPUT" "DRYRUN: paru -S --needed ttfx"
assert_contains "last-resort warning" "$OUTPUT" "building from the AUR (last resort): ttfx"
# A PKGBUILD's sudo never finds the timestamp the pacman step warmed: the build
# runs cold, on the sudo on PATH and with no sudo loop (plan 185).
assert_contains "AUR build runs cold" "$OUTPUT" \
    $'DRYRUN: sudo -k\nDRYRUN: paru -S --needed ttfx --sudo sudo --nosudoloop (each sudo it runs is sudo -N'
src xpadneo-dkms ttfx lib32-nvidia-580xx-utils
assert_contains "mixed: chaotic part" "$OUTPUT" "pacman -S --needed chaotic-aur/xpadneo-dkms"
assert_eq "mixed: only ttfx is built from the AUR" \
    "DRYRUN: paru -S --needed ttfx --sudo sudo --nosudoloop (each sudo it runs is sudo -N: it asks, and caches nothing)" \
    "$(grep 'paru -S' <<<"$OUTPUT")"
assert_dry_pure "package source order" "$OUTPUT"
# What the helper would install for an AUR build gets the omarchy guard too:
# a build whose dependencies bring in omarchy-settings is refused under --yes
# (plan 185). The fixture's NAME.deps stands in for the AUR's answer.
printf 'cmake\nomarchy-settings\n' >"$fx/var/lib/pacman/sync/omarfoo.deps"
capture env HASEEN_SYSROOT="$fx" DRY_RUN=true ASSUME_YES=true bash -c 'source "$HASEEN_PATH/lib/packages.sh"; pkg_install_aur "$@"' _ omarfoo
assert_status "AUR build pulling omarchy-settings refused under --yes" 1 "$STATUS"
assert_contains "AUR closure listed" "$OUTPUT" "building them would install: omarfoo cmake omarchy-settings"
assert_contains "AUR closure refusal" "$OUTPUT" "omarfoo would bring in omarchy packages, which --yes never accepts"
assert_not_contains "refused AUR build never starts" "$OUTPUT" "paru -S --needed omarfoo"
src omarfoo
assert_status "without --yes the dry run asks and goes on" 0 "$STATUS"
assert_contains "without --yes: the guard warns" "$OUTPUT" "installing omarfoo also installs omarchy-settings"
command rm -f "$fx/var/lib/pacman/sync/omarfoo.deps"
sed -i '/chaotic-aur/,+1d' "$fx/etc/pacman.conf"
src ttfx
assert_contains "without Chaotic-AUR: suggests enabling it" "$OUTPUT" "haseen layer apply chaotic"
# A dry run that applies chaotic before this layer plans from Chaotic-AUR, as
# the real run will once chaotic is enabled; it never plans an AUR build, or
# needs a helper, for it (plan 185).
capture env HASEEN_SYSROOT="$fx" DRY_RUN=true HASEEN_APPLY_LAYERS="base chaotic desktop" LAYER_NAME=desktop \
    bash -c 'source "$HASEEN_PATH/lib/packages.sh"; pkg_install_aur "$@"' _ ttfx
assert_status "dry run after chaotic: planned" 0 "$STATUS"
assert_contains "dry run after chaotic: from Chaotic-AUR" "$OUTPUT" "DRYRUN: sudo pacman -S --needed chaotic-aur/ttfx"
assert_contains "dry run after chaotic: says why" "$OUTPUT" "planned from Chaotic-AUR, which this run enables first: ttfx"
assert_not_contains "dry run after chaotic: no AUR build" "$OUTPUT" "paru -S"
capture env HASEEN_SYSROOT="$fx" DRY_RUN=true HASEEN_APPLY_LAYERS="base desktop chaotic" LAYER_NAME=desktop \
    bash -c 'source "$HASEEN_PATH/lib/packages.sh"; pkg_install_aur "$@"' _ ttfx
assert_contains "chaotic applied after this layer: still the AUR" "$OUTPUT" "DRYRUN: paru -S --needed ttfx"

capture env HASEEN_SYSROOT="$fx" haseen layer apply chaotic --dry-run
assert_dry_pure "chaotic layer" "$OUTPUT"
assert_contains "chaotic: pinned key" "$OUTPUT" "pacman-key --recv-key EF925EA60F33D0CB85C44AD13056513887B78AEB"
assert_contains "chaotic: fingerprint checked" "$OUTPUT" "verify the key fingerprint is EF925EA60F33D0CB85C44AD13056513887B78AEB"
assert_contains "chaotic: keyring + mirrorlist" "$OUTPUT" "chaotic-keyring.pkg.tar.zst https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst"
assert_contains "chaotic: stanza appended" "$OUTPUT" "    | [chaotic-aur]"
assert_contains "chaotic: full upgrade, not -Sy" "$OUTPUT" "DRYRUN: sudo pacman -Syu"
printf '[chaotic-aur]\nInclude = /etc/pacman.d/chaotic-mirrorlist\n' >>"$fx/etc/pacman.conf"
capture env HASEEN_SYSROOT="$fx" haseen layer apply chaotic --dry-run
assert_contains "chaotic: idempotent when it works" "$OUTPUT" "Chaotic-AUR already enabled"
assert_not_contains "chaotic: no second stanza" "$OUTPUT" "append to /etc/pacman.conf"
# Applied after omarchy-repo, chaotic puts its stanza before [omarchy], which
# stays last (plan 185); a dry run that applies both says so.
command cp -f "$fx/etc/pacman.conf" "$SANDBOX/pacman.conf.keep"
printf '[options]\nArchitecture = auto\n[core]\nInclude = x\n[omarchy]\nServer = x\n' >"$fx/etc/pacman.conf"
capture env HASEEN_SYSROOT="$fx" haseen layer apply chaotic --dry-run
assert_dry_pure "chaotic after omarchy-repo" "$OUTPUT"
assert_contains "chaotic after omarchy-repo: stanza before [omarchy]" "$OUTPUT" \
    $'DRYRUN: write /etc/pacman.conf (mode 0644):\n    | [options]\n    | Architecture = auto\n    | [core]\n    | Include = x\n    | [chaotic-aur]\n    | Include = /etc/pacman.d/chaotic-mirrorlist\n    | \n    | [omarchy]\n    | Server = x\n'
assert_not_contains "chaotic after omarchy-repo: no append after it" "$OUTPUT" "append to /etc/pacman.conf"
sed -i '/^\[omarchy\]/,+1d' "$fx/etc/pacman.conf"
capture env HASEEN_SYSROOT="$fx" haseen layer apply omarchy-repo chaotic --dry-run
assert_contains "omarchy-repo then chaotic in one dry run: before [omarchy]" "$OUTPUT" \
    "DRYRUN: put the [chaotic-aur] stanza before the [omarchy] section omarchy-repo adds to /etc/pacman.conf"
# pacman can list [omarchy] from an Include'd file, with no plain [omarchy]
# line to put the stanza before: chaotic appends it rather than rewrite the
# file unchanged and carry on without Chaotic-AUR (plan 185).
capture env HASEEN_SYSROOT="$fx" DRY_RUN=true bash -c 'source "$HASEEN_PATH/lib/layers.sh"; preflight_all
    LAYER_DIR="$HASEEN_PATH/layers/chaotic"; source "$LAYER_DIR/layer.sh"
    omarchy_repo_enabled() { true; }; layer_apply'
assert_status "[omarchy] from an Include: applied" 0 "$STATUS"
assert_contains "[omarchy] from an Include: stanza appended" "$OUTPUT" \
    $'DRYRUN: append to /etc/pacman.conf:\n    | \n    | [chaotic-aur]'
assert_contains "[omarchy] from an Include: says why" "$OUTPUT" "is enabled but not as a plain [omarchy] line"
assert_not_contains "[omarchy] from an Include: no unchanged rewrite" "$OUTPUT" "DRYRUN: write /etc/pacman.conf"
command cp -f "$SANDBOX/pacman.conf.keep" "$fx/etc/pacman.conf"

# --- [omarchy] repo: after Chaotic-AUR, before the AUR; never Omarchy itself --
printf '[omarchy]\nSigLevel = Required DatabaseOptional\nServer = x\n' >>"$fx/etc/pacman.conf"
printf 'ttfx\nomarchy-keyring\nxpadneo-dkms\nomarchy-settings\n' >"$fx/var/lib/pacman/sync/omarchy.pkgs"
src ttfx
assert_contains "omarchy repo before the AUR" "$OUTPUT" "DRYRUN: sudo pacman -S --needed omarchy/ttfx"
assert_not_contains "omarchy hit never builds" "$OUTPUT" "paru -S"
src xpadneo-dkms
assert_contains "Chaotic-AUR before the omarchy repo" "$OUTPUT" "pacman -S --needed chaotic-aur/xpadneo-dkms"
for denied in omarchy omarchy-settings; do
    src "$denied"
    assert_status "refuses $denied via pkg_install_aur" 1 "$STATUS"
    assert_contains "refusal names $denied" "$OUTPUT" "haseen never installs '$denied'"
    capture env HASEEN_SYSROOT="$fx" DRY_RUN=true bash -c 'source "$HASEEN_PATH/lib/packages.sh"; pkg_install "$1"' _ "$denied"
    assert_status "refuses $denied via pkg_install" 1 "$STATUS"
done
assert_dry_pure "omarchy tier" "$OUTPUT"

sed -i '/^\[omarchy\]/,+2d' "$fx/etc/pacman.conf"
capture env HASEEN_SYSROOT="$fx" haseen layer apply omarchy-repo --dry-run
assert_dry_pure "omarchy-repo layer" "$OUTPUT"
assert_contains "omarchy-repo: pinned key" "$OUTPUT" "pacman-key --recv-keys 40DFB630FF42BCFFB047046CF0134EE680CAC571 --keyserver keys.openpgp.org"
assert_contains "omarchy-repo: fingerprint checked" "$OUTPUT" "verify the key fingerprint is 40DFB630FF42BCFFB047046CF0134EE680CAC571"
assert_contains "omarchy-repo: signed packages required" "$OUTPUT" "    | SigLevel = Required DatabaseOptional"
assert_contains "omarchy-repo: stable channel" "$OUTPUT" '    | Server = https://pkgs.omarchy.org/stable/$arch'
assert_contains "omarchy-repo: keyring from the repo" "$OUTPUT" "pacman -S --needed omarchy/omarchy-keyring"
# The base layer applied first may print its Omarchy package guard hook, which
# names omarchy-settings as a trigger (plan 101): only that file's own lines
# (its write and the `    | ` lines after it) are left out.
assert_not_contains "omarchy-repo: never Omarchy itself" \
    "$(awk '/^DRYRUN: write \/etc\/pacman\.d\/hooks\/50-haseen-omarchy\.hook /{h=1; next} h && /^    \| /{next} {h=0; print}' <<<"$OUTPUT")" \
    "omarchy-settings"
printf '[omarchy]\nServer = x\n' >>"$fx/etc/pacman.conf"
capture env HASEEN_SYSROOT="$fx" haseen layer status omarchy-repo
assert_status "omarchy-repo: status ok once enabled" 0 "$STATUS"
assert_not_contains "omarchy-repo: last in pacman.conf, no shadow warning" "$OUTPUT" "not the last repo"

# --- append_root_file under a restrictive umask -------------------------------
# sudo keeps the caller's umask, so a 077 owner's append would create a root
# config file only root can read. A sudo that just runs its argv shows the
# mode the helper really creates, and that an existing file keeps its own.
sandbox root-umask
stub sudo 'exec "$@"'
dest="$SANDBOX/root/etc/haseen.conf"
mkdir -p "$SANDBOX/root/etc"
capture bash -c 'umask 077; source "$HASEEN_PATH/lib/common.sh"; DRY_RUN=false; echo x | append_root_file "$1"' _ "$dest"
assert_status "append_root_file under umask 077" 0 "$STATUS"
assert_eq "a new file is created world-readable" "644 x" "$(stat -c %a "$dest") $(cat "$dest")"
chmod 0600 "$dest"
capture bash -c 'umask 022; source "$HASEEN_PATH/lib/common.sh"; DRY_RUN=false; echo y | append_root_file "$1"' _ "$dest"
assert_eq "an existing file keeps its mode and gains the line" "600 x y" "$(stat -c %a "$dest") $(paste -sd' ' "$dest")"

# A test file run by hand, without tests/run.sh, has no sandbox: it must stop
# before its fixtures reach the real ~/.config (it once overwrote an owner's
# plugin that way).
direct="$SANDBOX/direct-home"
mkdir -p "$direct"
refused=0
for f in "$REPO"/tests/test-*.sh; do
    env -u TESTS_RUN HOME="$direct" XDG_CONFIG_HOME="$direct/.config" bash "$f" >/dev/null 2>&1 && continue
    [[ $? -eq 2 ]] && refused=$((refused + 1))
done
assert_eq "every test file refuses to run outside tests/run.sh" "$(ls "$REPO"/tests/test-*.sh | wc -l)" "$refused"
assert_eq "a test file run directly writes nothing" "" "$(ls -A "$direct")"

# --- run_cold (plan 103) ------------------------------------------------------
# Code haseen did not write runs with sudo's timestamp dropped around it and a
# `sudo` first on PATH that adds -N. The command's own status comes back, the
# wrapper goes away even when the command fails, and a sudo path with a quote
# and a space in it still reaches the real one.
sandbox common-cold
odd="$SANDBOX/it's here"
mkdir -p "$odd" "$SANDBOX/tmp"
log="$SANDBOX/cold.log"
cat >"$odd/sudo" <<EOF
#!/bin/sh
echo "SUDO: \$*" >>"$log"
[ "\$1" = -h ] && echo 'usage: sudo [-ABbEHkNnPS] [-C num]'
exit 0
EOF
chmod +x "$odd/sudo"
cold() { # STATUS — run_cold on a command that runs sudo twice, then exits STATUS
    : >"$log"
    capture env PATH="$odd:$PATH" TMPDIR="$SANDBOX/tmp" bash -c \
        'source "$1"; DRY_RUN=false; run_cold sh -c "sudo -V; sudo id -u; exit $2"' _ "$HASEEN_PATH/lib/common.sh" "$1"
}
cold 0
assert_status "run_cold: a command that succeeds" 0 "$STATUS"
assert_eq "run_cold: the timestamp is dropped around it, -N on all but -V" \
    "SUDO: -k|SUDO: -h|SUDO: -V|SUDO: -N id -u|SUDO: -k" "$(paste -sd'|' "$log")"
cold 3
assert_status "run_cold: a failing command's status comes back" 3 "$STATUS"
assert_eq "run_cold: and the timestamp is still dropped after it" "SUDO: -k" "$(tail -n1 "$log")"
assert_eq "run_cold: no wrapper is left behind" "" "$(find "$SANDBOX/tmp" -mindepth 1)"
# A temporary directory that cannot run the wrapper (mounted noexec; here a
# chmod that does nothing leaves it unexecutable): the command still runs,
# cold before and after, and the warning says why it had no -N.
mkdir -p "$SANDBOX/no-chmod"
printf '#!/bin/sh\nexit 0\n' >"$SANDBOX/no-chmod/chmod"
chmod +x "$SANDBOX/no-chmod/chmod"
: >"$log"
capture env PATH="$SANDBOX/no-chmod:$odd:$PATH" TMPDIR="$SANDBOX/tmp" bash -c \
    'source "$1"; DRY_RUN=false; run_cold sh -c "sudo id -u"' _ "$HASEEN_PATH/lib/common.sh"
assert_status "run_cold, wrapper cannot run: the command still runs" 0 "$STATUS"
assert_eq "run_cold, wrapper cannot run: cold before and after, no -N" \
    "SUDO: -k|SUDO: -h|SUDO: id -u|SUDO: -k" "$(paste -sd'|' "$log")"
assert_contains "run_cold, wrapper cannot run: says why" "$OUTPUT" "$SANDBOX/tmp cannot run programs"
assert_eq "run_cold, wrapper cannot run: nothing left behind" "" "$(find "$SANDBOX/tmp" -mindepth 1)"
capture bash -c 'source "$1"; DRY_RUN=true; run_cold paru -Sua' _ "$HASEEN_PATH/lib/common.sh"
assert_eq "run_cold: a dry run prints both drops and the command" \
    $'DRYRUN: sudo -k\nDRYRUN: paru -Sua (each sudo it runs is sudo -N: it asks, and caches nothing)\nDRYRUN: sudo -k' "$OUTPUT"
assert_dry_pure "run_cold" "$OUTPUT"
# A wrapper that cannot be made (mktemp fails: a full or read-only TMPDIR) or
# written (chmod fails) is the same as one that cannot run: the command runs
# cold, with a warning that says why, and nothing is left behind (plan 111).
# Under errexit, as haseen update runs it: the failure must not end the run.
for tool in mktemp chmod; do
    rm -rf "$SANDBOX/broken"
    mkdir -p "$SANDBOX/broken"
    printf '#!/bin/sh\nexit 1\n' >"$SANDBOX/broken/$tool"
    chmod +x "$SANDBOX/broken/$tool"
    : >"$log"
    capture env PATH="$SANDBOX/broken:$odd:$PATH" TMPDIR="$SANDBOX/tmp" bash -c \
        'set -Eeuo pipefail; source "$1"; DRY_RUN=false; run_cold sh -c "sudo id -u; exit 4"' _ "$HASEEN_PATH/lib/common.sh"
    assert_status "run_cold, $tool fails: the command still runs, its status back" 4 "$STATUS"
    assert_eq "run_cold, $tool fails: cold before and after, no -N" \
        "SUDO: -k|SUDO: -h|SUDO: id -u|SUDO: -k" "$(paste -sd'|' "$log")"
    assert_contains "run_cold, $tool fails: says why" "$OUTPUT" \
        "$([[ $tool == mktemp ]] && echo "no directory for the wrapper could be made in $SANDBOX/tmp" || echo "the wrapper could not be written in $SANDBOX/tmp")"
    assert_eq "run_cold, $tool fails: nothing left behind" "" "$(find "$SANDBOX/tmp" -mindepth 1)"
done
# The wrapper's directory goes first on PATH: a relative TMPDIR is resolved,
# so the entry cannot be looked up from the directory a build runs in, and
# one that does not resolve, or holds a ':' (which would split the entry),
# falls back to /tmp.
mkdir -p "$SANDBOX/rel" "$SANDBOX/a:b"
cold_path() { # TMPDIR — run_cold from $SANDBOX; the command looks sudo up from rel/
    capture env PATH="$odd:$PATH" TMPDIR="$1" bash -c \
        'source "$1"; DRY_RUN=false; cd "$2" && run_cold sh -c "cd rel && command -v sudo"' _ "$HASEEN_PATH/lib/common.sh" "$SANDBOX"
}
cold_path rel
assert_eq "run_cold: a relative TMPDIR is resolved first" "$(realpath "$SANDBOX/rel")/haseen-sudo." "${OUTPUT%??????/sudo}"
assert_eq "run_cold: and the wrapper is gone after" "" "$(find "$SANDBOX/rel" -mindepth 1)"
cold_path missing
assert_eq "run_cold: a relative TMPDIR that does not resolve: /tmp" "/tmp/haseen-sudo." "${OUTPUT%??????/sudo}"
cold_path "$SANDBOX/a:b"
assert_eq "run_cold: a TMPDIR with a ':': /tmp" "/tmp/haseen-sudo." "${OUTPUT%??????/sudo}"
assert_eq "run_cold: nothing left in it either" "" "$(find "$SANDBOX/a:b" -mindepth 1)"

# A signal while the command runs (plan 111): Ctrl+C, a closed terminal or a
# SIGTERM to the whole job, or to the shell that called run_cold alone. Once
# the command has stopped, the wrapper is removed and the timestamp dropped.
# The job runs in a session of its own, with the signals' default actions (a
# background job of a script starts with SIGINT ignored).
cold_go="$SANDBOX/cold-go" cold_ready="$SANDBOX/cold-ready"
cat >"$SANDBOX/cold-build" <<'EOF'
#!/bin/sh
# A build that runs one sudo, says it has started, then waits to be let go.
sudo id -u
: >"$1"
while [ ! -e "$2" ]; do sleep 0.1; done
EOF
chmod +x "$SANDBOX/cold-build"
for sig in INT TERM HUP; do
    for target in job caller; do
        : >"$log"
        rm -f "$cold_go" "$cold_ready"
        find "$SANDBOX/tmp" -mindepth 1 -delete
        # In braces: the shell's own notice of a job a signal ended stays quiet.
        {
            setsid env --default-signal=INT,QUIT,TERM,HUP PATH="$odd:$PATH" TMPDIR="$SANDBOX/tmp" bash -c \
                'source "$1"; DRY_RUN=false; shift; run_cold "$@"' _ "$HASEEN_PATH/lib/common.sh" \
                "$SANDBOX/cold-build" "$cold_ready" "$cold_go" </dev/null >/dev/null 2>&1 &
            leader=$!
            for _ in $(seq 100); do [[ -e $cold_ready ]] && break; sleep 0.1; done
            if [[ $target == job ]]; then
                kill "-$sig" -- "-$leader" 2>/dev/null || true
            else
                kill "-$sig" "$leader" 2>/dev/null || true
                : >"$cold_go"
            fi
            for _ in $(seq 100); do
                [[ $(tail -n1 "$log") == "SUDO: -k" && -z $(find "$SANDBOX/tmp" -mindepth 1) ]] && break
                sleep 0.1
            done
            : >"$cold_go"
            wait "$leader" || true
        } 2>/dev/null
        assert_eq "run_cold, SIG$sig to the $target: the timestamp is dropped after" \
            "SUDO: -k|SUDO: -h|SUDO: -N id -u|SUDO: -k" "$(paste -sd'|' "$log")"
        assert_eq "run_cold, SIG$sig to the $target: the wrapper is removed" "" "$(find "$SANDBOX/tmp" -mindepth 1)"
    done
done

# --- replace_user_file and run_polkit (plan 093) --------------------------------
sandbox common-replace
f="$SANDBOX/state.json"
printf '{"a":1}\n' >"$f"
chmod 0640 "$f"
capture bash -c 'source "$1"; DRY_RUN=true; printf "{\"a\":2}\n" | replace_user_file "$2"; DRY_RUN=true; run_polkit /usr/bin/true x' _ "$HASEEN_PATH/lib/common.sh" "$f"
assert_contains "replace_user_file: a dry run prints the new content" "$OUTPUT" "DRYRUN: write $f:"
assert_contains "replace_user_file: as a quoted block" "$OUTPUT" '    | {"a":2}'
assert_contains "run_polkit: a dry run prints pkexec" "$OUTPUT" "DRYRUN: pkexec /usr/bin/true x"
assert_eq "replace_user_file: a dry run leaves the file" '{"a":1}' "$(cat "$f")"
capture bash -c 'source "$1"; DRY_RUN=false; printf "{\"a\":3}\n" | replace_user_file "$2"' _ "$HASEEN_PATH/lib/common.sh" "$f"
assert_eq "replace_user_file: writes the new content" '{"a":3}' "$(cat "$f")"
assert_eq "replace_user_file: keeps the file's mode" "640" "$(stat -c %a "$f")"
assert_eq "replace_user_file: leaves no temporary file" "state.json" "$(cd "$SANDBOX" && ls state.json*)"
# A stowed or yadm-managed dotfile is a link: it stays one, and the file it
# points to gets the new content.
mkdir -p "$SANDBOX/dotfiles"
printf '{"a":1}\n' >"$SANDBOX/dotfiles/state.json"
chmod 0644 "$SANDBOX/dotfiles/state.json"
ln -s dotfiles/state.json "$SANDBOX/linked.json"
capture bash -c 'source "$1"; DRY_RUN=false; printf "{\"a\":4}\n" | replace_user_file "$2"' _ "$HASEEN_PATH/lib/common.sh" "$SANDBOX/linked.json"
assert_eq "replace_user_file: a linked destination stays a link" "dotfiles/state.json" "$(readlink "$SANDBOX/linked.json")"
assert_eq "replace_user_file: the link's target gets the content" '{"a":4}' "$(cat "$SANDBOX/dotfiles/state.json")"
assert_eq "replace_user_file: the target keeps its mode" "644" "$(stat -c %a "$SANDBOX/dotfiles/state.json")"
# A new file gets the umask's mode, as a plain write would.
capture bash -c 'source "$1"; DRY_RUN=false; umask 027; printf "{}\n" | replace_user_file "$2"' _ "$HASEEN_PATH/lib/common.sh" "$SANDBOX/new/state.json"
assert_eq "replace_user_file: a new file is written" "{}" "$(cat "$SANDBOX/new/state.json")"
assert_eq "replace_user_file: with the umask's mode, not 0600" "640" "$(stat -c %a "$SANDBOX/new/state.json")"
