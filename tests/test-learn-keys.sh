# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# Plan 071: Learn › Tmux as Omarchy's annotated list (a throwaway tmux server
# on its own socket reads the config) and `haseen menu select`, the menu
# card's dmenu mode, as seen from its caller. The key bindings list is in
# test-keybinds.sh.

# --- haseen tmux keybinds --------------------------------------------------------
if ! command -v tmux >/dev/null; then
    echo "  SKIP tmux keybinds: tmux not found" >&2
else
    sandbox tmux-keybinds
    export TMUX_TMPDIR="$SANDBOX/tmux"
    mkdir -p "$TMUX_TMPDIR"
    unset TMUX TMUX_CONF
    conf="$SANDBOX/tmux.conf"
    # unbind -a on root: tmux 3.7 then lists nothing for `list-keys -T root`,
    # which hid every root key from Omarchy's listing.
    cat >"$conf" <<'EOF'
set -g prefix C-a
set -g prefix2 C-b
set -g mode-keys vi
unbind-key -a -T root
bind -N "Split right" | split-window -h
bind C-- resize-pane -D
bind -n M-Left select-pane -L
bind -n M-S-Enter split-window -v
bind -n MouseDown1Pane select-pane -t =
bind -T copy-mode-vi v send -X begin-selection
run-shell 'exit 127'
EOF
    capture haseen tmux keybinds --print --config "$conf"
    assert_status "the config is read" 0 "$STATUS"
    rows="$OUTPUT"
    assert_eq "the prefix leads" "PREFIX                           → CTRL + A / CTRL + B" "$(head -1 <<<"$rows")"
    assert_contains "a note annotates its key" "$rows" "PREFIX + |                       → Split right"
    assert_contains "C-- is CTRL + -" "$rows" "PREFIX + CTRL + -                → resize-pane -D"
    assert_contains "root keys are bare, modifiers named" "$rows" "ALT + LEFT                       → select-pane -L"
    assert_contains "several modifiers, a named key" "$rows" "ALT + SHIFT + ENTER              → split-window -v"
    assert_contains "copy mode keys are COPY MODE + KEY" "$rows" "COPY MODE + v                    → send-keys -X begin-selection"
    assert_contains "tmux's own prefix keys stay, with tmux's notes" "$rows" "PREFIX + d                       → Detach the current client"
    assert_not_contains "mouse events are not keys" "$rows" "MouseDown"
    assert_not_contains "the emacs copy table is not the one in use" "$rows" "COPY MODE + CTRL + G "
    assert_eq "every row reads KEYS → what" "" "$(grep -v ' → ' <<<"$rows" || true)"
    assert_eq "no row twice" "" "$(sort <<<"$rows" | uniq -d)"
    assert_eq "the throwaway server is gone" "" "$(pgrep -f 'haseen-keys cat' || true)"

    order="$(cut -d' ' -f1 <<<"$rows" | uniq | paste -sd' ' -)"
    assert_eq "prefix keys, then root keys, then copy mode" "PREFIX ALT COPY" "$(tr ' ' '\n' <<<"$order" | grep -E '^(PREFIX|ALT|COPY)$' | uniq | paste -sd' ' -)"

    capture haseen tmux keybinds --print
    assert_status "no config at all: tmux's own bindings" 0 "$STATUS"
    assert_eq "tmux's own prefix" "PREFIX                           → CTRL + B" "$(head -1 <<<"$OUTPUT")"

    mkdir -p "$XDG_CONFIG_HOME/tmux"
    cp "$conf" "$XDG_CONFIG_HOME/tmux/tmux.conf"
    capture haseen tmux keybinds --print
    assert_eq "\$XDG_CONFIG_HOME/tmux/tmux.conf is the default" "PREFIX                           → CTRL + A / CTRL + B" "$(head -1 <<<"$OUTPUT")"

    capture haseen tmux keybinds --config "$SANDBOX/missing.conf"
    assert_status "a missing config is an error" 1 "$STATUS"
    assert_contains "naming it" "$OUTPUT" "missing.conf"

    # Shown in the menu's list, 800 wide and 40% of the focused monitor high;
    # choosing a row only closes it, as in Omarchy.
    stub hyprctl 'echo "[{\"focused\": false, \"height\": 2160}, {\"focused\": true, \"height\": 900}]"'
    stub haseen-menu-select 'printf "%s\n" "$*" >"'"$SANDBOX"'/picker.args"; cat >"'"$SANDBOX"'/picker.in"; echo picked'
    capture haseen-tmux-keybinds
    assert_status "the list opens" 0 "$STATUS"
    assert_eq "titled and sized like Omarchy's" "Tmux keybindings --width 800 --height 360" "$(cat "$SANDBOX/picker.args")"
    assert_eq "the list gets the rows --print shows" "$rows" "$(cat "$SANDBOX/picker.in")"
    assert_eq "the choice is not printed" "" "$OUTPUT"
fi

# --- haseen menu select ----------------------------------------------------------
# The shell side is stubbed: qs answers the IPC call the way Panel.qml does,
# writing the choice and then one line to the caller's FIFO.
sandbox menu-select
export XDG_RUNTIME_DIR="$SANDBOX/run"
mkdir -p "$XDG_RUNTIME_DIR"
answer() {
    stub qs 'req="$7"
cp "$req" "'"$SANDBOX"'/request.json"
sel=$(jq -r .selectionFile "$req"); done=$(jq -r .doneFile "$req")
'"$1"'
printf "x\n" 1<>"$done"
echo 1'
}
answer 'jq -r ".options[1]" "$req" >"$sel"'
capture bash -c 'printf "one\ntwo words\n\tglyph row\tdetail\n" | haseen menu select Pick -- --width 800 --height 500'
assert_status "a choice exits 0" 0 "$STATUS"
assert_eq "the chosen line is printed" "two words" "$OUTPUT"
assert_eq "the request carries prompt, size and stdin's lines" \
    '{"prompt":"Pick","options":["one","two words","\tglyph row\tdetail"],"width":800,"height":500}' \
    "$(jq -c '{prompt, options, width, height}' "$SANDBOX/request.json")"
assert_eq "the request files live in a private runtime dir" "true" \
    "$(jq -r '.doneFile | startswith("'"$XDG_RUNTIME_DIR"'/haseen-select.")' "$SANDBOX/request.json")"
assert_eq "and are removed afterwards" "" "$(ls "$XDG_RUNTIME_DIR")"

capture haseen menu select Size small large --width 400
assert_eq "options as arguments, haseen's --width" '{"options":["small","large"],"width":400,"height":null}' \
    "$(jq -c '{options, width, height}' "$SANDBOX/request.json")"

answer ':'
capture haseen menu select Pick a b
assert_status "nothing chosen exits 1" 1 "$STATUS"
assert_eq "and prints nothing" "" "$OUTPUT"

capture haseen menu select Pick
assert_status "no options is a usage error" 1 "$STATUS"
assert_contains "saying so" "$OUTPUT" "nothing to choose from"

# A shell that dies with the list open: the caller stops waiting.
stub qs 'sh -c "exit 0" & wait; echo 999999'
capture timeout 10 haseen menu select Pick a b
assert_status "a dead shell ends the wait" 1 "$STATUS"
assert_contains "with a reason" "$OUTPUT" "the shell went away"
