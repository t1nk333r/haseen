# shellcheck shell=bash disable=SC2034  # AGENT_ACCOUNT_PROVIDERS, PROVIDER and ACCT_ARGS are read by the commands that source this
# agent-accounts.sh — several Claude, Codex and Grok subscriptions on one
# machine (plan 108). Sourced by bin/haseen-agent-account-* and by haseen's
# answers to Omarchy's omarchy-agent-account-* commands; never executed.
#
# Adapted from Omarchy bin/omarchy-agent-account-state@v4.5.0-rc1 (MIT,
# Copyright (c) David Heinemeier Hansson; c05d90196 #13770, f9646299b #14233),
# rewritten in bash and jq:
#
# - The login a CLI already has stays where the CLI put it (~/.claude,
#   ~/.codex, ~/.grok): the primary account, "main". An added account gets a
#   home of its own, $HASEEN_USER_STATE/agents/accounts/<provider>/<id>/,
#   selected by CLAUDE_CONFIG_DIR, CODEX_HOME or GROK_HOME. The CLI's own
#   login writes its credentials into that home; haseen never copies, moves,
#   prints or logs a credential file, and reads only display-safe fields out
#   of one (the account id, email, organisation and plan name).
# - Everything else (history, settings, skills, sessions) is a link back to
#   the primary home, so a session continues across a switch.
# - One registry per provider, <provider>.json beside the homes, in Omarchy's
#   format (active, switch, threshold, alert, accounts). It holds no token.
#   Every change is read-modify-write under a per-provider lock.
# - Homes, registry and lock are private: the commands run under umask 077
#   (directories 0700, files 0600), and a new account's credential files are
#   set to 0600 after its login.
# - Without a haseen registry, Omarchy's (~/.local/state/omarchy/agents/
#   accounts/<provider>.json, same format) is read: accounts added under
#   Omarchy 4.5 keep resolving, and haseen's first change adopts them into
#   its own registry. Omarchy's registry files are never written. An adopted
#   account's home stays where Omarchy made it and is never deleted, but
#   using it lays the shared links in it as for any account (mkdir, chmod
#   700, missing links), and signing it in again lets the CLI write there.
# - A registry that exists but does not parse is never overwritten: every
#   change refuses until it is fixed or moved; list shows the main login.
# - The feature is off until used: with no registry nothing resolves to
#   anything but the primary home, and nothing here signs in by itself (no
#   seed, layer, migration or timer runs a login; only `haseen agent account
#   add` does). A machine or user can refuse sign-ins per provider (below).
# - Not built: switching near a limit (not chosen, plan 146; the Claude
#   collector does read every account's limits) and copying logins to
#   another machine (refused; plan 108).

[[ -n ${HASEEN_AGENT_ACCOUNTS_SH:-} ]] && return 0
HASEEN_AGENT_ACCOUNTS_SH=1

AGENT_ACCOUNT_PROVIDERS=(claude codex grok)
AGENT_ACCOUNTS_DIR="${HASEEN_AGENT_ACCOUNTS_DIR:-$HASEEN_USER_STATE/agents/accounts}"
# Omarchy keeps its registry here; read when haseen has none of its own.
OMARCHY_AGENT_ACCOUNTS_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/agents/accounts"
# Ids an account cannot take: `use next` cycles, a provider name is read as
# the provider when it comes first, and `primary` names the first login
# (Omarchy's list).
AGENT_ACCOUNT_RESERVED=" next add claude codex grok primary "

acct_provider_ok() { [[ $1 == claude || $1 == codex || $1 == grok ]]; }

acct_name() {
    case $1 in
    claude) echo Claude ;;
    codex) echo Codex ;;
    grok) echo Grok ;;
    esac
}

acct_home_env() {
    case $1 in
    claude) echo CLAUDE_CONFIG_DIR ;;
    codex) echo CODEX_HOME ;;
    grok) echo GROK_HOME ;;
    esac
}

# The CLI's own sign-in command, run with the account's home selected.
acct_login_command() {
    case $1 in
    claude) printf '%s\n' claude auth login ;;
    codex) printf '%s\n' codex login ;;
    grok) printf '%s\n' grok login ;;
    esac
}

