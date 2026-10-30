# shellcheck shell=bash
# haseen:covers bin/haseen-agent-account-* share/haseen/lib/agent-accounts.sh
# haseen:covers share/haseen/omarchy/bin/omarchy-agent-account-* share/haseen/omarchy/commands.tsv
# haseen:covers share/haseen/omarchy/bin/omarchy-{agent,default-agent,agent-usage-update}
# haseen:covers bin/haseen-setup-default share/haseen/default/menu.jsonc
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# Several Claude, Codex and Grok accounts (plan 108): haseen agent account
# add, list, use, rename, remove, home and exec, the omarchy-agent-account-*
# answers on top, the account a launch and a usage record use, and Omarchy
# 4.5's agent names. The agent CLIs are fakes whose "login" writes obviously
# fake files; no real token, host or account appears here, and nothing
# reaches a network.

OMA="$HASEEN_PATH/omarchy/bin"
# Marks every fake credential: no command may ever print it.
FAKE_TOKEN="fake-token-not-a-secret"
unset GROK_HOME OMARCHY_AGENT_CLAUDE_HOME OMARCHY_AGENT_CODEX_HOME OMARCHY_AGENT_GROK_HOME

# acct NAME — a sandbox with fake claude, codex and grok CLIs. `<cli> login`
# (claude: `auth login`) writes a login for FAKE_ACCOUNT/FAKE_USER into the
# home the CLI was pointed at, or nothing when FAKE_LOGIN=fail; every call is
# logged with that home and BROWSER. Other calls print the home they run in.
acct() {
    sandbox "$1"
    LOG="$SANDBOX/calls"
    : >"$LOG"
    STATE="$HOME/.local/state/haseen/agents/accounts"
    # A user manager stand-in (plan 146's limits timer): it records every call
    # and links the timer into timers.target.wants as `enable` does, so the
    # next change sees it enabled.
    SYSTEMCTL_LOG="$SANDBOX/systemctl.log"
    : >"$SYSTEMCTL_LOG"
    local wants="$XDG_CONFIG_HOME/systemd/user/timers.target.wants"
    stub systemctl "echo \"systemctl \$*\" >>\"$SYSTEMCTL_LOG\"
case \" \$* \" in
*' enable --now '*) mkdir -p \"$wants\" && ln -sf /dev/null \"$wants/haseen-agent-usage.timer\" ;;
*' disable --now '*) rm -f \"$wants/haseen-agent-usage.timer\" ;;
esac"
    local cli
    for cli in claude codex grok; do
        cat >"$SANDBOX/stubs/$cli" <<EOF
#!/usr/bin/env bash
cli=$cli
log=$LOG
token=$FAKE_TOKEN
EOF
        cat >>"$SANDBOX/stubs/$cli" <<'EOF'
case $cli in
claude) home="${CLAUDE_CONFIG_DIR:-$HOME/.claude}" ;;
codex) home="${CODEX_HOME:-$HOME/.codex}" ;;
grok) home="${GROK_HOME:-$HOME/.grok}" ;;
esac
if [[ "$*" == "auth login" || "$*" == login ]]; then
    echo "$cli login home=$home browser=${BROWSER:-none}" >>"$log"
    [[ ${FAKE_LOGIN:-ok} == ok ]] || exit 0
    mkdir -p "$home"
    acct="${FAKE_ACCOUNT:-uuid-main}" user="${FAKE_USER:-main}"
    case $cli in
    claude)
        printf '{"claudeAiOauth":{"accessToken":"%s","refreshToken":"%s","expiresAt":1,"rateLimitTier":"default_claude_max_20x","subscriptionType":"max"}}\n' \
            "$token" "$token" >"$home/.credentials.json"
        account_file="$home/.claude.json"
        [[ $home == "$HOME/.claude" ]] && account_file="$HOME/.claude.json"
        printf '{"oauthAccount":{"accountUuid":"%s","emailAddress":"%s@example.com","organizationName":"Example"}}\n' \
            "$acct" "$user" >"$account_file"
        ;;
    codex)
        payload="$(printf '{"email":"%s@example.com","https://api.openai.com/auth":{"chatgpt_plan_type":"plus"}}' "$user" |
            base64 -w0 | tr '+/' '-_' | tr -d '=')"
        printf '{"tokens":{"id_token":"x.%s.y","access_token":"%s","refresh_token":"%s","account_id":"%s"}}\n' \
            "$payload" "$token" "$token" "$acct" >"$home/auth.json"
        ;;
    grok)
        printf '{"https://auth.example.com":{"user_id":"%s","email":"%s@example.com","access_token":"%s"}}\n' \
            "$acct" "$user" "$token" >"$home/auth.json"
        printf '{"payload":"{\\"settings\\":{\\"subscription_tier_display\\":\\"SuperGrok\\"}}"}\n' >"$home/settings_cache.json"
        ;;
    esac
    exit 0
fi
echo "$cli home=$home $*"
EOF
        chmod +x "$SANDBOX/stubs/$cli"
    done
}
logins() { cat "$LOG"; }
timer_calls() { cat "$SYSTEMCTL_LOG"; }
# never_printed LABEL TEXT — no fake credential appears in TEXT.
never_printed() { assert_not_contains "$1 prints no credential" "$2" "$FAKE_TOKEN"; }

# --- nothing set up: nothing changes ------------------------------------------
acct accounts-none
capture haseen agent account list
assert_status "list without accounts succeeds" 0 "$STATUS"
assert_contains "and says nobody is signed in" "$OUTPUT" "No Claude, Codex or Grok account is signed in here."
assert_eq "home prints nothing" "" "$(haseen agent account home claude)"
assert_eq "a run uses the CLI's own home" "claude home=$HOME/.claude --version" "$(haseen agent account exec claude --version)"
assert_eq "reading creates no state" "no" "$([[ -e $HOME/.local/state/haseen ]] && echo yes || echo no)"
capture haseen agent account add --check
assert_eq "--check: every first sign-in is still to come" "claude first
codex first
grok first" "$OUTPUT"
capture haseen agent account use claude next --dry-run
assert_contains "use without a provider's accounts stays on main" "$OUTPUT" "already use Main"

# --- the first sign-in goes to the CLI's own home -----------------------------
acct accounts-claude
capture haseen agent account add claude
assert_status "the first Claude sign-in succeeds" 0 "$STATUS"
assert_contains "it is the main account" "$OUTPUT" "This login is your main Claude account."
assert_eq "the CLI's own login ran in its own home, through the normal browser" \
    "claude login home=$HOME/.claude browser=none" "$(logins)"
assert_eq "a first sign-in writes no registry" "no" "$([[ -e $STATE/claude.json ]] && echo yes || echo no)"
assert_eq "--check sees it" "claude additional" "$(haseen agent account add --check | head -n1)"

