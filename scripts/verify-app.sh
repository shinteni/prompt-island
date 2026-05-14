#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT/dist/Vibelsland Free.app"
INFO="$APP_DIR/Contents/Info.plist"
EXECUTABLE="$APP_DIR/Contents/MacOS/VibelslandFree"
ICON="$APP_DIR/Contents/Resources/AppIcon.icns"

cd "$ROOT"

swift build
zsh scripts/run-tests.sh
zsh scripts/build-app.sh >/dev/null

/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_DIR"
SIGNATURE_INFO="$(/usr/bin/codesign -dv --verbose=4 "$APP_DIR" 2>&1)"
[[ "$SIGNATURE_INFO" == *"Signature=adhoc"* ]]
[[ "$SIGNATURE_INFO" == *"Identifier=free.vibelsland.macos"* ]]
[[ "$(/usr/bin/plutil -extract LSUIElement raw -o - "$INFO")" == "true" ]]
[[ "$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$INFO")" == "free.vibelsland.macos" ]]
[[ "$(/usr/bin/plutil -extract CFBundleIconFile raw -o - "$INFO")" == "AppIcon" ]]
[[ "$(/usr/bin/plutil -extract CFBundlePackageType raw -o - "$INFO")" == "APPL" ]]
[[ "$(/usr/bin/plutil -extract CFBundleExecutable raw -o - "$INFO")" == "VibelslandFree" ]]
[[ "$(/usr/bin/plutil -extract LSApplicationCategoryType raw -o - "$INFO")" == "public.app-category.developer-tools" ]]
[[ -n "$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$INFO")" ]]
[[ -n "$(/usr/bin/plutil -extract CFBundleVersion raw -o - "$INFO")" ]]
[[ -x "$EXECUTABLE" ]]
[[ -s "$ICON" ]]

echo "App verification passed"
