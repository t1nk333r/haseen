# shellcheck shell=bash
# haseen:covers bin/** share/**
# haseen:covers tests/fixtures/{arch-bios,arch-sdboot-sb-enabled,cachyos-grub-plain}/**
# haseen:covers tests/fixtures/{cachyos-limine-luks-dualboot,nixos,omarchy-limine-host}/**
# haseen:covers tests/fixtures/{sb-grub-setup,sb-limine-setup-windows,sb-sdboot-enabled}/**
# haseen:covers tests/fixtures/sb-sdboot-setup-tpm/** tests/fixtures/*/expected.preflight
# haseen:covers tests/test-*.sh install.sh
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

capture env HASEEN_SYSROOT="$FIXTURES/nixos" haseen layer apply a --dry-run
assert_contains "distro gate" "$OUTPUT" "does not support distro 'nixos'"

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
src xpadneo-dkms ttfx lib32-nvidia-580xx-utils
assert_contains "mixed: chaotic part" "$OUTPUT" "pacman -S --needed chaotic-aur/xpadneo-dkms"
assert_eq "mixed: only ttfx is built from the AUR" "DRYRUN: paru -S --needed ttfx" "$(grep 'paru -S' <<<"$OUTPUT")"
assert_dry_pure "package source order" "$OUTPUT"
sed -i '/chaotic-aur/,+1d' "$fx/etc/pacman.conf"
src ttfx
assert_contains "without Chaotic-AUR: suggests enabling it" "$OUTPUT" "haseen layer apply chaotic"

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