# --- a second account gets a private home -------------------------------------
: >"$LOG"
capture env FAKE_ACCOUNT=uuid-work FAKE_USER=work haseen agent account add claude "Day Job" </dev/null
assert_status "adding a second account succeeds" 0 "$STATUS"
assert_contains "it is named" "$OUTPUT" "Added Day Job (work@example.com)."
assert_contains "and says how to switch" "$OUTPUT" "haseen agent account use claude day-job"
never_printed "add" "$OUTPUT"
WORK="$STATE/claude/day-job"
assert_contains "the login ran in the new home" "$(logins)" "claude login home=$STATE/claude/.pending/login-"
assert_contains "through a private-window browser" "$(logins)" "browser=$XDG_RUNTIME_DIR/haseen-account-browser."
assert_eq "the browser wrapper is gone afterwards" "" "$(find "$XDG_RUNTIME_DIR" -name 'haseen-account-browser.*')"
assert_eq "the pending home became the account's" "" "$(find "$STATE/claude/.pending" -mindepth 1)"
assert_eq "the home is private" "700" "$(stat -c %a "$WORK")"
assert_eq "its credentials are this user's alone" "600 600" \
    "$(stat -c %a "$WORK/.credentials.json" "$WORK/.claude.json" | tr '\n' ' ' | sed 's/ $//')"
assert_eq "the registry is private" "600" "$(stat -c %a "$STATE/claude.json")"
assert_eq "the accounts directory is private" "700" "$(stat -c %a "$STATE")"
assert_eq "history and settings are links to the main home" "$HOME/.claude/projects $HOME/.claude/settings.json" \
    "$(readlink "$WORK/projects") $(readlink "$WORK/settings.json")"
assert_eq "the registry holds no token" "" "$(grep -l "$FAKE_TOKEN\|accessToken\|refreshToken" "$STATE/claude.json" || true)"
assert_eq "it records the account by display fields" "day-job|Day Job|uuid-work|work@example.com|Max 20x" \
    "$(jq -r '.accounts[] | select(.id == "day-job") | [.id, .label, .accountId, .email, .plan] | join("|")' "$STATE/claude.json")"
capture haseen agent account list claude
assert_contains "list marks the active account" "$OUTPUT" "*  main"
assert_contains "and shows the added one" "$OUTPUT" "day-job  Day Job  Max 20x  work@example.com"
never_printed "list" "$OUTPUT"
capture haseen agent account list --json
assert_eq "--json has display fields only" "active,email,home,id,label,org,plan,primary,signedIn" \
    "$(jq -r '[.[0].accounts[0] | keys[]] | join(",")' <<<"$OUTPUT")"
never_printed "list --json" "$OUTPUT"

# Signing in as an account that is already here adds nothing.
: >"$LOG"
capture env FAKE_ACCOUNT=uuid-work FAKE_USER=work haseen agent account add claude Again </dev/null
assert_status "the same login twice is refused" 1 "$STATUS"
assert_contains "naming the account it already is" "$OUTPUT" "that is Day Job (work@example.com), already here"
assert_eq "and leaves no home behind" "" "$(find "$STATE/claude/.pending" -mindepth 1)"
capture env FAKE_LOGIN=fail haseen agent account add claude Gone </dev/null
assert_status "a login that did not finish is refused" 1 "$STATUS"
assert_contains "and says no account was added" "$OUTPUT" "no account was added"
assert_eq "no half-made home stays" "" "$(find "$STATE/claude/.pending" -mindepth 1)"
assert_eq "the registry still has two accounts" "2" "$(jq '.accounts | length' "$STATE/claude.json")"

# --- switching ----------------------------------------------------------------
capture haseen agent account use claude day-job
assert_contains "use switches new sessions" "$OUTPUT" "New Claude sessions now use Day Job (Max 20x). Running sessions stay on Main."
assert_contains "and says where a plain CLI follows it" "$OUTPUT" \
    "The agent key, the menu, haseen agent account exec and plain claude in a haseen shell follow it; elsewhere (a script, a GUI launch) use haseen agent account exec."
assert_eq "home names the active account's" "$WORK" "$(haseen agent account home claude)"
assert_eq "a run selects it" "claude home=$WORK -p" "$(haseen agent account exec claude -p)"
assert_eq "Omarchy's exec name selects it too" "claude home=$WORK -p" "$("$OMA/omarchy-agent-account-exec" claude -p)"
assert_eq "an explicit home still wins" "claude home=/srv/x -p" "$(CLAUDE_CONFIG_DIR=/srv/x haseen agent account exec claude -p)"
assert_eq "a session's pin wins" "" "$(OMARCHY_AGENT_CLAUDE_HOME='' haseen agent account home claude)"
capture haseen agent account use claude day-job
assert_contains "using the active account again changes nothing" "$OUTPUT" "already use Day Job"
haseen agent account use claude next >/dev/null
assert_eq "next cycles back to main" "" "$(haseen agent account home claude)"
capture haseen agent account use claude nobody
assert_status "an unknown account fails" 1 "$STATUS"
assert_contains "and says where to look" "$OUTPUT" "haseen agent account list claude"
before="$(cat "$STATE/claude.json")"
capture haseen agent account use claude day-job --dry-run
assert_contains "a dry switch prints the write" "$OUTPUT" "DRYRUN: write $STATE/claude.json"
assert_eq "and writes nothing" "$before" "$(cat "$STATE/claude.json")"
# The default agent stands in for the provider.
capture env HASEEN_AGENT=claude haseen agent account use day-job --dry-run
assert_contains "the provider can be left out for the default agent" "$OUTPUT" "DRYRUN: write $STATE/claude.json"
capture env HASEEN_AGENT=pi haseen agent account use day-job
assert_status "a default agent without accounts names no provider" 2 "$STATUS"

# --- rename and remove ----------------------------------------------------------
haseen agent account use claude day-job >/dev/null
capture haseen agent account rename claude day-job Client Work
assert_contains "rename names the new id" "$OUTPUT" "haseen agent account use claude client-work"
assert_eq "the active account follows the rename" "client-work" "$(jq -r .active "$STATE/claude.json")"
assert_eq "its home stays where it is" "$WORK" "$(haseen agent account home claude)"
capture haseen agent account rename claude main Next
assert_contains "a reserved id is never taken" "$(jq -r '.accounts[0].id' "$STATE/claude.json")" "next-2"
haseen agent account rename claude next-2 Main >/dev/null
capture haseen agent account remove claude main --yes
assert_status "the main login is never removed" 1 "$STATUS"
assert_contains "and the CLI's logout is named" "$OUTPUT" "the CLI's own logout does"
# A running session in the home: its environment, in a fixture /proc.
export HASEEN_SYSROOT="$SANDBOX/root"
mkdir -p "$HASEEN_SYSROOT/proc/4242"
printf 'PATH=/usr/bin\0CLAUDE_CONFIG_DIR=%s\0' "$WORK" >"$HASEEN_SYSROOT/proc/4242/environ"
capture haseen agent account remove claude client-work --yes
assert_status "a home a session uses is not removed" 1 "$STATUS"
assert_contains "and says so" "$OUTPUT" "a running Claude session uses Client Work"
rm -rf "$HASEEN_SYSROOT/proc/4242"
capture haseen agent account remove claude client-work --dry-run
assert_contains "a dry removal prints the delete" "$OUTPUT" "DRYRUN: rm -rf -- $WORK"
assert_eq "and deletes nothing" "yes" "$([[ -d $WORK ]] && echo yes || echo no)"
capture haseen agent account remove claude client-work </dev/null
assert_status "without a yes nothing is removed" 1 "$STATUS"
capture haseen agent account remove claude client-work --yes
assert_status "remove succeeds" 0 "$STATUS"
assert_eq "the home is gone" "no" "$([[ -e $WORK ]] && echo yes || echo no)"
assert_eq "its links' targets stay" "yes" "$([[ -d $HOME/.claude/projects ]] && echo yes || echo no)"
assert_eq "the main login stays" "yes" "$([[ -f $HOME/.claude/.credentials.json ]] && echo yes || echo no)"
assert_eq "the active account falls back to main" "main" "$(jq -r .active "$STATE/claude.json")"
assert_eq "and the logout never ran" "" "$(grep -v ' login ' "$LOG" || true)"
unset HASEEN_SYSROOT

