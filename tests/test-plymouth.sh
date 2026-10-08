# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# The boot splash: the colours come from the current theme, the hook and the
# kernel command line are what decide whether it is ever seen, and status says
# which of those is missing.
# node runs the script against a fake Plymouth API; looked up before sandbox()
# narrows PATH.
NODE="$(command -v node || true)"
sandbox plymouth

sysroot="$SANDBOX/sysroot"
mkdir -p "$sysroot/etc/mkinitcpio.conf.d" "$sysroot/etc/plymouth" "$sysroot/proc" \
    "$SANDBOX/state/haseen/current/theme" "$sysroot/boot/EFI"
export HASEEN_SYSROOT="$sysroot" XDG_STATE_HOME="$SANDBOX/state"

cat >"$SANDBOX/state/haseen/current/theme/colors.toml" <<'EOF'
mode = "dark"
accent = "#dcd7ba"
background = "#1f1f28"
foreground = "#dcd7ba"
EOF
printf 'HOOKS=(base udev autodetect modconf block encrypt filesystems fsck)\n' \
    >"$sysroot/etc/mkinitcpio.conf"
printf 'BOOT_IMAGE=/vmlinuz-linux root=/dev/mapper/root rw\n' >"$sysroot/proc/cmdline"
# plymouth_installed looks in the sysroot, so this is what "installed" means.
mkdir -p "$sysroot/usr/bin"
printf '#!/bin/sh\nexit 0\n' >"$sysroot/usr/bin/plymouth-set-default-theme"
chmod +x "$sysroot/usr/bin/plymouth-set-default-theme"
stub plymouth-set-default-theme 'exit 0'
stub mkinitcpio 'exit 0'
stub bootctl 'echo "System: ..."; exit 0'

# --- status before anything is set up -----------------------------------------
capture haseen plymouth status
assert_contains "no theme is set yet" "$OUTPUT" "theme:"
assert_contains "the hook is missing" "$OUTPUT" "missing from HOOKS"
assert_contains "and so is splash" "$OUTPUT" "no 'splash'"
assert_contains "so it is not ready" "$OUTPUT" "ready:     no"

# --- what `plymouth set` plans ------------------------------------------------
capture haseen plymouth set --dry-run
assert_dry_pure "plymouth set dry run" "$OUTPUT"
assert_contains "it reads the theme's colours" "$OUTPUT" "background #1f1f28"
assert_contains "it installs the theme descriptor" "$OUTPUT" "/usr/share/plymouth/themes/haseen/haseen.plymouth"
assert_contains "and the script" "$OUTPUT" "/usr/share/plymouth/themes/haseen/haseen.script"
assert_contains "it adds the initramfs hook" "$OUTPUT" "haseen-plymouth.conf"
assert_contains "sets the default theme" "$OUTPUT" "plymouth-set-default-theme haseen"
assert_contains "puts splash on the command line" "$OUTPUT" "quiet splash"
assert_contains "and rebuilds the initramfs" "$OUTPUT" "mkinitcpio -P"
assert_contains "it renders the selected mark in the accent (plan 059)" "$OUTPUT" "render $HASEEN_PATH/branding/kufic/mark.svg in #dcd7ba -> logo.png (mark: kufic)"
assert_contains "and installs it beside the script" "$OUTPUT" "/usr/share/plymouth/themes/haseen/logo.png"
mkdir -p "$XDG_CONFIG_HOME/haseen"
echo '{"branding": {"mark": "gate"}}' >"$XDG_CONFIG_HOME/haseen/shell.json"
capture haseen plymouth set --dry-run
assert_contains "a mark change reaches the splash" "$OUTPUT" "branding/gate/mark.svg"
rm -f "$XDG_CONFIG_HOME/haseen/shell.json"

capture haseen plymouth set --theme kanagawa --dry-run
assert_contains "a named theme is used instead" "$OUTPUT" "background #1f1f28"
capture haseen plymouth set --theme nosuchtheme --dry-run
assert_status "an unknown theme is refused" 1 "$STATUS"

capture haseen plymouth set --dry-run --no-rebuild
assert_not_contains "--no-rebuild skips mkinitcpio" "$OUTPUT" "mkinitcpio -P"
assert_contains "and says what is left to do" "$OUTPUT" "regenerate it yourself"

