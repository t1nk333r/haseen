# shellcheck shell=bash
# Owner inventory: waydots/packages/security, plus the plan 087 groups whose
# tool names come from oniomarchy category facts. Source names/pins are facts;
# provisioning policy here is independent of either source's installer.
VAPT_DIR="${LAYER_DIR:-$(dirname "${BASH_SOURCE[0]}")}"
source "$HASEEN_PATH/lib/packages.sh"
source "$VAPT_DIR/pacman.sh"
source "$VAPT_DIR/blackarch.sh"
source "$VAPT_DIR/oniomarchy.sh"
source "$VAPT_DIR/native.sh"
source "$VAPT_DIR/environment.sh"
VAPT_GROUPS=(core network web passwords ad osint cloud mobile forensics api htb-cjca htb-cpts htb-cwes htb-cwee htb-coae
    sdr wireless privacy anonymity automotive social reporting ai exploitation services)
# The reviewed fixed oniomarchy admission set (packages/oniomarchy.tsv): a
# 53rd published name needs a reviewed table and code change, never adoption.
VAPT_ONIOMARCHY_ADMITTED=52
vapt_reset() {
    declare -gA VAPT_NATIVE_SPEC=() VAPT_NATIVE_PROBE=() VAPT_NATIVE_BA=() VAPT_NATIVE_GROUP=() VAPT_PINS=()
    declare -gA VAPT_MEMBERSHIP=() VAPT_ENABLED=() VAPT_DATABASE=() VAPT_PACKAGE=() VAPT_VERSION=() VAPT_URL=() VAPT_PROVIDES=() VAPT_UNSAFE=() VAPT_SOURCE_BLOCKED=()
    declare -gA VAPT_SOURCE=() VAPT_TARGET=() VAPT_RESOLUTION=() VAPT_APPLIED=() VAPT_REASON=() VAPT_ATTEMPTS=() VAPT_INFRA_DONE=()
    declare -gA VAPT_INFRA_TARGET=() VAPT_INFRA_APPLY=() VAPT_INFRA_REASON=()
    declare -gA VAPT_ID_SOURCE=() VAPT_ID_TARGET=() VAPT_ID_UPSTREAM=() VAPT_ID_POLICY=() VAPT_ID_POLICY_REASON=()
    declare -gA VAPT_ALIAS=() VAPT_DEPENDENCY=() VAPT_DEPENDENCY_SOURCE=() VAPT_ONIO_ROLE=() VAPT_ONIO_LOGICAL=()
    declare -ga VAPT_SELECTED=() VAPT_ITEMS=() VAPT_REPOS=() VAPT_INFRA_ROWS=() VAPT_NATIVE_ORDER=() VAPT_DEPENDENCY_ROWS=()
    VAPT_MUTATION_FAILED=0 VAPT_PACMAN_BLOCKED=0 VAPT_ENV_STATUS=unknown VAPT_STAGE='' VAPT_COAE_REQUIRED=0 VAPT_BLACKARCH_STAGED=''
    VAPT_ONIOMARCHY_OPT=0 VAPT_ONIOMARCHY_SCOPE='' VAPT_ONIOMARCHY_STATE=not-selected VAPT_ONIOMARCHY_REASON='' VAPT_ONIO_TRUST_CHANGED='' VAPT_ONIO_UNSEEN='' VAPT_ONIO_ROTATION_NOTE=''
    vapt_native_paths
}
vapt_select() {
    VAPT_SELECTED=()
    local arg group known all=false selection='' seen=false
    while (($#)); do
        arg="$1"; shift
        case "$arg" in
        --groups) (($#)) || { warn '--groups needs a comma-separated list'; return 2; }; [[ $seen == false && $all == false ]] || return 2; selection="$1"; shift; seen=true ;;
        --all) [[ $seen == false && $all == false ]] || return 2; all=true ;;
        # Per-operation source consent; it selects no tool and is not stored.
        --with-oniomarchy) [[ $VAPT_ONIOMARCHY_OPT == 0 ]] || return 2; VAPT_ONIOMARCHY_OPT=1 ;;
        *) warn "unknown VAPT argument: $arg"; return 2 ;;
        esac
    done
    if $all; then VAPT_SELECTED=("${VAPT_GROUPS[@]}")
    elif $seen && [[ -n $selection && $selection != ,* && $selection != *, && $selection != *,,* ]]; then IFS=, read -r -a VAPT_SELECTED <<<"$selection"
    else warn 'VAPT requires --groups GROUP,... or --all (no default tools; --with-oniomarchy selects none)'; return 2
    fi
    local -A selected=()
    local dedup=()
    for group in "${VAPT_SELECTED[@]}"; do
        known=false
        for arg in "${VAPT_GROUPS[@]}"; do [[ $group != "$arg" ]] || known=true; done
        $known || { warn "unknown VAPT group: $group"; return 2; }
        [[ ${selected[$group]:-} ]] || dedup+=("$group")
        selected[$group]=1
    done
    VAPT_SELECTED=("${dedup[@]}")
}
# vapt_url_parse URL — split an absolute http(s) URL into VAPT_URL_SCHEME,
# VAPT_URL_HOST and VAPT_URL_PATH (lowercase, no trailing slash). Userinfo,
# ports, queries, fragments, escapes and empty or dot path segments are
# refused, so a path boundary check cannot be steered around.
vapt_url_parse() {
    local path
    [[ $1 =~ ^([Hh][Tt][Tt][Pp][Ss]?)://([A-Za-z0-9.-]+)(/[A-Za-z0-9._~+/-]*)?$ ]] || return 1
    VAPT_URL_SCHEME="${BASH_REMATCH[1],,}" VAPT_URL_HOST="${BASH_REMATCH[2],,}" path="${BASH_REMATCH[3],,}"
    while [[ $path == */ ]]; do path="${path%/}"; done
    [[ $VAPT_URL_HOST != .* && $VAPT_URL_HOST != *. && $VAPT_URL_HOST != *..* ]] || return 1
    [[ $path/ != *//* && $path/ != */./* && $path/ != */../* ]] || return 1
    VAPT_URL_PATH="$path"
}
vapt_manifest_validate() {
    local group logical ba manager spec probe rest line target
    local -A roots=()
    for group in "${VAPT_GROUPS[@]}"; do
        [[ -r $VAPT_DIR/packages/security/$group.txt ]] || return 2
        while IFS= read -r line || [[ -n $line ]]; do
            line="${line%%#*}"; line="${line//[$PKG_SPACE]/}"
            [[ -z $line || $line =~ $PKG_NAME_RE ]] || { warn "malformed VAPT manifest: $group"; return 2; }
            [[ -z $line ]] || roots[$line]=1
        done <"$VAPT_DIR/packages/security/$group.txt"
    done
    local table
    for table in security/native.tsv pins.tsv identities.tsv identity-policy.tsv dependencies.tsv aliases.tsv oniomarchy.tsv; do
        [[ -r $VAPT_DIR/packages/$table ]] || { warn "missing VAPT table: $table"; return 2; }
    done
    while IFS=$'\t' read -r group logical ba manager spec probe rest; do
        [[ -n $group && $group != \#* ]] || continue
        [[ $group == security/* && $logical =~ $PKG_NAME_RE && $ba =~ $PKG_NAME_RE && $manager == pipx && $probe =~ ^[A-Za-z0-9._+-]+$ && -z $rest ]] || return 2
        [[ $ba != none || $logical == pyrit ]] || return 2
        [[ $spec =~ ^[a-z0-9._-]+==[0-9][a-zA-Z0-9.+-]*$ || $spec == git+https://github.com/Pennyw0rth/NetExec@c7dc286ba65daf10402cdc470e531b84e6d3d911 ]] || return 2
        local present=false candidate
        for candidate in "${VAPT_GROUPS[@]}"; do [[ ${group#security/} != "$candidate" ]] || present=true; done
        $present && [[ ! ${VAPT_NATIVE_SPEC[$logical]:-} ]] || return 2
        VAPT_NATIVE_SPEC[$logical]="$spec"; VAPT_NATIVE_PROBE[$logical]="$probe"; VAPT_NATIVE_BA[$logical]="$ba"; VAPT_NATIVE_GROUP[$logical]="${group#security/}"
        VAPT_NATIVE_ORDER+=("$logical")
        roots[$logical]=1
    done <"$VAPT_DIR/packages/security/native.tsv"
    while IFS=$'\t' read -r logical target rest; do
        [[ -n $logical && $logical != \#* ]] || continue
        # A pin never names the private source: it is only ever the last tier.
        [[ $logical =~ $PKG_NAME_RE && ${roots[$logical]:-} && ! ${VAPT_PINS[$logical]:-} && $target == */* && ${target##*/} =~ $PKG_NAME_RE && -z $rest ]] && vapt_repo_allowed "${target%%/*}" && [[ ${target%%/*} != oniomarchy ]] || return 2
        VAPT_PINS[$logical]="$target"
    done <"$VAPT_DIR/packages/pins.tsv"
    local required_source required_target upstream reason
    while IFS=$'\t' read -r logical required_source required_target upstream reason rest; do
        [[ -n $logical && $logical != \#* ]] || continue
        [[ $logical =~ $PKG_NAME_RE && ${roots[$logical]:-} && ! ${VAPT_ID_SOURCE[$logical]:-} && ( $required_source == native || $required_source == repository ) && -n $required_target && -n $upstream && -n $reason && -z $rest ]] || return 2
        # Identities are canonical http(s) URLs matched by host and path
        # boundary; a repository identity names any target (*) or exactly one.
        vapt_url_parse "$upstream" && [[ $upstream != */ ]] || return 2
        if [[ $required_source == repository && $required_target != '*' ]]; then
            [[ $required_target == */* && ${required_target##*/} =~ $PKG_NAME_RE ]] && vapt_repo_allowed "${required_target%%/*}" && [[ ${required_target%%/*} != oniomarchy ]] || return 2
        fi
        VAPT_ID_SOURCE[$logical]="$required_source"; VAPT_ID_TARGET[$logical]="$required_target"
        VAPT_ID_UPSTREAM[$logical]="$upstream"
    done <"$VAPT_DIR/packages/identities.tsv"
    [[ ${VAPT_ID_SOURCE[pyrit]:-} == native && ${VAPT_ID_TARGET[pyrit]:-} == pyrit==1.1.0 ]] || return 2
    [[ ${VAPT_NATIVE_SPEC[pyrit]:-} == pyrit==1.1.0 && ${VAPT_NATIVE_BA[pyrit]:-} == none ]] || return 2
    local policy
    while IFS=$'\t' read -r logical policy reason rest; do
        [[ -n $logical && $logical != \#* ]] || continue
        [[ $logical =~ $PKG_NAME_RE && ${roots[$logical]:-} && ! ${VAPT_ID_POLICY[$logical]:-} && ( $policy == blocked || $policy == exact-name ) && -n $reason && -z $rest ]] || return 2
        # A blocked identity has no route a pin or adapter could reopen.
        [[ $policy != blocked || ( ! ${VAPT_PINS[$logical]:-} && ! ${VAPT_NATIVE_SPEC[$logical]:-} && ! ${VAPT_ID_SOURCE[$logical]:-} ) ]] || return 2
        VAPT_ID_POLICY[$logical]="$policy"; VAPT_ID_POLICY_REASON[$logical]="$reason"
    done <"$VAPT_DIR/packages/identity-policy.tsv"
    local consumer
    while IFS=$'\t' read -r logical consumer target reason rest; do
        [[ -n $logical && $logical != \#* ]] || continue
        # Dependency-only packages never become selectable roots.
        [[ $logical =~ $PKG_NAME_RE && ! ${roots[$logical]:-} && ! ${VAPT_DEPENDENCY[$logical]:-} && ( $consumer == '*' || ${roots[$consumer]:-} ) ]] || return 2
        [[ $target == */* && ${target##*/} =~ $PKG_NAME_RE && $reason == dependency && -z $rest ]] && vapt_repo_allowed "${target%%/*}" || return 2
        VAPT_DEPENDENCY[$logical]="$consumer"; VAPT_DEPENDENCY_SOURCE[$logical]="$target"
    done <"$VAPT_DIR/packages/dependencies.tsv"
    local repo package
    while IFS=$'\t' read -r logical repo package rest; do
        [[ -n $logical && $logical != \#* ]] || continue
        [[ $logical =~ $PKG_NAME_RE && ( ${roots[$logical]:-} || ${VAPT_DEPENDENCY[$logical]:-} ) && $package =~ $PKG_NAME_RE && $package != "$logical" && -z $rest ]] && vapt_repo_allowed "$repo" || return 2
        [[ ! ${VAPT_ALIAS[$logical/$repo]:-} && ( $repo != blackarch || ! ${VAPT_NATIVE_SPEC[$logical]:-} ) && ${VAPT_ID_POLICY[$logical]:-} != blocked ]] || return 2
        VAPT_ALIAS[$logical/$repo]="$package"
    done <"$VAPT_DIR/packages/aliases.tsv"
    # A dependency's concrete package is its own name or a reviewed alias.
    for logical in "${!VAPT_DEPENDENCY_SOURCE[@]}"; do
        target="${VAPT_DEPENDENCY_SOURCE[$logical]}"
        [[ ${target##*/} == "$logical" || ${VAPT_ALIAS[$logical/${target%%/*}]:-} == "${target##*/}" ]] || return 2
    done
    # The fixed oniomarchy admission table: exactly the reviewed published
    # names, each a candidate (serving one item by exact name or reviewed
    # alias, or none), a dependency, or the keyring infrastructure.
    local role count=0
    while IFS=$'\t' read -r package role logical rest; do
        [[ -n $package && $package != \#* ]] || continue
        [[ $package =~ $PKG_NAME_RE && ! ${VAPT_ONIO_ROLE[$package]:-} && -n $logical && -z $rest ]] || return 2
        case "$role" in
        infrastructure) [[ $package == oniomarchy-keyring && $logical == - ]] || return 2 ;;
        dependency)
            [[ $logical == - || ${VAPT_DEPENDENCY_SOURCE[$logical]:-} == "oniomarchy/$package" ]] || return 2 ;;
        candidate)
            if [[ $logical != - ]]; then
                [[ ${roots[$logical]:-} && ${VAPT_ID_POLICY[$logical]:-} != blocked && ! ${VAPT_DEPENDENCY[$package]:-} ]] || return 2
                [[ $package == "$logical" && ! ${VAPT_ALIAS[$logical/oniomarchy]:-} ]] || [[ ${VAPT_ALIAS[$logical/oniomarchy]:-} == "$package" ]] || return 2
            fi ;;
        *) return 2 ;;
        esac
        VAPT_ONIO_ROLE[$package]="$role"; VAPT_ONIO_LOGICAL[$package]="$logical"
        count=$((count + 1))
    done <"$VAPT_DIR/packages/oniomarchy.tsv"
    ((count == VAPT_ONIOMARCHY_ADMITTED)) || return 2
    # Every alias or dependency naming the source points at its exact row.
    for target in "${!VAPT_ALIAS[@]}"; do
        [[ $target == */oniomarchy ]] || continue
        package="${VAPT_ALIAS[$target]}" logical="${target%/oniomarchy}"
        [[ ${VAPT_ONIO_LOGICAL[$package]:-} == "$logical" ]] || return 2
    done
    for logical in "${!VAPT_DEPENDENCY_SOURCE[@]}"; do
        target="${VAPT_DEPENDENCY_SOURCE[$logical]}"
        [[ $target != oniomarchy/* || ${VAPT_ONIO_ROLE[${target#oniomarchy/}]:-} == dependency ]] || return 2
    done
    return 0
}
vapt_add_item() {
    local logical="$1" group="$2"
    [[ ${VAPT_MEMBERSHIP[$logical]:-} ]] || VAPT_ITEMS+=("$logical")
    if [[ ,${VAPT_MEMBERSHIP[$logical]:-}, != *,$group,* ]]; then
        VAPT_MEMBERSHIP[$logical]="${VAPT_MEMBERSHIP[$logical]:+${VAPT_MEMBERSHIP[$logical]},}$group"
    fi
}
vapt_collect_groups() {
    local group line logical
    for group in "$@"; do
        while IFS= read -r line || [[ -n $line ]]; do
            line="${line%%#*}"; line="${line//[$PKG_SPACE]/}"
            [[ -z $line ]] || vapt_add_item "$line" "$group"
        done <"$VAPT_DIR/packages/security/$group.txt"
        # Adapters indexed globally; native-only membership injected solely
        # for selected groups, duplicates share the same adapter everywhere.
        for logical in "${VAPT_NATIVE_ORDER[@]}"; do
            [[ ${VAPT_NATIVE_GROUP[$logical]} != "$group" ]] || vapt_add_item "$logical" "$group"
        done
    done
}
vapt_snapshot() {
    local output kind repo name version url provides flags=()
    $DRY_RUN && flags+=(--offline)
    output="$(vapt_meta snapshot "${flags[@]}" 2>/dev/null)" || { warn 'VAPT source metadata unreadable; cannot claim provisioning'; return 1; }
    VAPT_ENABLED=(); VAPT_DATABASE=(); VAPT_PACKAGE=(); VAPT_VERSION=(); VAPT_URL=(); VAPT_PROVIDES=(); VAPT_UNSAFE=(); VAPT_REPOS=()
    while IFS=$'\t' read -r kind repo name version url provides; do
        [[ -n $kind ]] || continue
        case "$kind" in
        repo) VAPT_ENABLED[$repo]=1; VAPT_REPOS+=("$repo") ;;
        database) VAPT_DATABASE[$repo]=1 ;;
        unsafe) VAPT_UNSAFE[$repo]=1 ;;
        # A record whose metadata would break these columns or reach a
        # terminal is not offered; the reason column says which.
        rejected) warn "vapt: $repo: $name" ;;
        package) VAPT_PACKAGE[$repo/$name]=1; VAPT_VERSION[$repo/$name]="$version"; VAPT_URL[$repo/$name]="$url"; VAPT_PROVIDES[$repo/$name]="$provides" ;;
        esac
    done <<<"$output"
    return 0
}
vapt_identity_ok() {
    local logical="$1" target="$2" scheme host path
    # Tool-specific mappings must never exempt a forbidden provider.
    [[ ${target##*/} != omarchy* ]] || return 1
    [[ ${VAPT_ID_SOURCE[$logical]:-} != native && ${VAPT_ID_POLICY[$logical]:-} != blocked ]] || return 1
    if [[ ${VAPT_ID_UPSTREAM[$logical]:-} ]]; then
        [[ ${VAPT_ID_TARGET[$logical]} == '*' || ${VAPT_ID_TARGET[$logical]} == "$target" ]] || return 1
        # Same host, the identity's path or a descendant at a '/' boundary;
        # an http identity also accepts https, never the reverse.
        vapt_url_parse "${VAPT_ID_UPSTREAM[$logical]}" || return 1
        scheme="$VAPT_URL_SCHEME" host="$VAPT_URL_HOST" path="$VAPT_URL_PATH"
        vapt_url_parse "${VAPT_URL[$target]:-}" || return 1
        [[ $VAPT_URL_HOST == "$host" && ( $VAPT_URL_SCHEME == "$scheme" || $VAPT_URL_SCHEME == https ) ]] || return 1
        [[ $VAPT_URL_PATH == "$path" || $VAPT_URL_PATH == "$path"/* ]] || return 1
    fi
    case "$logical" in
    android-tools) [[ $target != blackarch/* || $target == blackarch/android-tools || $target == blackarch/android-sdk-platform-tools ]] ;;
    *) return 0 ;;
    esac
}
vapt_repo_usable() {
    local repo="$1"
    [[ ${VAPT_ENABLED[$repo]:-} && ${VAPT_DATABASE[$repo]:-} && ! ${VAPT_UNSAFE[$repo]:-} && ! ${VAPT_SOURCE_BLOCKED[$repo]:-} ]] || return 1
    case "$repo" in
    blackarch) [[ $(vapt_blackarch_state) == usable ]] ;;
    chaotic-aur) [[ ${VAPT_PACKAGE[chaotic-aur/chaotic-keyring]:-} || ${VAPT_PACKAGE[chaotic-aur/chaotic-mirrorlist]:-} ]] ;;
    # The private source is usable only for an operation that opted in and
    # whose descriptor, database signature and keyring authority verified.
    oniomarchy) [[ $VAPT_ONIOMARCHY_STATE == usable && -n $VAPT_ONIOMARCHY_SCOPE ]] ;;
    *) return 0 ;;
    esac
}
vapt_repo_target() {
    local repo="$1" logical="$2" mapped="${3:-$2}" key token target='' count=0 exact=false
    vapt_repo_usable "$repo" || return 1
    # A reviewed alias names the one concrete package; exact-name policy
    # keeps any provider from substituting for the item.
    if [[ ${VAPT_ALIAS[$logical/$repo]:-} ]]; then mapped="${VAPT_ALIAS[$logical/$repo]}"; exact=true; fi
    [[ ${VAPT_ID_POLICY[$logical]:-} != exact-name ]] || exact=true
    if [[ ${VAPT_PACKAGE[$repo/$mapped]:-} ]] && vapt_identity_ok "$logical" "$repo/$mapped"; then printf '%s\n' "$repo/$mapped"; return 0; fi
    ! $exact || return 1
    local values=()
    for key in "${!VAPT_PACKAGE[@]}"; do
        [[ $key == "$repo/"* ]] || continue
        IFS=, read -r -a values <<<"${VAPT_PROVIDES[$key]:-}"
        for token in "${values[@]}"; do
            token="${token%%[<>=]*}"
            [[ $token == "$mapped" ]] || continue
            if vapt_identity_ok "$logical" "$key"; then target="$key"; count=$((count + 1)); fi
            break
        done
    done
    ((count == 1)) || return 1
    printf '%s\n' "$target"
}
vapt_resolve_item() {
    local logical="$1" target='' repo mapped="${VAPT_NATIVE_BA[$1]:-$1}" attempts='' pin_reason=''
    VAPT_SOURCE[$logical]=none; VAPT_TARGET[$logical]='-'; VAPT_RESOLUTION[$logical]=unavailable; VAPT_APPLIED[$logical]=skipped
    if [[ $logical == pyrit ]]; then
        VAPT_SOURCE[$logical]=native; VAPT_TARGET[$logical]="${VAPT_NATIVE_SPEC[$logical]}"; VAPT_RESOLUTION[$logical]=resolved
        VAPT_REASON[$logical]='Microsoft PyRIT identity override; BlackArch WPA homonym excluded'; VAPT_ATTEMPTS[$logical]=identity-native; return 0
    fi
    if [[ ${VAPT_ID_POLICY[$logical]:-} == blocked ]]; then
        VAPT_REASON[$logical]="identity blocked: ${VAPT_ID_POLICY_REASON[$logical]}"; VAPT_ATTEMPTS[$logical]=identity-blocked; return 0
    fi
    if [[ ${VAPT_PINS[$logical]:-} ]]; then
        target="${VAPT_PINS[$logical]}"; repo="${target%%/*}"
        attempts="pin:$target"
        if vapt_repo_usable "$repo" && [[ ${VAPT_PACKAGE[$target]:-} ]] && vapt_identity_ok "$logical" "$target"; then
            VAPT_SOURCE[$logical]="$repo"; VAPT_TARGET[$logical]="$target"; VAPT_RESOLUTION[$logical]=resolved; VAPT_REASON[$logical]='explicit repository pin'; VAPT_ATTEMPTS[$logical]="$attempts"; return 0
        fi
        pin_reason='pin missing; '
    fi
    attempts+="${attempts:+,}blackarch"
    if target="$(vapt_repo_target blackarch "$logical" "$mapped")"; then repo=blackarch
    elif [[ ${VAPT_NATIVE_SPEC[$logical]:-} ]]; then
        VAPT_SOURCE[$logical]=native; VAPT_TARGET[$logical]="${VAPT_NATIVE_SPEC[$logical]}"; VAPT_RESOLUTION[$logical]=resolved; VAPT_REASON[$logical]="${pin_reason}pinned native fallback"; VAPT_ATTEMPTS[$logical]="$attempts,native"; return 0
    else
        target=''; attempts+=',native,chaotic-aur'
        if target="$(vapt_repo_target chaotic-aur "$logical")"; then repo=chaotic-aur
        else
            for repo in "${VAPT_REPOS[@]}"; do
                [[ $repo == cachyos || $repo == cachyos-* ]] || continue
                attempts+=",$repo"
                target="$(vapt_repo_target "$repo" "$logical")" && break
            done
        fi
        if [[ -z $target ]]; then
            # Exact-name matches throughout the Arch tier precede providers.
            local name
            for repo in core extra multilib; do
                attempts+=",$repo"
                name="${VAPT_ALIAS[$logical/$repo]:-$logical}"
                if vapt_repo_usable "$repo" && [[ ${VAPT_PACKAGE[$repo/$name]:-} ]] && vapt_identity_ok "$logical" "$repo/$name"; then target="$repo/$name"; break; fi
            done
            if [[ -z $target ]]; then
                for repo in core extra multilib; do target="$(vapt_repo_target "$repo" "$logical")" && break; done
            fi
        fi
        if [[ -z $target ]]; then
            local state
            vapt_oniomarchy_target "$logical" || true
            state="$VAPT_ONIO_TIER"
            attempts+=",oniomarchy${state:+:$state}"
            [[ -n $state ]] || target="$VAPT_ONIO_TARGET"
        fi
    fi
    VAPT_ATTEMPTS[$logical]="$attempts"
    if [[ -n $target ]]; then
        VAPT_SOURCE[$logical]="${target%%/*}"; VAPT_TARGET[$logical]="$target"; VAPT_RESOLUTION[$logical]=resolved; VAPT_REASON[$logical]="${pin_reason}concrete allowed repository identity"
        if [[ ${target%%/*} == oniomarchy ]]; then
            VAPT_REASON[$logical]+='; private oniomarchy source (opted in for this operation), exact reviewed mapping; publisher metadata, not independent provenance'
            [[ -z $VAPT_ONIO_UNSEEN ]] ||
                VAPT_REASON[$logical]+="; earlier source unavailable this run ($VAPT_ONIO_UNSEEN); not proof this is the inventory tool"
        fi
    else
        VAPT_REASON[$logical]="${pin_reason}no acceptable source in available metadata; disabled/unavailable sources are not proof of absence"
    fi
    return 0
}
# vapt_oniomarchy_target LOGICAL — the last tier. Only the item's exact name
# or its reviewed alias, only an admitted candidate mapped to this item, never
# Provides, and never a name another configured source also publishes.
# Sets VAPT_ONIO_TARGET, or VAPT_ONIO_TIER to the state recorded in
# attempted_tiers (not-selected, declined, unavailable, ...). On success,
# VAPT_ONIO_UNSEEN lists earlier configured sources this run could not read.
vapt_oniomarchy_target() {
    local logical="$1" package repo
    VAPT_ONIO_TARGET='' VAPT_ONIO_TIER='' VAPT_ONIO_UNSEEN=''
    if [[ $VAPT_ONIOMARCHY_STATE != usable ]]; then
        case "$VAPT_ONIOMARCHY_STATE" in
        not-selected | declined | unsupported-architecture) VAPT_ONIO_TIER="$VAPT_ONIOMARCHY_STATE" ;;
        *) VAPT_ONIO_TIER=unavailable ;;
        esac
        return 1
    fi
    package="${VAPT_ALIAS[$logical/oniomarchy]:-$logical}"
    if ! vapt_repo_usable oniomarchy || [[ ${VAPT_ONIO_ROLE[$package]:-} != candidate || ${VAPT_ONIO_LOGICAL[$package]:-} != "$logical" ||
        ! ${VAPT_PACKAGE[oniomarchy/$package]:-} ]]; then
        VAPT_ONIO_TIER=unavailable; return 1
    fi
    # The homonym rule metadata.py closure applies (earlier_homonym): every
    # other configured repository with readable, safe metadata, usable this
    # run or not, by the package name and by the item's logical name.
    for repo in "${VAPT_REPOS[@]}"; do
        [[ $repo != oniomarchy ]] || continue
        if [[ ${VAPT_DATABASE[$repo]:-} && ! ${VAPT_UNSAFE[$repo]:-} ]]; then
            [[ ! ${VAPT_PACKAGE[$repo/$package]:-} && ! ${VAPT_PACKAGE[$repo/$logical]:-} ]] || { VAPT_ONIO_TIER=identity-rejected; return 1; }
        fi
        vapt_repo_usable "$repo" || VAPT_ONIO_UNSEEN+="${VAPT_ONIO_UNSEEN:+, }$repo"
    done
    vapt_identity_ok "$logical" "oniomarchy/$package" || { VAPT_ONIO_TIER=identity-rejected; VAPT_ONIO_UNSEEN=''; return 1; }
    VAPT_ONIO_TARGET="oniomarchy/$package"
}
vapt_resolve_groups() {
    vapt_collect_groups "$@"
    local logical
    for logical in "${VAPT_ITEMS[@]}"; do vapt_resolve_item "$logical"; done
}
vapt_install_infra() {
    local name repo target rc result=0
    for name in "$@"; do
        [[ $name =~ $PKG_NAME_RE && $name != omarchy* ]] || { result=1; continue; }
        # A cached decision never skips the recovery-record recheck: another
        # user's incomplete reviewed full upgrade blocks native/COAE use too.
        if vapt_upgrade_pending; then
            VAPT_PACMAN_BLOCKED=1 result=1
            continue
        fi
        if [[ ${VAPT_INFRA_DONE[$name]:-} ]]; then
            [[ ${VAPT_INFRA_DONE[$name]} == ok ]] || result=1
            continue
        fi
        target=''
        # Infrastructure is binary-only. Preserve host native repo priority;
        # already-enabled Chaotic is last, never an AUR manager/build path.
        for repo in "${VAPT_REPOS[@]}"; do
            [[ $repo == cachyos || $repo == cachyos-* || $repo == core || $repo == extra || $repo == multilib ]] || continue
            if vapt_repo_usable "$repo" && [[ ${VAPT_PACKAGE[$repo/$name]:-} ]]; then target="$repo/$name"; break; fi
        done
        if [[ -z $target ]] && vapt_repo_usable chaotic-aur && [[ ${VAPT_PACKAGE[chaotic-aur/$name]:-} ]]; then target="chaotic-aur/$name"; fi
        VAPT_INFRA_TARGET[$name]="${target:--}"
        if [[ -z $target || $VAPT_PACMAN_BLOCKED == 1 ]]; then
            VAPT_INFRA_DONE[$name]=unavailable; VAPT_INFRA_REASON[$name]='no usable binary source or full-upgrade block'
            VAPT_INFRA_ROWS+=("$name"$'\t'"${target:--}"$'\t''unavailable'$'\t'"${VAPT_INFRA_REASON[$name]}")
            result=1; continue
        fi
        rc=0; vapt_pacman_apply "$target" || rc=$?
        case "$rc" in
        0) VAPT_INFRA_DONE[$name]=ok; VAPT_INFRA_APPLY[$name]="$VAPT_PACMAN_STATE" ;;
        2) VAPT_INFRA_DONE[$name]=rejected; result=1 ;;
        *) VAPT_INFRA_DONE[$name]=failed; result=1 ;;
        esac
        VAPT_INFRA_REASON[$name]="${VAPT_APPLY_REASON:-}"
        VAPT_INFRA_REASON[$name]="${VAPT_INFRA_REASON[$name]//$'\n'/ }"
        VAPT_INFRA_REASON[$name]="${VAPT_INFRA_REASON[$name]//$'\t'/ }"
        VAPT_INFRA_ROWS+=("$name"$'\t'"$target"$'\t'"${VAPT_INFRA_DONE[$name]}"$'\t'"${VAPT_INFRA_REASON[$name]}")
    done
    return "$result"
}
vapt_report() {
    printf '# haseen-vapt-report-v1\nlogical\tselected_groups\tselected_source\ttarget\tresolution_state\tapply_state\treason\tattempted_tiers\n'
    local logical reason
    for logical in "${VAPT_ITEMS[@]}"; do
        reason="${VAPT_REASON[$logical]}"; reason="${reason//$'\n'/ }"; reason="${reason//$'\t'/ }"
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$logical" "${VAPT_MEMBERSHIP[$logical]}" "${VAPT_SOURCE[$logical]}" "${VAPT_TARGET[$logical]}" "${VAPT_RESOLUTION[$logical]}" "${VAPT_APPLIED[$logical]}" "$reason" "${VAPT_ATTEMPTS[$logical]}"
    done
    printf '# environment\t%s\n# source\t%s\n# mutation-failed\t%s\n' "$VAPT_ENV_STATUS" "${VAPT_SOURCE_REASON:-observed source metadata}" "$VAPT_MUTATION_FAILED"
    # The private source's state for this operation is an annotation: a
    # declined or unselected source alone never degrades a complete run.
    reason="${VAPT_ONIOMARCHY_REASON//$'\n'/ }"
    printf '# oniomarchy\t%s\t%s\n' "$VAPT_ONIOMARCHY_STATE" "${reason//$'\t'/ }"
    for logical in "${VAPT_INFRA_ROWS[@]}"; do printf '# infrastructure\t%s\n' "$logical"; done
    # Dependencies a commit installed: annotations, never launcher roots.
    for logical in "${VAPT_DEPENDENCY_ROWS[@]}"; do printf '# dependency\t%s\n' "$logical"; done
}
# vapt_shell_active — 0 when ~/.bashrc or ~/.zshrc already sources the owned
# link, directly or through the optional shell-rc layer's default/shell/init.sh
# (which loads the same link; that layer may be absent). Read-only: haseen
# seeds only the owned link and never edits a user rc file (plan 087 batch C).
vapt_shell_active() {
    local general="${HASEEN_INSTALL_PATH:-$HASEEN_PATH}/default/shell/init.sh"
    local include="$HASEEN_USER_CONFIG/vapt/shell.sh" rc
    for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
        vapt_meta includes "$rc" "$include" "$general" 2>/dev/null && return 0
    done
    return 1
}
# vapt_shell_line — the exact line a user may add to their rc; inert once the
# owned link is removed.
vapt_shell_line() {
    local include="$HASEEN_USER_CONFIG/vapt/shell.sh"
    printf '[ -r "%s" ] && . "%s"\n' "$include" "$include"
}
vapt_provision() (
    local logical rc=0 output report="$HASEEN_USER_STATE/vapt/report.tsv"
    # Reject unreadable source metadata before even creating the lock tree.
    vapt_snapshot || return 1
    vapt_lifecycle_lock || return 1
    trap 'vapt_transaction_cleanup; vapt_pacman_cleanup' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    vapt_state_path_safe "$report" || { warn 'VAPT report conflict preserved'; return 1; }
    VAPT_COAE_REQUIRED="$(vapt_meta report-requires "$(vapt_read_path "$report")" htb-coae)" || return 1
    for logical in "${VAPT_SELECTED[@]}"; do
        [[ $logical != htb-coae ]] || VAPT_COAE_REQUIRED=1
    done
    vapt_state_repair || { warn "VAPT: $VAPT_APPLY_REASON"; return 1; }
    vapt_state_path_safe "$HASEEN_STATE_DIR/vapt/upgrade-pending" || return 1
    if [[ -e $(vapt_read_path "$HASEEN_STATE_DIR/vapt/upgrade-pending") || -L $(vapt_read_path "$HASEEN_STATE_DIR/vapt/upgrade-pending") ]]; then
        VAPT_PACMAN_BLOCKED=1
        VAPT_SOURCE_REASON='recorded full upgrade remains incomplete; package installs blocked'
        if confirm 'An interrupted VAPT full upgrade is recorded. Review/resume the allowed full upgrade?'; then
            rc=0; vapt_pacman_recover || rc=$?
            if ((rc == 0)); then
                VAPT_PACMAN_BLOCKED=0
                vapt_snapshot || return 1
            else
                local reason="${VAPT_APPLY_REASON:-}"
                VAPT_SOURCE_REASON="recorded full upgrade remains incomplete; recovery refused${reason:+: ${reason//$'\n'/ }}"
            fi
        fi
    fi
    vapt_blackarch_prepare || VAPT_MUTATION_FAILED=1
    # Last: the private source joins only this operation's configuration.
    vapt_oniomarchy_prepare || VAPT_MUTATION_FAILED=1
    vapt_resolve_groups "${VAPT_SELECTED[@]}"
    vapt_install_infra openldap perl-image-exiftool python-pipx || true
    # A partially successful activation must not remain hidden behind a
    # previous removal marker, even if another provisioning item fails.
    vapt_state_clear "$HASEEN_USER_STATE/vapt/removed" || return 1
    rc=0; vapt_environment_apply "${VAPT_SELECTED[@]}" || rc=$?
    if ((rc == 0)); then VAPT_ENV_STATUS=ok
    else
        VAPT_ENV_STATUS=degraded
        ((rc != 1)) || VAPT_MUTATION_FAILED=1
    fi
    [[ ${VAPT_ENV_DEGRADED:-0} == 0 ]] || VAPT_ENV_STATUS=degraded
    if ! vapt_shell_active; then
        info "VAPT shell activation: no ~/.bashrc or ~/.zshrc sources $HASEEN_USER_CONFIG/vapt/shell.sh, and haseen never edits them."
        info "To put the VAPT tool directories on PATH in interactive shells, add this line yourself: $(vapt_shell_line)"
    fi
    for logical in "${VAPT_ITEMS[@]}"; do
        [[ ${VAPT_RESOLUTION[$logical]} == resolved ]] || continue
        rc=0
        if [[ ${VAPT_SOURCE[$logical]} == native ]]; then
            VAPT_APPLY_STATE=skipped; vapt_native_apply "$logical" || rc=$?
            ((rc != 1)) || VAPT_APPLY_STATE=failed
            VAPT_APPLIED[$logical]="$VAPT_APPLY_STATE"
        elif [[ ${VAPT_INFRA_TARGET[$logical]:-} == "${VAPT_TARGET[$logical]}" ]]; then
            VAPT_APPLY_REASON="${VAPT_INFRA_REASON[$logical]:-}"
            case "${VAPT_INFRA_DONE[$logical]}" in
            ok) VAPT_APPLIED[$logical]="${VAPT_INFRA_APPLY[$logical]}" ;;
            failed) VAPT_APPLIED[$logical]=failed; rc=1 ;;
            *) VAPT_APPLIED[$logical]=skipped; rc=2 ;;
            esac
        elif [[ $VAPT_PACMAN_BLOCKED == 1 ]]; then
            VAPT_APPLIED[$logical]=skipped; VAPT_APPLY_REASON='package transaction blocked following incomplete full upgrade'; rc=2
        else
            vapt_pacman_apply "${VAPT_TARGET[$logical]}" || rc=$?
            case "$rc" in
            0) VAPT_APPLIED[$logical]="$VAPT_PACMAN_STATE" ;;
            1) VAPT_APPLIED[$logical]=failed ;;
            *) VAPT_APPLIED[$logical]=skipped ;;
            esac
        fi
        if [[ -n ${VAPT_APPLY_REASON:-} ]]; then VAPT_REASON[$logical]+="; $VAPT_APPLY_REASON"; fi
    done
    vapt_pacman_cleanup || VAPT_MUTATION_FAILED=1
    output="$(vapt_report)"
    output="$(printf '%s\n' "$output" | vapt_meta report-merge "$(vapt_read_path "$report")")" || {
        warn 'VAPT cumulative report cannot be reconciled'; return 1;
    }
    printf '%s\n' "$output"
    printf '%s\n' "$output" | vapt_state_write "$report" || VAPT_MUTATION_FAILED=1
    [[ $VAPT_MUTATION_FAILED == 0 ]]
)
