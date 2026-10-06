# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# Speaker tuning: which tuning a machine matches, the WirePlumber config an
# apply plans, and the two refusals (no limiter, no speaker sink).
sandbox audio

WP_DIR="$HOME/.config/wireplumber/wireplumber.conf.d"
FRAGMENT="$WP_DIR/90-haseen-speaker-tuning.conf"
SOFT_MIXER="$WP_DIR/50-haseen-alsa-soft-mixer.conf"
SPEAKER="alsa_output.pci-0000_00_1f.3-platform-sof_sdw.HiFi__Speaker__sink"
TUNING_DIR="$REPO/share/haseen/audio/tunings/dell-xps-2026"

# pactl is the only live-graph read the command makes. The fake answers the two
# listings from the environment; anything that would change the graph reports
# itself the way tests/lib.sh's stubs do, so a dry run that reached it fails
# assert_dry_pure.
stub pactl 'case "$*" in
  "list sinks short") printf "%s" "${FAKE_SINKS:-}" ;;
  "list sink-inputs") printf "%s" "${FAKE_SINK_INPUTS:-}" ;;
  *) echo "STUB-CALLED: pactl $*" >&2; exit 97 ;;
esac'

exists() { if [[ -e $1 ]]; then echo present; else echo absent; fi; }

export FAKE_SINKS="0	$SPEAKER	PipeWire	s32le 2ch 48000Hz	RUNNING"
export FAKE_SINK_INPUTS=""

# --- a machine a tuning was measured for -------------------------------------
export HASEEN_SYSROOT="$FIXTURES/audio-dell-xps"

capture haseen audio tuning show
assert_status "show reports on a matching machine" 0 "$STATUS"
assert_contains "the DMI identity is printed" "$OUTPUT" "Dell Inc. | XPS 14 9450 | XPS"
assert_contains "the SKU the tuning is keyed on is printed" "$OUTPUT" "SKU:          0DB9"
assert_contains "the matched tuning is named" "$OUTPUT" "Dell XPS 14/16 (2026) speakers (dell-xps-2026)"
assert_contains "the speaker sink it would sit in front of" "$OUTPUT" "Speaker sink: $SPEAKER"
assert_contains "the limiter is found in the fixture" "$OUTPUT" "Limiter:      present"
assert_contains "nothing is installed yet" "$OUTPUT" "Installed:    no"
assert_contains "and the tuning sink is not in the graph" "$OUTPUT" "Tuning sink:  absent"

capture haseen audio tuning show --quiet
assert_status "--quiet is the predicate for the limiter package" 0 "$STATUS"
assert_eq "--quiet prints the tuning id alone" "dell-xps-2026" "$OUTPUT"

# --- applying it: the WirePlumber config it plans ----------------------------
capture haseen audio tuning apply --dry-run
assert_status "a planned apply succeeds" 0 "$STATUS"
assert_dry_pure "apply on a matching machine" "$OUTPUT"
assert_contains "the fragment is written into wireplumber.conf.d" "$OUTPUT" "DRYRUN: write $FRAGMENT"
assert_contains "it is a filter-chain module" "$OUTPUT" "name = libpipewire-module-filter-chain"
assert_contains "the chain ends in the LSP lookahead limiter" "$OUTPUT" \
    'plugin = "http://lsp-plug.in/plugins/lv2/limiter_stereo"'
assert_contains "the tuning sink carries haseen's name" "$OUTPUT" 'node.name   = "haseen_speaker_tuning"'
assert_contains "its output targets the matched speaker sink" "$OUTPUT" "target.object = \"$SPEAKER\""
assert_not_contains "no placeholder survives rendering" "$OUTPUT" "@SPEAKER_SINK@"
assert_contains "the soft-mixer default is seeded beside it" "$OUTPUT" "DRYRUN: seed $SOFT_MIXER"
assert_contains "and WirePlumber is restarted to load it" "$OUTPUT" \
    "DRYRUN: systemctl --user restart wireplumber.service"
assert_contains "the tuning that was applied is named" "$OUTPUT" \
    "Installed speaker tuning: Dell XPS 14/16 (2026) speakers (in front of $SPEAKER)"
assert_eq "a dry run writes no fragment" absent "$(exists "$FRAGMENT")"
assert_eq "and no soft-mixer drop-in" absent "$(exists "$SOFT_MIXER")"

# The rendered fragment is the shipped graph with one substitution, so a test
# can produce the same bytes and check the "already current" short-circuit.
mkdir -p "$WP_DIR"
sed "s|@SPEAKER_SINK@|$SPEAKER|g" "$TUNING_DIR/filter-chain.conf" >"$FRAGMENT"
export FAKE_SINKS="0	$SPEAKER	PipeWire	s32le 2ch 48000Hz	IDLE
1	haseen_speaker_tuning	PipeWire	f32le 2ch 48000Hz	RUNNING"

capture haseen audio tuning apply --dry-run
assert_status "a current tuning is left alone" 0 "$STATUS"
assert_dry_pure "apply when already current" "$OUTPUT"
assert_contains "and says so" "$OUTPUT" "already current: Dell XPS 14/16 (2026) speakers"
assert_not_contains "without planning a write" "$OUTPUT" "DRYRUN: write"

