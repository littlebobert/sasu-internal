#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Sasu"
RELEASE_ENV_FILE="${RELEASE_ENV_FILE:-$ROOT_DIR/.env.release}"

if [[ -f "$RELEASE_ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$RELEASE_ENV_FILE"
  set +a
fi

REPO="${GITHUB_REPO:-littlebobert/sasu}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT_DIR/AppBundle/Info.plist")"
BUILD_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$ROOT_DIR/AppBundle/Info.plist")"
TAG="${RELEASE_TAG:-$VERSION}"
LANDING_PAGE="${LANDING_PAGE:-$ROOT_DIR/../littlebobert.github.io/sasu.html}"
APPCAST_PATH="${APPCAST_PATH:-$(dirname "$LANDING_PAGE")/appcast.xml}"
APPCAST_DOWNLOAD_URL_PREFIX="${APPCAST_DOWNLOAD_URL_PREFIX:-https://github.com/$REPO/releases/download/$TAG}"
APPCAST_PRODUCT_LINK="${APPCAST_PRODUCT_LINK:-http://sasu.jp}"
SPARKLE_GENERATE_APPCAST="${SPARKLE_GENERATE_APPCAST:-$ROOT_DIR/.build/artifacts/sparkle/Sparkle/bin/generate_appcast}"
OPENAI_MODEL="${OPENAI_MODEL:-gpt-5.5}"
OPENAI_REASONING_EFFORT="${OPENAI_REASONING_EFFORT:-high}"
NOTES_JSON="$ROOT_DIR/Build/release-notes-$VERSION.json"
NOTES_MD="$ROOT_DIR/Build/release-notes-$VERSION.md"
NOTES_PAIR_JSON="$ROOT_DIR/Build/release-notes-$VERSION-pair.json"
APPCAST_WORK_DIR="$ROOT_DIR/Build/appcast"

APPCAST_DOWNLOAD_URL_PREFIX="${APPCAST_DOWNLOAD_URL_PREFIX%/}/"

usage() {
  cat <<EOF
Usage:
  ./Scripts/deploy-github-release.sh [version] [--notes TEXT] [--notes-file PATH]

If version is passed, ./Scripts/bump-version.sh is run for that version.
Otherwise the patch version is bumped automatically (for example, 0.1.6 -> 0.1.7).

With --notes or --notes-file, the provided English release notes are used
as-is and only translated to Japanese (no diff-based note generation).
Repeat --notes for multiple bullets, or put one bullet per line in a file.

Examples:
  ./Scripts/deploy-github-release.sh --notes "Added automatic updates."
  ./Scripts/deploy-github-release.sh 0.1.7 --notes "Added automatic updates."
  ./Scripts/deploy-github-release.sh --notes-file Build/release-notes.txt

Environment:
  RELEASE_ENV_FILE            Optional env file to source. Default: $RELEASE_ENV_FILE
  GITHUB_REPO                 GitHub repo to create the release in. Default: $REPO
  LANDING_PAGE                Path to sasu.html. Default: $LANDING_PAGE
  APPCAST_PATH                Path to appcast.xml. Default: $APPCAST_PATH
  APPCAST_DOWNLOAD_URL_PREFIX Download URL prefix for appcast updates.
                               Default: $APPCAST_DOWNLOAD_URL_PREFIX
  APPCAST_PRODUCT_LINK        Product link in appcast. Default: $APPCAST_PRODUCT_LINK
  SPARKLE_GENERATE_APPCAST    Path to Sparkle generate_appcast tool.
                               Default: $SPARKLE_GENERATE_APPCAST
  SPARKLE_ED_KEY_FILE         Optional private EdDSA key file for appcast signing.
  SPARKLE_PRIVATE_ED_KEY      Optional private EdDSA key string for appcast signing.
                               If neither is set, generate_appcast uses Keychain.
  OPENAI_API_KEY              Required. Used to generate or translate release notes.
  OPENAI_MODEL                Default: $OPENAI_MODEL
  OPENAI_REASONING_EFFORT     Default: $OPENAI_REASONING_EFFORT
  NOTARY_PROFILE              Passed through to Scripts/notarize-app.sh. Default there: sasu-notary
  RELEASE_TAG                 Default: current app version, $VERSION
EOF
}

VERSION_ARG=""
CUSTOM_NOTES=()
CUSTOM_NOTES_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --notes)
      shift
      if [[ $# -eq 0 ]]; then
        echo "error: --notes requires a value." >&2
        exit 1
      fi
      CUSTOM_NOTES+=("$1")
      shift
      ;;
    --notes-file)
      shift
      if [[ $# -eq 0 ]]; then
        echo "error: --notes-file requires a path." >&2
        exit 1
      fi
      CUSTOM_NOTES_FILE="$1"
      shift
      ;;
    -*)
      echo "error: unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      if [[ -n "$VERSION_ARG" ]]; then
        echo "error: unexpected argument: $1" >&2
        usage >&2
        exit 1
      fi
      VERSION_ARG="$1"
      shift
      ;;
  esac
done

if [[ -n "$VERSION_ARG" ]]; then
  "$ROOT_DIR/Scripts/bump-version.sh" "${VERSION_ARG#v}"
else
  "$ROOT_DIR/Scripts/bump-version.sh" --patch
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT_DIR/AppBundle/Info.plist")"
BUILD_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$ROOT_DIR/AppBundle/Info.plist")"
TAG="${RELEASE_TAG:-$VERSION}"
NOTES_JSON="$ROOT_DIR/Build/release-notes-$VERSION.json"
NOTES_MD="$ROOT_DIR/Build/release-notes-$VERSION.md"
NOTES_PAIR_JSON="$ROOT_DIR/Build/release-notes-$VERSION-pair.json"
APPCAST_DOWNLOAD_URL_PREFIX="${APPCAST_DOWNLOAD_URL_PREFIX:-https://github.com/$REPO/releases/download/$TAG}"
APPCAST_DOWNLOAD_URL_PREFIX="${APPCAST_DOWNLOAD_URL_PREFIX%/}/"

USE_CUSTOM_NOTES=false
if [[ -n "$CUSTOM_NOTES_FILE" ]]; then
  if [[ ! -f "$CUSTOM_NOTES_FILE" ]]; then
    echo "error: release notes file not found: $CUSTOM_NOTES_FILE" >&2
    exit 1
  fi
  USE_CUSTOM_NOTES=true
elif [[ ${#CUSTOM_NOTES[@]} -gt 0 ]]; then
  USE_CUSTOM_NOTES=true
fi

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "error: missing required command: $1" >&2
    exit 1
  fi
}

require_command curl
require_command gh
require_command git
require_command python3
require_command xcrun

if ! [[ "$BUILD_VERSION" =~ ^[0-9]+$ ]]; then
  echo "error: CFBundleVersion must be numeric for Sparkle updates: $BUILD_VERSION" >&2
  exit 1
fi

if [[ -z "${OPENAI_API_KEY:-}" ]]; then
  echo "error: OPENAI_API_KEY is required to generate release notes." >&2
  exit 1
fi

if [[ ! -f "$LANDING_PAGE" ]]; then
  echo "error: landing page not found: $LANDING_PAGE" >&2
  exit 1
fi

if [[ ! -x "$SPARKLE_GENERATE_APPCAST" ]]; then
  echo "error: Sparkle generate_appcast not found: $SPARKLE_GENERATE_APPCAST" >&2
  echo "Run 'swift package resolve' and try again." >&2
  exit 1
fi

LANDING_REPO="$(git -C "$(dirname "$LANDING_PAGE")" rev-parse --show-toplevel)"
APPCAST_REPO="$(git -C "$(dirname "$APPCAST_PATH")" rev-parse --show-toplevel)"
if [[ "$APPCAST_REPO" != "$LANDING_REPO" ]]; then
  echo "error: APPCAST_PATH must live in the same git repo as LANDING_PAGE." >&2
  echo "LANDING_PAGE repo: $LANDING_REPO" >&2
  echo "APPCAST_PATH repo: $APPCAST_REPO" >&2
  exit 1
fi
LANDING_RELATIVE_PATH="$(
  python3 - "$LANDING_REPO" "$LANDING_PAGE" <<'PY'
import os
import sys

print(os.path.relpath(sys.argv[2], sys.argv[1]))
PY
)"
APPCAST_RELATIVE_PATH="$(
  python3 - "$LANDING_REPO" "$APPCAST_PATH" <<'PY'
import os
import sys

print(os.path.relpath(sys.argv[2], sys.argv[1]))
PY
)"

mkdir -p "$ROOT_DIR/Build"
cd "$ROOT_DIR"

if [[ "$USE_CUSTOM_NOTES" == true ]]; then
  echo "Translating provided release notes with $OPENAI_MODEL ($OPENAI_REASONING_EFFORT reasoning)..."

  python3 - "$OPENAI_MODEL" "$OPENAI_REASONING_EFFORT" "$VERSION" "$CUSTOM_NOTES_FILE" ${CUSTOM_NOTES[@]+"${CUSTOM_NOTES[@]}"} <<'PY' \
    | curl -sS https://api.openai.com/v1/responses \
        -H "Authorization: Bearer ${OPENAI_API_KEY}" \
        -H "Content-Type: application/json" \
        -d @- > "$NOTES_JSON"
import json
import sys

model = sys.argv[1]
reasoning_effort = sys.argv[2]
version = sys.argv[3]
notes_file = sys.argv[4] or ""
inline_notes = [note.strip() for note in sys.argv[5:] if note.strip()]

if notes_file:
    with open(notes_file) as handle:
        english_notes = [line.strip() for line in handle.readlines() if line.strip()]
else:
    english_notes = inline_notes

if not english_notes:
    raise SystemExit("No release notes provided.")

english_json = json.dumps(english_notes, ensure_ascii=False)
prompt = f"""
Translate these English release notes for Sasu {version} into Japanese.

Return JSON only with this exact shape:
{{
  "title": "Sasu {version}",
  "summary": "One short sentence.",
  "en": ["same English items, unchanged"],
  "ja": ["Japanese translations of the English items"]
}}

Guidelines:
- Keep the same number of items as the English list.
- Copy each English item exactly into the "en" array. Do not rewrite, merge, or add items.
- Provide natural Japanese translations in the "ja" array, one per English item.
- Write each item as a complete sentence with no Markdown bullet marker.
- Keep each item under 140 characters if possible.

English release notes:
{english_json}
""".strip()

body = {
    "model": model,
    "input": [
        {
            "role": "user",
            "content": [
                {"type": "input_text", "text": prompt}
            ],
        }
    ],
    "reasoning": {"effort": reasoning_effort},
}
print(json.dumps(body))
PY
else
  git fetch --tags --quiet origin 2>/dev/null || true

  last_release_tag="$(
    gh release list \
      --repo "$REPO" \
      --limit 20 \
      --json tagName,isDraft \
      --jq '[.[] | select(.isDraft == false) | .tagName | select(. != "'"$TAG"'")] | .[0] // ""'
  )"

  if [[ -n "$last_release_tag" ]] && git rev-parse --verify --quiet "$last_release_tag^{commit}" >/dev/null; then
    compare_range="$last_release_tag..HEAD"
    comparison_label="$last_release_tag to $TAG"
    release_context="$(
      {
        echo "Comparison: $comparison_label"
        echo
        echo "Commit log:"
        git log --oneline "$compare_range"
        echo
        echo "Diff stat:"
        git diff --stat "$compare_range"
        echo
        echo "Diff:"
        git diff --no-ext-diff --unified=2 "$compare_range" -- \
          ':!Build/**' \
          ':!.build/**'
      } || true
    )"
  else
    comparison_label="working tree to $TAG"
    release_context="$(
      {
        echo "Comparison: $comparison_label"
        echo
        echo "Recent commits:"
        git log --oneline -20
        echo
        echo "Working tree diff stat:"
        git diff --stat
        echo
        echo "Working tree diff:"
        git diff --no-ext-diff --unified=2 -- \
          ':!Build/**' \
          ':!.build/**'
      } || true
    )"
  fi
  release_context="${release_context:0:60000}"

  echo "Generating release notes with $OPENAI_MODEL ($OPENAI_REASONING_EFFORT reasoning)..."

  python3 - "$OPENAI_MODEL" "$OPENAI_REASONING_EFFORT" "$VERSION" "$comparison_label" "$release_context" <<'PY' \
    | curl -sS https://api.openai.com/v1/responses \
        -H "Authorization: Bearer ${OPENAI_API_KEY}" \
        -H "Content-Type: application/json" \
        -d @- > "$NOTES_JSON"
