#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Vibelsland Free"
APP_VERSION="0.1.0"
DIST_DIR="$ROOT/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
ARCHIVE_BASENAME="Vibelsland-Free-$APP_VERSION-macos"
ARCHIVE="$DIST_DIR/$ARCHIVE_BASENAME.zip"
CHECKSUM="$ARCHIVE.sha256"

cd "$ROOT"
zsh scripts/verify-app.sh

rm -f "$ARCHIVE" "$CHECKSUM"
(
    cd "$DIST_DIR"
    /usr/bin/ditto -c -k --norsrc --keepParent "$APP_NAME.app" "$ARCHIVE"
)

/usr/bin/shasum -a 256 "$ARCHIVE" > "$CHECKSUM"
echo "$ARCHIVE"
echo "$CHECKSUM"
