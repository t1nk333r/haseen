# shellcheck shell=bash
# haseen's shell functions. Sourced by default/shell/init.sh, which is sourced
# by one line in ~/.bashrc (and ~/.zshrc). haseen owns this file: it is
# replaced on upgrade, so put your own functions in your rc, not here.
#
# Adapted from Omarchy (MIT, Copyright (c) David Heinemeier Hansson):
# default/bash/fns/{compression,worktrees,ssh-port-forwarding,rsyncing,tmux,herdr}.
#
# Changes from upstream:
#   - every function that needs a tool checks for it with `command -v` and says
#     what is missing instead of failing with "command not found";
#   - `gd` asks with `read` instead of `gum`, which haseen does not ship;
#   - the eight layout names dispatch through one resolver (_haseen_mux), so
#     `tdl` and `hdl` both do the right thing on a machine that has only one of
#     the two multiplexers, and herdr wins when both are available;
#   - the layouts take the editor from $EDITOR and the agent from $HASEEN_AGENT
#     (`haseen setup default agent`) instead of hard-coding nvim and opencode;
#   - `iso2sd` and `format-drive` are deliberately NOT ported: they run `sudo
#     dd`/`sgdisk` against a whole disk, and in haseen every privileged
#     mutation goes through the dry-run helpers in lib/common.sh and gets a
#     --dry-run. That is `haseen drive select` / `haseen drive info` territory,
#     not an rc fragment's;
#   - the `ssh` reconnect wrapper is not ported either: wrapping the ssh binary
#     in a retry loop for every login shell was not asked for.

# --- archives ---------------------------------------------------------------

# compress PATH — tar.gz the file or directory, next to it.
compress() {
    if [ -z "${1:-}" ]; then
        echo "Usage: compress <file|dir>" >&2
        return 1
    fi
    tar -czf "${1%/}.tar.gz" "${1%/}"
}

# decompress ARCHIVE... — expand a tar.gz (a function, not an alias, so it can
# check its argument).
decompress() {
    if [ -z "${1:-}" ]; then
        echo "Usage: decompress <file.tar.gz>" >&2
        return 1
    fi
    local archive
    for archive in "$@"; do
        tar -xzf "$archive" || return 1
    done
}

# --- git worktrees ----------------------------------------------------------

# ga BRANCH — new worktree and branch beside this repository; jump into it.
ga() {
    if [ -z "${1:-}" ]; then
        echo "Usage: ga <branch>" >&2
        return 1
    fi
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        echo "ga: not inside a git repository" >&2
        return 1
    fi
    local branch="$1" base worktree
    base="$(basename "$PWD")"
    worktree="../${base}--${branch}"
    git worktree add -b "$branch" "$worktree" || return 1
    # mise trusts a config per directory, so a fresh worktree needs it again.
    if command -v mise >/dev/null 2>&1; then
        mise trust "$worktree" >/dev/null 2>&1 || true
    fi
    cd "$worktree" || return 1
}

# gd [-y] — remove the worktree you are in, and its branch.
gd() {
    local assume_yes=0 reply cwd worktree root branch
    case "${1:-}" in
    -y | --yes) assume_yes=1 ;;
    "") ;;
    *)
        echo "Usage: gd [-y]" >&2
        return 1
        ;;
    esac
    cwd="$PWD"
    worktree="$(basename "$cwd")"
    # Worktrees ga made are named <repo>--<branch>. Anything else is some
    # other directory, and removing it would not be what you meant.
    root="${worktree%%--*}"
    branch="${worktree#*--}"
    if [ "$root" = "$worktree" ]; then
        echo "gd: $worktree is not a <repo>--<branch> worktree" >&2
        return 1
    fi
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        echo "gd: not inside a git repository" >&2
        return 1
    fi
    if [ "$assume_yes" -eq 0 ]; then
        printf 'Remove worktree %s and branch %s? [y/N] ' "$worktree" "$branch"
        read -r reply
        case "$reply" in
        [Yy]*) ;;
        *) return 1 ;;
        esac
    fi
    cd "../$root" || return 1
    git worktree remove "$cwd" --force || return 1
    git branch -D "$branch"
}

