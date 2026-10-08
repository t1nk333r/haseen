# shellcheck shell=bash disable=SC2034  # VAPT_* outputs are consumed by provision.sh/native.sh/layer.sh
# layers/vapt/environment.sh — the VAPT layer's per-user environment: the
# shared COAE Python environment and the owned links that activate the
# layer's PATH fragment. Sourced once by provision.sh after pacman.sh (which
# supplies vapt_read_path and the vapt_path_ancestors_safe / vapt_state_*
# ownership-file helpers), blackarch.sh and native.sh; never
# executed. Runs as the invoking user, never as root.
#
# Public seams:
#   vapt_environment_apply GROUP...   provision current/retained requirements
#   vapt_environment_remove           delete the owned activation links only
#   vapt_environment_status           "ok:"/"missing:"/"warn:" lines; returns
#                                     0 healthy, 1 not applied, 2 degraded;
#                                     honours engine VAPT_COAE_REQUIRED=1
#   vapt_coae_interpreter_ok          read-only gate for the native PyRIT
#                                     adapter (see VAPT_COAE_STATUS below)
#
# Observed paths and destinations. Every path below is named by its logical
# destination (the user's real XDG location); commands and messages print
# that. What is READ — ownership records, journals, links, every parent
# directory and the COAE metadata — goes through vapt_read_path, so under
# HASEEN_SYSROOT only the fixture tree is ever inspected, never the host.
#
# COAE environment. The htb-coae group needs transformers, textattack and
# modelscan in ONE interpreter with torch, and modelscan requires Python
# below 3.13 while the system Python is newer. So the group gets one uv
# virtual environment at ${XDG_DATA_HOME:-~/.local/share}/htb-coae on a
# uv-managed CPython 3.12 with the exact pin set below (resolved together for
# 3.12 per the owner's waydots COAE notes; change them as a set). It is
# separate from Arch's python-pytorch and never on PATH. Only the 3.12 minor
# is pinned: no source records a patch release, so the resolved patch is
# reported from pyvenv.cfg rather than invented.
#
# Ownership. haseen only touches an environment it created, recorded in
# $HASEEN_USER_STATE/vapt/coae.tsv. The pending record is written (checked,
# atomically, never through a symlink) before uv runs; a record that cannot
# be written stops the mutation. An existing environment at that path
# without the record is the user's: it is inspected and reported, never
# modified. A symlinked or non-directory parent of the environment or of the
# record is preserved and the environment is not provisioned. Package state
# comes from dist-info METADATA files and the interpreter from pyvenv.cfg and
# the bin/python link chain; nothing inside the environment is imported or
# executed to check it.
#
# VAPT_COAE_STATUS, set by vapt_environment_apply for the native adapters
# that run after it: available (haseen-owned, Python 3.12, bin/python
# resolves through the verified uv-managed store), planned (dry-run creation or
# reconciliation of the owned environment), unmanaged (a user environment;
# reported, never borrowed as an interpreter), unavailable, or unselected.
#
# Activation links. Both point at default/vapt/shell.sh, a passive fragment:
#   shell    ${XDG_CONFIG_HOME:-~/.config}/haseen/vapt/shell.sh, sourced by a
#            line the user adds to their rc (vapt_shell_line; the layer never
#            edits an rc) or by the optional shell-rc layer's
#            default/shell/init.sh when the rc already sources that;
#   session  ${XDG_CONFIG_HOME:-~/.config}/uwsm/env.d/70-haseen-vapt, the
#            desktop layer's uwsm env.d convention, so apps launched from the
#            session see the same PATH (the owner's waydots kept these
#            variables in uwsm/env). Only on a desktop host: it is created
#            only when that env.d directory already exists, never required.
# Only a link this module created is journaled in
# $HASEEN_USER_STATE/vapt/links.tsv (pending before the link is made, created
# after); a matching link that was already there is borrowed and never
# removed. Files, other links, dangling links and symlinked or non-directory
# parents at the destination are conflicts, preserved and reported.
#
# Removal deletes a journaled link only if its parents are unchanged and it
# is still exactly what was created. The COAE environment, uv's Python
# downloads, pipx stores, packages and every user file stay; they are
# reported as retained.

VAPT_COAE_PYTHON=3.12
VAPT_COAE_PINS=(torch==2.14.1 transformers==5.18.0 modelscan==0.8.8 textattack==0.3.11)
# Arch's uv, from extra via the engine's vapt_install_infra; never a mise or
# user-local uv that happens to be first on PATH.
VAPT_UV=/usr/bin/uv