capture haseen audio tuning apply --dry-run --force
assert_contains "--force plans the write anyway" "$OUTPUT" "DRYRUN: write $FRAGMENT"

capture haseen audio tuning show
assert_contains "show finds the installed fragment" "$OUTPUT" "Installed:    yes ($FRAGMENT)"
assert_contains "and the tuning sink in the graph" "$OUTPUT" "Tuning sink:  present"

# --- removing it -------------------------------------------------------------
capture haseen audio tuning remove --dry-run
assert_status "a planned removal succeeds" 0 "$STATUS"
assert_dry_pure "remove" "$OUTPUT"
assert_contains "the fragment is deleted" "$OUTPUT" "DRYRUN: rm -f $FRAGMENT"
assert_contains "and WirePlumber restarted" "$OUTPUT" "DRYRUN: systemctl --user restart wireplumber.service"
assert_contains "the shared soft mixer is kept" "$OUTPUT" "stays: it is not part of a tuning"
assert_eq "a dry run removes nothing" present "$(exists "$FRAGMENT")"

rm -f "$FRAGMENT"
capture haseen audio tuning remove --dry-run
assert_status "removing nothing is not an error" 0 "$STATUS"
assert_eq "and says so" "No speaker tuning installed." "$OUTPUT"

# --- the limiter is a hard requirement ---------------------------------------
# A copy of the fixture with the LV2 limiter taken out: the tuning still
# matches, but its graph could not instantiate.
cp -a "$FIXTURES/audio-dell-xps" "$SANDBOX/no-lv2"
rm -r "$SANDBOX/no-lv2/usr"
export HASEEN_SYSROOT="$SANDBOX/no-lv2"

capture haseen audio tuning show
assert_contains "show names the missing package" "$OUTPUT" "Limiter:      missing (needs lsp-plugins-lv2)"
assert_contains "while still matching the machine" "$OUTPUT" "(dell-xps-2026)"

capture haseen audio tuning apply --dry-run
assert_status "apply refuses without the limiter" 1 "$STATUS"
assert_dry_pure "apply without the limiter" "$OUTPUT"
assert_contains "and says what to install" "$OUTPUT" "lsp-plugins-lv2 is required for the tuning limiter"
assert_eq "nothing is planned" absent "$(exists "$FRAGMENT")"

# --- the graph has to be up --------------------------------------------------
export HASEEN_SYSROOT="$FIXTURES/audio-dell-xps"
export FAKE_SINKS="0	alsa_output.usb-Generic_USB_Audio-00.analog-stereo	PipeWire	s16le 2ch 48000Hz	IDLE"
capture haseen audio tuning apply --dry-run
assert_status "apply refuses when the speaker sink is absent" 1 "$STATUS"
assert_dry_pure "apply with no speaker sink" "$OUTPUT"
assert_contains "and says to re-run after login" "$OUTPUT" "re-run after login: haseen audio tuning apply"

# EasyEffects would move every default-following stream onto its own sink, so a
# tuning installed underneath it is bypassed.
export FAKE_SINKS="0	$SPEAKER	PipeWire	s32le 2ch 48000Hz	IDLE
1	easyeffects_sink	PipeWire	f32le 2ch 48000Hz	RUNNING"
capture haseen audio tuning apply --dry-run
assert_status "apply refuses under EasyEffects" 1 "$STATUS"
assert_contains "and says how to stop it" "$OUTPUT" "systemctl --user disable --now easyeffects.service"

# --- a machine nothing was measured for --------------------------------------
export FAKE_SINKS="0	$SPEAKER	PipeWire	s32le 2ch 48000Hz	IDLE"
export HASEEN_SYSROOT="$FIXTURES/hw-asus-rog"

capture haseen audio tuning show
assert_status "show works on an unmatched machine" 0 "$STATUS"
assert_contains "it says nothing ships for it" "$OUTPUT" "Tuning:       nothing ships for this laptop"
assert_not_contains "and names no tuning" "$OUTPUT" "dell-xps-2026"

capture haseen audio tuning show --quiet
assert_status "--quiet exits 1 there, so no limiter is installed" 1 "$STATUS"
assert_eq "and prints nothing" "" "$OUTPUT"

capture haseen audio tuning apply --dry-run
assert_status "apply is a no-op, not a failure" 0 "$STATUS"
assert_dry_pure "apply on an unmatched machine" "$OUTPUT"
assert_contains "it says why" "$OUTPUT" "No speaker tuning matches this laptop"
assert_not_contains "and plans no WirePlumber config at all" "$OUTPUT" "DRYRUN:"
assert_eq "nothing landed in wireplumber.conf.d" "" "$(ls "$WP_DIR")"

# --- the command's own surface -----------------------------------------------
capture haseen audio tuning
assert_status "a missing verb is a usage error" 2 "$STATUS"
assert_contains "usage is printed" "$OUTPUT" "Usage: haseen audio tuning"
capture haseen audio tuning sideways
assert_status "an unknown verb is a usage error" 2 "$STATUS"
capture haseen audio tuning --help
assert_status "--help exits 0" 0 "$STATUS"
assert_contains "--help explains the predicate" "$OUTPUT" "exits 1 when nothing"
