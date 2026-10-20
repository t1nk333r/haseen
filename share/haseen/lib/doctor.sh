# shellcheck shell=bash
# doctor_shell_cmdline_matches SHELL_DIR PROCESS_CWD CMDLINE_FILE — whether argv names the
# haseen shell as Quickshell's project (-p DIR, -p=DIR, --path DIR, --path=DIR, or
# the project's .qml file), resolving relative paths from the process cwd. A
# Quickshell client subcommand (ipc, kill, list, log) talks to a shell; it is not
# one, so it never matches.
doctor_shell_cmdline_matches() {
    local shell_dir="$1" process_cwd="$2" cmdline_file="$3" arg value first=true want=false matched=false
    local process_shell_dir
    shell_dir="$(readlink -f -- "$shell_dir")" || return 1
    [[ -n $shell_dir && -r $cmdline_file ]] || return 1
    while IFS= read -r -d '' arg; do
        if $first; then
            first=false
            continue
        fi
        if $want; then
            value="$arg"
            want=false
        else
            case "$arg" in
            -p | --path)
                want=true
                continue
                ;;
            -p=* | --path=*) value="${arg#*=}" ;;
            ipc | kill | list | log) return 1 ;;
            *) continue ;;
            esac
        fi
        [[ $value == /* ]] || value="$process_cwd/$value"
        process_shell_dir="$(readlink -f -- "$value" 2>/dev/null)" || continue
        if [[ $process_shell_dir == *.qml && -f $process_shell_dir ]]; then
            process_shell_dir="${process_shell_dir%/*}"
        fi
        [[ $process_shell_dir == "$shell_dir" ]] && matched=true
    done <"$cmdline_file"
    $matched
}

# doctor_hyprland_pid — the running Hyprland's pid, from the lock file it keeps
# in its instance directory ($XDG_RUNTIME_DIR/hypr/<instance>/hyprland.lock,
# the pid on line 1): this session's instance when HYPRLAND_INSTANCE_SIGNATURE
# is set, else the newest. Read through sysroot_path; fails without one.
doctor_hyprland_pid() {
    local dir lock="" candidate pid
    dir="$(sysroot_path "${XDG_RUNTIME_DIR:-/run/user/$UID}/hypr")"
    if [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then
        lock="$dir/$HYPRLAND_INSTANCE_SIGNATURE/hyprland.lock"
    else
        for candidate in "$dir"/*/hyprland.lock; do
            [[ -f $candidate ]] || continue
            [[ -z $lock || $candidate -nt $lock ]] && lock="$candidate"
        done
    fi
    [[ -n $lock && -r $lock ]] && read -r pid <"$lock" && [[ $pid =~ ^[0-9]+$ ]] || return 1
    printf '%s\n' "$pid"
}

# doctor_environ_path FILE — the PATH in a /proc/<pid>/environ file; fails
# when the file cannot be read or has no PATH.
doctor_environ_path() {
    local path
    [[ -r $1 ]] || return 1
    path="$(tr '\0' '\n' <"$1" | sed -n 's/^PATH=//p' | head -n1)"
    [[ -n $path ]] && printf '%s\n' "$path"
}

# doctor_omarchy_first PATH — the first PATH entry holding an executable
# omarchy-launch-shell, a tab, and whose it is: "haseen" (haseen's omarchy/bin,
# or a link into it as install.sh puts in PREFIX/bin) or "other". Nothing when
# no entry has one. Entries are read through sysroot_path.
doctor_omarchy_first() {
    local dir f dirs ours
    ours="$(readlink -f -- "$HASEEN_PATH/omarchy/bin/omarchy-launch-shell")"
    IFS=: read -ra dirs <<<"$1"
    for dir in "${dirs[@]}"; do
        [[ -n $dir ]] || continue
        f="$(sysroot_path "$dir/omarchy-launch-shell")"
        [[ -x $f ]] || continue
        if [[ ${dir%/} == "${HASEEN_PATH%/}/omarchy/bin" || $(readlink -- "$f") == *share/haseen/omarchy/bin/omarchy-launch-shell ||
            $(readlink -f -- "$f") == "$ours" ]]; then
            printf '%s\thaseen\n' "$dir"
        else
            printf '%s\tother\n' "$dir"
        fi
        return 0
    done
}

# doctor_omarchy_path WHAT PATH FIX — report whose omarchy-launch-shell WHAT's
# PATH finds first. Another's first is a failure: there, Omarchy's own
# commands run, and its shell restart brings back Omarchy's shell beside
# haseen's (plan 093). FIX says how to put haseen's first.
doctor_omarchy_path() {
    local first
    first="$(doctor_omarchy_first "$2")"
    if [[ -z $first ]]; then
        echo "$1 omarchy commands=none on its PATH"
    elif [[ ${first#*$'\t'} == haseen ]]; then
        echo "$1 omarchy commands=haseen's (${first%$'\t'*})"
    else
        echo "$1 omarchy commands=FAIL: ${first%$'\t'*}/omarchy-launch-shell comes before haseen's, so Omarchy's commands run there and its shell restart starts Omarchy's shell; $3"
        return 1
    fi
}
