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
print(metadata["version"])
print(metadata["archive"]["name"])
print(metadata["checksum_file"]["name"])
PY
)}")
APP_BUNDLE_NAME="$metadata[1]"
APP_NAME="${APP_BUNDLE_NAME%.app}"
APP_VERSION="$metadata[2]"
ARCHIVE_NAME="$metadata[3]"
CHECKSUM_NAME="$metadata[4]"
DIST_DIR="$ROOT/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
ARCHIVE="$DIST_DIR/$ARCHIVE_NAME"
CHECKSUM="$DIST_DIR/$CHECKSUM_NAME"
LEGACY_ARCHIVE="$DIST_DIR/prompt-island-$APP_VERSION-macos.zip"
LEGACY_CHECKSUM="$LEGACY_ARCHIVE.sha256"

cd "$ROOT"
zsh scripts/verify-app.sh

rm -f "$ARCHIVE" "$CHECKSUM" "$LEGACY_ARCHIVE" "$LEGACY_CHECKSUM"
(
    cd "$DIST_DIR"
    /usr/bin/ditto -c -k --norsrc --keepParent "$APP_BUNDLE_NAME" "$ARCHIVE"
)

(
    cd "$DIST_DIR"
    /usr/bin/shasum -a 256 "$ARCHIVE_NAME" > "$CHECKSUM"
)
echo "$ARCHIVE"
echo "$CHECKSUM"
