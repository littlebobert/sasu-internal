#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE_ID="dev.sasu.Sasu"
APP_NAME="Sasu"
APP_DIR="$ROOT_DIR/Build/$APP_NAME.app"
SAVED_STATE_DIR="$HOME/Library/Saved Application State/$BUNDLE_ID.savedState"

reset_permission() {
  local service="$1"

  if ! tccutil reset "$service" "$BUNDLE_ID"; then
    echo "warning: could not reset $service for $BUNDLE_ID" >&2
  fi
}

echo "Stopping $APP_NAME if it is running..."
pkill -x "$APP_NAME" 2>/dev/null || true

echo "Clearing user defaults for $BUNDLE_ID..."
defaults delete "$BUNDLE_ID" 2>/dev/null || true

echo "Resetting macOS permissions for $BUNDLE_ID..."
reset_permission ScreenCapture
reset_permission Accessibility
reset_permission AppleEvents

echo "Clearing saved window state..."
rm -rf "$SAVED_STATE_DIR"

echo "Building app..."
"$ROOT_DIR/Scripts/build-app.sh"

echo "Opening $APP_DIR..."


echo "Done. Keychain items, including the saved OpenAI key, were not changed."