import json
import sys

model, reasoning_effort, version, comparison_label, release_context = sys.argv[1:6]
prompt = f"""
You write concise release notes for a small macOS app called Sasu.

Release version: {version}
Comparison: {comparison_label}

Use the code changes below to produce end-user-facing release notes.
Return JSON only with this exact shape:
{{
  "title": "Sasu {version}",
  "summary": "One short sentence.",
  "en": ["1-3 concise English release-note sentences"],
  "ja": ["Japanese translations of the English release-note sentences"]
}}

Guidelines:
- Prefer user-visible behavior over implementation details.
- Ignore minor changes, tiny visual polish, release automation, version bumps, website copy, refactors, and internal cleanup.
- Only include changes that users would reasonably notice or care about.
- Mention meaningful bug fixes plainly.
- Do not invent features that are not supported by the diff.
- Write each English item as a complete sentence with no Markdown bullet marker.
- Keep each item under 140 characters if possible.
- Use the style of these examples:
  Fixed transcript spacing so words no longer run together when answers contain line breaks.
  When an answer finishes while Sasu is in the background, Sasu now bounces the Dock icon instead of bringing itself to the foreground.
  Improved background answer handling so the transcript updates quietly until you switch back to Sasu.

Changes:
{release_context}
""".strip()

body = {
    "model": model,
    "input": [
        {
            "role": "user",
            "content": [
                {"type": "input_text", "text": prompt}
            ],
        }
    ],
    "reasoning": {"effort": reasoning_effort},
}
print(json.dumps(body))
PY
fi

