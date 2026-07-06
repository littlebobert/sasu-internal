#!/usr/bin/env bash
set -euo pipefail

BUNDLE_ID="${SASU_BUNDLE_ID:-dev.sasu.Sasu}"
APP_NAME="${SASU_APP_NAME:-Sasu}"
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

echo "Done. Keychain items, including saved OpenAI keys, were not changed."
