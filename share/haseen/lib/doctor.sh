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
