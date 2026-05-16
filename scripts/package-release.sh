#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME=">_ - island"
APP_VERSION="0.1.0"
DIST_DIR="$ROOT/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
ARCHIVE_BASENAME="Vibelsland-Free-$APP_VERSION-macos"
ARCHIVE="$DIST_DIR/$ARCHIVE_BASENAME.zip"
CHECKSUM="$ARCHIVE.sha256"
LEGACY_ARCHIVE="$DIST_DIR/prompt-island-$APP_VERSION-macos.zip"
LEGACY_CHECKSUM="$LEGACY_ARCHIVE.sha256"

cd "$ROOT"
zsh scripts/verify-app.sh

rm -f "$ARCHIVE" "$CHECKSUM" "$LEGACY_ARCHIVE" "$LEGACY_CHECKSUM"
(
    cd "$DIST_DIR"
    /usr/bin/ditto -c -k --norsrc --keepParent "$APP_NAME.app" "$ARCHIVE"
)

(
    cd "$DIST_DIR"
    /usr/bin/shasum -a 256 "$ARCHIVE_BASENAME.zip" > "$CHECKSUM"
)
echo "$ARCHIVE"
echo "$CHECKSUM"