# _vapt_env_paths — every path this module owns or reads, from the current
# user's XDG variables. Called at the top of each public function.
_vapt_env_paths() {
    local data="${XDG_DATA_HOME:-$HOME/.local/share}" config="${XDG_CONFIG_HOME:-$HOME/.config}"
    VAPT_COAE_DIR="$data/htb-coae"
    VAPT_COAE_SEEN="$(vapt_read_path "$VAPT_COAE_DIR")"
    VAPT_COAE_RECORD="$HASEEN_USER_STATE/vapt/coae.tsv"
    VAPT_UV_PYTHON_DIR="$data/uv/python"
    VAPT_LINK_WANT="${HASEEN_INSTALL_PATH:-$HASEEN_PATH}/default/vapt/shell.sh"
    VAPT_LINK_SHELL="$config/haseen/vapt/shell.sh"
    VAPT_LINK_SESSION_DIR="$config/uwsm/env.d"
    VAPT_LINK_SESSION="$VAPT_LINK_SESSION_DIR/70-haseen-vapt"
    VAPT_LINK_JOURNAL="$HASEEN_USER_STATE/vapt/links.tsv"
    VAPT_PIPX_STORE="${VAPT_PIPX_HOME:-$data/haseen/vapt/pipx}"
}

# ---------------------------------------------------------------------------
# COAE environment

# _vapt_coae_record_state — prints pending, created, none or conflict. The
# record is data: one "v1<TAB>STATE<TAB>DIR" line, read field by field, never
# sourced, and ignored (with a warning) when it names another directory. It
# is read only after its parents and the file itself are checked: a symlinked
# or non-regular record is a conflict, never ownership authority.
_vapt_coae_record_state() {
    local ver state dir seen
    if ! vapt_state_path_safe "$VAPT_COAE_RECORD"; then
        echo conflict
        return
    fi
    seen="$(vapt_read_path "$VAPT_COAE_RECORD")"
    [[ -f $seen ]] || {
        echo none
        return
    }
    IFS=$'\t' read -r ver state dir <"$seen" || true
    if [[ $ver == v1 && $dir == "$VAPT_COAE_DIR" && ($state == pending || $state == created) ]]; then
        echo "$state"
    else
        warn "vapt-env: ignoring unrecognised ownership record $VAPT_COAE_RECORD"
        echo none
    fi
}

_vapt_coae_record() {
    printf 'v1\t%s\t%s\n' "$1" "$VAPT_COAE_DIR" | vapt_state_write "$VAPT_COAE_RECORD"
}

# _vapt_coae_python — prints the interpreter version pyvenv.cfg records
# (version_info, or version for older writers); empty when unknown.
_vapt_coae_python() {
    local key value
    vapt_path_ancestors_safe "$VAPT_COAE_DIR/pyvenv.cfg" 2>/dev/null || return 0
    [[ -f $VAPT_COAE_SEEN/pyvenv.cfg && ! -L $VAPT_COAE_SEEN/pyvenv.cfg ]] || return 0
    while IFS='=' read -r key value; do
        key="${key//[[:space:]]/}" value="${value//[[:space:]]/}"
        case "$key" in
        version_info | version)
            printf '%s\n' "$value"
            return 0
            ;;
        esac
    done <"$VAPT_COAE_SEEN/pyvenv.cfg"
}

# _vapt_coae_python_ok VERSION — true when VERSION is a 3.12 release.
_vapt_coae_python_ok() { [[ $1 == "$VAPT_COAE_PYTHON" || $1 == "$VAPT_COAE_PYTHON".* ]]; }

# _vapt_coae_interpreter_resolves [AUTHORITY] — prove the compatible interpreter
# chain inside the intended uv store, using metadata only. Ownership is required
# by default; "unmanaged" is read-only observation, never native borrowing or
# mutation authority. Absolute symlinks are fixture-rooted; no Python executes.
_vapt_coae_interpreter_resolves() {
    if [[ ${1:-owned} == unmanaged ]]; then
        vapt_meta coae-interpreter-observe "$VAPT_COAE_SEEN" \
            "$(vapt_read_path "$VAPT_UV_PYTHON_DIR")" >/dev/null 2>&1
    else
        vapt_meta coae-interpreter "$VAPT_COAE_SEEN" \
            "$(vapt_read_path "$VAPT_COAE_RECORD")" \
            "$(vapt_read_path "$VAPT_UV_PYTHON_DIR")" >/dev/null 2>&1
    fi
}

