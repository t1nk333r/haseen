# shellcheck shell=bash
# Shell rc. Sourced by bin/haseen-seed-user, which defines DEFAULTS, CONFIG and
# COMPOSE and calls seed_main once.
#
# haseen:seed $HOME/.bashrc|one line sourcing haseen's aliases, functions and tool init
# haseen:seed $HOME/.zshrc|the same line, only if you already have a zshrc
#
# The rc is the user's file, so this is the one seed that appends instead of
# writing: exactly one line, only if it is not there yet, never touching what
# is above it. Everything haseen owns lives behind that line, in
# share/haseen/default/shell/, and is replaced on upgrade (architecture §3).
#
# The path is absolute because the rc has no $HASEEN_PATH, and it differs
# between the checkout, /usr/local and /usr.
seed_main() {
    local include="$DEFAULTS/shell/init.sh"
    local rc
    for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
        # A zshrc is only written when the user already has one: haseen does
        # not decide that you use zsh.
        [[ $rc == *.zshrc && ! -e $rc ]] && continue
        # grep -F on the path, so an edited comment or a reordered rc still
        # counts as "already included".
        grep -qsF "$include" "$rc" && continue
        append_user_file "$rc" <<EOF

# haseen: aliases, functions and tool init. Yours is everything else here.
[ -r "$include" ] && . "$include"
EOF
    done
}
