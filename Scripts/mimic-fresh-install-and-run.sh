#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Sasu"
APP_DIR="$ROOT_DIR/Build/$APP_NAME.app"

"$ROOT_DIR/Scripts/reset-first-run-state.sh"

echo "Building app..."
"$ROOT_DIR/Scripts/build-app.sh"

echo "Opening $APP_DIR..."
open "$APP_DIR"

echo "Done."