# _vapt_coae_pin_state PIN — the helper guards every directory before globbing
# or reading METADATA. Nested metadata symlinks cannot consult the live host.
# A local version label (+cu…) still satisfies ==, as in PEP 440.
_vapt_coae_pin_state() {
    local state
    if state="$(vapt_meta dist-state "$VAPT_COAE_SEEN" "$1" 2>/dev/null)"; then
        printf '%s\n' "$state"
    else
        echo unknown
    fi
}

# _vapt_coae_report PREFIX [AUTHORITY] — one line per pin plus the interpreter;
# returns 0 when everything matches, 1 otherwise. Read-only.
_vapt_coae_report() {
    local prefix="$1" authority="${2:-owned}" py pin st bad=0
    py="$(_vapt_coae_python)"
    if ! _vapt_coae_python_ok "$py"; then
        echo "warn: $prefix interpreter is Python ${py:-unknown}, htb-coae needs $VAPT_COAE_PYTHON"
        bad=1
    elif ! _vapt_coae_interpreter_resolves "$authority"; then
        echo "warn: $prefix interpreter $VAPT_COAE_DIR/bin/python lacks a compatible $authority uv-managed Python $VAPT_COAE_PYTHON chain"
        bad=1
    else
        echo "ok: $prefix interpreter Python $py"
    fi
    for pin in "${VAPT_COAE_PINS[@]}"; do
        st="$(_vapt_coae_pin_state "$pin")"
        case "$st" in
        exact*) echo "ok: $prefix $pin (installed ${st#exact })" ;;
        drifted*)
            echo "warn: $prefix $pin drifted (installed ${st#drifted })"
            bad=1
            ;;
        *)
            echo "warn: $prefix $pin $st"
            bad=1
            ;;
        esac
    done
    return "$bad"
}

# _vapt_coae_shape_ok — the observed path is a real directory holding a real
# pyvenv.cfg (not a link, file or half-created tree).
_vapt_coae_shape_ok() {
    [[ ! -L $VAPT_COAE_SEEN && -d $VAPT_COAE_SEEN && -f $VAPT_COAE_SEEN/pyvenv.cfg && ! -L $VAPT_COAE_SEEN/pyvenv.cfg ]]
}

# _vapt_coae_skip MESSAGE — report a skipped requirement: degraded, rc 0.
_vapt_coae_skip() {
    warn "vapt-env: $1"
    VAPT_ENV_DEGRADED=1
    return 0
}

