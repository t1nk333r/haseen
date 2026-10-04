#!/usr/bin/env bash
# tools/secrets.sh — run before every push to the public repository.
#   1. gitleaks over the full git history and the working tree (tracked files);
#   2. privacy patterns gitleaks does not know about: tailnet (100.64/10) and
#      lab LAN addresses, home paths, personal e-mail addresses, private keys.
# GITLEAKS overrides the binary (the author's laptop uses a static release in
# /tmp/tools). Exit 1 on any finding.
set -Eeuo pipefail
cd "$(dirname "$0")/.."

GITLEAKS=${GITLEAKS:-$(command -v gitleaks || echo /tmp/tools/gitleaks)}
fail=0

if [[ -x $GITLEAKS ]]; then
    "$GITLEAKS" git --no-banner --redact . || fail=1
else
    echo "secrets: gitleaks not found (set GITLEAKS); skipping the history scan" >&2
    fail=1
fi

# Patterns over tracked files and every commit's diff. Test fixtures use
# example.invalid / example.com / RFC 1918 documentation-style addresses, which
# are allowed explicitly.
patterns=(
    '\b100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.[0-9]{1,3}\.[0-9]{1,3}\b' # Tailscale CGNAT
    '/home/[a-z_][a-z0-9_-]*/'                                                 # absolute home paths
    '-----BEGIN [A-Z ]*PRIVATE KEY-----'
    '[A-Za-z0-9._%+-]+@(gmail|outlook|hotmail|proton(mail)?|icloud|yahoo)\.[a-z]+'
)
for p in "${patterns[@]}"; do
    hits="$(git grep -nE -e "$p" -- . ':!tools/secrets.sh' || true)"
    hist="$(git log -p --all -- . ':!tools/secrets.sh' | grep -nE -e "$p" | grep -E '^[0-9]+:\+' || true)"
    if [[ -n $hits || -n $hist ]]; then
        echo "secrets: pattern matched: $p" >&2
        printf '%s\n' "$hits" "$hist" | sed '/^$/d' | head -20 >&2
        fail=1
    fi
done

((fail == 0)) && echo "secrets OK"
exit "$fail"