# --- a host's policy refuses a sign-in before anything starts -----------------
acct accounts-policy
mkdir -p "$HOME/.config/haseen/agents"
printf '# no official sign-in here\nclaude\n' >"$HOME/.config/haseen/agents/login-refused"
capture haseen agent account add claude
assert_status "a refused provider is refused" 1 "$STATUS"
assert_contains "naming the file that refuses it" "$OUTPUT" "$HOME/.config/haseen/agents/login-refused lists it"
assert_eq "the CLI's login never ran" "" "$(logins)"
capture haseen agent account add --reauth main claude
assert_status "so is signing in again" 1 "$STATUS"
assert_eq "still no login" "" "$(logins)"
haseen agent account add codex >/dev/null
assert_contains "another provider still signs in" "$(logins)" "codex login"
rm "$HOME/.config/haseen/agents/login-refused"
export HASEEN_SYSROOT="$SANDBOX/root"
mkdir -p "$HASEEN_SYSROOT/etc/haseen/agents"
echo all >"$HASEEN_SYSROOT/etc/haseen/agents/login-refused"
: >"$LOG"
capture haseen agent account add grok
assert_status "the machine's file refuses every provider with all" 1 "$STATUS"
assert_contains "and is named" "$OUTPUT" "/etc/haseen/agents/login-refused lists it"
assert_eq "no login ran" "" "$(logins)"
unset HASEEN_SYSROOT

# The file fails closed: any case, commas or white space between names, a
# carriage return, comments; a file that is there but cannot be read refuses.
REFUSED="$HOME/.config/haseen/agents/login-refused"
refused_case() { # LABEL CONTENT — CONTENT (printf format) refuses Claude
    printf "$2" >"$REFUSED"
    : >"$LOG"
    capture haseen agent account add claude
    assert_status "refused: $1" 1 "$STATUS"
    assert_contains "refused: $1, naming the file" "$OUTPUT" "$REFUSED lists it"
    assert_eq "refused: $1, before any login" "" "$(logins)"
}
refused_case "padded upper case" '  CLAUDE  \n'
refused_case "capitalised" 'Claude\n'
refused_case "two names on a line" 'claude codex\n'
refused_case "a comma list" 'claude, codex\n'
refused_case "a comma without a space" 'codex,claude\n'
refused_case "a tab and a carriage return" 'codex\tclaude\r\n'
refused_case "after a comment line and a blank line" '# managed by hand\n\n  grok  # not this one\nclaude # this one\n'
refused_case "ALL" 'ALL\n'
refused_case "no final newline" 'claude'
printf '# claude\ngrok # claude\n\n' >"$REFUSED"
: >"$LOG"
capture haseen agent account add claude
assert_status "a name only in comments refuses nothing" 0 "$STATUS"
assert_contains "and the login runs" "$(logins)" "claude login"
rm -rf "$HOME/.claude" "$HOME/.claude.json"
unreadable_case() { # LABEL — REFUSED is in place, unreadable
    : >"$LOG"
    capture haseen agent account add claude
    assert_status "an unreadable file refuses: $1" 1 "$STATUS"
    assert_contains "and names it: $1" "$OUTPUT" "$REFUSED cannot be read"
    assert_eq "before any login: $1" "" "$(logins)"
}
if ((EUID != 0)); then
    printf 'codex\n' >"$REFUSED"
    chmod 000 "$REFUSED"
    unreadable_case "mode 000"
    chmod 600 "$REFUSED"
else
    echo "  skip: running as root, mode 000 is readable" >&2
fi
rm -f "$REFUSED"
mkdir "$REFUSED"
unreadable_case "a directory"
rmdir "$REFUSED"
ln -s "$SANDBOX/nowhere" "$REFUSED"
unreadable_case "a dangling link"
rm -f "$REFUSED"
export HASEEN_SYSROOT="$SANDBOX/root"
rm -f "$HASEEN_SYSROOT/etc/haseen/agents/login-refused"
mkdir "$HASEEN_SYSROOT/etc/haseen/agents/login-refused"
: >"$LOG"
capture haseen agent account add claude
assert_contains "so is the machine's file" "$OUTPUT" "/etc/haseen/agents/login-refused cannot be read"
assert_eq "no login ran for it" "" "$(logins)"
rmdir "$HASEEN_SYSROOT/etc/haseen/agents/login-refused"

# A directory on the path that cannot be entered may hide the file: refused,
# naming the file and the directory (review round 2).
if ((EUID != 0)); then
    printf 'claude\n' >"$HASEEN_SYSROOT/etc/haseen/agents/login-refused"
    for locked in "$HASEEN_SYSROOT/etc/haseen/agents" "$HASEEN_SYSROOT/etc/haseen"; do
        chmod 000 "$locked"
        : >"$LOG"
        capture haseen agent account add codex
        chmod 755 "$locked"
        assert_status "a locked ${locked#"$HASEEN_SYSROOT"} refuses" 1 "$STATUS"
        assert_contains "naming the file and the directory: ${locked#"$HASEEN_SYSROOT"}" "$OUTPUT" \
            "/etc/haseen/agents/login-refused cannot be read ($locked cannot be entered)"
        assert_eq "before any login: ${locked#"$HASEEN_SYSROOT"}" "" "$(logins)"
    done
    rm -f "$HASEEN_SYSROOT/etc/haseen/agents/login-refused"
    mkdir -p "$(dirname "$REFUSED")"
    printf 'claude\n' >"$REFUSED"
    chmod 000 "$(dirname "$REFUSED")"
    : >"$LOG"
    capture haseen agent account add claude
    chmod 700 "$(dirname "$REFUSED")"
    assert_status "a locked ~/.config/haseen/agents refuses" 1 "$STATUS"
    assert_contains "and names it" "$OUTPUT" "$REFUSED cannot be read ($(dirname "$REFUSED") cannot be entered)"
    assert_eq "before any login" "" "$(logins)"
    rm -f "$REFUSED"
else
    echo "  skip: running as root, a mode 000 directory can be entered" >&2
fi
unset HASEEN_SYSROOT

