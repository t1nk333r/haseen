# Plan 124: CLIProxyAPI's own stats in the agents panel

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW. A new record file next to the other collectors' and a read of
  a local OpenMetrics endpoint; nothing is read or written unless a URL is
  configured, and the panel never asks the proxy itself.
- **Depends on**: 093, 108
- **Category**: shell
- **Planned at**: 2026-10-25
- **State**: DONE 2026-10-25 (owner, "stats for the plugin you might get use of
  its exporter for grafana").

## Why

`haseen.agents` reports Claude, Codex, Grok and Kimi from their local session
files; the backbone that carries all of them — CLIProxyAPI, which backs
haseen.agents itself and several accounts here — is invisible. It is also the
only party that knows the real traffic: `/proc` scans and session files count
this machine's sessions, not what the proxy routed.

The proxy cannot answer where the panel looks. Probed 2026-10-25 from luna:

```
$ curl -o /dev/null -w '%{http_code}' http://cliproxy-mars:8317/              -> 200
$ curl -o /dev/null -w '%{http_code}' http://cliproxy-mars:8317/metrics      -> 404
$ curl -o /dev/null -w '%{http_code}' \
      http://cliproxy-mars:8317/v0/management/auth-files                     -> 401
```

No usage endpoint either: since v6.10.0 CPA replaced its built-in usage
tracking with a short-lived, *destructive* queue that expects an external
consumer. `Adrastopoulos/cpa-usage-exporter` (MIT) is that consumer: it drains
the queue, snapshots credential health from `/v0/management/auth-files` and
polls the provider quota windows, serving `cpa_*` OpenMetrics on `:9185`, and
it ships `dashboards/cpa-usage-prometheus.json` for Grafana. Reading its
metrics is therefore the one supported way to get CLIProxyAPI's stats — for
the panel and for the dashboard alike.

## What changed

- **`share/haseen/libexec/agent-usage-cpa`** (new) — the row's collector. It
  reads `--url`, then `$HASEEN_CPA_USAGE_URL`, then `haseen.agents`'
  `usageUrl` from `shell.json`; with none it prints nothing. It sums the
  counters whatever their labels (`cpa_requests_total`,
  `cpa_request_errors_total`, `cpa_tokens_total`, `cpa_estimated_cost_total`)
  into `"1.5k requests · 1.7M tokens · $4.75 · 7 errors"`, and takes the three
  fullest `cpa_quota_used_ratio` windows as `limits` (`{label, percent}`,
  labelled `Codex · 7d`, a 0-1 fraction as the panel expects). An exporter
  that does not answer is not a collector failure: the record says
  `ready: false` and names the endpoint. `--force` and `--limits-only` are
  accepted and change nothing (the update passes them to every collector, and
  there is no cache to bypass), so they must not fail it.
  It lives in `libexec`, not in `omarchy/bin`: that directory is exactly
  Omarchy's command set, asserted by `tests/test-omarchy-commands.sh`, and this
  is haseen's own row for a backbone Omarchy has no collector for.
- **`share/haseen/omarchy/bin/omarchy-agent-usage-update`** — runs haseen's own
  collectors from `share/haseen/libexec` (`agent-usage-<agent>`) beside
  Omarchy's (`omarchy/bin/omarchy-agent-usage-<agent>`), with the same agent
  names and `--except`/`--only` behaviour. A collector that prints nothing and
  succeeds now means "no record": the previous file is removed instead of
  leaving a stale row, and the run is not an error — without this a machine
  that never configured cpa would fail every update.
- **`haseen.agents`** (`manifest.json:39`) — `usageUrl`, a string setting
  defaulting to `""`.
- **`Agents.js:143`** — a usage line shows the stats *and* its quota windows
  (`"Codex · 7d 91% · 1.5k requests · $4.75"`); limits used to hide the status
  text entirely. One line, elided as before.

## Evidence

- `tests/test-agent-usage-cpa.sh` -> 24/24: the record's name, summed status
  and ordered limits from a fixture; the 0.91 fraction the panel would draw as
  91%; an unreachable endpoint (`ready: false`, named); no endpoint configured
  (no output, exit 0); the `usageUrl` setting is read; `--dry-run` reads
  nothing; `omarchy-agent-usage-update cpa` writes `cpa.json` and, with the
  endpoint unset, removes it and exits 0; `--force` and `--limits-only`
  reach the collector and still write the row.
- `tests/test-widgets-c.sh` -> 114/114, with the new "stats beside limits"
  assertion.
- `tests/test-omarchy-commands.sh` -> 179/179 (the new file is outside
  `omarchy/bin`, so the parity invariant is untouched).
- `shellcheck -x --severity=warning` on both scripts: clean; `bash -n` clean.
- `tools/affected-tests.sh --check`: every file covered.

## What the Grafana side needs (owner steps)

The exporter is not running yet — `:9185` answers nothing from luna — and the
Grafana/Prometheus pair is on the infrastructure, not in this repo. Probed
2026-10-25: Grafana's `/api/health` answers, Prometheus's `:9090/-/ready` does
not from luna, so its scrape config is edited on the NAS itself
(`/mnt/deimos/appdata/prometheus-stack/prometheus/prometheus.yml`).
SSH to cliproxy-mars times out from luna, so this is done there or through
Dockhand.

1. On the proxy host, in CPA's config: `usage-statistics-enabled: true`, and
   `redis-usage-queue-retention-seconds: 300` to widen the queue's window.
2. Run the consumer where it can reach the proxy (never two: each drainer sees
   half the traffic):
   `CPA_MANAGEMENT_URL=http://127.0.0.1:8317/v0/management`, `CPA_MANAGEMENT_KEY=…`,
   then `cpa-usage-exporter --check-config` and
   `pip install git+https://github.com/Adrastopoulos/cpa-usage-exporter`
   (or its Docker image), serving `:9185/metrics`.
3. Add a Prometheus scrape target for it (`cpa-usage-exporter:9185` or its
   tailnet address) and reload Prometheus.
4. Import `dashboards/cpa-usage-prometheus.json` into the NAS's Grafana.
5. Point the panel at it: `usageUrl` in `haseen.agents`'
   `~/.config/haseen/shell.json` (or `HASEEN_CPA_USAGE_URL`), then
   `omarchy-agent-usage-update cpa`; the panel's usage section reads the
   record on refresh.

Without step 5 the panel writes no cpa record at all — the row appears only
where an exporter is configured.

## Rejected options

- **Scraping CPA's management API from the collector**: it needs a bearer key
  on every desktop, and v6.10.0 no longer keeps usage there; the queue is
  destructive and expires in ~60 s unless Redis retention widens it.
- **Shipping the exporter in a haseen layer**: it is a Python service with a
  secret and a Redis queue, and it belongs on the proxy host, not on every
  desktop; one consumer per proxy is a correctness rule, not a preference.
- **Reading `cpa_rate_limit_utilization_ratio` instead of
  `cpa_quota_used_ratio`**: it is live header state per key, not the
  subscription windows the panel's limits mean.
- **A default `usageUrl` of `http://127.0.0.1:9185/metrics`**: the exporter
  runs beside the proxy here, not on the desktop, so a default would put a
  dead row on every machine that never configured one.
- **Folding the stats into `limits`**: the panel draws every limit as a
  percentage, so "1.5k requests" would become "150000%".
- **Changing `Agents.js` to prefer the stats over the limits** (instead of
  joining them): the quota windows are the more urgent fact when they exist,
  so neither may hide the other.
