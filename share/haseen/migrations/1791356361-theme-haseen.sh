# shellcheck shell=bash
# Plan 066: the stock theme greek-noir-akane is now haseen. Only when it is
# this user's current theme: move ~/.config/haseen/backgrounds/greek-noir-akane/
# to backgrounds/haseen/ (unless that folder exists already), point
# current/background at the same image in the moved folder, then rename
# theme.name. The rendered current/theme stays; its colours are the same.
# Safe to re-run: after theme.name says haseen there is nothing to do.

# shellcheck source=../lib/common.sh
source "$HASEEN_PATH/lib/common.sh"
# shellcheck source=../layers/theme/theme-lib.sh
source "$HASEEN_PATH/layers/theme/theme-lib.sh"

old=greek-noir-akane
new=haseen
[[ -r $THEME_NAME_FILE && $(<"$THEME_NAME_FILE") == "$old" ]] || exit 0

from="$THEME_USER_BACKGROUNDS_DIR/$old"
to="$THEME_USER_BACKGROUNDS_DIR/$new"
if [[ -d $from && ! -e $to && ! -L $to ]]; then
    mv -T -- "$from" "$to"
    info "moved $from to $to"
fi

# The link is written before theme.name, so a run that stops in between
# finds theme.name unchanged and finishes the job.
link="$(readlink "$THEME_BACKGROUND_LINK" 2>/dev/null || true)"
if [[ $link == "$from"/* && -e $to/${link#"$from"/} ]]; then
    theme_set_background_link "$to/${link#"$from"/}"
fi

printf '%s\n' "$new" >"$THEME_NAME_FILE.tmp"
mv -- "$THEME_NAME_FILE.tmp" "$THEME_NAME_FILE"
info "theme $old is now called $new"