# An entry that is not exactly claude, codex, grok or all refuses every
# sign-in, naming the entry; a leading UTF-8 byte-order mark is not an entry.
not_understood() { # LABEL CONTENT (printf format) [PROVIDER]
    printf "$2" >"$REFUSED"
    : >"$LOG"
    capture haseen agent account add "${3:-claude}"
    assert_status "not understood: $1" 1 "$STATUS"
    assert_contains "not understood: $1, said so" "$OUTPUT" "$REFUSED has an entry it does not understand: "
    assert_eq "not understood: $1, before any login" "" "$(logins)"
}
not_understood "a semicolon" 'claude;codex\n'
not_understood "a bar" 'claude|codex\n' codex
not_understood "double quotes" '"claude"\n'
not_understood "single quotes" "'claude'\\n"
not_understood "a colon" 'claude:\n'
not_understood "an assignment" 'claude=true\n'
not_understood "a star" '*\n' grok
not_understood "a zero-width space" 'claude\xe2\x80\x8b\n'
not_understood "fullwidth letters" '\xef\xbd\x83\xef\xbd\x8c\xef\xbd\x81\xef\xbd\x95\xef\xbd\x84\xef\xbd\x85\n'
not_understood "a no-break space between names" 'claude\xc2\xa0codex\n' codex
not_understood "a typo beside a good name" 'claude\ncodx\n' grok
assert_contains "the entry is printed escaped" "$OUTPUT" "does not understand: codx"
not_understood "an escape in an entry" 'claude\x1b[2J\n'
assert_not_contains "printed without its control byte" "$OUTPUT" $'\x1b'
printf '\xef\xbb\xbfclaude\n' >"$REFUSED"
: >"$LOG"
capture haseen agent account add claude
assert_contains "a byte-order mark before claude still lists it" "$OUTPUT" "$REFUSED lists it"
assert_eq "and no login ran" "" "$(logins)"
capture haseen agent account add grok
assert_status "a valid file still allows the others" 0 "$STATUS"
assert_contains "and grok signs in" "$(logins)" "grok login"
printf '\xff\xfec\x00l\x00a\x00u\x00d\x00e\x00\n\x00' >"$REFUSED"
: >"$LOG"
capture haseen agent account add codex
assert_status "a UTF-16 file refuses" 1 "$STATUS"
assert_contains "as not plain text" "$OUTPUT" "$REFUSED cannot be read (not plain text)"
assert_eq "before any login" "" "$(logins)"
rm -f "$REFUSED"
truncate -s 200M "$REFUSED"
: >"$LOG"
started=$SECONDS
capture haseen agent account add codex
assert_status "a file over 64 KiB refuses" 1 "$STATUS"
assert_contains "as too large to read" "$OUTPUT" "$REFUSED cannot be read (over 64 KiB)"
assert_eq "without reading it" "yes" "$( ((SECONDS - started < 10)) && echo yes || echo no)"
assert_eq "before any login" "" "$(logins)"
rm -f "$REFUSED"

# A relative HASEEN_USER_CONFIG, HASEEN_SYSROOT or XDG_CONFIG_HOME has no
# parent to strip at its last component: the search for the nearest
# directory ends at the working directory instead of spinning (review round
# 3). Each runs under timeout, so a regression fails instead of hanging.
in_sandbox() { capture timeout 20 bash -c 'cd "$1" && shift && exec "$@"' _ "$SANDBOX" "$@"; }
n=0
for spec in "HASEEN_USER_CONFIG=nope|grok" "HASEEN_USER_CONFIG=nope/deeper|codex" \
    "HASEEN_SYSROOT=nosuchroot|grok" "XDG_CONFIG_HOME=relcfg|codex"; do
    : >"$LOG"
    n=$((n + 1))
    in_sandbox env FAKE_ACCOUNT="uuid-rel-$n" FAKE_USER="rel$n" "${spec%|*}" haseen agent account add "${spec#*|}"
    assert_status "a relative ${spec%%=*} ends the search (${spec%|*})" 0 "$STATUS"
    assert_contains "and the login runs (${spec%|*})" "$(logins)" "${spec#*|} login"
done
if ((EUID != 0)); then
    mkdir -p "$SANDBOX/locked"
    chmod 000 "$SANDBOX/locked"
    : >"$LOG"
    in_sandbox env HASEEN_USER_CONFIG=locked/haseen haseen agent account add grok
    chmod 755 "$SANDBOX/locked"
    assert_status "a relative path behind a locked directory refuses" 1 "$STATUS"
    assert_contains "naming it" "$OUTPUT" "locked/haseen/agents/login-refused cannot be read (locked cannot be entered)"
    assert_eq "before any login" "" "$(logins)"
fi
mkdir -p "$SANDBOX/relcfg2/haseen/agents"
printf 'grok\n' >"$SANDBOX/relcfg2/haseen/agents/login-refused"
: >"$LOG"
in_sandbox env -u HASEEN_USER_CONFIG XDG_CONFIG_HOME=relcfg2 haseen agent account add grok
assert_status "a relative config that lists grok still refuses it" 1 "$STATUS"
assert_contains "naming the file" "$OUTPUT" "relcfg2/haseen/agents/login-refused lists it"
assert_eq "before any login" "" "$(logins)"

# --- a dry run signs in nobody ------------------------------------------------
acct accounts-dry
haseen agent account add claude >/dev/null
: >"$LOG"
capture haseen agent account add claude Side --dry-run
assert_status "a dry add succeeds" 0 "$STATUS"
assert_contains "it prints the login it would run" "$OUTPUT" "DRYRUN: env -u CLAUDE_CONFIG_DIR -u CODEX_HOME -u GROK_HOME BROWSER="
assert_contains "in a pending home" "$OUTPUT" "CLAUDE_CONFIG_DIR=$STATE/claude/.pending/login-XXXXXX"
assert_eq "no login ran" "" "$(logins)"
assert_eq "nothing was made" "no" "$([[ -e $STATE ]] && echo yes || echo no)"
assert_not_contains "and its cleanup deletes nothing" "$OUTPUT" "DRYRUN: rm"

# --- sign in again where an account lives ---------------------------------------
FAKE_ACCOUNT=uuid-side FAKE_USER=side haseen agent account add claude Side </dev/null >/dev/null
: >"$LOG"
FAKE_ACCOUNT=uuid-side FAKE_USER=side haseen agent account add --reauth side claude </dev/null >/dev/null
assert_contains "--reauth signs in in the account's own home" "$(logins)" "claude login home=$STATE/claude/side browser="
assert_eq "the registry gains no account" "2" "$(jq '.accounts | length' "$STATE/claude.json")"

# --- Codex and Grok identities come from display fields -------------------------
acct accounts-codex-grok
haseen agent account add codex >/dev/null
FAKE_ACCOUNT=acct-2 FAKE_USER=second haseen agent account add codex Second </dev/null >/dev/null
haseen agent account add grok >/dev/null
capture haseen agent account list --json
assert_eq "Codex's email and plan come from the id token's claims" "main@example.com Plus|second@example.com Plus" \
    "$(jq -r '.[] | select(.provider == "codex") | [.accounts[] | .email + " " + .plan] | join("|")' <<<"$OUTPUT")"
assert_eq "Grok's from its login and cached settings" "main@example.com SuperGrok" \
    "$(jq -r '.[] | select(.provider == "grok") | .accounts[0] | .email + " " + .plan' <<<"$OUTPUT")"
