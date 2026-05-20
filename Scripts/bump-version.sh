#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLIST="$ROOT_DIR/AppBundle/Info.plist"

usage() {
  cat <<'EOF'
Usage:
  ./Scripts/bump-version.sh [new-version]

Without an argument, bumps the minor version and resets patch to 0.
Examples:
  0.1.5 -> 0.2.0
  ./Scripts/bump-version.sh 0.1.6
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

current_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"

if [[ $# -gt 0 ]]; then
  new_version="${1#v}"
else
  IFS='.' read -r major minor patch_extra <<<"$current_version"
  if [[ -z "${major:-}" || -z "${minor:-}" || -z "${patch_extra:-}" ]]; then
    echo "error: cannot minor-bump non-semver version: $current_version" >&2
    exit 1
  fi

  if ! [[ "$major" =~ ^[0-9]+$ && "$minor" =~ ^[0-9]+$ ]]; then
    echo "error: cannot minor-bump non-semver version: $current_version" >&2
    exit 1
  fi

  new_version="$major.$((minor + 1)).0"
fi

if [[ -z "$new_version" ]]; then
  echo "error: new version cannot be empty." >&2
  exit 1
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $new_version" "$PLIST"

echo "Bumped Sasu from $current_version to $new_version"
echo "Updated $PLIST"