# _vapt_coae_apply — create or reconcile the owned environment. Returns 1
# only when an attempted mutation (including an ownership record write)
# failed; an unavailable prerequisite or a user-owned/conflicting path is
# reported, marked degraded and skipped.
_vapt_coae_apply() {
    local dir="$VAPT_COAE_DIR" seen="$VAPT_COAE_SEEN" owner py pin st create=false
    VAPT_COAE_STATUS=unavailable
    owner="$(_vapt_coae_record_state)"
    if [[ $owner == conflict ]]; then
        _vapt_coae_skip "the ownership record $VAPT_COAE_RECORD (or a parent) is a symlink or not a regular file; preserved, htb-coae environment not provisioned"
        return
    fi
    if ! vapt_path_ancestors_safe "$dir"; then
        _vapt_coae_skip "a parent of $dir is a symlink or not a directory; preserved, htb-coae environment not provisioned"
        return
    fi

    if [[ -e $seen || -L $seen ]]; then
        if ! _vapt_coae_shape_ok; then
            if [[ $owner == none ]]; then
                _vapt_coae_skip "$dir exists but is not a virtual environment; left untouched, htb-coae environment not provisioned"
            else
                _vapt_coae_skip "$dir, recorded as haseen's, is not a complete virtual environment (interrupted creation?); remove it and reapply"
            fi
            return
        fi
        if [[ $owner == none ]]; then
            info "vapt-env: $dir is an existing environment haseen did not create; reporting only, not modifying it"
            VAPT_COAE_STATUS=unmanaged
            if ! _vapt_coae_report "htb-coae (unmanaged)" unmanaged; then
                _vapt_coae_skip "the unmanaged htb-coae environment differs from the pins; reconcile it yourself or move it aside and reapply"
            fi
            return 0
        fi
        py="$(_vapt_coae_python)"
        if ! _vapt_coae_python_ok "$py"; then
            _vapt_coae_skip "owned $dir runs Python ${py:-unknown}, not $VAPT_COAE_PYTHON; not rebuilding it in place — remove it and reapply"
            return
        fi
        if ! _vapt_coae_interpreter_resolves; then
            _vapt_coae_skip "owned $dir/bin/python lacks a compatible uv-managed Python $VAPT_COAE_PYTHON chain; not rebuilding it in place — remove it and reapply"
            return
        fi
        if _vapt_coae_report "htb-coae" >/dev/null; then
            if [[ $owner == pending ]] && ! _vapt_coae_record created; then
                warn "vapt-env: could not record $dir as complete in $VAPT_COAE_RECORD; the pending record is kept"
                return 1
            fi
            info "vapt-env: htb-coae environment matches its pins"
            VAPT_COAE_STATUS=available
            return 0
        fi
        # Reconcile only unambiguous missing or drifted pins. Unsafe or
        # duplicate metadata is not evidence authorizing a package mutation.
        for pin in "${VAPT_COAE_PINS[@]}"; do
            st="$(_vapt_coae_pin_state "$pin")"
            case "$st" in
            exact* | drifted* | missing) ;;
            *)
                _vapt_coae_skip "owned $dir has $st metadata for $pin; left untouched, htb-coae environment not reconciled"
                return
                ;;
            esac
        done
    else
        create=true
    fi
    if ! vapt_path_ancestors_safe "$VAPT_UV_PYTHON_DIR/.managed"; then
        _vapt_coae_skip "the intended uv Python store $VAPT_UV_PYTHON_DIR (or a parent) is a symlink or not a directory; preserved, htb-coae environment not provisioned"
        return
    fi

    if ! declare -F vapt_install_infra >/dev/null || ! vapt_install_infra uv; then
        _vapt_coae_skip "unavailable: uv (extra/uv); htb-coae environment not provisioned"
        return
    fi
    if ! $DRY_RUN && [[ ! -x $(vapt_read_path "$VAPT_UV") ]]; then
        _vapt_coae_skip "unavailable: $VAPT_UV missing after provisioning; htb-coae environment not provisioned"
        return
    fi

    if $create; then
        # Durably recorded before creation, so an interrupted run is still
        # ours to finish next time rather than looking like a user's
        # environment. No record, no environment.
        if ! _vapt_coae_record pending; then
            warn "vapt-env: could not record ownership in $VAPT_COAE_RECORD; $dir not created"
            return 1
        fi
        info "vapt-env: creating $dir on a uv-managed CPython $VAPT_COAE_PYTHON"
        if ! run env "UV_PYTHON_INSTALL_DIR=$VAPT_UV_PYTHON_DIR" "$VAPT_UV" venv --no-project --managed-python --python "$VAPT_COAE_PYTHON" "$dir"; then
            warn "vapt-env: uv venv failed for $dir; the pending ownership record is kept"
            return 1
        fi
    fi
    if ! $DRY_RUN && ! _vapt_coae_interpreter_resolves; then
        warn "vapt-env: $dir/bin/python lacks verified owned uv-managed provenance; packages not installed, ownership record kept"
        VAPT_ENV_DEGRADED=1
        return 1
    fi
    info "vapt-env: installing the htb-coae pin set into $dir"
    if ! run env "UV_PYTHON_INSTALL_DIR=$VAPT_UV_PYTHON_DIR" "$VAPT_UV" pip install --python "$dir/bin/python" "${VAPT_COAE_PINS[@]}"; then
        warn "vapt-env: uv pip install failed for $dir; the environment is kept for the next run"
        return 1
    fi
    if ! _vapt_coae_record created; then
        warn "vapt-env: could not record $dir as complete in $VAPT_COAE_RECORD; the pending record is kept"
        return 1
    fi
    if $DRY_RUN; then
        VAPT_COAE_STATUS=planned
        return 0
    fi
    if ! _vapt_coae_report "htb-coae"; then
        warn "vapt-env: htb-coae interpreter or metadata does not match the pins after installation"
        return 1
    fi
    VAPT_COAE_STATUS=available
}

