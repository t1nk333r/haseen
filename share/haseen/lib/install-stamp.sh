# shellcheck shell=bash
# install-stamp.sh — what the last install put where (plan 134). install.sh
# writes it once the tree is in place; `haseen update haseen` reads it to say
# "already installed" instead of reinstalling the commit that is already
# here, and to find the prefix it installed into. Sourced, never executed.
#
# A tree installed by an older haseen has no stamp. That reads as unknown —
# never as "current" — so the first update after upgrading haseen installs.
[[ -n ${HASEEN_INSTALL_STAMP_SH:-} ]] && return 0
HASEEN_INSTALL_STAMP_SH=1

# install_stamp_path PREFIX — where the stamp lives in an installed tree.
install_stamp_path() { printf '%s/share/haseen/.installed\n' "${1%/}"; }

# install_stamp_write PREFIX COMMIT VERSION — replace the stamp, as root,
# atomically: a run interrupted mid-write leaves the previous stamp.
install_stamp_write() {
    local path tmp
    path="$(install_stamp_path "$1")"
    tmp="$path.new.$$"
    printf 'prefix=%s\ncommit=%s\nversion=%s\ndate=%s\n' "${1%/}" "$2" "$3" "$(date -Iseconds)" | write_root_file "$tmp"
    run_root mv -f -- "$tmp" "$path"
}

# install_stamp_get PREFIX KEY — one field of the stamp; fails when there is
# no stamp, or no such field in it.
install_stamp_get() {
    local path value
    path="$(install_stamp_path "$1")"
    [[ -r $path ]] || return 1
    value="$(sed -n "s/^$2=//p" "$path" | head -n1)"
    [[ -n $value ]] || return 1
    printf '%s\n' "$value"
}
