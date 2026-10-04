# shellcheck shell=bash
# Nix: what the flake relies on, checked without nix. The flake itself is
# evaluated with `nix flake check` (plans/009-nixos-flake.md).

# --- the package layout (nix/package.nix) -----------------------------------
# Real scripts in libexec/haseen/, makeWrapper-style wrappers in bin/ that set
# HASEEN_PATH to the package's share/haseen. The router must still list
# commands with their summaries and resolve share/ through HASEEN_PATH.
sandbox nix-layout
P="$SANDBOX/out"
mkdir -p "$P/bin" "$P/libexec/haseen" "$P/share"
cp -r "$REPO/share/haseen" "$P/share/haseen"
echo "9.9.9-nix" >"$P/share/haseen/VERSION"
for f in "$REPO"/bin/haseen*; do
    install -m 0755 "$f" "$P/libexec/haseen/"
    # Same shape as makeWrapper --set/--prefix output.
    printf '#!/bin/bash\nexport HASEEN_PATH=%q\nexport PATH=%q:$PATH\nexec -a "$0" %q "$@"\n' \
        "$P/share/haseen" "$SANDBOX/stubs" "$P/libexec/haseen/${f##*/}" >"$P/bin/${f##*/}"
    chmod +x "$P/bin/${f##*/}"
done
# A stale HASEEN_PATH from an older generation must not win over the wrapper.
capture env HASEEN_PATH=/nonexistent "$P/bin/haseen" version
assert_eq "wrapped version reads the package's share/haseen" "9.9.9-nix" "$OUTPUT"
capture "$P/bin/haseen" commands
summary="$(sed -n 's/^# haseen:summary[[:space:]]*//p' "$REPO/bin/haseen-layer-apply" | head -n1)"
assert_contains "wrapped router lists commands" "$OUTPUT" "haseen layer apply"
assert_contains "wrapped router keeps summaries" "$OUTPUT" "$summary"
capture "$P/bin/haseen-layer-list" --help
assert_status "wrapped subcommand runs directly" 0 "$STATUS"

# --- the installer points NixOS users at a doc that exists -----------------
sandbox nix-refusal
capture env HASEEN_SYSROOT="$FIXTURES/nixos" "$REPO/install.sh" --dry-run
assert_status "installer refuses NixOS" 1 "$STATUS"
doc="$(grep -o 'nix/[A-Za-z]*\.md' <<<"$OUTPUT" | head -n1)"
assert_eq "refusal names nix/README.md" "nix/README.md" "$doc"
if [[ -r $REPO/$doc ]]; then _pass; else _fail "nix/README.md exists"; fi

# --- paths the Nix modules hard-code exist in the tree ---------------------
# Every ${haseenPath}/<rel> in nix/home.nix (the Hyprland entry, the shell
# root) must exist in share/haseen, or the generated config breaks at login.
mapfile -t rels < <(grep -o '\${haseenPath}/[A-Za-z0-9_./-]*' "$REPO/nix/home.nix" | sed 's|^\${haseenPath}/||' | sort -u)
assert_eq "home.nix references share/haseen paths" "default/hypr/init.lua shell" "${rels[*]}"
for rel in "${rels[@]}"; do
    if [[ -e $HASEEN_PATH/$rel ]]; then _pass; else _fail "share/haseen/$rel exists (used by nix/home.nix)"; fi
done
if [[ -r $HASEEN_PATH/shell/shell.qml ]]; then _pass; else _fail "share/haseen/shell/shell.qml exists (qs -p entry)"; fi

# --- the flake inputs are locked ---------------------------------------------
capture jq -r '.nodes.root.inputs | keys | join(" ")' "$REPO/flake.lock"
assert_eq "flake.lock pins every input" "home-manager lanzaboote nixpkgs" "$OUTPUT"
