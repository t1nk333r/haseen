# shellcheck shell=sh
# haseen VAPT layer: PATH for its tool stores. Reached only through links
# `haseen layer apply vapt` creates and `haseen layer remove vapt` deletes, so
# removing the layer deactivates this file without editing any rc:
#   ${XDG_CONFIG_HOME:-~/.config}/haseen/vapt/shell.sh, sourced in interactive
#     shells only by a `[ -r … ] && .` line the user adds to their rc (the
#     layer prints it and never edits an rc), or by the optional shell-rc
#     layer's default/shell/init.sh when the rc already sources that. Such a
#     line is inert once the link is gone;
#   ${XDG_CONFIG_HOME:-~/.config}/uwsm/env.d/70-haseen-vapt, sourced by uwsm
#     at login on a desktop host, so session-launched apps get the same PATH.
# Both may source it in one session; the result is the same.
#
# Passive on purpose: plain POSIX sh, no command runs here, only directory
# tests and variable assignments. Every directory is APPENDED to PATH, never
# prepended, so nothing here shadows a system command, the system Python or
# a directory the user already put on PATH (`haseen layer status vapt`
# reports owned natives that such a directory hides). Directories that do
# not exist are skipped, and none is added twice.
#
# Facts adapted from the owner's waydots session environment (uwsm/env):
# each package manager keeps its binaries under ~/.local/share/<manager>/bin,
# named by UV_TOOL_BIN_DIR and PIPX_BIN_DIR.

_haseen_vapt_data="${XDG_DATA_HOME:-$HOME/.local/share}"

# The general uv/pipx tool directories are exported only when the user has
# not chosen others and the directory already exists: haseen follows the
# layout, it does not impose it.
if [ -z "${UV_TOOL_BIN_DIR:-}" ] && [ -d "$_haseen_vapt_data/uv/bin" ]; then
    export UV_TOOL_BIN_DIR="$_haseen_vapt_data/uv/bin"
fi
if [ -z "${PIPX_BIN_DIR:-}" ] && [ -d "$_haseen_vapt_data/pipx/bin" ]; then
    export PIPX_BIN_DIR="$_haseen_vapt_data/pipx/bin"
fi

# Order: the layer's own pinned pipx store first among the appended entries,
# then the user's general manager and script directories.
for _haseen_vapt_dir in \
    "$_haseen_vapt_data/haseen/vapt/pipx/bin" \
    "${UV_TOOL_BIN_DIR:-$_haseen_vapt_data/uv/bin}" \
    "${PIPX_BIN_DIR:-$_haseen_vapt_data/pipx/bin}" \
    "$HOME/.local/bin"; do
    [ -d "$_haseen_vapt_dir" ] || continue
    case ":$PATH:" in
    *":$_haseen_vapt_dir:"*) ;;
    *) PATH="$PATH:$_haseen_vapt_dir" ;;
    esac
done
export PATH

# The shared COAE interpreter is named, not activated: put
# "$HASEEN_VAPT_COAE_ENV/bin/python" in front of a command when you want it.
if [ -x "$_haseen_vapt_data/htb-coae/bin/python" ]; then
    export HASEEN_VAPT_COAE_ENV="$_haseen_vapt_data/htb-coae"
fi

unset _haseen_vapt_data _haseen_vapt_dir