python3 - "$NOTES_JSON" "$NOTES_MD" "$NOTES_PAIR_JSON" <<'PY'
import json
import sys

response_path, markdown_path, pair_path = sys.argv[1:4]
data = json.load(open(response_path))

text = (data.get("output_text") or "").strip()
if not text:
    parts = []
    for item in data.get("output", []):
        for content in item.get("content", []):
            if "text" in content:
                parts.append(content["text"])
    text = "\n".join(parts).strip()

if text.startswith("```"):
    lines = text.splitlines()
    text = "\n".join(lines[1:-1] if lines[-1].startswith("```") else lines[1:])

notes = json.loads(text)
en = notes.get("en") or []
ja = notes.get("ja") or []
if not en:
    raise SystemExit("OpenAI did not return English release notes.")
if len(ja) != len(en):
    ja = en

with open(markdown_path, "w") as handle:
    handle.write("\n".join(en) + "\n")

with open(pair_path, "w") as handle:
    json.dump({"en": en, "ja": ja}, handle, ensure_ascii=False)
PY

if [[ "$USE_CUSTOM_NOTES" == true ]]; then
  python3 - "$NOTES_PAIR_JSON" "$NOTES_MD" "$CUSTOM_NOTES_FILE" ${CUSTOM_NOTES[@]+"${CUSTOM_NOTES[@]}"} <<'PY'
