#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# rollback.sh — revert an app container to its previous image
#
# Usage (run from /root/hq on the Droplet):
#   ./scripts/rollback.sh anelia    # rollback anelia to the previous image
#   ./scripts/rollback.sh school    # rollback school to the previous image
#
# How it works:
#   1. Tags the current "latest" image as "broken" for reference.
#   2. Promotes the "previous" image tag back to "latest".
#   3. Restarts the container.
#   4. Verifies /health returns 200.
#
# To save a rollback point before a deploy, run:
#   docker tag <app>:latest <app>:previous
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/.."

APP="${1:-}"

if [[ -z "$APP" || ( "$APP" != "anelia" && "$APP" != "school" ) ]]; then
  echo "Usage: $0 {anelia|school}"
  exit 1
fi

PORT=""
case "$APP" in
  anelia) PORT=3001 ;;
  school) PORT=3002 ;;
esac

echo "▶  Rolling back ${APP}..."

# Check a previous image exists
if ! docker image inspect "${APP}:previous" &>/dev/null; then
  echo "❌  No '${APP}:previous' image found."
  echo "    Save a rollback point before deploys with:"
  echo "      docker tag ${APP}:latest ${APP}:previous"
  exit 1
fi

# Tag current as broken (for post-mortem inspection)
if docker image inspect "${APP}:latest" &>/dev/null; then
  docker tag "${APP}:latest" "${APP}:broken"
  echo "   Tagged current image as '${APP}:broken'"
fi

# Promote previous → latest
docker tag "${APP}:previous" "${APP}:latest"
echo "   Promoted '${APP}:previous' → '${APP}:latest'"

# Restart the container with the promoted image
cd "${REPO_ROOT}"
docker compose up -d --no-build "${APP}"
echo "   Container restarted"

# Verify health
echo "▶  Verifying /health..."
sleep 3
if curl -sf --max-time 10 "http://localhost:${PORT}/health" -o /dev/null; then
  echo "✅  ${APP} is healthy on port ${PORT} — rollback complete."
else
  echo "❌  /health check failed after rollback. Inspect with:"
  echo "    docker compose logs --tail=50 ${APP}"
  exit 1
fi
