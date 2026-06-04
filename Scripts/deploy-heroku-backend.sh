#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HEROKU_APP="${HEROKU_APP:-${1:-}}"

if [[ -z "$HEROKU_APP" ]]; then
  echo "Usage: HEROKU_APP=sasu-backend ./Scripts/deploy-heroku-backend.sh" >&2
  echo "   or: ./Scripts/deploy-heroku-backend.sh sasu-backend" >&2
  exit 1
fi

cd "$ROOT_DIR"
heroku git:remote --app "$HEROKU_APP"
git subtree push --prefix backend heroku main