never_printed "Codex and Grok list" "$OUTPUT"
assert_eq "the Codex credential file is private" "600" "$(stat -c %a "$STATE/codex/second/auth.json")"

# --- a registry that does not parse is never overwritten ---------------------------
acct accounts-broken
haseen agent account add claude >/dev/null
FAKE_ACCOUNT=uuid-work FAKE_USER=work haseen agent account add claude Work </dev/null >/dev/null
printf '{"active": "work", "accounts": [' >"$STATE/claude.json"
broken_before="$(cat "$STATE/claude.json")"
for cmd in "use claude main" "rename claude work Job" "remove claude work --yes"; do
    read -ra argv <<<"$cmd"
    capture haseen agent account "${argv[@]}"
    assert_status "${argv[0]} refuses a registry that does not parse" 1 "$STATUS"
    assert_contains "${argv[0]} names it" "$OUTPUT" "registry $STATE/claude.json does not parse"
done
assert_eq "the registry is left as it was" "$broken_before" "$(cat "$STATE/claude.json")"
assert_eq "and the account's home stays" "yes" "$([[ -d $STATE/claude/work ]] && echo yes || echo no)"
: >"$LOG"
capture env FAKE_ACCOUNT=uuid-side FAKE_USER=side haseen agent account add claude Side </dev/null
assert_status "add refuses it" 1 "$STATUS"
assert_eq "before the login" "" "$(logins)"
capture haseen agent account list claude
assert_status "list still answers" 0 "$STATUS"
assert_contains "with a warning" "$OUTPUT" "registry $STATE/claude.json does not parse"
assert_contains "and the main login" "$OUTPUT" "main@example.com"
assert_eq "a broken registry selects the main login" "" "$(haseen agent account home claude)"
# Valid JSON whose accounts are not a list of objects with ids is refused the
# same way: rewriting it would drop them (review round 2).
for junk in '{"accounts":5}' '{"accounts":"x"}' '{"accounts":[1,2]}' '{"accounts":[{"label":"no id"}]}' '[]'; do
    printf '%s\n' "$junk" >"$STATE/claude.json"
    capture haseen agent account use claude main
    assert_status "use refuses $junk" 1 "$STATUS"
    assert_contains "naming the registry: $junk" "$OUTPUT" "registry $STATE/claude.json does not parse"
    assert_eq "and keeps it: $junk" "$junk" "$(cat "$STATE/claude.json")"
done
printf '{"active":"main","accounts":[]}\n' >"$STATE/claude.json"
capture haseen agent account use claude main
assert_status "an empty account list is a registry" 0 "$STATUS"

# --- a long label gives a short id ---------------------------------------------------
acct accounts-long
haseen agent account add claude >/dev/null
long="$(printf 'Abcdefghij%.0s' {1..40})"
capture env FAKE_ACCOUNT=uuid-long FAKE_USER=long haseen agent account add claude "$long" </dev/null
assert_status "a 400-character label still adds the account" 0 "$STATUS"
long_id="$(jq -r '.accounts[1].id' "$STATE/claude.json")"
assert_eq "its id is cut to 48 characters" "48" "${#long_id}"
assert_eq "its home is named by that id" "yes" "$([[ -d $STATE/claude/$long_id ]] && echo yes || echo no)"
assert_eq "the label is kept whole" "${#long}" "$(jq -r '.accounts[1].label | length' "$STATE/claude.json")"

# --- Omarchy's registry: read until haseen adopts it, never written ---------------
acct accounts-omarchy
haseen agent account add codex >/dev/null
OM="$HOME/.local/state/omarchy/agents/accounts"
mkdir -p "$OM/codex/side"
printf '{"tokens":{"account_id":"acct-side","access_token":"%s"}}\n' "$FAKE_TOKEN" >"$OM/codex/side/auth.json"
printf '{"active":"side","switch":"manual","threshold":95,"alert":"","accounts":[{"id":"main","label":"Main","home":"","primary":true},{"id":"side","label":"Side","home":"%s","primary":false}]}\n' \
    "$OM/codex/side" >"$OM/codex.json"
om_before="$(cat "$OM/codex.json")"
assert_eq "an account added under Omarchy keeps resolving" "$OM/codex/side" "$(haseen agent account home codex)"
assert_eq "for Omarchy's name too" "$OM/codex/side" "$("$OMA/omarchy-agent-account-home" codex)"
capture haseen agent account list codex
assert_contains "list says whose registry it read" "$OUTPUT" "(read from Omarchy: $OM/codex.json)"
haseen agent account use codex main >/dev/null
assert_eq "the first change adopts it into haseen's registry" "main side" "$(jq -r '[.accounts[].id] | join(" ")' "$STATE/codex.json")"
assert_eq "Omarchy's registry is never written" "$om_before" "$(cat "$OM/codex.json")"
haseen agent account remove codex side --yes >/dev/null
assert_eq "removing an adopted account keeps the home Omarchy made" "yes" "$([[ -f $OM/codex/side/auth.json ]] && echo yes || echo no)"

# --- the omarchy-agent-account-* answers ----------------------------------------
acct accounts-answers
haseen agent account add claude >/dev/null
FAKE_ACCOUNT=uuid-work FAKE_USER=work haseen agent account add claude Work </dev/null >/dev/null
capture "$OMA/omarchy-agent-account-list" claude --json
assert_eq "omarchy-agent-account-list is haseen's list" "main work" "$(jq -r '[.[0].accounts[].id] | join(" ")' <<<"$OUTPUT")"
capture "$OMA/omarchy-agent-account-use" claude work
assert_contains "omarchy-agent-account-use is haseen's use" "$OUTPUT" "New Claude sessions now use Work"
capture "$OMA/omarchy-agent-account-rename" claude work Work Two
assert_contains "omarchy-agent-account-rename is haseen's rename" "$OUTPUT" "Renamed to Work Two."
capture "$OMA/omarchy-agent-account-state" homes claude
assert_eq "state homes prints Omarchy's lines: id, home, active" "main	$HOME/.claude	0
work-two	$STATE/claude/work	1" "$OUTPUT"
assert_eq "state home" "$STATE/claude/work" "$("$OMA/omarchy-agent-account-state" home claude)"
assert_eq "state registry" "work-two" "$("$OMA/omarchy-agent-account-state" registry claude | jq -r .active)"
capture "$OMA/omarchy-agent-account-state" refresh
assert_status "state refresh has nothing to do" 0 "$STATUS"
capture "$OMA/omarchy-agent-account-state" register claude x /tmp/x
assert_status "Omarchy's internal steps are refused" 1 "$STATUS"
capture "$OMA/omarchy-agent-account-mode" claude
assert_contains "mode says accounts switch when told" "$OUTPUT" "Claude switches accounts when you say so"
capture "$OMA/omarchy-agent-account-mode" claude auto 90
assert_status "automatic switching is refused" 1 "$STATUS"
assert_contains "with the reason" "$OUTPUT" "switching near a limit is not built (plan 146)"
: >"$LOG"
capture "$OMA/omarchy-agent-account-add" --events claude --dry-run
assert_status "add drops Omarchy's --events" 0 "$STATUS"
assert_contains "and runs haseen's add" "$OUTPUT" "DRYRUN: register the login"
capture "$OMA/omarchy-agent-account-remove" claude work-two </dev/null
assert_status "remove without a terminal does not ask, as Omarchy's" 0 "$STATUS"
assert_eq "the account is gone" "main" "$(jq -r '[.accounts[].id] | join(" ")' "$STATE/claude.json")"
stub ssh 'echo "STUB-CALLED: ssh $*" >&2; exit 97'
for n in omarchy-agent-account-copy omarchy-agent-account-transfer; do
    capture "$OMA/$n" host.example.com claude
    assert_status "$n is refused" 1 "$STATUS"
    assert_contains "$n says credentials never leave" "$OUTPUT" "haseen never ships agent credentials to another host"
    assert_dry_pure "$n never reaches SSH" "$OUTPUT"
