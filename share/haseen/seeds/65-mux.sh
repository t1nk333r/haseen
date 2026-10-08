# shellcheck shell=bash
# Terminal multiplexer. Sourced by bin/haseen-seed-user, which defines
# DEFAULTS, CONFIG and COMPOSE and calls seed_main once.
#
# haseen:seed $CONFIG/herdr/config.toml|herdr, the default multiplexer, on the tmux keymap
# haseen:seed $CONFIG/tmux/tmux.conf|tmux, the fallback, with the same keymap
# haseen:seed $CONFIG/haseen/mux|which of the two haseen prefers
#
# haseen ships both. herdr is the default: it is what the owner runs, and the
# `[omarchy]` build is Apache-2.0. tmux is kept because it is on every machine
# worth sshing into, and both configs carry the same chords, so the fingers
# learn one keymap. The herdr config annotates every binding with the tmux
# command it replaces — that is the point of it, and why neither file is a
# copy of upstream's.
#
# ~/.config/haseen/mux holds the choice as one bare word and nothing else, so
# reading it is `read -r mux <file` with no parsing. It is resolved once here
# and the user's to edit afterwards. share/haseen/default/shell/functions.sh
# reads it: already being inside a multiplexer wins, then this file, then
# whichever binary is installed.
seed_main() {
    seed_user_file "$DEFAULTS/herdr/config.toml" "$CONFIG/herdr/config.toml"
    seed_user_file "$DEFAULTS/tmux/tmux.conf" "$CONFIG/tmux/tmux.conf"

    local choice="$CONFIG/haseen/mux"
    # -L too: a dangling link is the user's, never written through.
    [[ -e $choice || -L $choice ]] && return 0
    # herdr wins whenever it is there, including when tmux is too. A home
    # seeded before the packages land still gets herdr: that is what the
    # layers install, and the resolver falls back on its own if it is absent.
    local mux=herdr
    if ! have herdr && have tmux; then
        mux=tmux
    fi
    write_user_file "$choice" <<<"$mux"
}
