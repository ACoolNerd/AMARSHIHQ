#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# health-check.sh — verify all production services are up on the Droplet
#
# Run from the Droplet:
#   chmod +x scripts/health-check.sh
#   ./scripts/health-check.sh
#
# Exit codes:
#   0 — all checks passed
#   1 — one or more checks failed
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

PASS=0
FAIL=0

check() {
  local label="$1"
  local result="$2"   # "ok" or any other string = failure
  if [[ "$result" == "ok" ]]; then
    echo "  ✅  $label"
    PASS=$((PASS + 1))
  else
    echo "  ❌  $label  ($result)"
    FAIL=$((FAIL + 1))
  fi
}

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  AMARSHIHQ — Production Health Check"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ── Docker containers ─────────────────────────────────────────────────────────
echo "▸ Docker containers"

anelia_state=$(docker inspect --format '{{.State.Status}}' anelia 2>/dev/null || echo "not found")
check "anelia container running" "$([ "$anelia_state" = "running" ] && echo ok || echo "$anelia_state")"

school_state=$(docker inspect --format '{{.State.Status}}' school 2>/dev/null || echo "not found")
check "school container running" "$([ "$school_state" = "running" ] && echo ok || echo "$school_state")"

# ── HTTP health endpoints ─────────────────────────────────────────────────────
echo ""
echo "▸ HTTP health endpoints"

anelia_http=$(curl -sf --max-time 5 http://localhost:3001/health -o /dev/null && echo ok || echo "HTTP error")
check "localhost:3001/health" "$anelia_http"

school_http=$(curl -sf --max-time 5 http://localhost:3002/health -o /dev/null && echo ok || echo "HTTP error")
check "localhost:3002/health" "$school_http"

# ── Cloudflare Tunnel ─────────────────────────────────────────────────────────
echo ""
echo "▸ Cloudflare Tunnel (cloudflared)"

cf_active=$(systemctl is-active cloudflared 2>/dev/null || echo "inactive")
check "cloudflared service active" "$([ "$cf_active" = "active" ] && echo ok || echo "$cf_active")"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [[ $FAIL -eq 0 ]]; then
  echo "  ✅  All $PASS checks passed — stack is healthy"
else
  echo "  ❌  $FAIL check(s) failed, $PASS passed"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

exit $(( FAIL > 0 ? 1 : 0 ))
