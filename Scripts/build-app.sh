#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-debug}"
APP_NAME="Sasu"
APP_DIR="$ROOT_DIR/Build/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"
SPARKLE_FRAMEWORK="$ROOT_DIR/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
ENTITLEMENTS="$ROOT_DIR/AppBundle/Sasu.entitlements"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:-}"

cd "$ROOT_DIR"

swift build -c "$CONFIGURATION"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$FRAMEWORKS_DIR"

cp "$ROOT_DIR/AppBundle/Info.plist" "$CONTENTS_DIR/Info.plist"
if [[ -d "$ROOT_DIR/AppBundle/Resources" ]]; then
  cp -R "$ROOT_DIR/AppBundle/Resources/." "$RESOURCES_DIR/"
fi
cp "$ROOT_DIR/.build/$CONFIGURATION/$APP_NAME" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"
if [[ ! -d "$SPARKLE_FRAMEWORK" ]]; then
  echo "error: Sparkle framework not found at $SPARKLE_FRAMEWORK" >&2
  echo "Run 'swift package resolve' and try again." >&2
  exit 1
fi
ditto "$SPARKLE_FRAMEWORK" "$FRAMEWORKS_DIR/Sparkle.framework"
printf "APPL????" > "$CONTENTS_DIR/PkgInfo"

if [[ -z "$CODESIGN_IDENTITY" ]]; then
  if [[ "$CONFIGURATION" == "release" ]]; then
    CODESIGN_IDENTITY="$(
      security find-identity -v -p codesigning \
        | awk -F'"' '/Developer ID Application/ { print $2; exit }'
    )"
  else
    CODESIGN_IDENTITY="$(
      security find-identity -v -p codesigning \
        | awk -F'"' '/Apple Development/ { print $2; exit }'
    )"
  fi
fi

if [[ -n "$CODESIGN_IDENTITY" ]]; then
  framework_codesign_args=(--force --deep --sign "$CODESIGN_IDENTITY")
  app_codesign_args=(--force --deep --sign "$CODESIGN_IDENTITY" --entitlements "$ENTITLEMENTS")

  if [[ "$CONFIGURATION" == "release" ]]; then
    framework_codesign_args+=(--options runtime --timestamp)
    app_codesign_args+=(--options runtime --timestamp)
  fi

  codesign "${framework_codesign_args[@]}" "$FRAMEWORKS_DIR/Sparkle.framework" >/dev/null
  codesign "${app_codesign_args[@]}" "$APP_DIR" >/dev/null
  echo "Signed with: $CODESIGN_IDENTITY"
else
  if [[ "$CONFIGURATION" == "release" ]]; then
    echo "error: release builds require a Developer ID Application certificate." >&2
    echo "Install one with Xcode > Settings > Accounts > Manage Certificates." >&2
    exit 1
  fi

  codesign --force --deep --sign - "$FRAMEWORKS_DIR/Sparkle.framework" >/dev/null
  codesign --force --deep --sign - --entitlements "$ENTITLEMENTS" "$APP_DIR" >/dev/null
  echo "Signed ad-hoc. Screen Recording permission may need to be reset after each rebuild."
fi

echo "Built $APP_DIR"
echo "Launch with: open \"$APP_DIR\""
