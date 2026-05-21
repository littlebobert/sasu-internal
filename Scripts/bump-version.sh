#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLIST="$ROOT_DIR/AppBundle/Info.plist"

usage() {
  cat <<'EOF'
Usage:
  ./Scripts/bump-version.sh [new-version] [new-build]

Without arguments, bumps the minor version, resets patch to 0, and increments
CFBundleVersion. With a version argument, increments CFBundleVersion unless a
new build number is also supplied.
Examples:
  0.1.5 (1) -> 0.2.0 (2)
  ./Scripts/bump-version.sh 0.1.6
  ./Scripts/bump-version.sh 0.1.6 7
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

current_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
current_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")"

if [[ $# -gt 2 ]]; then
  usage >&2
  exit 1
fi

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

if ! [[ "$current_build" =~ ^[0-9]+$ ]]; then
  echo "error: cannot compare non-numeric CFBundleVersion: $current_build" >&2
  exit 1
fi

if [[ $# -gt 1 ]]; then
  new_build="$2"
else
  new_build="$((10#$current_build + 1))"
fi

if ! [[ "$new_build" =~ ^[0-9]+$ ]]; then
  echo "error: CFBundleVersion must be numeric: $new_build" >&2
  exit 1
fi

if (( 10#$new_build <= 10#$current_build )); then
  echo "error: CFBundleVersion must increase from $current_build to a larger number." >&2
  exit 1
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $new_version" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $new_build" "$PLIST"

echo "Bumped Sasu from $current_version ($current_build) to $new_version ($new_build)"
echo "Updated $PLIST"