_vapt_coae_status() {
    local owner rc=0
    owner="$(_vapt_coae_record_state 2>/dev/null)"
    if [[ $owner == conflict ]]; then
        echo "warn: htb-coae ownership record $VAPT_COAE_RECORD (or a parent) is a symlink or not a regular file"
        return 2
    fi
    if ! vapt_path_ancestors_safe "$VAPT_COAE_DIR" 2>/dev/null; then
        echo "warn: a parent of $VAPT_COAE_DIR is a symlink or not a directory"
        return 2
    fi
    if [[ ! -e $VAPT_COAE_SEEN && ! -L $VAPT_COAE_SEEN ]]; then
        if [[ $owner == none && ${VAPT_COAE_REQUIRED:-0} != 1 ]]; then return 0; fi
        echo "warn: required htb-coae environment $VAPT_COAE_DIR is missing"
        _vapt_coae_report "htb-coae" || true
        return 2
    fi
    if ! _vapt_coae_shape_ok; then
        echo "warn: $VAPT_COAE_DIR is not a virtual environment"
        return 2
    fi
    if [[ $owner == none ]]; then
        _vapt_coae_report "htb-coae (unmanaged)" unmanaged || rc=2
    else
        _vapt_coae_report "htb-coae" || rc=2
        [[ $owner == pending ]] && {
            echo "warn: htb-coae environment creation did not finish; reapply the layer"
            rc=2
        }
    fi
    return "$rc"
}

# vapt_coae_interpreter_ok — the PyRIT adapter's gate: true only for the
# haseen-owned, completely created environment whose pyvenv.cfg says 3.12
# and whose bin/python resolves through the verified intended uv store.
# Read-only, quiet, fixture-rooted; never runs the interpreter.
vapt_coae_interpreter_ok() {
    _vapt_env_paths
    [[ $(_vapt_coae_record_state 2>/dev/null) == created ]] || return 1
    vapt_path_ancestors_safe "$VAPT_COAE_DIR" 2>/dev/null || return 1
    _vapt_coae_shape_ok || return 1
    _vapt_coae_python_ok "$(_vapt_coae_python)" || return 1
    _vapt_coae_interpreter_resolves
}

# ---------------------------------------------------------------------------
# Activation links

