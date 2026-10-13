# shellcheck shell=bash
# Shell rc. Sourced by bin/haseen-seed-user.
#
# haseen:seed $HOME/.bashrc|one line sourcing haseen's aliases, functions and tool init, added once
# haseen:seed $HOME/.zshrc|the same line, only if you already have a zshrc
#
# The rc is the user's file. The one exception to "seed once, never edit"
# (owner, 2026-10-08, plan 038): this seed appends exactly one include line to
# it, once, never touching what is above it. Everything haseen owns lives behind
# that line, in share/haseen/default/shell/, and is replaced on upgrade.
#
# "Once" is recorded per rc in $HASEEN_USER_STATE/rc-include: install.sh and
# a migration both seed, and a line the user deleted stays deleted.
#
# The path is absolute because the rc has no $HASEEN_PATH, and it differs
# between the checkout, /usr/local and /usr.
seed_main() {
    # shellcheck source=share/haseen/lib/shellrc.sh
    source "$HASEEN_PATH/lib/shellrc.sh"
    local include="$DEFAULTS/shell/init.sh"
    local marker="$HASEEN_USER_STATE/rc-include"
    local rc state
    for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
        # haseen does not decide that you use zsh.
        [[ $rc == *.zshrc && ! -e $rc && ! -L $rc ]] && continue
        # A dangling rc link (stow before the clone) is never followed.
        if [[ -L $rc && ! -e $rc ]]; then
            warn "$rc is a dangling link; not adding haseen's include through it"
            continue
        fi
        state="$(shellrc_include "$rc")"
        if grep -qsxF "$rc" "$marker"; then
            # Added once already. A dead include (haseen moved) is the user's
            # line to fix: say how, change nothing.
            if [[ $state == dead ]]; then
                warn "$rc includes haseen's shell fragment from a path that no longer exists; replace that line with: [ -r \"$include\" ] && . \"$include\""
            fi
            continue
        fi
        # A live include from any tree (the checkout, then /usr/local) is
        # enough: a second one would run init.sh twice. A dead one, from an rc
        # shared with a machine where haseen has another prefix, does nothing
        # here, so this machine's line goes under it; the old line stays.
        if [[ $state != live ]]; then
            append_user_file "$rc" <<EOF

# haseen: aliases, functions and tool init. Yours is everything else here.
[ -r "$include" ] && . "$include"
EOF
        fi
        printf '%s\n' "$rc" | append_user_file "$marker"
    done
}