# The primary home is where the CLI keeps a login when nothing says otherwise.
# It is not read from CLAUDE_CONFIG_DIR and the like: those select an added
# account, so honouring them would make whichever launched this the primary.
acct_primary_home() { printf '%s/.%s\n' "$HOME" "$1"; }

# Files the CLI writes at login: they hold the account's tokens. haseen only
# ever sets their mode.
acct_credential_files() {
    case $1 in
    claude) printf '%s\n' .credentials.json .claude.json ;;
    codex) printf '%s\n' auth.json ;;
    grok) printf '%s\n' auth.json settings_cache.json ;;
    esac
}

# What a session reads or writes that is not tied to the login (Omarchy's
# lists): linked back to the primary home so all accounts share one set.
acct_shared_dirs() {
    case $1 in
    claude) printf '%s\n' projects skills agents commands plugins hooks themes output-styles file-history todos plans ;;
    codex) printf '%s\n' sessions archived_sessions prompts skills rules plugins ;;
    grok) printf '%s\n' sessions skills agents plugins installed-plugins marketplace-cache hooks memory memory-v2 rules \
        commands workflows personas worktrees ;;
    esac
}
acct_shared_files() {
    case $1 in
    claude) printf '%s\n' settings.json CLAUDE.md history.jsonl keybindings.json ;;
    codex) printf '%s\n' config.toml AGENTS.md history.jsonl hooks.json ;;
    grok) printf '%s\n' config.toml settings.json lsp.json pager.toml sandbox.toml trusted_folders.toml statusline.sh worktrees.db ;;
    esac
}

acct_registry() { printf '%s/%s.json\n' "$AGENT_ACCOUNTS_DIR" "$1"; }
# Account ids name directories: a long label gives a short id, so a login
# never fails at the rename after it (NAME_MAX).
AGENT_ACCOUNT_ID_MAX=48
acct_omarchy_registry() { printf '%s/%s.json\n' "$OMARCHY_AGENT_ACCOUNTS_DIR" "$1"; }

# acct_registry_source P — the registry file to read: haseen's, else
# Omarchy's; fails when neither exists.
acct_registry_source() {
    local f
    for f in "$(acct_registry "$1")" "$(acct_omarchy_registry "$1")"; do
        [[ -e $f || -L $f ]] && {
            printf '%s\n' "$f"
            return 0
        }
    done
    return 1
}

# acct_registry_broken P — the registry to read exists but is not one
# haseen can rewrite without losing an account (unreadable, truncated, edited
# by hand): not a JSON object, or its accounts not a list of objects with an
# id. Print it and succeed.
acct_registry_broken() {
    local src
    src="$(acct_registry_source "$1")" || return 1
    jq -e 'type == "object" and ((.accounts // []) | type == "array"
        and all(.[]; type == "object" and (.id | type == "string" and . != "")))' "$src" &>/dev/null && return 1
    printf '%s\n' "$src"
}

# acct_require_registry P — stop a change while the registry does not parse:
# loading it would give the main login alone, and saving that would drop
# every added account.
acct_require_registry() {
    local broken
    broken="$(acct_registry_broken "$1")" || return 0
    die "the $(acct_name "$1") account registry $broken does not parse; haseen will not overwrite it (fix or move it, then try again)"
}

# acct_plan_label TIER SUBSCRIPTION — "Max 20x" from default_claude_max_20x,
# else the subscription name capitalised.
acct_plan_label() {
    if [[ ${1,,} =~ max_([0-9]+x) ]]; then
        printf 'Max %s\n' "${BASH_REMATCH[1]}"
    elif [[ -n ${2:-} ]]; then
        printf '%s\n' "${2^}"
    fi
}