import json
import sys

pair_path, markdown_path, notes_file = sys.argv[1:4]
inline_notes = [note.strip() for note in sys.argv[4:] if note.strip()]

if notes_file:
    english_notes = [line.strip() for line in open(notes_file) if line.strip()]
else:
    english_notes = inline_notes

data = json.load(open(pair_path))
japanese_notes = data.get("ja") or []
if len(japanese_notes) < len(english_notes):
    japanese_notes.extend(english_notes[len(japanese_notes):])
japanese_notes = japanese_notes[: len(english_notes)]

with open(pair_path, "w") as handle:
    json.dump({"en": english_notes, "ja": japanese_notes}, handle, ensure_ascii=False)

with open(markdown_path, "w") as handle:
    handle.write("\n".join(english_notes) + "\n")
PY
fi

notes_pair_json="$(python3 -c 'import pathlib, sys; print(pathlib.Path(sys.argv[1]).read_text())' "$NOTES_PAIR_JSON")"

echo "Updating landing page: $LANDING_PAGE"
python3 - "$LANDING_PAGE" "$VERSION" "$notes_pair_json" <<'PY'
import html
import json
import re
import sys

path, version, notes_json = sys.argv[1:4]
notes = json.loads(notes_json)
en_items = notes["en"]
ja_items = notes["ja"]
if len(ja_items) != len(en_items):
    ja_items = en_items

