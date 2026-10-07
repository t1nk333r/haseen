# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# ./install.sh's guided picker (plan 063), driven through --pick with scripted
# stdin and --dry-run: the layer list it hands to `haseen layer apply`, the
# optional setup steps (all off unless ticked), install.toml and its reuse,
# and that a run without a terminal and without --pick is unchanged.
sandbox install-picker
export HASEEN_SYSROOT="$FIXTURES/cachyos-grub-plain"
TOML="$HOME/.config/haseen/install.toml"
DEFAULT_ORDER="[*] apply order: base chaotic omarchy-repo desktop theme shell"
# The plain picker's numbers: the six default layers, then the optional ones
# sorted (7 ai, 8 dms, 9 flatpak, 10 gaming, 11 secureboot), 12 continues.
# Setup steps: 1 keyd, 2 fingerprint, 3 geoclue, 4 dotfiles, 5 continues.

install_with() { # STDIN ARG... — run install.sh with STDIN as its input
    local input="$1"
    shift
    capture "$REPO/install.sh" "$@" <<<"$input"
}

saved() { # FILE-CONTENT — a choice saved by an earlier run
    mkdir -p "$(dirname "$TOML")"
    printf '%s\n' "$1" >"$TOML"
}

# --- no terminal, no --pick: unchanged -----------------------------------------
capture "$REPO/install.sh" --dry-run </dev/null
assert_status "piped run succeeds" 0 "$STATUS"
assert_dry_pure "piped run" "$OUTPUT"
assert_contains "piped run applies the default layers" "$OUTPUT" "$DEFAULT_ORDER"$'\n'
assert_not_contains "piped run shows no picker" "$OUTPUT" "Toggle a number"
assert_not_contains "piped run saves no choice" "$OUTPUT" "install.toml"
assert_not_contains "piped run runs no setup step" "$OUTPUT" "setup step:"

saved 'layers = ["base", "flatpak"]
setup = ["keyd"]'
capture "$REPO/install.sh" --dry-run </dev/null
assert_contains "piped run ignores a saved choice" "$OUTPUT" "$DEFAULT_ORDER"$'\n'
assert_not_contains "piped run offers no reuse" "$OUTPUT" "last install choices"
assert_not_contains "piped run runs no saved setup step" "$OUTPUT" "setup step:"
rm -f "$TOML"

capture "$REPO/install.sh" --dry-run --layers base,flatpak </dev/null
assert_contains "--layers still decides alone" "$OUTPUT" "[*] apply order: base chaotic desktop flatpak"
assert_not_contains "--layers shows no picker" "$OUTPUT" "Toggle a number"

install_with "" --pick --layers base --dry-run
assert_status "--pick with --layers is refused" 1 "$STATUS"
assert_contains "and says why" "$OUTPUT" "does not combine"
install_with "" --pick --yes --dry-run
assert_status "--pick with --yes is refused" 1 "$STATUS"

# --- the picker's defaults: core layers on, every optional piece off -----------
install_with "" --pick --dry-run
assert_status "picker at end of input succeeds" 0 "$STATUS"
assert_dry_pure "picker defaults" "$OUTPUT"
assert_contains "picker lists the layers" "$OUTPUT" "[ ] secureboot"
assert_contains "core layers start ticked" "$OUTPUT" "[x] omarchy-repo"
assert_contains "optional setup starts off" "$OUTPUT" "[ ] keyd"
assert_contains "defaults apply the default layers" "$OUTPUT" "$DEFAULT_ORDER"$'\n'
assert_contains "defaults are saved (dry-run: printed)" "$OUTPUT" "DRYRUN: write $TOML:"
assert_contains "saved setup is empty" "$OUTPUT" '| setup = []'
assert_not_contains "no setup step runs" "$OUTPUT" "setup step:"
assert_eq "dry-run writes no install.toml" "absent" "$([[ -e $TOML ]] && echo present || echo absent)"

