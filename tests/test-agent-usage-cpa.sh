# shellcheck shell=bash
# haseen:covers share/haseen/libexec/agent-usage-cpa
# haseen:covers share/haseen/omarchy/bin/omarchy-agent-usage-update
# haseen:covers share/haseen/shell/plugins/haseen.agents/manifest.json
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# The CLIProxyAPI row (plan 124): cpa-usage-exporter drains the proxy's usage
# queue and serves the cpa_ series for Prometheus and Grafana; the agents panel
# reads one record built from them. No real endpoint is contacted — the metric
# text is a fixture read through file://.

sandbox agent-usage-cpa
# The sandbox stubs curl (plan 094); this one hands the call to the real
# binary, which only ever reads the fixture below.
stub curl 'exec /usr/bin/curl "$@"'
OMA="$HASEEN_PATH/omarchy/bin"
CPA="$HASEEN_PATH/libexec/agent-usage-cpa"
USAGE="$SANDBOX/usage"

cat >"$SANDBOX/metrics.txt" <<'METRICS'
# HELP cpa_requests_total Requests observed in the CLIProxyAPI usage queue.
# TYPE cpa_requests_total counter
cpa_requests_total{provider="claude",model="opus",endpoint="/v1/messages"} 1200.0
cpa_requests_total{provider="codex",model="gpt-6.1-sol",endpoint="/v1/responses"} 300.0
cpa_request_errors_total{provider="claude",model="opus",auth_index="0",status_code="429"} 7.0
cpa_tokens_total{provider="claude",model="opus",auth_index="0",kind="input"} 1500000.0
cpa_tokens_total{provider="claude",model="opus",auth_index="0",kind="output"} 200000.0
cpa_estimated_cost_total{provider="claude",model="opus",auth_index="0",currency="USD"} 4.75
cpa_quota_used_ratio{provider="claude",account="me",window="5h",tier="max"} 0.42
cpa_quota_used_ratio{provider="codex",account="me",window="7d",tier="plus"} 0.91
cpa_quota_used_ratio{provider="codex",account="me",window="5h",tier="plus"} 0.1
METRICS

# --- the record ------------------------------------------------------------
capture env HASEEN_CPA_USAGE_URL="file://$SANDBOX/metrics.txt" "$CPA"
assert_status "the collector answers" 0 "$STATUS"
assert_eq "the row's name" "CLIProxyAPI" "$(jq -r .name <<<"$OUTPUT")"
assert_eq "every request, whatever its provider" "1.5k requests · 1.7M tokens · \$4.75 · 7 errors" \
    "$(jq -r .usageStatusText <<<"$OUTPUT")"
assert_eq "the fullest quota window comes first" "Codex · 7d" "$(jq -r '.limits[0].label' <<<"$OUTPUT")"
assert_eq "as a 0-1 fraction the panel draws as a percent" "0.91" "$(jq -r '.limits[0].percent' <<<"$OUTPUT")"
assert_eq "three windows at most" "3" "$(jq '.limits | length' <<<"$OUTPUT")"

# --- an exporter that does not answer --------------------------------------
capture env HASEEN_CPA_USAGE_URL="file://$SANDBOX/missing.txt" "$CPA"
assert_status "an unreachable exporter is not a collector failure" 0 "$STATUS"
assert_eq "it says so instead" "false" "$(jq -r .ready <<<"$OUTPUT")"
assert_contains "naming the endpoint" "$OUTPUT" "Exporter unreachable at file://$SANDBOX/missing.txt"

# --- nothing configured ----------------------------------------------------
capture env -u HASEEN_CPA_USAGE_URL "$CPA"
assert_status "no endpoint is not an error" 0 "$STATUS"
assert_eq "and prints no record" "" "$OUTPUT"

mkdir -p "$HOME/.config/haseen"
jq -n --arg url "file://$SANDBOX/metrics.txt" \
    '{plugins: {"haseen.agents": {settings: {usageUrl: $url}}}}' >"$HOME/.config/haseen/shell.json"
capture env -u HASEEN_CPA_USAGE_URL "$CPA"
assert_status "the haseen.agents usageUrl setting is read" 0 "$STATUS"
assert_eq "and names the endpoint's record" "CLIProxyAPI" "$(jq -r .name <<<"$OUTPUT")"

# --- dry run ---------------------------------------------------------------
capture env HASEEN_CPA_USAGE_URL="file://$SANDBOX/metrics.txt" "$CPA" --dry-run
assert_status "the dry run succeeds" 0 "$STATUS"
assert_contains "and says what it would read" "$OUTPUT" "DRYRUN: read file://$SANDBOX/metrics.txt"
assert_dry_pure "the dry run" "$OUTPUT"

# --- the update command ----------------------------------------------------
rm -f "$HOME/.config/haseen/shell.json"
capture env HASEEN_CPA_USAGE_URL="file://$SANDBOX/metrics.txt" HASEEN_AGENT_USAGE_DIR="$USAGE" \
    "$OMA/omarchy-agent-usage-update" cpa
assert_status "the update succeeds" 0 "$STATUS"
assert_eq "the panel gets its row" "CLIProxyAPI" "$(jq -r .name "$USAGE/cpa.json")"

capture env -u HASEEN_CPA_USAGE_URL HASEEN_AGENT_USAGE_DIR="$USAGE" "$OMA/omarchy-agent-usage-update" cpa
assert_status "an unconfigured backbone is a clean run" 0 "$STATUS"
assert_eq "and the stale row goes away" "gone" "$([[ -e $USAGE/cpa.json ]] && echo here || echo gone)"
