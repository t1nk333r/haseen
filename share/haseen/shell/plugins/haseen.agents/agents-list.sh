#!/usr/bin/env bash
# haseen.agents: one snapshot of this user's running coding agents, as TSV on
# stdout, one process per line:
#
#   pid <TAB> name <TAB> seconds-running <TAB> working-directory
#
#   agents-list.sh [NAME...]    NAME: the agent commands to look for
#                               (default: the list below)
#
# Read-only: it reads /proc and changes nothing, so it has no --dry-run.
# $HASEEN_SYSROOT prefixes /proc the way sysroot_path does in the CLI, so the
# tests point it at a fixture tree instead of the live machine.
#
# Adapted from Omarchy shell/plugins/agents (MIT, Copyright (c) David
# Heinemeier Hansson). Upstream draws usage records that
# `omarchy-agent-usage-update` collects per subscription; haseen ships no
# collectors and wants nothing installed or signed in, so the panel answers
# the cheap question instead: which coding agents are running right now,
# where, and for how long.
set -uo pipefail

proc="${HASEEN_SYSROOT:-}/proc"
agents=("$@")
((${#agents[@]} > 0)) || agents=(claude codex opencode aider goose crush gemini cursor-agent)

# A CLI shipped as a script runs under its interpreter: argv[0] is then the
# interpreter and the first non-flag argument is the agent.
interpreters=" node bun deno python python3 ruby perl uv uvx npx pnpm "

ticks="$(getconf CLK_TCK 2>/dev/null || echo 100)"
[[ $ticks =~ ^[0-9]+$ ]] && ((ticks > 0)) || ticks=100
uptime=0
[[ -r $proc/uptime ]] && read -r uptime _ <"$proc/uptime"
uptime=${uptime%%.*}
[[ $uptime =~ ^[0-9]+$ ]] || uptime=0

# is_agent NAME — NAME is one of the commands we are looking for.
is_agent() {
    local candidate
    for candidate in "${agents[@]}"; do
        [[ $candidate == "$1" ]] && return 0
    done
    return 1
}

# started_seconds PID — seconds since the process started, 0 when /proc does
# not say (field 22 of stat is the start time in clock ticks; the command name
# before it may itself contain spaces and parentheses).
started_seconds() {
    local stat rest seconds
    local -a fields
    [[ -r $proc/$1/stat ]] || return 1
    stat="$(<"$proc/$1/stat")"
    rest=${stat##*") "}
    read -ra fields <<<"$rest"
    local start=${fields[19]:-0}
    [[ $start =~ ^[0-9]+$ ]] || start=0
    seconds=$((uptime - start / ticks))
    ((seconds > 0)) || seconds=0
    printf '%s\n' "$seconds"
}

{
    for dir in "$proc"/[0-9]*; do
        pid=${dir##*/}
        # Only this user's processes: another user's agent is not ours to show,
        # and its cwd is not readable anyway.
        [[ -O $dir && -r $dir/cmdline ]] || continue
        mapfile -d '' -t argv 2>/dev/null <"$dir/cmdline" || continue
        ((${#argv[@]} > 0)) || continue

        name=${argv[0]##*/}
        if ! is_agent "$name"; then
            [[ $interpreters == *" $name "* ]] || continue
            name=""
            for arg in "${argv[@]:1}"; do
                [[ $arg == -* ]] && continue
                name=${arg##*/}
                break
            done
            [[ -n $name ]] && is_agent "$name" || continue
        fi

        seconds="$(started_seconds "$pid")" || seconds=0
        cwd="$(readlink "$dir/cwd" 2>/dev/null || true)"
        printf '%s\t%s\t%s\t%s\n' "$pid" "$name" "$seconds" "$cwd"
    done
} | sort -n -k1,1
