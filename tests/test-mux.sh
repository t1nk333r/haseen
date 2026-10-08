# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# The multiplexer (herdr + tmux) and yazi seeds, the strings their shipped
# defaults are not allowed to carry, and the lab wrapper's prerequisite report.
sandbox mux

CONFIG="$HOME/.config"
export HASEEN_SYSROOT="$FIXTURES/seeds-plain"
DEFAULTS="$REPO/share/haseen/default"

# A PATH this file controls. "Is herdr installed?" has to be a property of the
# test, not of the machine running it: the author's laptop has herdr and tmux
# in /usr/bin and CI has neither, and the seed's answer depends on exactly
# that. So /usr/bin is mirrored as symlinks once, with the three binaries the
# tests care about removed, and each case puts back the ones it wants.
MIRROR="$OUT/mux-mirror"
rm -rf "$MIRROR"
cp -as /usr/bin "$MIRROR"
rm -f "$MIRROR/herdr" "$MIRROR/tmux" "$MIRROR/qemu-system-x86_64"

# use_path — re-apply the controlled PATH after a sandbox() call resets it.
use_path() { export PATH="$SANDBOX/stubs:$REPO/bin:$MIRROR"; }
# present CMD... — make those binaries exist for the next seed run.
present() {
    local c
    for c in "$@"; do
        printf '#!/bin/sh\nexit 0\n' >"$MIRROR/$c"
        chmod +x "$MIRROR/$c"
    done
}
absent() {
    local c
    for c in "$@"; do rm -f "$MIRROR/$c"; done
}
use_path

# --- the plan ----------------------------------------------------------------
present herdr tmux
capture haseen seed user --dry-run
assert_status "a user seed dry run succeeds" 0 "$STATUS"
assert_dry_pure "user seed dry run" "$OUTPUT"
assert_contains "the herdr config is planned" "$OUTPUT" "DRYRUN: seed $CONFIG/herdr/config.toml"
assert_contains "the tmux config is planned" "$OUTPUT" "DRYRUN: seed $CONFIG/tmux/tmux.conf"
assert_contains "the multiplexer choice is planned" "$OUTPUT" "DRYRUN: write $CONFIG/haseen/mux"
assert_contains "yazi's settings are planned" "$OUTPUT" "DRYRUN: seed $CONFIG/yazi/yazi.toml"
assert_contains "yazi's keymap is planned" "$OUTPUT" "DRYRUN: seed $CONFIG/yazi/keymap.toml"
assert_contains "yazi's theme link is planned" "$OUTPUT" \
    "DRYRUN: ln -snf $HOME/.local/state/haseen/current/theme/yazi.toml $CONFIG/yazi/theme.toml"
assert_eq "the dry run wrote nothing of ours" "" \
    "$(find "$CONFIG/herdr" "$CONFIG/tmux" "$CONFIG/yazi" "$CONFIG/haseen/mux" 2>/dev/null | tr '\n' ' ')"

# --- applied -----------------------------------------------------------------
capture haseen seed user
assert_status "seeding succeeds" 0 "$STATUS"

herdr_conf="$(cat "$CONFIG/herdr/config.toml")"
assert_contains "herdr takes tmux's prefix" "$herdr_conf" 'prefix = "ctrl+space"'
assert_contains "herdr rides the terminal palette" "$herdr_conf" 'name = "terminal"'
# The whole value of this file is that it says which tmux command each binding
# replaces; a copy without the comments is just a keymap.
assert_contains "the tmux mapping is explained" "$herdr_conf" "tmux session -> herdr workspace"
assert_contains "swap-window's binding is annotated" "$herdr_conf" \
    "# Like swap-window -t -1/+1 on M-S-Left/Right"
assert_contains "mouse_capture names its tmux original" "$herdr_conf" "# set -g mouse on"
assert_contains "new_cwd names its tmux original" "$herdr_conf" '# Matches -c "#{pane_current_path}"'
# close_workspace takes herdr's default swap_pane_up chord (omarchy#10062), so
# the four swaps have to be bound somewhere else or one of them is dead.
assert_contains "close_workspace keeps the tmux chord" "$herdr_conf" 'close_workspace = "prefix+shift+k"'
assert_contains "swap_pane_up is rebound off that chord" "$herdr_conf" \
    'swap_pane_up = "prefix+ctrl+shift+up"'
assert_eq "all four pane swaps are bound" "4" "$(grep -c '^swap_pane_' <<<"$herdr_conf")"
assert_contains "the first run asks nothing" "$herdr_conf" "onboarding = false"