done

# --- a launch uses the account chosen now -----------------------------------------
acct accounts-launch
haseen agent account add claude >/dev/null
FAKE_ACCOUNT=uuid-work FAKE_USER=work haseen agent account add claude Work </dev/null >/dev/null
export HASEEN_SYSROOT="$SANDBOX/root"
mkdir -p "$HASEEN_SYSROOT/etc/mise/conf.d"
: >"$HASEEN_SYSROOT/etc/mise/conf.d/omarchy-agent-accounts.toml"
capture haseen agent account use claude work
assert_contains "with Omarchy 4.5's mise wrapper a plain CLI follows everywhere" "$OUTPUT" \
    "The agent key, the menu, haseen agent account exec and plain claude follow it (a haseen shell, and every mise shim)."
unset HASEEN_SYSROOT
FAKE="$SANDBOX/fake"
mkdir -p "$FAKE/bin" "$FAKE/share/haseen"
for d in lib omarchy; do ln -s "$HASEEN_PATH/$d" "$FAKE/share/haseen/$d"; done
printf '#!/bin/sh\n[ "$1" = agent ] && [ $# -eq 1 ] && echo "${AGENT:-claude}"; exit 0\n' >"$FAKE/bin/haseen-setup-default"
chmod +x "$FAKE/bin/haseen-setup-default"
fa() { env HASEEN_PATH="$FAKE/share/haseen" "$OMA/$1" "${@:2}"; }
assert_eq "omarchy-agent pins the active account's home" \
    "DRYRUN: env -u CLAUDE_CONFIG_DIR OMARCHY_AGENT_CLAUDE_HOME=$STATE/claude/work CLAUDE_CONFIG_DIR=$STATE/claude/work claude --permission-mode auto" \
    "$(fa omarchy-agent --inline --dry-run)"
assert_eq "a parent session's pin is not inherited" \
    "DRYRUN: env -u CLAUDE_CONFIG_DIR OMARCHY_AGENT_CLAUDE_HOME=$STATE/claude/work CLAUDE_CONFIG_DIR=$STATE/claude/work claude --permission-mode auto" \
    "$(OMARCHY_AGENT_CLAUDE_HOME='' fa omarchy-agent --inline --dry-run)"
assert_eq "an explicit home wins" "DRYRUN: claude --permission-mode auto" \
    "$(CLAUDE_CONFIG_DIR=/srv/explicit fa omarchy-agent --inline --dry-run)"
for spec in "agy|agy --dangerously-skip-permissions" "kimi|kimi --yolo" "ori|ori code" "gemini|gemini --yolo"; do
    stub "${spec%%|*}" 'exit 0'
    assert_eq "omarchy-agent starts ${spec%%|*}" "DRYRUN: ${spec#*|}" "$(AGENT=${spec%%|*} fa omarchy-agent --inline --dry-run)"
done
assert_eq "kimi takes a prompt in print mode" "DRYRUN: kimi --prompt hi" "$(AGENT=kimi fa omarchy-agent --inline --prompt hi --dry-run)"

# The usage record describes, and names, the active account.
cat >"$STATE/claude/work/.credentials.json" <<EOF
{"claudeAiOauth":{"accessToken":"$FAKE_TOKEN","expiresAt":1}}
EOF
capture env HASEEN_AGENT_USAGE_DIR="$SANDBOX/usage" "$OMA/omarchy-agent-usage-update" claude
assert_status "the usage update succeeds" 0 "$STATUS"
assert_eq "the record names the active account" "work Work" "$(jq -r '.account.id + " " + .account.label' "$SANDBOX/usage/claude.json")"
assert_eq "and read its home's sign-in" "Sign-in expired" "$(jq -r .usageStatusText "$SANDBOX/usage/claude.json")"
never_printed "the usage record" "$(cat "$SANDBOX/usage/claude.json")"

# --- Omarchy 4.5's agent names ------------------------------------------------------
acct accounts-names
for name in agy kimi ori gemini; do
    capture haseen setup default agent "$name" --dry-run
    assert_status "haseen setup default agent takes $name" 0 "$STATUS"
done
# omarchy-default-agent finds haseen's commands beside its tree: a fake tree
# whose setup-default records the name it is given.
FAKE="$SANDBOX/fake"
mkdir -p "$FAKE/bin" "$FAKE/share/haseen"
for d in lib omarchy; do ln -s "$HASEEN_PATH/$d" "$FAKE/share/haseen/$d"; done
printf '#!/bin/sh\necho "setup-default $*" >>"%s"\n' "$LOG" >"$FAKE/bin/haseen-setup-default"
chmod +x "$FAKE/bin/haseen-setup-default"
for spec in antigravity:agy antigravity-cli:agy kimi-code:kimi openrouter:ori gemini-cli:gemini; do
    : >"$LOG"
    env HASEEN_PATH="$FAKE/share/haseen" "$OMA/omarchy-default-agent" "${spec%%:*}" --dry-run >/dev/null 2>&1 || true
    assert_contains "omarchy-default-agent maps ${spec%%:*}" "$(logins)" "setup-default agent ${spec#*:}"
done
assert_eq "the menu offers the three new agents" "agy kimi ori" \
    "$(grep -oE '"setup\.default\.agent\.(agy|kimi|ori)"' "$HASEEN_PATH/default/menu.jsonc" | grep -oE '(agy|kimi|ori)' | tr '\n' ' ' | sed 's/ $//')"

# --- every Claude account's limits (plan 146) -------------------------------------
acct accounts-limits
# Any probe that slipped past the seeded caches would end at a closed local
# port: https goes through the proxy's CONNECT, so no token leaves TLS and
# nothing reaches Anthropic.
export https_proxy=http://127.0.0.1:9 HTTPS_PROXY=http://127.0.0.1:9
unset no_proxy NO_PROXY
haseen agent account add claude >/dev/null
assert_eq "one Claude account starts no timer" "" "$(timer_calls)"
capture env FAKE_ACCOUNT=uuid-work FAKE_USER=work haseen agent account add claude Work </dev/null
assert_status "the second account is added" 0 "$STATUS"
assert_eq "and the second Claude account starts the limits timer" \
    "systemctl --user enable --now haseen-agent-usage.timer" "$(timer_calls)"
