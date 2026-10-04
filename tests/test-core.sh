# shellcheck shell=bash
# Core: preflight detection, CLI router, layer runner, installer dry-run.

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
assert_contains "nixos refused" "$OUTPUT" "flake"

# --- the owner's Omarchy/DMS plugins are read-only (AGENTS.md) ---------------
# Static: no line naming those dirs (literally or via the variables that hold
# them) may also delete, move or write.
assert_eq "no destructive op on ~/.config/omarchy|DankMaterialShell/plugins" "" \
    "$(grep -rnE '(omarchy|DankMaterialShell)/plugins|PLUGIN_(OMARCHY|DMS)_DIR|omarchyPlugins|dmsPlugins' \
        "$REPO/bin" "$REPO/share" "$REPO/install.sh" "$REPO/nix" |
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
