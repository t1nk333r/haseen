# shellcheck shell=bash
# registry.sh — where third-party plugins come from and how an install is
# pinned. Sourced by bin/haseen-plugin-{registry,search,install,update,
# uninstall,lock,restore}; never executed.
#
# Adapted from DankMaterialShell core/internal/{registries,plugins} (MIT,
# Copyright (c) 2025 Avenge Media LLC): a registry is a git repository whose
# plugins/ directory holds one JSON file per plugin, an install is a clone at a
# commit, and plugins.lock.json pins {repo, path, commit} so another machine
# resolves the same thing. git and jq do the work; there is no daemon and no
# index service.
#
# What haseen adds, because upstream verifies nothing before enabling foreign
# QML (registry.go/manager.go have no schema, signature or checksum check):
# every install and restore runs the plugin through `haseen plugin validate`
# and refuses to keep a plugin that fails. The lockfile's own invariants
# (no credentials in a URL, no path that climbs out, a full 40-hex commit) are
# upstream's and are kept.

[[ -n ${HASEEN_REGISTRY_SH:-} ]] && return 0
HASEEN_REGISTRY_SH=1

# shellcheck source=plugin.sh
source "$(dirname "${BASH_SOURCE[0]}")/plugin.sh"

require_cmds git jq

REGISTRY_CONFIG="$HASEEN_USER_CONFIG/registries.json"
REGISTRY_CACHE="${HASEEN_USER_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/haseen}/registries"
PLUGIN_LOCKFILE="$HASEEN_USER_CONFIG/plugins.lock.json"
PLUGIN_REPOS_DIR="$PLUGIN_USER_DIR/.repos"
LOCKFILE_VERSION=1
# shellcheck disable=SC2034  # read by bin/haseen-plugin-{install,lock}
COMMIT_RE='^[0-9a-f]{40}$'

# The official DankMaterialShell registry is the default source: its plugins
# are DMS-format, which haseen loads through the compat adapter (architecture
# 5.4). haseen publishes no registry of its own yet. HASEEN_REGISTRY_DEFAULT
# replaces it, and an empty value removes it, which is what the tests use so
# they never reach the network.
REGISTRY_DEFAULT_NAME=dms
REGISTRY_DEFAULT_URL="${HASEEN_REGISTRY_DEFAULT-https://github.com/AvengeMedia/dms-plugin-registry.git}"

# --- sources ---------------------------------------------------------------

# registry_sources — "name<TAB>url", the default first, then the user's.
registry_sources() {
    [[ -n $REGISTRY_DEFAULT_URL ]] &&
        printf '%s\t%s\n' "$REGISTRY_DEFAULT_NAME" "$REGISTRY_DEFAULT_URL"
    [[ -f $REGISTRY_CONFIG ]] || return 0
    jq -r '.sources[]? | select(.name and .url) | "\(.name)\t\(.url)"' "$REGISTRY_CONFIG"
}

registry_url() { registry_sources | awk -F'\t' -v n="$1" '$1 == n { print $2; exit }'; }

registry_name_ok() { [[ $1 =~ ^[a-z0-9][a-z0-9-]*$ ]]; }