: >"$SYSTEMCTL_LOG"
haseen agent account add codex >/dev/null
FAKE_ACCOUNT=acct-2 FAKE_USER=second haseen agent account add codex Second </dev/null >/dev/null
FAKE_ACCOUNT=uuid-third FAKE_USER=third haseen agent account add claude Third </dev/null >/dev/null
assert_eq "Codex accounts and a third Claude one leave the timer alone" "" "$(timer_calls)"
haseen agent account remove claude third --yes >/dev/null
assert_eq "so does a remove that leaves two" "" "$(timer_calls)"

# A live token whose numbers were just measured, and a lapsed one whose
# refresh token is still good, each with its own cache. The fresh cache is
# dated ahead, so the probe's reuse window cannot lapse on a slow runner.
now_ms=$(($(date +%s) * 1000))
future_ms=$((now_ms + 86400000))
LIMITS="$XDG_CACHE_HOME/haseen/agent-usage"
mkdir -p "$LIMITS"
printf '{"claudeAiOauth":{"accessToken":"%s","refreshToken":"%s","expiresAt":%s,"refreshTokenExpiresAt":%s,"rateLimitTier":"default_claude_max_20x"}}\n' \
    "$FAKE_TOKEN" "$FAKE_TOKEN" "$future_ms" "$future_ms" >"$HOME/.claude/.credentials.json"
printf '{"claudeAiOauth":{"accessToken":"%s","refreshToken":"%s","expiresAt":1,"refreshTokenExpiresAt":%s}}\n' \
    "$FAKE_TOKEN" "$FAKE_TOKEN" "$future_ms" >"$STATE/claude/work/.credentials.json"
printf '{"fetchedAtMs":%s,"limits":[{"label":"Session","title":"Session","percent":0.42,"resetsAt":""}]}\n' \
    "$((now_ms + 600000))" >"$LIMITS/claude-limits-uuid-main.json"
printf '{"fetchedAtMs":1700000000000,"limits":[{"label":"Week","title":"Week","percent":0.5,"resetsAt":""}]}\n' \
    >"$LIMITS/claude-limits-uuid-work.json"
haseen agent account use claude work >/dev/null
capture env HASEEN_AGENT_USAGE_DIR="$SANDBOX/usage" "$OMA/omarchy-agent-usage-update" claude
assert_status "the usage update with two accounts succeeds" 0 "$STATUS"
rec="$(cat "$SANDBOX/usage/claude.json")"
assert_eq "the record lists every account, in the registry's order" "main:false work:true" \
    "$(jq -r '[.accounts[] | .id + ":" + (.active | tostring)] | join(" ")' <<<"$rec")"
assert_eq "each account's limits come from its own sign-in" "main 0.42|work 0.5" \
    "$(jq -r '[.accounts[] | .id + " " + (.limits[0].percent | tostring)] | join("|")' <<<"$rec")"
assert_eq "numbers measured now are current" "false|||Max 20x" \
    "$(jq -r '.accounts[0] | [(.stale | tostring), .usageStatusText, .authHelpText, .plan] | join("|")' <<<"$rec")"
assert_eq "a lapsed access token with a good refresh token pauses, keeping its numbers" "true|Limits paused|1700000000000" \
    "$(jq -r '.accounts[1] | [(.stale | tostring), .usageStatusText, (.fetchedAt | tostring)] | join("|")' <<<"$rec")"
assert_contains "and needs no new sign-in" "$(jq -r '.accounts[1].authHelpText' <<<"$rec")" "signing in again is not needed"
assert_eq "the record's own fields describe the account in use" "work|Limits paused|0.5|true|1700000000000" \
    "$(jq -r '[.account.id, .usageStatusText, (.limits[0].percent | tostring), (.limitsStale | tostring), (.limitsFetchedAt | tostring)] | join("|")' <<<"$rec")"
never_printed "the record" "$rec"
assert_eq "no cache holds a token" "" "$(grep -rl "$FAKE_TOKEN" "$LIMITS" "$SANDBOX/usage" || true)"
assert_eq "no shared cache stands in for an account" "no" "$([[ -e $LIMITS/claude-limits.json ]] && echo yes || echo no)"

# haseen agent account usage: by hand it asks for fresh numbers; the timer's
# run asks only while there is a second account and the panel shows usage.
capture haseen agent account usage --dry-run
assert_eq "a run by hand forces fresh numbers" "DRYRUN: $OMA/omarchy-agent-usage-update --force claude" "$OUTPUT"
capture haseen agent account usage --timer --dry-run
assert_status "the timer's run with the usage section off" 0 "$STATUS"
assert_eq "asks nobody" "" "$OUTPUT"
mkdir -p "$XDG_CONFIG_HOME/haseen"
printf '{"plugins":{"haseen.agents":{"settings":{"usage":true}}}}\n' >"$XDG_CONFIG_HOME/haseen/shell.json"
capture haseen agent account usage --timer --dry-run
assert_eq "with it on, the timer's run reuses recent numbers" \
    "DRYRUN: $OMA/omarchy-agent-usage-update --limits-only claude" "$OUTPUT"
capture haseen agent account usage --help
assert_status "usage --help" 0 "$STATUS"
assert_contains "names the timer" "$OUTPUT" "haseen-agent-usage.timer"
capture haseen agent account usage --every-minute
assert_status "an unknown option is refused" 2 "$STATUS"

: >"$SYSTEMCTL_LOG"
capture haseen agent account remove claude work --dry-run
assert_contains "a dry remove that leaves one prints the timer's stop" "$OUTPUT" \
    "DRYRUN: systemctl --user disable --now haseen-agent-usage.timer"
assert_eq "and stops nothing" "" "$(timer_calls)"
haseen agent account remove claude work --yes >/dev/null
assert_eq "the remove that leaves one stops the timer" \
    "systemctl --user disable --now haseen-agent-usage.timer" "$(timer_calls)"
capture haseen agent account usage --timer --dry-run
assert_eq "and with one account the timer's run asks nobody" "" "$OUTPUT"

# One account: its cache is keyed by who the home is signed in as, so the
# numbers a shared cache kept for another subscription are never shown.
printf '{"fetchedAtMs":%s,"limits":[{"label":"Session","title":"Session","percent":0.99,"resetsAt":""}]}\n' \
    "$((now_ms + 600000))" >"$LIMITS/claude-limits.json"
capture env HASEEN_AGENT_USAGE_DIR="$SANDBOX/usage" "$OMA/omarchy-agent-usage-update" claude
assert_eq "one account reads its own cache, not the shared one" "0.42|false" \
    "$(jq -r '[(.limits[0].percent | tostring), (has("accounts") | tostring)] | join("|")' "$SANDBOX/usage/claude.json")"

# No user manager (a console, a container): the account is still added.
stub systemctl 'exit 1'
capture env FAKE_ACCOUNT=uuid-late FAKE_USER=late haseen agent account add claude Late </dev/null
assert_status "an add without a user manager still succeeds" 0 "$STATUS"
assert_contains "and says the timer did not start" "$OUTPUT" "could not start haseen-agent-usage.timer"
unset https_proxy HTTPS_PROXY