# --- ssh port forwards ------------------------------------------------------

# fip HOST PORT... — forward remote ports to the same local ports.
fip() {
    if [ "$#" -lt 2 ]; then
        echo "Usage: fip <host> <port> [port...]" >&2
        return 1
    fi
    local host="$1" port
    shift
    for port in "$@"; do
        ssh -f -N -L "${port}:localhost:${port}" "$host" &&
            echo "Forwarding localhost:$port -> $host:$port"
    done
}

# dip PORT... — stop forwarding those ports.
dip() {
    if [ "$#" -eq 0 ]; then
        echo "Usage: dip <port> [port...]" >&2
        return 1
    fi
    local port
    for port in "$@"; do
        if pkill -f "ssh.*-L ${port}:localhost:${port}"; then
            echo "Stopped forwarding port $port"
        else
            echo "No forwarding on port $port"
        fi
    done
}

# lip — list the forwards this shell's user has open.
lip() {
    pgrep -af "ssh.*-L [0-9]+:localhost:[0-9]+" || echo "No active forwards"
}

# --- rsync watchers ---------------------------------------------------------

# rsw SRC DEST — mirror SRC to DEST now, then on every change. DEST may be
# remote (rsw ~/Work/app host:Work/app).
rsw() {
    if [ "$#" -ne 2 ]; then
        echo "Usage: rsw <source> <destination>" >&2
        return 1
    fi
    # inotify-tools is not a haseen package: the watchers are the only thing
    # that wants it, so rsw asks for it rather than every install carrying it.
    local missing=""
    command -v rsync >/dev/null 2>&1 || missing="rsync"
    command -v inotifywait >/dev/null 2>&1 || missing="${missing:+$missing }inotify-tools"
    if [ -n "$missing" ]; then
        echo "rsw: needs $missing (pacman -S $missing)" >&2
        return 1
    fi
    local src="${1%/}" dest="$2" sockets rsh
    # One shared SSH connection per login, so a passphrase is asked for once.
    sockets="${XDG_RUNTIME_DIR:-$HOME/.ssh/sockets}"
    mkdir -p "$sockets"
    rsh="ssh -o ControlMaster=auto -o ControlPath=$sockets/rsw-%r@%h:%p -o ControlPersist=yes"
    setsid --fork env RSYNC_RSH="$rsh" bash -c \
        'rsync -a "$1/" "$2"; while inotifywait -r -q -e modify,create,delete,move "$1"; do rsync -a "$1/" "$2"; done' \
        rsw-watch "$src" "$dest" >/dev/null 2>&1
    echo "Watching $src -> $dest"
}

# lsw — list the watchers rsw started.
lsw() {
    local pid cmd rest found=0
    while read -r pid cmd; do
        rest="${cmd##*rsw-watch }"
        echo "$pid: ${rest% *} -> ${rest##* }"
        found=1
    done < <(pgrep -af 'rsw-watch ')
    [ "$found" -eq 1 ] || echo "No active watches"
}

# dsw — stop every watcher rsw started.
dsw() {
    local pid found=0
    for pid in $(pgrep -f 'rsw-watch '); do
        if kill -- -"$pid" 2>/dev/null; then
            echo "Stopped watch (pid $pid)"
            found=1
        fi
    done
    [ "$found" -eq 1 ] || echo "No active watches"
}

# --- multiplexer layouts ----------------------------------------------------

# _haseen_mux — which multiplexer the layouts should drive, or nothing.
# The session you are already in wins; then the preference `haseen seed user`
# wrote to ~/.config/haseen/mux (a user file, editable); then what is
# installed, herdr first, because that is haseen's default.
_haseen_mux() {
    local file preferred
    if [ -n "${HERDR_PANE_ID:-}" ]; then
        echo herdr
        return 0
    fi
    if [ -n "${TMUX:-}" ]; then
        echo tmux
        return 0
    fi
    file="${XDG_CONFIG_HOME:-$HOME/.config}/haseen/mux"
    if [ -r "$file" ]; then
        read -r preferred <"$file" || preferred=""
        case "$preferred" in
        herdr | tmux)
            if command -v "$preferred" >/dev/null 2>&1; then
                echo "$preferred"
                return 0
            fi
            ;;
        esac
    fi
    if command -v herdr >/dev/null 2>&1; then
        echo herdr
        return 0
    fi
    if command -v tmux >/dev/null 2>&1; then
        echo tmux
        return 0
    fi
    return 1
}

