#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RELEASE_METADATA="$ROOT/docs/release.json"
metadata=("${(@f)$(python3 - "$RELEASE_METADATA" <<'PY'
import json
import sys
from pathlib import Path

metadata = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
print(metadata["app"]["bundle_name"])
print(metadata["app"]["binary_name"])
print(metadata["app"]["bundle_identifier"])
print(metadata["version"])
print(metadata["app"]["bundle_version"])
PY
)}")
APP_BUNDLE_NAME="$metadata[1]"
APP_BINARY_NAME="$metadata[2]"
APP_BUNDLE_ID="$metadata[3]"
APP_VERSION="$metadata[4]"
APP_BUILD_NUMBER="$metadata[5]"
APP_DIR="$ROOT/dist/$APP_BUNDLE_NAME"
INFO="$APP_DIR/Contents/Info.plist"
EXECUTABLE="$APP_DIR/Contents/MacOS/$APP_BINARY_NAME"
ICON="$APP_DIR/Contents/Resources/AppIcon.icns"

cd "$ROOT"

swift build
zsh scripts/run-tests.sh
zsh scripts/build-app.sh >/dev/null

/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_DIR"
SIGNATURE_INFO="$(/usr/bin/codesign -dv --verbose=4 "$APP_DIR" 2>&1)"
[[ "$SIGNATURE_INFO" == *"Signature=adhoc"* ]]
[[ "$SIGNATURE_INFO" == *"Identifier=$APP_BUNDLE_ID"* ]]
[[ "$(/usr/bin/plutil -extract LSUIElement raw -o - "$INFO")" == "true" ]]
[[ "$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$INFO")" == "$APP_BUNDLE_ID" ]]
[[ "$(/usr/bin/plutil -extract CFBundleIconFile raw -o - "$INFO")" == "AppIcon" ]]
[[ "$(/usr/bin/plutil -extract CFBundlePackageType raw -o - "$INFO")" == "APPL" ]]
[[ "$(/usr/bin/plutil -extract CFBundleExecutable raw -o - "$INFO")" == "$APP_BINARY_NAME" ]]
[[ "$(/usr/bin/plutil -extract LSApplicationCategoryType raw -o - "$INFO")" == "public.app-category.developer-tools" ]]
[[ "$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$INFO")" == "$APP_VERSION" ]]
[[ "$(/usr/bin/plutil -extract CFBundleVersion raw -o - "$INFO")" == "$APP_BUILD_NUMBER" ]]
[[ -x "$EXECUTABLE" ]]
[[ -s "$ICON" ]]

echo "App verification passed"