# registry_url_ok URL — a repository haseen is willing to clone: https, an ssh
# git@host:path, or a local path (a registry or a plugin you are writing).
# Credentials are refused in every form, because a URL that carries a token
# would be written into the lockfile.
registry_url_ok() {
    case "$1" in
    /* | file://*) [[ $1 != *"@"* ]] ;;
    git@*:*) return 0 ;;
    *@*:*) return 1 ;;
    https://*) [[ $1 != *"@"* ]] ;;
    *) return 1 ;;
    esac
}

# --- the index -------------------------------------------------------------

registry_clone_dir() { printf '%s/%s\n' "$REGISTRY_CACHE" "$1"; }

# registry_sync [NAME] — clone or fast-forward each source. A clone that cannot
# be updated is re-made, the way upstream's updateOne does.
registry_sync() {
    local name url dir
    while IFS=$'\t' read -r name url; do
        [[ -z ${1:-} || $1 == "$name" ]] || continue
        registry_url_ok "$url" || {
            warn "registry $name: refusing URL $url"
            continue
        }
        dir="$(registry_clone_dir "$name")"
        if [[ -d $dir/.git ]]; then
            run git -C "$dir" fetch --quiet --depth 1 origin HEAD ||
                run rm -rf "$dir"
            [[ -d $dir/.git ]] && run git -C "$dir" reset --quiet --hard FETCH_HEAD && continue
        fi
        run mkdir -p "$(dirname "$dir")"
        run git clone --quiet --depth 1 "$url" "$dir" || warn "registry $name: clone failed"
    done < <(registry_sources)
}

# registry_entries — every indexed plugin as one JSON object per line, with the
# source name added. Entry fields are upstream's: id, name, repo, optional
# path, description, author, capabilities.
registry_entries() {
    local name url dir file
    while IFS=$'\t' read -r name url; do
        dir="$(registry_clone_dir "$name")"
        [[ -d $dir/plugins ]] || continue
        for file in "$dir"/plugins/*.json; do
            [[ -f $file ]] || continue
            jq -c --arg source "$name" \
                'select(.id and .repo) | {id, name: (.name // .id), repo, path: (.path // ""),
                 description: (.description // ""), author: (.author // ""), source: $source}' \
                "$file" 2>/dev/null || warn "registry $name: ${file##*/} is not valid JSON"
        done
    done < <(registry_sources)
}

registry_entry() { registry_entries | jq -c --arg id "$1" 'select(.id == $id)' | head -n1; }

# --- the lockfile ----------------------------------------------------------

lockfile_read() {
    if [[ -f $PLUGIN_LOCKFILE ]]; then
        jq -c . "$PLUGIN_LOCKFILE"
    else
        printf '{"version":%d,"plugins":{},"repositories":{}}\n' "$LOCKFILE_VERSION"
    fi
}