# --- the script that actually gets installed ----------------------------------
script="$(HASEEN_SYSROOT="$sysroot" bash -c '
    source "'"$REPO"'/share/haseen/lib/plymouth.sh"
    read -r bg fg accent <<<"$(plymouth_theme_colors "'"$SANDBOX"'/state/haseen/current/theme/colors.toml")"
    plymouth_script "$bg" "$fg" "$accent"')"
assert_not_contains "no placeholder survives" "$script" "@@"
# #1f1f28 -> 31/255 = 0.122, 40/255 = 0.157
assert_contains "the background is the theme's, as plymouth floats" "$script" "bg_r = 0.122"
assert_contains "and its blue channel too" "$script" "bg_b = 0.157"
assert_contains "the password prompt is drawn by the theme" "$script" "SetDisplayPasswordFunction"
assert_not_contains "boot messages are not drawn: the splash shows no text" "$script" "SetMessageFunction"

# --- the LUKS prompt under a fake Plymouth (plan 036, 2026-10-08) -------------
# tests/fixtures/plymouth-harness.js runs the rendered script with a recording
# Window/Image/Sprite/Plymouth and drives it as plymouthd does: 50 refreshes a
# second, the password prompt with 0, 3 and 120 asterisks, normal, quit.
if [[ -z $NODE ]]; then
    echo "  SKIP prompt checks: node not found" >&2