# _haseen_layout KIND ARGS... — run KIND (dl|ds|dlm|sl) on the resolved
# multiplexer. tdl/hdl and friends are both entry points to this, so muscle
# memory from either tool lands on whatever is actually running.
_haseen_layout() {
    local kind="$1" mux
    shift
    mux="$(_haseen_mux)" || {
        echo "neither herdr nor tmux is installed" >&2
        return 1
    }
    "_haseen_${mux}_${kind}" "$@"
}

# The agent the layouts start: `haseen setup default agent` sets $HASEEN_AGENT.
_haseen_agent() { printf '%s\n' "${1:-${HASEEN_AGENT:-opencode}}"; }
_haseen_editor() { printf '%s\n' "${EDITOR:-nvim}"; }
# hunk is Omarchy's diff watcher and is not a haseen package; fall back to git.
_haseen_diff_watch() {
    if command -v hunk >/dev/null 2>&1; then
        echo "hunk diff --watch"
    else
        echo "git diff"
    fi
}

tdl() { _haseen_layout dl "$@"; }
tds() { _haseen_layout ds "$@"; }
tdlm() { _haseen_layout dlm "$@"; }
tsl() { _haseen_layout sl "$@"; }
hdl() { _haseen_layout dl "$@"; }
hds() { _haseen_layout ds "$@"; }
hdlm() { _haseen_layout dlm "$@"; }
hsl() { _haseen_layout sl "$@"; }

# --- tmux layouts -----------------------------------------------------------

_haseen_tmux_ready() {
    if [ -z "${TMUX:-}" ]; then
        echo "start tmux first (haseen's layouts drive the session you are in)" >&2
        return 1
    fi
}

# editor left, agent right, terminal underneath.
_haseen_tmux_dl() {
    _haseen_tmux_ready || return 1
    local dir="$PWD" editor_pane ai_pane ai2_pane ai ai2
    ai="$(_haseen_agent "${1:-}")"
    ai2="${2:-}"
    editor_pane="$TMUX_PANE"
    tmux rename-window -t "$editor_pane" "$(basename "$dir")"
    tmux split-window -v -p 15 -t "$editor_pane" -c "$dir"
    ai_pane="$(tmux split-window -h -p 30 -t "$editor_pane" -c "$dir" -P -F '#{pane_id}')"
    if [ -n "$ai2" ]; then
        ai2_pane="$(tmux split-window -v -t "$ai_pane" -c "$dir" -P -F '#{pane_id}')"
        tmux send-keys -t "$ai2_pane" "$ai2" C-m
    fi
    tmux send-keys -t "$ai_pane" "$ai" C-m
    tmux send-keys -t "$editor_pane" "$(_haseen_editor) ." C-m
    # Upstream selects an unset variable here; focus belongs on the editor.
    tmux select-pane -t "$editor_pane"
}

# editor, diff watch, terminal and agent in four quarters.
_haseen_tmux_ds() {
    _haseen_tmux_ready || return 1
    local dir="$PWD" editor_pane diff_pane terminal_pane ai_pane
    editor_pane="$TMUX_PANE"
    tmux rename-window -t "$editor_pane" "$(basename "$dir")"
    terminal_pane="$(tmux split-window -v -p 50 -t "$editor_pane" -c "$dir" -P -F '#{pane_id}')"
    diff_pane="$(tmux split-window -h -p 50 -t "$editor_pane" -c "$dir" -P -F '#{pane_id}')"
    ai_pane="$(tmux split-window -h -p 50 -t "$terminal_pane" -c "$dir" -P -F '#{pane_id}')"
    tmux send-keys -t "$editor_pane" -l "$(_haseen_editor) ."
    tmux send-keys -t "$editor_pane" C-m
    tmux send-keys -t "$diff_pane" -l "$(_haseen_diff_watch)"
    tmux send-keys -t "$diff_pane" C-m
    tmux send-keys -t "$ai_pane" -l "$(_haseen_agent)"
    tmux send-keys -t "$ai_pane" C-m
    tmux select-pane -t "$editor_pane"
}

