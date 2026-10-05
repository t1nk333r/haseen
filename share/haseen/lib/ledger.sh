# shellcheck shell=bash
# ledger.sh — "this ran once already" markers. Sourced, never executed.
#
# One marker file per entry under $HASEEN_USER_STATE/<kind>/<name>, holding how
# it was recorded, when, and the version that did it. The ledger lives in the
# user's state, never in the installed tree, so replacing or repackaging haseen
# does not replay anything.
#
# Kinds in use: `migrations` (plan 028) and `hardware` (plan 031).

[[ -n ${HASEEN_LEDGER_SH:-} ]] && return 0
HASEEN_LEDGER_SH=1

# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

ledger_dir() { printf '%s\n' "${HASEEN_LEDGER_DIR:-$HASEEN_USER_STATE}/$1"; }

ledger_applied() { [[ -f "$(ledger_dir "$1")/$2" ]]; }

# ledger_how KIND NAME — the first word of the marker (applied, sealed, ...).
ledger_how() {
    local marker
    marker="$(ledger_dir "$1")/$2"
    [[ -f $marker ]] || return 1
    read -r how _ <"$marker"
    printf '%s\n' "$how"
}

# ledger_record KIND NAME HOW — mark NAME done. HOW is kept so a later bug
# report can tell a first install (`sealed`) from a real run (`applied`).
ledger_record() {
    local kind="$1" name="$2" how="$3" dir
    dir="$(ledger_dir "$kind")"
    if $DRY_RUN; then
        echo "DRYRUN: record $kind $name ($how)"
        return 0
    fi
    mkdir -p "$dir"
    printf '%s %s %s\n' "$how" "$(date -Is)" "$(cat "$HASEEN_PATH/VERSION")" >"$dir/$name"
}

ledger_forget() {
    local marker
    marker="$(ledger_dir "$1")/$2"
    if $DRY_RUN; then
        echo "DRYRUN: rm $marker"
        return 0
    fi
    rm -f "$marker"
}