text = open(path).read()

text = re.sub(
    r'https://github\.com/littlebobert/sasu/releases/download/[^/]+/Sasu-[^"/]+-mac\.zip',
    f'https://github.com/littlebobert/sasu/releases/download/{version}/Sasu-{version}-mac.zip',
    text,
)
text = re.sub(r'data-label-en="Download [^"]*for macOS"', 'data-label-en="Download for macOS"', text)
text = re.sub(r'data-label-ja="macOS版[^"]*をダウンロード"', 'data-label-ja="macOS版をダウンロード"', text)
text = re.sub(r'>Download [^<]*for macOS</a>', '>Download for macOS</a>', text)
text = re.sub(r'data-label-en="\\(version [^"]+\\)"', f'data-label-en="(version {version})"', text)
text = re.sub(r'data-label-ja="（バージョン [^"]+）"', f'data-label-ja="（バージョン {version}）"', text)
text = re.sub(r'>\\(version [^<]+\\)</span>', f'>(version {version})</span>', text)

text = re.sub(r'(<h3\s+data-label-en="[^"]+ \(Current\)"\s+data-label-ja="[^"]+（現在）"\s*>[^<]+)</h3>', lambda m: m.group(1).replace(" (Current)", "").replace("（現在）", "") + "</h3>", text)

items_html = "\n".join(
    "        <li\n"
    f"          data-label-en=\"{html.escape(en, quote=True)}\"\n"
    f"          data-label-ja=\"{html.escape(ja, quote=True)}\"\n"
    f"        >{html.escape(en)}</li>"
    for en, ja in zip(en_items, ja_items)
)
current_block = f"""      <h3
        data-label-en="{version}"
        data-label-ja="{version}"
      >{version}</h3>
      <ul>
{items_html}
      </ul>

"""

existing_current_pattern = re.compile(
    r'\s*<h3\s+data-label-en="' + re.escape(version) + r'(?: \(Current\))?"\s+data-label-ja="' + re.escape(version) + r'(?:（現在）)?"\s*>.*?</h3>\s*<ul>.*?</ul>\s*',
    re.S,
)
release_notes_details_open = (
    r'(<div class="sasu-section release-notes">\s*<details>\s*<summary[^>]*>.*?</summary>\s*)'
)
release_notes_legacy_open = (
    r'(<h2 data-label-en="Release notes" data-label-ja="リリースノート">Release notes</h2>\s*'
    r'<details>\s*<summary[^>]*>.*?</summary>\s*)'
)
if existing_current_pattern.search(text):
    text = existing_current_pattern.sub("\n" + current_block, text, count=1)