# _vapt_link_journal DEST — prints "STATE<TAB>READLINK" for DEST's journal
# entry, or nothing. Journal lines are "v1<TAB>STATE<TAB>DEST<TAB>READLINK";
# unrecognised or duplicate destination entries return 2, as do a symlinked
# journal/parent or a non-regular journal. None of these is ownership authority;
# preserve the journal rather than silently deleting its unknown state.
_vapt_link_journal() {
    local want="$1" ver state dest target seen entry='' destinations=()
    vapt_state_path_safe "$VAPT_LINK_JOURNAL" || return 2
    seen="$(vapt_read_path "$VAPT_LINK_JOURNAL")"
    [[ -f $seen ]] || return 0
    while IFS=$'\t' read -r ver state dest target || [[ -n $ver$state$dest$target ]]; do
        [[ $ver == v1 && $dest == /* && -n $target && $target != *$'\t'* ]] || return 2
        [[ $state == pending || $state == created ]] || return 2
        local previous
        for previous in "${destinations[@]}"; do
            [[ $previous != "$dest" ]] || return 2
        done
        destinations+=("$dest")
        [[ $dest == "$want" ]] && entry="$state"$'\t'"$target"
    done <"$seen"
    [[ -z $entry ]] || printf '%s\n' "$entry"
    return 0
}

# _vapt_link_journal_set DEST STATE [READLINK] — replace DEST's entry, keeping
# the other links' entries; an empty STATE drops it, and an empty journal is
# removed. Checked and atomic through vapt_state_write/vapt_state_clear.
_vapt_link_journal_set() {
    local want="$1" new="$2" link="${3:-}" seen ver state dest target lines=()
    _vapt_link_journal "$want" >/dev/null || return 1
    seen="$(vapt_read_path "$VAPT_LINK_JOURNAL")"
    if [[ -f $seen && ! -L $seen ]]; then
        while IFS=$'\t' read -r ver state dest target; do
            [[ $ver == v1 && -n $dest && $dest != "$want" && -n $target ]] || continue
            [[ $state == pending || $state == created ]] || continue
            lines+=("v1"$'\t'"$state"$'\t'"$dest"$'\t'"$target")
        done <"$seen"
    fi
    [[ -z $new ]] || lines+=("v1"$'\t'"$new"$'\t'"$want"$'\t'"$link")
    if ((${#lines[@]} == 0)); then
        vapt_state_clear "$VAPT_LINK_JOURNAL"
    else
        printf '%s\n' "${lines[@]}" | vapt_state_write "$VAPT_LINK_JOURNAL"
    fi
}

# _vapt_link_create DEST — make the link; DEST is known to be absent and its
# parents safe. The pending entry must be durable first; a failed created
# entry rolls back only the link this call made, if it is still exactly that.
_vapt_link_create() {
    local dest="$1" seen made=false entry
    seen="$(vapt_read_path "$dest")"
    if ! _vapt_link_journal_set "$dest" pending "$VAPT_LINK_WANT"; then
        warn "vapt-env: could not journal $dest in $VAPT_LINK_JOURNAL; link not created"
        return 1
    fi
    if run mkdir -p -- "${dest%/*}" && vapt_path_ancestors_safe "$dest" &&
        run ln -s -- "$VAPT_LINK_WANT" "$dest"; then
        made=true
        if $DRY_RUN || [[ -L $seen && $(readlink -- "$seen") == "$VAPT_LINK_WANT" ]]; then
            if _vapt_link_journal_set "$dest" created "$VAPT_LINK_WANT"; then
                info "vapt-env: activated the VAPT PATH fragment ($dest)"
                return 0
            fi
            warn "vapt-env: could not record $dest as created in $VAPT_LINK_JOURNAL"
        fi
    fi
    if ! vapt_path_ancestors_safe "$dest"; then
        warn "vapt-env: $dest parents changed during creation; link preserved and pending journal entry kept"
        VAPT_ENV_DEGRADED=1
        return 1
    fi
    if $made && ! $DRY_RUN &&
        [[ -L $seen && $(readlink -- "$seen") == "$VAPT_LINK_WANT" ]]; then
        run rm -f -- "$dest" || true
    fi
    if $made && [[ -L $seen || -e $seen ]]; then
        warn "vapt-env: $dest could not be rolled back; its pending journal entry is kept"
    else
        # A failed ln never grants ownership of an EEXIST link. Drop only
        # our pending entry, not a subsequently completed journal record.
        # Layer apply/remove serializes this read/modify/write transaction.
        entry="$(_vapt_link_journal "$dest")" || return 1
        if [[ $entry == pending$'\t'"$VAPT_LINK_WANT" ]]; then
            _vapt_link_journal_set "$dest" '' ||
                warn "vapt-env: $dest pending journal entry could not be dropped"
        fi
    fi
    warn "vapt-env: could not create $dest"
    return 1
}

# _vapt_link_apply DEST — create, adopt or retarget the owned link at DEST.
_vapt_link_apply() {
    local dest="$1" seen entry jrc=0 state recorded current
    seen="$(vapt_read_path "$dest")"
    entry="$(_vapt_link_journal "$dest")" || jrc=$?
    if ((jrc != 0)); then
        warn "vapt-env: the link journal $VAPT_LINK_JOURNAL is unsafe or unrecognised; preserved, $dest not managed"
        VAPT_ENV_DEGRADED=1
        return 0
    fi
    state="${entry%%$'\t'*}" recorded="${entry#*$'\t'}"
    if ! vapt_path_ancestors_safe "$dest"; then
        warn "vapt-env: a parent of $dest is a symlink or not a directory; preserved, PATH fragment not activated there"
        VAPT_ENV_DEGRADED=1
        return 0
    fi

    if [[ -L $seen ]]; then
        current="$(readlink -- "$seen")"
        if [[ $current == "$VAPT_LINK_WANT" ]]; then
            if [[ -z $entry ]]; then
                info "vapt-env: $dest already points at the fragment; borrowed, not journaled"
            elif [[ $state == pending ]] && ! _vapt_link_journal_set "$dest" created "$VAPT_LINK_WANT"; then
                warn "vapt-env: could not record $dest as created in $VAPT_LINK_JOURNAL; the pending entry is kept"
                return 1
            fi
            return 0
        fi
        if [[ -n $entry && $current == "$recorded" ]]; then
            # Ours, created for another haseen location (checkout vs
            # installed tree): replace it with the current one.
            info "vapt-env: retargeting the owned activation link $dest to $VAPT_LINK_WANT"
            run rm -f -- "$dest" || return 1
            _vapt_link_create "$dest"
            return
        fi
        warn "vapt-env: $dest is a symlink to $current, not haseen's; preserved, PATH fragment not activated there"
        VAPT_ENV_DEGRADED=1
        return 0
    fi
    if [[ -e $seen ]]; then
        warn "vapt-env: $dest exists and is not haseen's link; preserved, PATH fragment not activated there"
        VAPT_ENV_DEGRADED=1
        return 0
    fi
    _vapt_link_create "$dest"
}

# _vapt_link_session_apply — the optional uwsm session link. Desktop hosts
# only: without an existing env.d directory there is nothing to join (a
# stale entry for an already-absent link is dropped).
_vapt_link_session_apply() {
    local entry jrc=0
    if [[ ! -e $(vapt_read_path "$VAPT_LINK_SESSION_DIR") && ! -L $(vapt_read_path "$VAPT_LINK_SESSION_DIR") ]]; then
        entry="$(_vapt_link_journal "$VAPT_LINK_SESSION" 2>/dev/null)" || jrc=$?
        if ((jrc == 0)) && [[ -n $entry ]]; then
            _vapt_link_journal_set "$VAPT_LINK_SESSION" '' || return 1
        fi
        info "vapt-env: no $VAPT_LINK_SESSION_DIR (no uwsm desktop session); the VAPT PATH stays shell-only"
        return 0
    fi
    local degraded_before="${VAPT_ENV_DEGRADED:-0}" rc=0
    _vapt_link_apply "$VAPT_LINK_SESSION" || rc=$?
    if ((rc == 0)) && [[ $VAPT_ENV_DEGRADED == "$degraded_before" ]]; then
        info "vapt-env: graphical apps see the VAPT PATH from the next login"
    fi
    return "$rc"
}

# _vapt_link_remove DEST — delete DEST only when the journal names it, its
# parents are unchanged and it still points where haseen pointed it.
_vapt_link_remove() {
    local dest="$1" seen entry jrc=0 state recorded current
    seen="$(vapt_read_path "$dest")"
    entry="$(_vapt_link_journal "$dest")" || jrc=$?
    if ((jrc != 0)); then
        warn "vapt-env: the link journal $VAPT_LINK_JOURNAL is unsafe or unrecognised; $dest left in place"
        VAPT_ENV_DEGRADED=1
        return 0
    fi
    [[ -n $entry ]] || return 0
    state="${entry%%$'\t'*}" recorded="${entry#*$'\t'}"
    if ! vapt_path_ancestors_safe "$dest"; then
        warn "vapt-env: a parent of $dest changed since haseen created it; preserved, journal kept at $VAPT_LINK_JOURNAL"
        VAPT_ENV_DEGRADED=1
        return 0
    fi
    if [[ ! -L $seen && ! -e $seen ]]; then
        _vapt_link_journal_set "$dest" '' || return 1
        return 0
    fi
    if [[ -L $seen ]]; then
        current="$(readlink -- "$seen")"
        if [[ $current == "$recorded" ]]; then
            run rm -f -- "$dest" || return 1
            _vapt_link_journal_set "$dest" '' || return 1
            info "vapt-env: deactivated the VAPT PATH fragment (removed $dest)"
            return 0
        fi
    fi
    warn "vapt-env: $dest changed since haseen created it ($state); preserved, journal kept at $VAPT_LINK_JOURNAL"
    VAPT_ENV_DEGRADED=1
    return 0
}

# _vapt_link_status DEST OPTIONAL — rc 0 active, 1 missing, 2 conflict. An
# optional link that is absent and unjournaled prints nothing.
_vapt_link_status() {
    local dest="$1" optional="$2" seen entry jrc=0 current
    seen="$(vapt_read_path "$dest")"
    entry="$(_vapt_link_journal "$dest" 2>/dev/null)" || jrc=$?
    if ((jrc != 0)); then
        echo "warn: link journal $VAPT_LINK_JOURNAL is unsafe or unrecognised"
        return 2
    fi
    if ! vapt_path_ancestors_safe "$dest" 2>/dev/null; then
        echo "warn: a parent of $dest is a symlink or not a directory"
        return 2
    fi
    if [[ -L $seen ]]; then
        current="$(readlink -- "$seen")"
        if [[ $current != "$VAPT_LINK_WANT" ]]; then
            echo "warn: $dest points at $current, not $VAPT_LINK_WANT"
            return 2
        fi
        if [[ ! -f $VAPT_LINK_WANT ]]; then
            echo "warn: $dest is dangling ($VAPT_LINK_WANT is missing)"
            return 2
        fi
        if [[ -n $entry ]]; then
            echo "ok: VAPT PATH fragment active at $dest (haseen-owned link)"
        else
            echo "ok: VAPT PATH fragment active at $dest (borrowed link, not removed by haseen)"
        fi
        return 0
    fi
    if [[ -e $seen ]]; then
        echo "warn: $dest is not haseen's link"
        return 2
    fi
    if $optional && [[ -z $entry ]]; then
        return 0
    fi
    echo "missing: VAPT PATH fragment link $dest"
    [[ -n $entry ]] && return 2
    return 1
}

# _vapt_path_shadows — the fragment APPENDS the layer's pipx store to PATH,
# so a same-named command in any directory before it wins. Report every
# owned store executable that the current PATH would not reach first,
# instead of silently letting the user's choice and the reported native
# disagree. Directories are inspected through vapt_read_path. Returns 1 when
# any is shadowed.
_vapt_path_shadows() {
    local store="$VAPT_PIPX_STORE/bin" seen exe name dir found=0 dirs=()
    seen="$(vapt_read_path "$store")"
    [[ -d $seen && ! -L $seen ]] || return 0
    IFS=: read -ra dirs <<<"$PATH"
    for exe in "$seen"/*; do
        [[ -e $exe || -L $exe ]] || continue
        name="${exe##*/}"
        for dir in "${dirs[@]}"; do
            [[ $dir == "$store" ]] && break
            [[ -n $dir ]] || continue
            if [[ -x $(vapt_read_path "$dir")/$name && ! -d $(vapt_read_path "$dir")/$name ]]; then
                echo "warn: $dir/$name precedes the VAPT-owned $store/$name on PATH; the owned native is not the one that runs"
                found=1
                break
            fi
        done
    done
    return "$found"
}

# ---------------------------------------------------------------------------
# Public seams

# vapt_environment_apply GROUP... — GROUP may carry the security/ prefix.
# Sets VAPT_ENV_DEGRADED=1 when a selected artifact was skipped (unavailable
# prerequisite, preserved conflict, drift left alone, shadowed native) so
# the caller's report can persist it, and VAPT_COAE_STATUS for the native
# adapters; the return code stays 0 for those and 1 only for a failed
# attempted mutation, including a failed ownership record.
vapt_environment_apply() {
    _vapt_env_paths
    VAPT_ENV_DEGRADED=0 VAPT_COAE_STATUS=unselected
    local g coae=false rc=0
    [[ ${VAPT_COAE_REQUIRED:-0} == 1 ]] && coae=true
    for g in "$@"; do
        [[ ${g#security/} == htb-coae ]] && coae=true
    done
    if $coae; then
        _vapt_coae_apply || rc=1
    fi
    if [[ ! -f $HASEEN_PATH/default/vapt/shell.sh ]]; then
        warn "vapt-env: $HASEEN_PATH/default/vapt/shell.sh is missing from this haseen tree; PATH fragment not activated"
        VAPT_ENV_DEGRADED=1
        return "$rc"
    fi
    _vapt_link_apply "$VAPT_LINK_SHELL" || rc=1
    _vapt_link_session_apply || rc=1
    if ! _vapt_path_shadows >&2; then
        warn "vapt-env: PATH order hides owned VAPT natives; left as the user set it"
        VAPT_ENV_DEGRADED=1
    fi
    return "$rc"
}

vapt_environment_remove() {
    _vapt_env_paths
    VAPT_ENV_DEGRADED=0
    local rc=0
    _vapt_link_remove "$VAPT_LINK_SHELL" || { rc=1; VAPT_ENV_DEGRADED=1; }
    _vapt_link_remove "$VAPT_LINK_SESSION" || { rc=1; VAPT_ENV_DEGRADED=1; }
    info "vapt-env: retained: $VAPT_COAE_DIR and uv's Python downloads, the pipx store $VAPT_PIPX_STORE, installed packages and every user file"
    return "$rc"
}

vapt_environment_status() {
    _vapt_env_paths
    local rc=0 r
    _vapt_link_status "$VAPT_LINK_SHELL" false
    r=$?
    ((r > rc)) && rc=$r
    _vapt_link_status "$VAPT_LINK_SESSION" true
    r=$?
    # A degraded environment outranks a merely missing link.
    ((r == 2)) && rc=2
    _vapt_coae_status
    r=$?
    ((r == 2)) && rc=2
    _vapt_path_shadows || rc=2
    return "$rc"
}
