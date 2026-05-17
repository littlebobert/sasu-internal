#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Sasu"
APP_DIR="$ROOT_DIR/Build/$APP_NAME.app"
NOTARY_PROFILE="${NOTARY_PROFILE:-sasu-notary}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT_DIR/AppBundle/Info.plist")"
NOTARY_ZIP="$ROOT_DIR/Build/$APP_NAME-notary.zip"
RELEASE_ZIP="$ROOT_DIR/Build/$APP_NAME-$VERSION-mac.zip"

cd "$ROOT_DIR"

developer_id_count="$(
  security find-identity -v -p codesigning \
    | awk '/Developer ID Application/ { count += 1 } END { print count + 0 }'
)"

if [[ "$developer_id_count" == "0" ]]; then
  echo "error: no Developer ID Application certificate found in Keychain." >&2
  echo "Create one in Xcode > Settings > Accounts > Manage Certificates." >&2
  exit 1
fi

CONFIGURATION=release "$ROOT_DIR/Scripts/build-app.sh"

rm -f "$NOTARY_ZIP" "$RELEASE_ZIP"
ditto -c -k --keepParent "$APP_DIR" "$NOTARY_ZIP"

xcrun notarytool submit "$NOTARY_ZIP" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait

xcrun stapler staple "$APP_DIR"

codesign --verify --deep --strict --verbose=2 "$APP_DIR"
spctl --assess --type execute --verbose=4 "$APP_DIR"

ditto -c -k --keepParent "$APP_DIR" "$RELEASE_ZIP"

echo "Notarized app: $APP_DIR"
echo "GitHub release artifact: $RELEASE_ZIP"