tmux_conf="$(cat "$CONFIG/tmux/tmux.conf")"
assert_contains "tmux has the same prefix" "$tmux_conf" "set -g prefix C-Space"
assert_contains "reload is on q, not r" "$tmux_conf" "bind -N \"Reload configuration\" q source-file"
assert_contains "yazi's sixels get through tmux" "$tmux_conf" "set -g allow-passthrough all"
assert_contains "CSI-u is on, or M-S-Enter is M-Enter" "$tmux_conf" "set -g extended-keys-format csi-u"
assert_contains "foot is told it speaks extended keys" "$tmux_conf" 'terminal-features "foot*:extkeys"'
# The multiplexer takes its colours from the terminal, which the theme
# pipeline already renders. A hex literal here would freeze one theme in.
assert_eq "no colour literals in the tmux config" "" \
    "$(grep -oE '#[0-9a-fA-F]{6}\b|colour[0-9]+' "$CONFIG/tmux/tmux.conf" | sort -u | tr '\n' ' ')"
# tpm is not installed by haseen; a `run` line for a plugin manager that is not
# there prints an error on every tmux start.
assert_not_contains "no plugin manager haseen does not ship" "$tmux_conf" "tpm"
assert_not_contains "no plugin declarations either" "$tmux_conf" "@plugin"

yazi_conf="$(cat "$CONFIG/yazi/yazi.toml")"
assert_contains "yazi opens files through haseen's default handlers" "$yazi_conf" "xdg-open %s1"
assert_contains "a remote session stays in the terminal" "$yazi_conf" 'SSH_CONNECTION'
assert_contains "images go to the desktop handler" "$yazi_conf" \
    '{ mime = "image/*", use = ["view", "reveal"] }'
assert_contains "PDFs go to the desktop handler" "$yazi_conf" \
    '{ mime = "application/pdf", use = ["document", "reveal"] }'
assert_contains "the sixel bounds are explained" "$yazi_conf" "Foot => [Sixel]"
assert_not_contains "no colours in yazi's settings file" "$yazi_conf" "[flavor]"
keymap="$(cat "$CONFIG/yazi/keymap.toml")"
assert_contains "the keymap only adds" "$keymap" "prepend_keymap"
assert_contains "a shell opens in the hovered directory" "$keymap" 'shell "$SHELL" --block'
# Every plugin bind in the owner's keymap needs `ya pkg add` first. haseen
# installs no yazi plugins, so a bind that calls one is a dead key.
assert_eq "no bind calls a plugin haseen does not install" "" \
    "$(grep -o 'run = "plugin [a-z-]*"' "$CONFIG/yazi/keymap.toml" | tr '\n' ' ')"
assert_eq "yazi's colours come from the theme pipeline" \
    "$HOME/.local/state/haseen/current/theme/yazi.toml" \
    "$(readlink "$CONFIG/yazi/theme.toml")"

# --- herdr wins over tmux ----------------------------------------------------
assert_eq "herdr is the default when both are installed" "herdr" "$(cat "$CONFIG/haseen/mux")"
assert_eq "the choice is one bare word, nothing to parse" "1" "$(wc -l <"$CONFIG/haseen/mux")"

sandbox mux-tmux-only
use_path
present tmux
absent herdr
capture haseen seed user
assert_status "seeding a machine without herdr succeeds" 0 "$STATUS"
assert_eq "tmux is used when it is the only one there" "tmux" "$(cat "$HOME/.config/haseen/mux")"

sandbox mux-neither
use_path
absent herdr tmux
capture haseen seed user
assert_status "seeding before the packages land succeeds" 0 "$STATUS"
assert_eq "herdr is still the choice when neither is installed yet" "herdr" \
    "$(cat "$HOME/.config/haseen/mux")"

# --- seeded files belong to the user ----------------------------------------
sandbox mux-again
use_path
present herdr tmux
CONFIG="$HOME/.config"
capture haseen seed user
assert_status "the first run succeeds" 0 "$STATUS"
echo "# mine" >"$CONFIG/herdr/config.toml"
echo "# mine too" >"$CONFIG/tmux/tmux.conf"
echo "# and mine" >"$CONFIG/yazi/yazi.toml"
echo "tmux" >"$CONFIG/haseen/mux"
rm -f "$CONFIG/yazi/theme.toml"
ln -snf /dev/null "$CONFIG/yazi/theme.toml"
capture haseen seed user
assert_status "a second run succeeds" 0 "$STATUS"
assert_eq "an edited herdr config is never overwritten" "# mine" "$(cat "$CONFIG/herdr/config.toml")"
assert_eq "an edited tmux config is never overwritten" "# mine too" "$(cat "$CONFIG/tmux/tmux.conf")"
assert_eq "an edited yazi config is never overwritten" "# and mine" "$(cat "$CONFIG/yazi/yazi.toml")"
assert_eq "a changed multiplexer choice is never overwritten" "tmux" "$(cat "$CONFIG/haseen/mux")"
assert_eq "a retargeted theme link is never overwritten" "/dev/null" "$(readlink "$CONFIG/yazi/theme.toml")"
capture haseen seed user --dry-run
assert_eq "a re-run plans nothing" "" "$(grep -c DRYRUN <<<"$OUTPUT" | tr -d '0')"

