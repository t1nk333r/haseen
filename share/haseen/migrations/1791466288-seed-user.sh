# shellcheck shell=bash
# Plans 037, 038, 041, 044, 047: haseen's user-level defaults are seeds: the
# fontconfig include and its Arabic fallbacks, the bash/zsh rc include that
# turns on zoxide, eza, bat, mise and fzf, the tmux, herdr and yazi configs,
# the satty and upload configs, and the user xdg-terminals.list. install.sh
# seeds on every run; a HOME upgraded another way (`install.sh --tree-only`,
# then `haseen migrate` or the login notice) gets them here.
# Safe to re-run: a seed writes only what is missing, so a file the user has
# made their own stays. A seed that fails (a read-only rc) is named and does
# not hold back the migrations after this one; `haseen seed user` retries it.

# shellcheck source=../lib/common.sh
source "$HASEEN_PATH/lib/common.sh"

haseen seed user || warn "some seeds failed (named above); fix them and run: haseen seed user"