# lockfile_check JSON — the invariants upstream enforces: the version, a plugin
# id that is a single safe path component, a path that cannot climb out, a full
# commit, and no credentials in a repository URL.
lockfile_check() {
    local json="$1" problems
    problems="$(jq -r --arg v "$LOCKFILE_VERSION" '
        [ (if (.version | tostring) != $v then "unsupported lockfile version \(.version)" else empty end),
          (.plugins // {} | to_entries[] |
            (if (.key | test("^[A-Za-z0-9][A-Za-z0-9._-]*$") | not) then "unsafe plugin id \(.key)" else empty end),
            (if (.value.path // "" | test("(^/)|(^\\.\\.?/)|(/\\.\\./)|(/\\.\\.$)")) then "unsafe path in \(.key)" else empty end),
            (if (.value.commit // "" | test("^[0-9a-f]{40}$") | not) then "not a full commit in \(.key)" else empty end)),
          (.repositories // {} | keys[] | select(test("https://[^/]*@")) | "credentials in repository URL \(.)")
        ] | .[]' <<<"$json" 2>/dev/null)"
    [[ -z $problems ]] || {
        printf '%s\n' "$problems" >&2
        return 1
    }
}

# lockfile_write JSON — atomic, and only after the invariants hold.
lockfile_write() {
    local json="$1"
    lockfile_check "$json" || die "refusing to write an invalid lockfile"
    if $DRY_RUN; then
        echo "DRYRUN: write $PLUGIN_LOCKFILE:"
        jq . <<<"$json" | sed 's/^/    | /'
        return 0
    fi
    mkdir -p "$(dirname "$PLUGIN_LOCKFILE")"
    jq --indent 2 . <<<"$json" >"$PLUGIN_LOCKFILE.new"
    mv "$PLUGIN_LOCKFILE.new" "$PLUGIN_LOCKFILE"
}

# lockfile_pin ID REPO PATH COMMIT — record one plugin and its repository.
# Plugins from one repository share a checkout, so they share its commit:
# pinning one moves every plugin taken from that repository, which is what
# upstream's repository-level entry means.
lockfile_pin() {
    local id="$1" repo="$2" path="$3" commit="$4"
    lockfile_write "$(lockfile_read | jq -c \
        --arg id "$id" --arg repo "$repo" --arg path "$path" --arg commit "$commit" \
        '.plugins[$id] = {repo: $repo, path: $path, commit: $commit}
         | .plugins |= with_entries(if .value.repo == $repo then .value.commit = $commit else . end)
         | .repositories[$repo] = $commit')"
}

# lockfile_drop ID — forget a plugin, and forget its repository when no other
# plugin still comes from it.
lockfile_drop() {
    local id="$1" repos
    repos="$(lockfile_read | jq -c --arg id "$id" '[.plugins | del(.[$id]) | .[].repo]')"
    lockfile_write "$(lockfile_read | jq -c --arg id "$id" --argjson repos "$repos" '
        del(.plugins[$id])
        | .repositories |= with_entries(select(.key as $repo | $repos | index($repo)))')"
}

lockfile_entry() { lockfile_read | jq -c --arg id "$1" '.plugins[$id] // empty'; }

# --- installing ------------------------------------------------------------

# repo_dir URL — the shared checkout for a repository, named by its hash so two
# plugins from one monorepo share one clone (upstream manager.go does the same).
repo_dir() { printf '%s/%s\n' "$PLUGIN_REPOS_DIR" "$(printf '%s' "$1" | sha256sum | cut -c1-16)"; }

# registry_fetch URL [COMMIT] — clone (or update) the repository and check out
# COMMIT, or its default branch. Prints the commit that is now checked out.
registry_fetch() {
    local url="$1" commit="${2:-}" dir
    registry_url_ok "$url" || die "refusing repository URL: $url"
    dir="$(repo_dir "$url")"
    if [[ ! -d $dir/.git ]]; then
        run mkdir -p "$PLUGIN_REPOS_DIR"
        run git clone --quiet "$url" "$dir" || die "could not clone $url"
    else
        run git -C "$dir" fetch --quiet --all --tags
    fi
    if $DRY_RUN; then
        # No apostrophe: inside "${x:-…}" bash reads one as an opening quote.
        printf '%s\n' "${commit:-<the default branch head>}"
        return 0
    fi
    if [[ -n $commit ]]; then
        git -C "$dir" checkout --quiet "$commit" 2>/dev/null ||
            die "$url has no commit $commit"
    else
        git -C "$dir" checkout --quiet "$(git -C "$dir" symbolic-ref --quiet --short HEAD ||
            git -C "$dir" rev-parse --abbrev-ref origin/HEAD | sed 's|^origin/||')" 2>/dev/null || true
        git -C "$dir" reset --quiet --hard "@{upstream}" 2>/dev/null || true
    fi
    git -C "$dir" rev-parse HEAD
}

# registry_link ID URL PATH — put the plugin's directory where the shell looks.
# A plugin that is the whole repository is a symlink to the checkout; one that
# lives in a subdirectory is a symlink to that subdirectory, which is how a
# monorepo registry entry (`path`) works.
registry_link() {
    local id="$1" url="$2" path="$3" src
    src="$(repo_dir "$url")${path:+/$path}"
    $DRY_RUN || [[ -d $src ]] || die "$url has no directory ${path:-/} for $id"
    run mkdir -p "$PLUGIN_USER_DIR"
    run rm -rf "$PLUGIN_USER_DIR/$id"
    run ln -sfn "$src" "$PLUGIN_USER_DIR/$id"
}

# registry_validate ID — the check upstream does not do. A plugin that fails is
# removed again, so a bad install never leaves something half-enabled behind.
registry_validate() {
    local id="$1"
    $DRY_RUN && return 0
    if ! haseen-plugin-validate "$PLUGIN_USER_DIR/$id" >/dev/null 2>&1; then
        haseen-plugin-validate "$PLUGIN_USER_DIR/$id" >&2 || true
        rm -rf "${PLUGIN_USER_DIR:?}/$id"
        return 1
    fi
}