# one dl window per subdirectory.
_haseen_tmux_dlm() {
    _haseen_tmux_ready || return 1
    local ai ai2 base first dir dirpath pane_id
    ai="$(_haseen_agent "${1:-}")"
    ai2="${2:-}"
    base="$PWD"
    first=1
    tmux rename-session "$(basename "$base" | tr '.:' '--')"
    for dir in "$base"/*/; do
        [ -d "$dir" ] || continue
        dirpath="${dir%/}"
        if [ "$first" -eq 1 ]; then
            tmux send-keys -t "$TMUX_PANE" "cd '$dirpath' && tdl $ai $ai2" C-m
            first=0
        else
            pane_id="$(tmux new-window -c "$dirpath" -P -F '#{pane_id}')"
            tmux send-keys -t "$pane_id" "tdl $ai $ai2" C-m
        fi
    done
}

# COUNT panes in a grid, all running the same command.
_haseen_tmux_sl() {
    _haseen_tmux_ready || return 1
    if [ -z "${1:-}" ] || [ -z "${2:-}" ]; then
        echo "Usage: tsl <pane_count> <command>" >&2
        return 1
    fi
    local count="$1" cmd="$2" dir="$PWD" last new_pane pane
    local -a panes
    tmux rename-window -t "$TMUX_PANE" "$(basename "$dir")"
    panes=("$TMUX_PANE")
    last="$TMUX_PANE"
    while [ "${#panes[@]}" -lt "$count" ]; do
        new_pane="$(tmux split-window -h -t "$last" -c "$dir" -P -F '#{pane_id}')"
        panes=("${panes[@]}" "$new_pane")
        last="$new_pane"
        tmux select-layout -t "$TMUX_PANE" tiled
    done
    for pane in "${panes[@]}"; do
        tmux send-keys -t "$pane" "$cmd" C-m
    done
    tmux select-pane -t "$TMUX_PANE"
}

# --- herdr layouts ----------------------------------------------------------

_haseen_herdr_ready() {
    if [ -z "${HERDR_PANE_ID:-}" ]; then
        echo "start herdr first (haseen's layouts drive the session you are in)" >&2
        return 1
    fi
}

_haseen_herdr_ratio() { awk -v a="$1" -v b="$2" 'BEGIN { printf "%.4f", a / b }'; }

# _haseen_herdr_split PANE right|down RATIO CWD — echoes the new pane id.
_haseen_herdr_split() {
    herdr pane split "$1" --direction "$2" --ratio "$3" --cwd "$4" --no-focus |
        jq -r '.result.pane.pane_id'
}

_haseen_herdr_dl() {
    _haseen_herdr_ready || return 1
    local dir="$PWD" editor_pane ai_pane ai2_pane ai ai2
    ai="$(_haseen_agent "${1:-}")"
    ai2="${2:-}"
    editor_pane="$HERDR_PANE_ID"
    herdr tab rename "$HERDR_TAB_ID" "$(basename "$dir")" >/dev/null
    _haseen_herdr_split "$editor_pane" down 0.85 "$dir" >/dev/null
    ai_pane="$(_haseen_herdr_split "$editor_pane" right 0.7 "$dir")"
    if [ -n "$ai2" ]; then
        ai2_pane="$(_haseen_herdr_split "$ai_pane" down 0.5 "$dir")"
        herdr pane run "$ai2_pane" "$ai2" >/dev/null
    fi
    herdr pane run "$ai_pane" "$ai" >/dev/null
    herdr pane run "$editor_pane" "$(_haseen_editor) ." >/dev/null
}

_haseen_herdr_ds() {
    _haseen_herdr_ready || return 1
    local dir="$PWD" editor_pane diff_pane terminal_pane ai_pane
    editor_pane="$HERDR_PANE_ID"
    herdr tab rename "$HERDR_TAB_ID" "$(basename "$dir")" >/dev/null
    terminal_pane="$(_haseen_herdr_split "$editor_pane" down 0.5 "$dir")"
    diff_pane="$(_haseen_herdr_split "$editor_pane" right 0.5 "$dir")"
    ai_pane="$(_haseen_herdr_split "$terminal_pane" right 0.5 "$dir")"
    herdr pane run "$editor_pane" "$(_haseen_editor) ." >/dev/null
    herdr pane run "$diff_pane" "$(_haseen_diff_watch)" >/dev/null
    herdr pane run "$ai_pane" "$(_haseen_agent)" >/dev/null
}

_haseen_herdr_dlm() {
    _haseen_herdr_ready || return 1
    local ai ai2 base first dir dirpath command pane_id
    ai="$(_haseen_agent "${1:-}")"
    ai2="${2:-}"
    base="$PWD"
    first=1
    herdr workspace rename "$HERDR_WORKSPACE_ID" "$(basename "$base")" >/dev/null
    for dir in "$base"/*/; do
        [ -d "$dir" ] || continue
        dirpath="${dir%/}"
        printf -v command 'hdl %q' "$ai"
        [ -n "$ai2" ] && printf -v command '%s %q' "$command" "$ai2"
        if [ "$first" -eq 1 ]; then
            printf -v command 'cd %q && %s' "$dirpath" "$command"
            herdr pane run "$HERDR_PANE_ID" "$command" >/dev/null
            first=0
        else
            pane_id="$(herdr tab create --workspace "$HERDR_WORKSPACE_ID" --cwd "$dirpath" --no-focus |
                jq -r '.result.root_pane.pane_id')"
            herdr pane run "$pane_id" "$command" >/dev/null
        fi
    done
}