# --- a finished sign-in an add could not register (plan 146) ----------------------
acct accounts-recover
haseen agent account add claude >/dev/null
P="$STATE/claude/.pending"
# finished_login HOME UUID USER — what the fake CLI's login leaves there.
finished_login() {
    mkdir -p "$1"
    chmod 700 "$1"
    printf '{"claudeAiOauth":{"accessToken":"%s","refreshToken":"%s","expiresAt":1}}\n' \
        "$FAKE_TOKEN" "$FAKE_TOKEN" >"$1/.credentials.json"
    printf '{"oauthAccount":{"accountUuid":"%s","emailAddress":"%s@example.com"}}\n' "$2" "$3" >"$1/.claude.json"
}
# receipt HOME LABEL OWNER STARTED — the add that owns HOME.
receipt() {
    jq -nc --arg label "$2" --argjson owner "$3" --arg started "$4" \
        '{label: $label, owner: $owner, started: $started}' >"$1/.haseen-login.json"
}
stat_rest="$(cat /proc/$$/stat)"
stat_rest=${stat_rest##*") "}
read -ra stat_fields <<<"$stat_rest"
alive_start=${stat_fields[19]}
finished_login "$P/login-dead" uuid-side side
receipt "$P/login-dead" Side 1 not-a-start-time
finished_login "$P/login-live" uuid-live live
receipt "$P/login-live" Live "$$" "$alive_start"
mkdir -p "$P/login-empty"
receipt "$P/login-empty" Empty 1 not-a-start-time
finished_login "$P/login-unowned" uuid-unowned unowned
: >"$LOG"
capture env FAKE_ACCOUNT=uuid-other FAKE_USER=other haseen agent account add claude Other </dev/null
assert_status "an add that finds a finished, abandoned sign-in succeeds" 0 "$STATUS"
assert_contains "it adds that one" "$OUTPUT" "Added Side (side@example.com), a sign-in that was interrupted before it was added."
assert_contains "and says how to switch" "$OUTPUT" "haseen agent account use claude side"
assert_eq "without a new login" "" "$(grep ' login ' "$LOG" || true)"
assert_eq "registered under its receipt's name" "main side" "$(jq -r '[.accounts[].id] | join(" ")' "$STATE/claude.json")"
assert_eq "in its own home, without the receipt" "yes no" \
    "$([[ -f $STATE/claude/side/.credentials.json ]] && echo yes || echo no) $([[ -e $STATE/claude/side/.haseen-login.json ]] && echo yes || echo no)"
assert_eq "an abandoned home without a login is deleted" "no" "$([[ -e $P/login-empty ]] && echo yes || echo no)"
assert_eq "a live add's home is left alone" "yes" "$([[ -d $P/login-live ]] && echo yes || echo no)"
assert_eq "a home without a receipt is left alone" "yes" "$([[ -d $P/login-unowned ]] && echo yes || echo no)"
assert_eq "the second account starts the timer" "systemctl --user enable --now haseen-agent-usage.timer" "$(timer_calls)"
never_printed "the recovery" "$OUTPUT"

# The same login abandoned twice: the copy is deleted, and the add goes on.
finished_login "$P/login-again" uuid-side side
receipt "$P/login-again" Side 1 not-a-start-time
: >"$LOG"
capture env FAKE_ACCOUNT=uuid-third FAKE_USER=third haseen agent account add claude Third </dev/null
assert_status "an add after a duplicate abandoned sign-in succeeds" 0 "$STATUS"
assert_eq "the duplicate is deleted" "no" "$([[ -e $P/login-again ]] && echo yes || echo no)"
assert_contains "and the add signs in as asked" "$(logins)" "claude login home=$P/login-"
assert_contains "and adds that account" "$OUTPUT" "Added Third (third@example.com)."

# Root ignores a read-only directory, so this part needs another user.
if ((EUID != 0)); then
    # The registry cannot be written (the accounts directory is read-only):
    # the add fails after moving the login into place, and its receipt
    # carries the entry for the next add.
    chmod 500 "$STATE"
    capture env FAKE_ACCOUNT=uuid-spare FAKE_USER=spare haseen agent account add claude Spare </dev/null
    chmod 700 "$STATE"
    assert_eq "an add whose registry cannot be written fails" "1" "$((STATUS != 0))"
    assert_eq "the finished login stays, with its receipt" "yes" \
        "$([[ -f $STATE/claude/spare/.credentials.json && -f $STATE/claude/spare/.haseen-login.json ]] && echo yes || echo no)"
    assert_eq "the receipt is private" "600" "$(stat -c %a "$STATE/claude/spare/.haseen-login.json")"
    assert_eq "and holds its owner and entry, no credential" "entry,label,owner,started|" \
        "$(jq -r '(keys | join(",")) + "|" + ([.. | strings | select(test("fake-token"))] | join(","))' "$STATE/claude/spare/.haseen-login.json")"
    assert_eq "the registry lacks it" "main side third" "$(jq -r '[.accounts[].id] | join(" ")' "$STATE/claude.json")"
    : >"$LOG"
    capture haseen agent account add claude </dev/null
    assert_status "the next add registers it" 0 "$STATUS"
    assert_contains "and says so" "$OUTPUT" "Added Spare (spare@example.com), a sign-in that was interrupted before it was added."
    assert_eq "with the entry it was moved with" "main side third spare" "$(jq -r '[.accounts[].id] | join(" ")' "$STATE/claude.json")"
    assert_eq "and no login" "" "$(grep ' login ' "$LOG" || true)"
    assert_eq "its receipt is gone" "no" "$([[ -e $STATE/claude/spare/.haseen-login.json ]] && echo yes || echo no)"
fi

# --- the agent finds tools installed after it started (plan 146) ------------------
acct accounts-shims
stub claude 'printf "%s\n" "$PATH"'
shim_path="$(MISE_DATA_DIR="$SANDBOX/mise" "$OMA/omarchy-agent-account-exec" claude)"
assert_eq "mise's wrappers come first" "$SANDBOX/mise/command-wrappers/bin" "${shim_path%%:*}"
assert_eq "and its shims last" "$SANDBOX/mise/shims" "${shim_path##*:}"
shim_path="$(PATH="$SANDBOX/mise/shims:$PATH" MISE_DATA_DIR="$SANDBOX/mise" "$OMA/omarchy-agent-account-exec" claude)"
assert_eq "shims already there are not added again" "1" "$(tr ':' '\n' <<<"$shim_path" | grep -cxF "$SANDBOX/mise/shims")"

# --- a Grok settings cache that is not an object costs only the plan --------------
acct accounts-grok-cache
haseen agent account add grok >/dev/null
printf '{"payload":"{\\"settings\\":\\"not an object\\"}"}\n' >"$HOME/.grok/settings_cache.json"
capture haseen agent account list --json grok
assert_status "list reads it" 0 "$STATUS"
assert_eq "the account keeps its identity, without a plan" "main@example.com|" \
    "$(jq -r '.[] | select(.provider == "grok") | .accounts[0] | .email + "|" + .plan' <<<"$OUTPUT")"
