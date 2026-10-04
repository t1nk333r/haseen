#!/usr/bin/env bash
# tools/check-docs.sh — read-only integrity check of the written record.
# Idea adapted from omacachy bin/check-docs.sh (own code).
#   1. every plans/NNN-*.md has exactly one "| NNN |" row in plans/README.md,
#      and every row has a file;
#   2. every commit hash cited in plans/ resolves in this repository;
#   3. every repo-relative path in backticks in AGENTS.md, handoff.md and
#      docs/architecture.md exists (globs and <placeholders> are skipped).
set -Eeuo pipefail
cd "$(dirname "$0")/.."
fail=0
err() { printf 'check-docs: %s\n' "$*" >&2; fail=1; }

# 1. plans <-> index
for f in plans/[0-9][0-9][0-9]-*.md; do
    n="${f#plans/}"
    n="${n%%-*}"
    c="$(grep -c "^| $n |" plans/README.md || true)"
    [[ $c == 1 ]] || err "plan $n has $c index rows"
done
while read -r n; do
    compgen -G "plans/$n-*.md" >/dev/null || err "index row $n has no plan file"
done < <(sed -n 's/^| \([0-9][0-9][0-9]\) |.*/\1/p' plans/README.md)

# 2. cited commit hashes (7-40 hex inside backticks); allowlist for ids that
#    are not commits of this repo: plans/.known-external-refs
external="$(cut -f1 plans/.known-external-refs 2>/dev/null | grep -v '^#' || true)"
if git rev-parse --git-dir >/dev/null 2>&1; then
    while read -r h; do
        grep -qxF "$h" <<<"$external" && continue
        git cat-file -e "$h^{commit}" 2>/dev/null || err "plans cite unknown commit $h (or list it in plans/.known-external-refs)"
    done < <(grep -ohE '`[0-9a-f]{7,40}`' plans/*.md | tr -d '`' | sort -u)
fi

# 3. paths asserted by the agent docs (allowlist: plans/.known-absent-paths)
allowed="$(cut -f1 plans/.known-absent-paths 2>/dev/null | grep -v '^#' || true)"
while read -r p; do
    [[ $p == *'<'* || $p == *'*'* || $p == *'{'* || $p == '~'* || $p == /* ]] && continue
    [[ $p == */* ]] || continue
    grep -qxF "$p" <<<"$allowed" && continue
    [[ -e $p ]] || err "path in docs does not exist: $p (or list it in plans/.known-absent-paths)"
done < <(grep -ohE '`[A-Za-z0-9_./{}<>*-]+`' AGENTS.md handoff.md | tr -d '`' | sort -u)

((fail == 0)) && echo "check-docs OK"
exit "$fail"