# acct_identity P HOME — who HOME is signed in as, as JSON
# {accountId, email, org, plan}. Read from the files the CLI wrote at login;
# jq selects the display-safe fields inside its own process, so no token ever
# reaches a variable, an argument or the output. An empty accountId means
# nobody is signed in there.
acct_identity() {
    local provider="$1" home="$2" account_file tier="" sub=""
    case $provider in
    claude)
        account_file="$home/.claude.json"
        [[ $home == "$(acct_primary_home claude)" ]] && account_file="$HOME/.claude.json"
        if [[ -r $home/.credentials.json ]]; then
            tier="$(jq -r '(.claudeAiOauth // {}) | .rateLimitTier // "" | tostring' "$home/.credentials.json" 2>/dev/null || true)"
            sub="$(jq -r '(.claudeAiOauth // {}) | .subscriptionType // "" | tostring' "$home/.credentials.json" 2>/dev/null || true)"
        fi
        jq -c --arg plan "$(acct_plan_label "$tier" "$sub")" '
            (if type == "object" then (.oauthAccount // {}) else {} end) as $a
            | {accountId: ($a.accountUuid // "" | tostring), email: ($a.emailAddress // "" | tostring),
               org: ($a.organizationName // "" | tostring), plan: $plan}' "$account_file" 2>/dev/null ||
            jq -nc --arg plan "$(acct_plan_label "$tier" "$sub")" '{accountId: "", email: "", org: "", plan: $plan}'
        ;;
    codex)
        # The email and plan are claims in the id token's payload.
        jq -c '
            def claims: (split(".")[1] // "") | gsub("-"; "+") | gsub("_"; "/")
                | . as $b | ($b + ("===="[0:((4 - ($b | length) % 4) % 4)]))
                | (try (@base64d | fromjson) catch {}) | if type == "object" then . else {} end;
            ((if type == "object" then .tokens else null end) // {}) as $t
            | ($t.id_token // "" | tostring | claims) as $c
            | ($c["https://api.openai.com/auth"] // {}) as $o
            | ($o.chatgpt_plan_type // "" | tostring) as $p
            | {accountId: ($t.account_id // $o.chatgpt_account_id // "" | tostring), email: ($c.email // "" | tostring),
               org: "", plan: (if $p == "" then "" else ($p[0:1] | ascii_upcase) + $p[1:] end)}' \
            "$home/auth.json" 2>/dev/null || echo '{"accountId":"","email":"","org":"","plan":""}'
        ;;
    grok)
        # One login per issuer in auth.json; the plan is cached settings, a
        # JSON string inside settings_cache.json.
        tier="$(jq -r '(.payload // "{}") | (try fromjson catch {}) | .settings.subscription_tier_display // "" | tostring' \
            "$home/settings_cache.json" 2>/dev/null || true)"
        jq -c --arg plan "$tier" '
            ([(if type == "object" then .[] else empty end) | objects] | first // {}) as $l
            | {accountId: ($l.user_id // "" | tostring), email: ($l.email // "" | tostring), org: "", plan: $plan}' \
            "$home/auth.json" 2>/dev/null || jq -nc --arg plan "$tier" '{accountId: "", email: "", org: "", plan: $plan}'
        ;;
    esac
}

# acct_signed_in P HOME — HOME holds a finished login: an identity and, for
# Claude, which writes the two separately, its OAuth credentials.
acct_signed_in() {
    [[ -n $(acct_identity "$1" "$2" | jq -r .accountId) ]] || return 1
    [[ $1 != claude ]] || jq -e 'has("claudeAiOauth")' "$2/.credentials.json" &>/dev/null
}

# acct_account_home P ENTRY_JSON — an entry's home; the primary has none.
acct_account_home() {
    local home
    home="$(jq -r '.home // ""' <<<"$2")"
    [[ -n $home ]] || home="$(acct_primary_home "$1")"
    printf '%s\n' "$home"
}

# acct_load P — the registry as normalized JSON: defaults filled in, the
# primary entry first when missing, an active id that exists. Identity is
# re-read from each home rather than trusted: a login run by hand in a home
# changes who it is.
acct_load() {
    local provider="$1" src raw='{}' primary reg out='[]' entry home
    src="$(acct_registry_source "$provider")" && raw="$(cat "$src" 2>/dev/null || echo '{}')"
    primary="$(jq -c '{id: "main", label: "Main", home: "", primary: true} + .' <<<"$(acct_identity "$provider" "$(acct_primary_home "$provider")")")"
    reg="$(jq -c --argjson primary "$primary" '
        (try (if type == "object" then . else {} end) catch {}) as $d
        | {active: ($d.active // "main" | tostring), switch: ($d.switch // "manual"),
           threshold: ($d.threshold // 95), alert: ($d.alert // "" | tostring),
           accounts: [($d.accounts // [])[]? | select(type == "object" and ((.id // "") | tostring) != "")]}
        | if any(.accounts[]; .primary == true) then . else .accounts = [$primary] + .accounts end
        | .switch = (if .switch == "auto" then "auto" else "manual" end)
        | .threshold = ((.threshold | tonumber? // 95) | floor | if . < 50 then 50 elif . > 100 then 100 else . end)
        | .active as $a | if any(.accounts[]; .id == $a) then . else .active = .accounts[0].id end' \
        <<<"$raw" 2>/dev/null)" || reg="$(jq -c --argjson primary "$primary" \
        -n '{active: "main", switch: "manual", threshold: 95, alert: "", accounts: [$primary]}')"
    while IFS= read -r entry; do
        home="$(acct_account_home "$provider" "$entry")"
        out="$(jq -c --argjson e "$entry" --argjson id "$(acct_identity "$provider" "$home")" '. + [$e + $id]' <<<"$out")"
    done < <(jq -c '.accounts[]' <<<"$reg")
    jq -c --argjson accounts "$out" '.accounts = $accounts' <<<"$reg"
}

# acct_find REG ID — the entry with ID (`primary` names the first login),
# printed as JSON; fails when there is none.
acct_find() {
    jq -ce --arg id "$2" 'first(.accounts[] | select(.id == $id)) //
        (if $id == "primary" then first(.accounts[] | select(.primary == true)) else empty end)' <<<"$1"
}

# acct_lock P — hold the provider's lock for the rest of the process, so the
# panel, a typed command and an Omarchy caller cannot drop each other's edits.
# A dry run creates nothing and takes no lock.
acct_lock() {
    $DRY_RUN && return 0
    run mkdir -p "$AGENT_ACCOUNTS_DIR"
    exec {ACCT_LOCK_FD}>"$AGENT_ACCOUNTS_DIR/.$1.lock"
    flock "$ACCT_LOCK_FD"
}

# acct_save P REG — write the registry atomically, private.
acct_save() {
    local file
    acct_require_registry "$1"
    file="$(acct_registry "$1")"
    run mkdir -p "$AGENT_ACCOUNTS_DIR"
    jq '.' <<<"$2" | replace_user_file "$file"
    run chmod 600 "$file"
}

# acct_slug LABEL — the id a label gives: lowercase words joined by dashes.
acct_slug() {
    local s="${1,,}"
    s="$(sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' <<<"$s")"
    s="${s:0:AGENT_ACCOUNT_ID_MAX}"
    printf '%s\n' "${s%-}"
}

# acct_unique_id P REG LABEL [KEEP_ID] — a free id for LABEL: not reserved,
# not another account's, and not a home left under that name.
acct_unique_id() {
    local provider="$1" reg="$2" base id n=2 taken
    base="$(acct_slug "$3")"
    [[ -n $base ]] || base=account
    id=$base
    while :; do
        taken="$(jq -r --arg id "$id" 'first(.accounts[] | select(.id == $id) | .id) // ""' <<<"$reg")"
        if [[ $AGENT_ACCOUNT_RESERVED != *" $id "* && (-z $taken || $taken == "${4:-}") ]]; then
            if [[ -n ${4:-} || ! -e $AGENT_ACCOUNTS_DIR/$provider/$id ]]; then
                printf '%s\n' "$id"
                return 0
            fi
        fi
        id="$base-$n"
        n=$((n + 1))
    done
}

# acct_link_shared P HOME — link what accounts share back to the primary
# home. Safe to repeat: an existing link or file is left as it is, so nothing
# an account wrote for itself is replaced.
acct_link_shared() {
    local provider="$1" home="$2" primary name
    primary="$(acct_primary_home "$provider")"
    run mkdir -p "$home"
    run chmod 700 "$home"
    while IFS= read -r name; do
        [[ -e $primary/$name ]] || run mkdir -p "$primary/$name"
    done < <(acct_shared_dirs "$provider")
    while IFS= read -r name; do
        [[ -e $home/$name || -L $home/$name ]] && continue
        run ln -s "$primary/$name" "$home/$name"
    done < <(acct_shared_dirs "$provider"; acct_shared_files "$provider")
}

# acct_carry_settings HOME — Claude only: a new account's .claude.json gets
# the primary's MCP servers, folder trust and onboarding choices, so a second
# login does not start over. Keys the account already has are kept.
acct_carry_settings() {
    local home="$1" merged
    [[ -r $HOME/.claude.json ]] || return 0
    merged="$(jq -c --slurpfile p "$HOME/.claude.json" '
        ($p[0] // {}) as $src
        | reduce ("mcpServers", "projects", "theme", "hasCompletedOnboarding", "lastOnboardingVersion", "editorMode") as $k
            (if type == "object" then . else {} end;
             if ($src | has($k)) and (has($k) | not) then .[$k] = $src[$k] else . end)' \
        "$home/.claude.json" 2>/dev/null)" || return 0
    jq '.' <<<"$merged" | replace_user_file "$home/.claude.json"
}

# acct_private_credentials P HOME — the login's files are this user's alone.
acct_private_credentials() {
    local name
    while IFS= read -r name; do
        [[ -f $2/$name && ! -L $2/$name ]] || continue
        run chmod 600 "$2/$name"
    done < <(acct_credential_files "$1")
}

# acct_home_in_use P HOME — a running session was started in HOME (its
# environment selects it). Removing the home would pull the login out from
# under that session. Only this user's processes are readable.
acct_home_in_use() {
    local want env_name real f entry
    env_name="$(acct_home_env "$1")"
    real="$(readlink -m -- "$2")"
    for f in "$(sysroot_path /proc)"/[0-9]*/environ; do
        [[ -O ${f%/environ} && -r $f ]] || continue
        while IFS= read -r -d '' entry; do
            [[ $entry == "$env_name="* ]] || continue
            want="${entry#"$env_name="}"
            [[ $(readlink -m -- "$want") == "$real" ]] && return 0
        done 2>/dev/null <"$f" || true
    done
    return 1
}

# acct_login_refused P — a sign-in for P is refused here, and why. P or `all`
# is listed in $HASEEN_USER_CONFIG/agents/login-refused or, for every user
# and service on the machine, /etc/haseen/agents/login-refused: ASCII names
# in any case, separated by commas or white space, `#` starting a comment, a
# leading UTF-8 byte-order mark ignored. haseen never writes either file: an
# owner whose policy forbids an official sign-in on a host creates it, and
# `add` then stops before any login starts.
#
# It fails closed, refusing every provider, when a file cannot be judged:
# one is there but is not a readable regular file, is over 64 KiB, holds a
# NUL byte (UTF-16, binary), or has an entry other than claude, codex, grok
# or all (a typo, a lookalike, other punctuation); and when a directory on
# its path exists but cannot be entered, so whether the file is there is
# unknown (review rounds 1 and 2).
acct_login_refused() {
    local LC_ALL=C f dir parent size content line token
    local -a tokens
    for f in "$HASEEN_USER_CONFIG/agents/login-refused" "$(sysroot_path /etc/haseen/agents/login-refused)"; do
        if [[ ! -e $f && ! -L $f ]]; then
            # The nearest directory that exists: one that cannot be entered
            # may hide the file. A path may be relative (a caller's
            # HASEEN_USER_CONFIG, HASEEN_SYSROOT or XDG_CONFIG_HOME): its
            # last component has no parent to strip, so the walk ends at the
            # working directory, and an absolute one at / (review round 3).
            dir="${f%/*}"
            while [[ ! -e $dir ]]; do
                parent="${dir%/*}"
                [[ -n $parent ]] || parent=/
                if [[ $parent == "$dir" ]]; then
                    dir=.
                    break
                fi
                dir=$parent
            done
            if [[ -d $dir && ! -x $dir ]]; then
                printf '%s cannot be read (%s cannot be entered)\n' "$f" "$dir"
                return 0
            fi
            continue
        fi
        if [[ ! -f $f || ! -r $f ]] || ! size="$(stat -L -c %s -- "$f" 2>/dev/null)"; then
            printf '%s cannot be read\n' "$f"
            return 0
        fi
        if ((size > 65536)); then
            printf '%s cannot be read (over 64 KiB)\n' "$f"
            return 0
        fi
        if [[ $(tr -d '\000' <"$f" 2>/dev/null | wc -c) != "$size" ]] || ! content="$(cat -- "$f" 2>/dev/null)"; then
            printf '%s cannot be read (not plain text)\n' "$f"
            return 0
        fi
        content="${content#$'\xef\xbb\xbf'}"
        # Every entry is understood before any is matched.
        while IFS= read -r line || [[ -n $line ]]; do
            line="${line%%#*}"
            # Any white space, a carriage return included, or a comma.
            IFS=$' \t\r\v\f,' read -ra tokens <<<"$line"
            for token in "${tokens[@]}"; do
                case ${token,,} in
                claude | codex | grok | all) ;;
                *)
                    printf '%s has an entry it does not understand: %q\n' "$f" "$token"
                    return 0
                    ;;
                esac
            done
        done <<<"$content"
        while IFS= read -r line || [[ -n $line ]]; do
            line="${line%%#*}"
            IFS=$' \t\r\v\f,' read -ra tokens <<<"$line"
            for token in "${tokens[@]}"; do
                if [[ ${token,,} == "$1" || ${token,,} == all ]]; then
                    printf '%s lists it\n' "$f"
                    return 0
                fi
            done
        done <<<"$content"
    done
    return 1
}

# acct_default_provider — the default coding agent when it has accounts.
acct_default_provider() {
    local agent
    agent="$("$HASEEN_PATH/../../bin/haseen-setup-default" agent 2>/dev/null || true)"
    acct_provider_ok "$agent" && printf '%s\n' "$agent"
}

# acct_parse_provider ARGS... — PROVIDER from the first argument when it
# names one, else the default agent when it has accounts (`haseen agent
# account use work`); the remaining arguments in ACCT_ARGS. Fails when
# neither names a provider.
acct_parse_provider() {
    if acct_provider_ok "${1:-}"; then
        PROVIDER=$1
        ACCT_ARGS=("${@:2}")
        return 0
    fi
    ACCT_ARGS=("$@")
    PROVIDER="$(acct_default_provider)" && [[ -n $PROVIDER ]]
}

# acct_summary P REG — what list prints for P, as JSON: display fields only.
acct_summary() {
    jq -c --arg p "$1" --arg name "$(acct_name "$1")" --arg primary "$(acct_primary_home "$1")" '
        {provider: $p, name: $name, active, switch, threshold,
         accounts: [.active as $a | .accounts[] | {id, label: (.label // .id), email: (.email // ""),
             org: (.org // ""), plan: (.plan // ""), primary: (.primary == true),
             home: (if (.home // "") == "" then $primary else .home end),
             active: (.id == $a), signedIn: ((.accountId // "") != "")}]}' <<<"$2"
}

# acct_active_home P — the active account's home, nothing for the primary.
# Without a registry no jq starts: this runs on every agent launch.
acct_active_home() {
    local src
    src="$(acct_registry_source "$1")" || return 0
    jq -r '(try (if type == "object" then . else {} end) catch {}) as $d
        | ($d.active // "main") as $a
        | first(($d.accounts // [])[]? | objects | select(.id == $a)) // {}
        | if .primary == true then "" else (.home // "") end' "$src" 2>/dev/null || true
}

# acct_active_label P — {id, label} of the active account as JSON, read from
# the registry without opening any home; fails without a registry.
acct_active_label() {
    local src
    src="$(acct_registry_source "$1")" || return 1
    jq -ce '(try (if type == "object" then . else {} end) catch {}) as $d
        | ($d.active // "main") as $a
        | (first(($d.accounts // [])[]? | objects | select(.id == $a)) // {id: "main", label: "Main"})
        | {id: (.id | tostring), label: (.label // .id | tostring)}' "$src" 2>/dev/null
}

# The user timer that keeps every Claude account's limits fresh for the
# agents panel (plan 146): `haseen agent account usage --timer` every 15
# minutes, enabled while Claude has two or more accounts. Only Claude's
# collector reads every account's limits.
AGENT_USAGE_TIMER=haseen-agent-usage.timer

# acct_usage_timer_on — the timer is enabled (`systemctl --user enable` links
# it into timers.target.wants). Read from the file system, so an account
# change that leaves it as it is starts no systemctl.
acct_usage_timer_on() {
    [[ -L ${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/timers.target.wants/$AGENT_USAGE_TIMER ]]
}

# acct_usage_timer_sync P REG — after a change to P's accounts, REG being the
# registry as saved: enable and start the timer once Claude has two or more,
# disable and stop it when one is left. Without a user manager (a console, a
# container) the accounts still change; this only warns.
acct_usage_timer_sync() {
    [[ $1 == claude ]] || return 0
    if (($(jq '.accounts | length' <<<"$2") >= 2)); then
        acct_usage_timer_on && return 0
        run systemctl --user enable --now "$AGENT_USAGE_TIMER" ||
            warn "could not start $AGENT_USAGE_TIMER; the agents panel shows each Claude account's limits once it runs (systemctl --user enable --now $AGENT_USAGE_TIMER)"
    else
        acct_usage_timer_on || return 0
        run systemctl --user disable --now "$AGENT_USAGE_TIMER" ||
            warn "could not stop $AGENT_USAGE_TIMER (systemctl --user disable --now $AGENT_USAGE_TIMER)"
    fi
    return 0
}

# acct_unlock — let the provider's lock go before a long wait (a browser
# login), so the panel and a typed command are not blocked by it.
acct_unlock() {
    [[ -n ${ACCT_LOCK_FD:-} ]] || return 0
    exec {ACCT_LOCK_FD}>&-
    ACCT_LOCK_FD=""
}

# A login in progress keeps a receipt in its home (plan 146, from Omarchy's
# LOGIN_RECEIPT, 64ec3839a #15399): the pid and start time of the `add` that
# owns it, the label it was given and, once it is about to be registered, its
# registry entry. Display fields only, never a credential. It lets a finished
# login survive the `add` dying before it was registered.
AGENT_LOGIN_RECEIPT=.haseen-login.json

# acct_process_fields PID — /proc/PID/stat from its state (field 3) on,
# nothing when it cannot be read. The command name before it may hold spaces
# and parentheses.
acct_process_fields() {
    local stat
    stat="$(cat -- "$(sysroot_path /proc)/$1/stat" 2>/dev/null)" || return 0
    printf '%s\n' "${stat##*") "}"
}

# acct_process_start PID — the process's start time (field 22, in clock
# ticks), nothing when it is gone. A zombie has exited: nothing reaps one
# reparented to a PID 1 that never waits (a container's).
acct_process_start() {
    local -a fields
    read -ra fields <<<"$(acct_process_fields "$1")"
    [[ ${fields[0]:-} != Z ]] || return 0
    printf '%s\n' "${fields[19]:-}"
}

# acct_receipt_write HOME LABEL [ENTRY_JSON] — HOME is this process's login.
acct_receipt_write() {
    jq -nc --arg label "$2" --argjson owner "$$" --arg started "$(acct_process_start "$$")" \
        --argjson entry "${3:-null}" '{label: $label, owner: $owner, started: $started}
        + (if $entry == null then {} else {entry: $entry} end)' |
        replace_user_file "$1/$AGENT_LOGIN_RECEIPT"
}

# acct_receipt_orphaned HOME P — HOME has a receipt whose `add` has exited,
# and no session runs in it: nothing is still writing there. A home without a
# receipt is never orphaned (an older add may still own it). A receipt written
# without a start time (an unreadable /proc) is owned while its pid lives.
acct_receipt_orphaned() {
    local receipt="$1/$AGENT_LOGIN_RECEIPT" owner started
    local -a fields
    [[ -f $receipt && ! -L $receipt ]] || return 1
    owner="$(jq -r '.owner // "" | tostring' "$receipt" 2>/dev/null)" || return 1
    started="$(jq -r '.started // "" | tostring' "$receipt" 2>/dev/null)" || return 1
    if [[ $owner =~ ^[0-9]+$ ]]; then
        if [[ -n $started ]]; then
            [[ $(acct_process_start "$owner") == "$started" ]] && return 1
        elif [[ -e $(sysroot_path /proc)/$owner ]]; then
            read -ra fields <<<"$(acct_process_fields "$owner")"
            [[ ${fields[0]:-} == Z ]] || return 1
        fi
    fi
    ! acct_home_in_use "$2" "$1"
}

# acct_recover P — register what an `add` that died left behind (Omarchy's
# recover), with the provider's lock held by the caller. In
# <provider>/.pending: an orphaned home with a finished login becomes an
# account, or is deleted when that login is already here; one without a
# finished login is deleted. Beside the homes: an orphaned home whose receipt
# holds the entry it was moved there with, but which the registry lacks (the
# add died between the move and the save), is registered with that entry.
# Each account it added, as JSON, is appended to ACCT_RECOVERED.
acct_recover() {
    local provider="$1" root home receipt reg found label id target entry
    ACCT_RECOVERED=()
    root="$AGENT_ACCOUNTS_DIR/$provider"
    for home in "$root/.pending"/login-*; do
        [[ -d $home && ! -L $home ]] && acct_receipt_orphaned "$home" "$provider" || continue
        receipt="$home/$AGENT_LOGIN_RECEIPT"
        if ! acct_signed_in "$provider" "$home"; then
            run rm -rf -- "$home"
            continue
        fi
        reg="$(acct_load "$provider")"
        found="$(acct_identity "$provider" "$home")"
        if jq -e --arg id "$(jq -r .accountId <<<"$found")" 'any(.accounts[]; (.accountId // "") == $id)' <<<"$reg" >/dev/null; then
            run rm -rf -- "$home"
            continue
        fi
        label="$(jq -r '.label // "" | tostring' "$receipt" 2>/dev/null || true)"
        [[ -n $label ]] || label="$(jq -r '.email | split("@")[0]' <<<"$found")"
        [[ -n $label ]] || label=Account
        id="$(acct_unique_id "$provider" "$reg" "$label")"
        target="$root/$id"
        [[ $provider == claude ]] && acct_carry_settings "$home"
        acct_private_credentials "$provider" "$home"
        entry="$(jq -c --arg id "$id" --arg label "$label" --arg home "$target" \
            '{id: $id, label: $label, home: $home, primary: false} + .' <<<"$found")"
        run mv -T -- "$home" "$target"
        acct_save "$provider" "$(jq -c --argjson e "$entry" '.accounts += [$e]' <<<"$reg")"
        run rm -f -- "$target/$AGENT_LOGIN_RECEIPT"
        ACCT_RECOVERED+=("$entry")
    done
    for home in "$root"/*/; do
        home="${home%/}"
        [[ -d $home && ! -L $home && ${home##*/} != .pending ]] || continue
        acct_receipt_orphaned "$home" "$provider" || continue
        receipt="$home/$AGENT_LOGIN_RECEIPT"
        reg="$(acct_load "$provider")"
        entry="$(jq -c '.entry // empty | objects' "$receipt" 2>/dev/null || true)"
        # A committed account (renamed since, maybe) needs only its receipt gone.
        if jq -e --arg home "$home" 'any(.accounts[]; (.home // "") == $home)' <<<"$reg" >/dev/null; then
            run rm -f -- "$receipt"
            continue
        fi
        [[ -n $entry && $(jq -r '.home // ""' <<<"$entry") == "$home" && $(jq -r '.id // ""' <<<"$entry") == "${home##*/}" ]] ||
            continue
        acct_signed_in "$provider" "$home" || continue
        found="$(acct_identity "$provider" "$home")"
        # Registered under another home by a retry: this copy goes.
        if jq -e --arg id "$(jq -r .accountId <<<"$found")" 'any(.accounts[]; (.accountId // "") == $id)' <<<"$reg" >/dev/null; then
            run rm -rf -- "$home"
            continue
        fi
        id="$(jq -r .id <<<"$entry")"
        jq -e --arg id "$id" 'any(.accounts[]; .id == $id)' <<<"$reg" >/dev/null &&
            id="$(acct_unique_id "$provider" "$reg" "$(jq -r '.label // .id' <<<"$entry")")"
        entry="$(jq -c --arg id "$id" --argjson found "$found" '.id = $id | . + $found' <<<"$entry")"
        acct_save "$provider" "$(jq -c --argjson e "$entry" '.accounts += [$e]' <<<"$reg")"
        run rm -f -- "$receipt"
        ACCT_RECOVERED+=("$entry")
    done
}
