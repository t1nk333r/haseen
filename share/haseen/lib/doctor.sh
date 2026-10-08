# shellcheck shell=bash
# doctor_shell_cmdline_matches SHELL_DIR PROCESS_CWD CMDLINE_FILE — whether argv names the
# haseen shell as Quickshell's -p project, resolving relative paths from the process cwd.
doctor_shell_cmdline_matches() {
    local shell_dir="$1" process_cwd="$2" cmdline_file="$3" arg previous_arg='' process_shell_dir
    shell_dir="$(readlink -f -- "$shell_dir")" || return 1
    [[ -n $shell_dir && -r $cmdline_file ]] || return 1
    while IFS= read -r -d '' arg; do
        if [[ $previous_arg == -p ]]; then
            [[ $arg == /* ]] || arg="$process_cwd/$arg"
            if process_shell_dir="$(readlink -f -- "$arg" 2>/dev/null)"; then
                [[ $process_shell_dir == "$shell_dir" ]] && return 0
            fi
        fi
        previous_arg="$arg"
    done <"$cmdline_file"
    return 1
}