else
    printf '%s\n' "$script" >"$SANDBOX/haseen.script"
    capture "$NODE" "$REPO/tests/fixtures/plymouth-harness.js" "$SANDBOX/haseen.script"
    assert_status "the script runs under the fake Plymouth" 0 "$STATUS"
    report="$OUTPUT"
    q() { jq -c "$1" <<<"$report"; }
    # Sprites by what they show: the caret is the bare block, the brackets are
    # blocks stretched to arms, the scanner is the stretched bullet, the
    # asterisks are text of '*'.
    CARET='map(select(.kind == "text" and .text == "█"))[0]'
    ARMS='map(select(.src == "█"))'
    STARS='map(select(.kind == "text" and (.text // "" | test("^\\*+$"))))[0]'
    SCAN='map(select(.src == "•"))'
    assert_eq "it registers the four callbacks it uses" \
        '["SetDisplayNormalFunction","SetDisplayPasswordFunction","SetQuitFunction","SetRefreshFunction"]' "$(q .registered)"

    # Before the first key: a lit caret inside four corner brackets, no text.
    assert_eq "before a key: the caret shows" "1" "$(q ".empty | $CARET | .opacity")"
    assert_eq "before a key: eight bracket arms show" "8" "$(q "[.empty | $ARMS | .[] | select(.opacity > 0)] | length")"
    assert_eq "the brackets are thin (2 px) arms of 12 px" '[[2,12],[12,2]]' "$(q "[.empty | $ARMS | .[] | [.w, .h]] | unique")"
    assert_eq "the brackets are dimmer than the caret" "0.6" "$(q "[.empty | $ARMS | .[] | .opacity] | unique | .[0]")"
    assert_eq "before a key: no asterisk shows" "true" "$(q "[.empty[] | select(.kind == \"text\" and .text != \"█\" and .opacity > 0)] | length == 0")"
    assert_eq "the scanner hides while the prompt is up" "0" "$(q "[.empty | $SCAN | .[] | .opacity] | max")"
    assert_eq "the caret is tinted like the scanner" "$(q ".empty | $SCAN | .[0].color")" "$(q ".empty | $CARET | .color")"
    # The field takes the scanner's place: the track's width (a quarter of the
    # 1920 px screen), centred, and the caret sits inside it.
    box() { q "(.$1 | $ARMS) as \$a | [([\$a[] | .x] | min), ([\$a[] | .y] | min), ([\$a[] | .x + .w] | max), ([\$a[] | .y + .h] | max)]"; }
    assert_eq "the field is the track's width, centred" '[720,519,1200,565]' "$(box empty)"
    inside() { q "(.$1 | $ARMS) as \$a | (.$1 | $CARET) as \$c | \$c.x > ([\$a[] | .x] | min) and \$c.x + \$c.w < ([\$a[] | .x + .w] | max) and \$c.y > ([\$a[] | .y] | min) and \$c.y + \$c.h < ([\$a[] | .y + .h] | max)"; }
    assert_eq "the caret sits inside the brackets" "true" "$(inside empty)"

    # About 1 Hz at 50 frames a second: lit 25 frames, then the scanner's
    # ghost falloff for 25, twice in 100 frames.
    assert_eq "the caret is lit 25 of every 50 frames" "25 25" \
        "$(q '[.blink[0:50], .blink[50:100]] | map(map(select(. == 1)) | length) | map(tostring) | join(" ")' | tr -d '"')"
    assert_eq "it goes dark twice in 100 frames (1 Hz)" "2" \
        "$(q '[range(0; 99) as $i | select(.blink[$i] == 1 and .blink[$i + 1] < 1)] | length')"
    assert_eq "the dark half fades out like a scanner ghost" "true" \
        "$(q '.blink[24:49] as $f | ($f | . == (sort | reverse)) and $f[0] < 1 and $f[-1] < 0.15 and $f[-1] > 0')"

    # Typing: the asterisks run from the left padding, the caret follows them.
    assert_eq "three keys: three asterisks" '"***"' "$(q ".typed | $STARS | .text")"
    assert_eq "the asterisks show" "1" "$(q ".typed | $STARS | .opacity")"
    assert_eq "the caret follows the last asterisk" "true" \
        "$(q "(.typed | $STARS) as \$s | (.typed | $CARET) as \$c | \$c.x == \$s.x + \$s.w + 2 and \$c.y == \$s.y")"
    assert_eq "a key press restarts the blink lit" "1" "$(q ".typedNextFrame | $CARET | .opacity")"
    assert_eq "the field keeps its size for a short password" "$(box empty)" "$(box typed)"
    assert_eq "120 keys: the field widens to hold them" "true" "$(q "(.long | $ARMS) as \$a | ([\$a[] | .x + .w] | max) - ([\$a[] | .x] | min) > 120 * 11")"
    assert_eq "and the caret stays inside" "true" "$(inside long)"
    assert_eq "the caret and the asterisks share one monospace font" '["Monospace 14"]' \
        "$(q '[.textCalls[] | select(.text == "█" or (.text | test("^\\*+$"))) | .font] | unique')"

    # Back to normal and quit: the prompt goes, the scanner comes back.
    assert_eq "normal: the caret hides" "0" "$(q ".normal | $CARET | .opacity")"
    assert_eq "normal: the brackets hide" "0" "$(q "[.normal | $ARMS | .[] | .opacity] | max")"
    assert_eq "normal: the asterisks hide" "0" "$(q ".normal | $STARS | .opacity")"
    assert_eq "normal: the scanner returns" "1" "$(q "[.normal | $SCAN | .[] | .opacity] | max")"
    assert_eq "quit: nothing of the prompt or the scanner stays" "0" \
        "$(q "[(.quit | $ARMS | .[]), (.quit | $SCAN | .[]), (.quit | $CARET), (.quit | $STARS)] | map(.opacity) | max")"
fi

# --- the hook is evaluated the way mkinitcpio does it -------------------------
printf 'HOOKS=(base systemd plymouth autodetect)\n' >"$sysroot/etc/mkinitcpio.conf.d/zz.conf"
capture haseen plymouth status
assert_contains "a drop-in that adds the hook counts" "$OUTPUT" "plymouth is in HOOKS"
capture haseen plymouth set --dry-run
assert_not_contains "and the hook is not added twice" "$OUTPUT" "haseen-plymouth.conf"
rm -f "$sysroot/etc/mkinitcpio.conf.d/zz.conf"

# --- a machine that already boots with splash ---------------------------------
printf 'BOOT_IMAGE=/vmlinuz-linux root=/dev/mapper/root rw quiet splash\n' >"$sysroot/proc/cmdline"
printf 'Theme=haseen\n' >"$sysroot/etc/plymouth/plymouthd.conf"
mkdir -p "$sysroot/usr/share/plymouth/themes/haseen"
touch "$sysroot/usr/share/plymouth/themes/haseen/haseen.script"
printf 'HOOKS=(base udev plymouth autodetect)\n' >"$sysroot/etc/mkinitcpio.conf"
capture haseen plymouth status
assert_contains "the theme is reported" "$OUTPUT" "theme:     haseen"
assert_contains "the splash will show" "$OUTPUT" "ready:     yes"
capture haseen plymouth set --dry-run
assert_not_contains "and the command line is left alone" "$OUTPUT" "quiet splash"

# --- without plymouth installed -----------------------------------------------
rm -f "$sysroot/usr/bin/plymouth-set-default-theme"
capture haseen plymouth status
assert_contains "status says plymouth is absent" "$OUTPUT" "not installed"
capture haseen plymouth set --dry-run
assert_status "and set refuses" 1 "$STATUS"