_haseen_herdr_sl() {
    _haseen_herdr_ready || return 1
    if [ -z "${1:-}" ] || [ -z "${2:-}" ]; then
        echo "Usage: hsl <pane_count> <command>" >&2
        return 1
    fi
    local count="$1" cmd="$2" dir="$PWD" cols=1 k last col index rows j pane
    local -a columns panes
    # ceil(sqrt(count)) columns, the rows spread across them.
    while [ $((cols * cols)) -lt "$count" ]; do cols=$((cols + 1)); done
    columns=("$HERDR_PANE_ID")
    last="$HERDR_PANE_ID"
    k=1
    while [ "$k" -lt "$cols" ]; do
        # Splitting the rightmost column off at 1/(n-k+1) keeps the columns
        # even and in left-to-right order.
        last="$(_haseen_herdr_split "$last" right "$(_haseen_herdr_ratio 1 $((cols - k + 1)))" "$dir")"
        columns=("${columns[@]}" "$last")
        k=$((k + 1))
    done
    index=0
    for col in "${columns[@]}"; do
        rows=$((count / cols))
        if [ "$index" -lt $((count % cols)) ]; then rows=$((rows + 1)); fi
        panes=("${panes[@]}" "$col")
        last="$col"
        j=1
        while [ "$j" -lt "$rows" ]; do
            last="$(_haseen_herdr_split "$last" down "$(_haseen_herdr_ratio 1 $((rows - j + 1)))" "$dir")"
            panes=("${panes[@]}" "$last")
            j=$((j + 1))
        done
        index=$((index + 1))
    done
    for pane in "${panes[@]}"; do
        herdr pane run "$pane" "$cmd" >/dev/null
    done
}

# --- pickers ----------------------------------------------------------------

# ff [dir] — pick a file with fzf, previewed with bat. Prints the path, so it
# composes: $EDITOR "$(ff)".
ff() {
    if ! command -v fzf >/dev/null 2>&1; then
        echo "ff: needs fzf" >&2
        return 1
    fi
    local preview='cat {}'
    if command -v bat >/dev/null 2>&1; then
        preview='bat --style=numbers --color=always {}'
    fi
    if [ -n "${1:-}" ]; then
        (cd "$1" && fzf --preview "$preview")
    else
        fzf --preview "$preview"
    fi
}
