#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# deploy.sh — Direct Netlify CLI deploy (no GitHub, no CI/CD)
#
# Usage:
#   ./scripts/deploy.sh anelia    # deploy Anelia frontend
#   ./scripts/deploy.sh school    # deploy School frontend
#   ./scripts/deploy.sh all       # deploy both
#
# Prerequisites (run once on Droplet):
#   npm install -g netlify-cli
#   netlify login                 # authenticates via browser or NETLIFY_AUTH_TOKEN env var
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

APP="${1:-}"

deploy_app() {
  local app="$1"
  local app_dir="/apps/${app}"
  local site_id_var="NETLIFY_SITE_ID_$(echo "$app" | tr '[:lower:]' '[:upper:]')"
  local site_id="${!site_id_var:-}"

  echo "▶  Building ${app}..."
  cd "${app_dir}"
  npm ci --silent
  npm run build --if-present

  echo "▶  Deploying ${app} to Netlify..."
  if [[ -n "${site_id}" ]]; then
    netlify deploy --prod --dir=dist --site="${site_id}"
  else
    # Falls back to the site linked in netlify.toml or .netlify/state.json
    netlify deploy --prod --dir=dist
  fi

  echo "✅  ${app} deployed."
  cd - > /dev/null
}

case "${APP}" in
  anelia)
    deploy_app "anelia"
    ;;
  school)
    deploy_app "school"
    ;;
  all)
    deploy_app "anelia"
    deploy_app "school"
    ;;
  *)
    echo "Usage: $0 {anelia|school|all}"
    exit 1
    ;;
esac