# --- nothing machine-specific ships -----------------------------------------
# The repository is public and tools/secrets.sh runs before every push. These
# defaults came from the owner's live $HOME, so the scan is part of the file's
# contract, not a formality.
mapfile -t shipped < <(find "$DEFAULTS/herdr" "$DEFAULTS/tmux" "$DEFAULTS/yazi" -type f | sort)
assert_eq "all four defaults ship" "4" "${#shipped[@]}"
for f in "${shipped[@]}"; do
    rel="${f#"$REPO"/}"
    # tools/secrets.sh's own privacy patterns.
    assert_eq "no tailnet address in $rel" "" \
        "$(grep -oE '\b100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.[0-9]{1,3}\.[0-9]{1,3}\b' "$f" | tr '\n' ' ')"
    assert_eq "no absolute home path in $rel" "" \
        "$(grep -oE '/home/[a-z_][a-z0-9_-]*/' "$f" | tr '\n' ' ')"
    assert_eq "no private key in $rel" "" \
        "$(grep -o 'BEGIN [A-Z ]*PRIVATE KEY' "$f" | tr '\n' ' ')"
    assert_eq "no personal mail address in $rel" "" \
        "$(grep -oE '[A-Za-z0-9._%+-]+@(gmail|outlook|hotmail|proton(mail)?|icloud|yahoo)\.[a-z]+' "$f" | tr '\n' ' ')"
    # This machine, by name or by address.
    assert_eq "no hostname or IP literal in $rel" "" \
        "$(grep -oiE "\b$(hostname)\b|\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" "$f" | tr '\n' ' ')"
    # The owner's own helpers and credential stores, which the live configs
    # called and haseen does not ship.
    assert_eq "no private helper or credential path in $rel" "" \
        "$(grep -oE 'upload-files\.sh|play-media\.sh|imv-dir|wallpaper-next\.sh|bitwarden|\.local/bin/omarchy' "$f" | tr '\n' ' ')"
    # A token-shaped assignment.
    assert_eq "no secret-shaped assignment in $rel" "" \
        "$(grep -oiE '(token|api[_-]?key|passwd|password|secret)[[:space:]]*=[[:space:]]*[\"'"'"'][^\"'"'"']+' "$f" | tr '\n' ' ')"
done

# --- the lab wrapper ---------------------------------------------------------
sandbox lab
use_path
export HASEEN_LAB_DIR="$SANDBOX/lab"
# A read-only probe, not a mutation: lab.sh asks docker whether it is there.
stub docker "exit 1"

capture "$REPO/tools/lab.sh" --help
assert_status "--help exits 0" 0 "$STATUS"
assert_contains "--help says the default is a dry run" "$OUTPUT" "the default"
assert_contains "--help names the lab checkout variable" "$OUTPUT" "HASEEN_LAB_DIR"

capture "$REPO/tools/lab.sh" --dry-run
assert_status "a run with no hypervisor fails" 1 "$STATUS"
assert_contains "the report is printed before the failure" "$OUTPUT" \
    "Prerequisites for a CachyOS lab guest:"
# One sentence, and it says why rather than just naming a binary.
assert_contains "the qemu failure is one clear sentence" "$OUTPUT" \
    "Error: qemu is unavailable: the lab runs it inside a container and docker is unreachable here, and there is no qemu-system-x86_64 on this host either, so no guest can be started."
assert_contains "the missing prerequisite is named" "$OUTPUT" "MISSING qemu"
assert_contains "the guest it would build is a CachyOS one" "$OUTPUT" \
    "CachyOS desktop ISO"
assert_contains "it points the lab at this checkout" "$OUTPUT" "$REPO -> ~/haseen in the guest"
# With no lab checkout there is no cachyos arm and no Secure Boot firmware
# knob to point at; both are prerequisites, and the report says where to fix them.
assert_contains "the missing cachyos guest mode is reported" "$OUTPUT" \
    "the lab checkout has no LAB_DISTRO=cachyos arm"
assert_contains "the missing Secure Boot firmware is reported" "$OUTPUT" \
    "the lab checkout has no LAB_SECUREBOOT knob"
assert_not_contains "no lab command was planned" "$OUTPUT" "DRYRUN:"
assert_eq "no clone landed anywhere" "" "$([[ -e $HASEEN_LAB_DIR ]] && echo exists)"
assert_eq "and nothing landed in the repo" "" \
    "$([[ -e $REPO/lab || -e $REPO/images || -e $REPO/t1nk33r-lab ]] && echo exists)"

capture "$REPO/tools/lab.sh" bogus
assert_status "an unexpected argument is rejected" 2 "$STATUS"