# --- a scripted pick: drop omarchy-repo, add flatpak, tick keyd and geoclue ----
install_with $'3\n9\n12\n1\n3\n5' --pick --dry-run
assert_status "scripted pick succeeds" 0 "$STATUS"
assert_dry_pure "scripted pick" "$OUTPUT"
assert_contains "the picked layers are applied" "$OUTPUT" "[*] apply order: base chaotic desktop theme shell flatpak"$'\n'
assert_contains "the pick is saved" "$OUTPUT" '| layers = ["base", "chaotic", "desktop", "theme", "shell", "flatpak"]'
assert_contains "the setup steps are saved" "$OUTPUT" '| setup = ["keyd", "geoclue"]'
assert_contains "keyd runs after the layers" "$OUTPUT" "[*] setup step: haseen setup keyd on"
assert_contains "keyd plans its config" "$OUTPUT" "DRYRUN: write /etc/keyd/default.conf"
assert_contains "geoclue runs after the layers" "$OUTPUT" "[*] setup step: haseen setup geoclue on"
assert_contains "geoclue plans its drop-in" "$OUTPUT" "DRYRUN: write /etc/geoclue/conf.d/90-haseen.conf"
assert_not_contains "fingerprint stays off" "$OUTPUT" "setup fingerprint"
order="$(grep -nE 'layer shell applied|setup step: haseen setup keyd' <<<"$OUTPUT" | cut -d: -f1 | paste -sd' ')"
read -r shell_line keyd_line <<<"$order"
assert_eq "setup steps follow the layers" "yes" "$( ((keyd_line > shell_line)) && echo yes || echo no)"

# --- reuse the last choice -------------------------------------------------------
saved '# written by an earlier run
layers = ["base", "chaotic", "desktop", "theme", "shell", "flatpak"]
setup = ["geoclue"]'
install_with "y" --pick --dry-run
assert_status "reuse succeeds" 0 "$STATUS"
assert_dry_pure "reuse" "$OUTPUT"
assert_contains "reuse is offered with the last choice" "$OUTPUT" "    layers: base, chaotic, desktop, theme, shell, flatpak"
assert_contains "reused layers are applied" "$OUTPUT" "[*] apply order: base chaotic desktop theme shell flatpak"$'\n'
assert_contains "reused setup step runs" "$OUTPUT" "[*] setup step: haseen setup geoclue on"
assert_not_contains "reuse shows no picker" "$OUTPUT" "Toggle a number"
assert_not_contains "a reused choice is not rewritten" "$OUTPUT" "DRYRUN: write $TOML"

install_with "" --pick --dry-run
assert_contains "end of input reuses" "$OUTPUT" "[*] apply order: base chaotic desktop theme shell flatpak"$'\n'

install_with $'n\n12\n2\n5' --pick --dry-run
assert_contains "declining opens the picker from the last choice" "$OUTPUT" "[x] flatpak"
assert_contains "and keeps the last setup ticked" "$OUTPUT" "[x] geoclue"
assert_contains "the new pick is saved" "$OUTPUT" '| setup = ["fingerprint", "geoclue"]'
assert_contains "the new setup step runs" "$OUTPUT" "[*] setup step: haseen setup fingerprint"

saved 'layers = ["base", "nonesuch"]
setup = ["keyd", "warp"]'
install_with "y" --pick --dry-run
assert_contains "an unknown layer is dropped" "$OUTPUT" "unknown layer 'nonesuch', dropped"
assert_contains "an unknown step is dropped" "$OUTPUT" "unknown setup step 'warp', dropped"
assert_contains "the rest is reused" "$OUTPUT" "[*] apply order: base"$'\n'
assert_contains "with its known step" "$OUTPUT" "[*] setup step: haseen setup keyd on"

saved 'setup = ["keyd"]'
install_with $'12\n5' --pick --dry-run
assert_not_contains "a choice without layers is not offered" "$OUTPUT" "last install choices"
assert_contains "the picker starts from the defaults" "$OUTPUT" "$DEFAULT_ORDER"$'\n'
rm -f "$TOML"

# --- dotfiles needs its URL ------------------------------------------------------
install_with $'12\n4\n5\n' --pick --dry-run
assert_contains "an empty dotfiles URL skips the step" "$OUTPUT" "skipping the dotfiles step"
assert_contains "and it is not saved" "$OUTPUT" '| setup = []'

# git answers like an unreachable remote: the step fails, the install does not.
stub git 'echo "fatal: unreachable in tests" >&2; exit 128'
install_with $'12\n4\n5\nhttps://example.invalid/dots.git' --pick --dry-run
assert_status "a failing setup step does not fail the install" 0 "$STATUS"
assert_contains "the URL is saved" "$OUTPUT" '| dotfiles_url = "https://example.invalid/dots.git"'
assert_contains "dotfiles runs with it" "$OUTPUT" "[*] setup step: haseen setup dotfiles https://example.invalid/dots.git"
assert_contains "its failure is reported" "$OUTPUT" "haseen setup dotfiles https://example.invalid/dots.git failed"

install_with $'12\n4\n5\nhttps://example.invalid/my dots.git' --pick --dry-run
assert_contains "a URL with a space is refused" "$OUTPUT" "skipping the dotfiles step"
