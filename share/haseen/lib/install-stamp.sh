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

# install_build_version REPO — the version a checkout installs as:
# share/haseen/VERSION plus the commits made since that file last changed, so
# every merge installs a higher number while the file, and the sidecar release
# named after it, stay as set by hand (plan 147). 0.2.0-dev 21 commits on is
# 0.2.0-dev.21, which orders above .20; a release such as 0.3.0 becomes
# 0.3.0+21. The file alone when git cannot say: no git, a history that never
# set it, an uncommitted edit to it, or no commits since.
install_build_version() {
    local repo="$1" version since count
    version="$(cat "$repo/share/haseen/VERSION")" || return 1
    since="$(git -C "$repo" log -1 --format=%H -- share/haseen/VERSION 2>/dev/null)" || since=''
    if [[ $since =~ ^[0-9a-f]{40,64}$ ]] &&
        git -C "$repo" diff --quiet HEAD -- share/haseen/VERSION 2>/dev/null; then
        count="$(git -C "$repo" rev-list --count "$since..HEAD" 2>/dev/null)" || count=''
    fi
    if [[ ${count:-} =~ ^[0-9]+$ ]] && ((count > 0)); then
        if [[ $version == *-* ]]; then
            version+=".$count"
        else
            version+="+$count"
        fi
    fi
    printf '%s\n' "$version"
}

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
