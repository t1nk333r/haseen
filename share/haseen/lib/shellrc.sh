# shellcheck shell=bash
# shellrc.sh — whether a shell rc includes haseen's fragment
# (share/haseen/default/shell/init.sh). Sourced by seeds/60-shell.sh, which
# adds the include, and lib/catalog.sh, which counts it as `mise activate`.

# shellrc_include RC — print `live` when a line of RC names an init.sh that
# exists on this machine, `dead` when every line that names one points at a
# path that does not (an rc shared with a machine whose haseen has another
# prefix, or a checkout since deleted), and `none` otherwise. A commented-out
# include counts as an include: the user turned it off, so the seed must not
# hand it back.
shellrc_include() {
    local path state=none
    while IFS= read -r path; do
        path="${path#[\"\']}"
        path="${path%[\"\']}"
        path="${path/#\~\//$HOME/}"
        path="${path/#\$HOME\//$HOME/}"
        path="${path/#\$\{HOME\}\//$HOME/}"
        if [[ -r $path ]]; then
            state=live
            break
        fi
        state=dead
    done < <(grep -soE "\"[^\"]*share/haseen/default/shell/init\.sh\"|'[^']*share/haseen/default/shell/init\.sh'|[^[:space:]\"';&|]*share/haseen/default/shell/init\.sh" "$1")
    printf '%s\n' "$state"
}