elif re.search(release_notes_details_open, text, re.S):
    text = re.sub(
        release_notes_details_open,
        r'\1' + current_block,
        text,
        count=1,
        flags=re.S,
    )
elif re.search(release_notes_legacy_open, text, re.S):
    text = re.sub(
        release_notes_legacy_open,
        r'\1' + current_block,
        text,
        count=1,
        flags=re.S,
    )
else:
    details_open = (
        '<details>\n'
        '        <summary data-label-en="Release notes" data-label-ja="リリースノート">Release notes</summary>\n\n'
    )
    text = re.sub(
        r'(<div class="sasu-section release-notes">\s*\n)',
        r'\1      ' + details_open + current_block + '      </details>\n',
        text,
        count=1,
    )

open(path, "w").write(text)
PY

echo "Notarizing app..."
"$ROOT_DIR/Scripts/notarize-app.sh"

release_zip="$ROOT_DIR/Build/$APP_NAME-$VERSION-mac.zip"
if [[ ! -f "$release_zip" ]]; then
  echo "error: expected release zip not found: $release_zip" >&2
  exit 1
fi

echo "Generating Sparkle appcast: $APPCAST_PATH"
rm -rf "$APPCAST_WORK_DIR"
mkdir -p "$APPCAST_WORK_DIR"
cp "$release_zip" "$APPCAST_WORK_DIR/"
cp "$NOTES_MD" "$APPCAST_WORK_DIR/$(basename "$release_zip" .zip).md"
if [[ -f "$APPCAST_PATH" ]]; then
  cp "$APPCAST_PATH" "$APPCAST_WORK_DIR/appcast.xml"
fi

appcast_args=(
  --download-url-prefix "$APPCAST_DOWNLOAD_URL_PREFIX"
  --embed-release-notes
  --link "$APPCAST_PRODUCT_LINK"
  --maximum-deltas 0
  --versions "$BUILD_VERSION"
  -o "$APPCAST_WORK_DIR/appcast.xml"
)

if [[ -n "${SPARKLE_PRIVATE_ED_KEY:-}" ]]; then
  printf '%s' "$SPARKLE_PRIVATE_ED_KEY" | "$SPARKLE_GENERATE_APPCAST" "${appcast_args[@]}" --ed-key-file - "$APPCAST_WORK_DIR"
elif [[ -n "${SPARKLE_ED_KEY_FILE:-}" ]]; then
  "$SPARKLE_GENERATE_APPCAST" "${appcast_args[@]}" --ed-key-file "$SPARKLE_ED_KEY_FILE" "$APPCAST_WORK_DIR"
else
  "$SPARKLE_GENERATE_APPCAST" "${appcast_args[@]}" "$APPCAST_WORK_DIR"
fi

cp "$APPCAST_WORK_DIR/appcast.xml" "$APPCAST_PATH"

echo "Creating GitHub release $TAG in $REPO..."
gh release create "$TAG" "$release_zip" \
  --repo "$REPO" \
  --title "Sasu $VERSION" \
  --notes-file "$NOTES_MD"

echo "Committing and pushing landing page/appcast..."
landing_changes="$(git -C "$LANDING_REPO" status --porcelain -- "$LANDING_RELATIVE_PATH" "$APPCAST_RELATIVE_PATH")"
if [[ -z "$landing_changes" ]]; then
  echo "Landing page and appcast already up to date."
else
  git -C "$LANDING_REPO" add "$LANDING_RELATIVE_PATH" "$APPCAST_RELATIVE_PATH"
  git -C "$LANDING_REPO" commit -m "update sasu $VERSION release notes" -- "$LANDING_RELATIVE_PATH" "$APPCAST_RELATIVE_PATH"
  git -C "$LANDING_REPO" push
fi

echo "Created GitHub release: $TAG"
echo "Release artifact: $release_zip"
echo "Updated appcast: $APPCAST_PATH"
echo "Updated landing page: $LANDING_PAGE"
