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

python3 - "$RELEASE_METADATA" "$ARCHIVE" "$CHECKSUM" <<'PY'
import hashlib
import json
import os
import sys
from pathlib import Path

metadata_path = Path(sys.argv[1])
archive_path = Path(sys.argv[2])
checksum_path = Path(sys.argv[3])
metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
fatal_on_mismatch = os.environ.get("VIBELSLAND_EXPECT_RELEASE_METADATA") == "1"


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


archive_hash = sha256(archive_path)
archive_size = archive_path.stat().st_size
checksum_hash = sha256(checksum_path)
checksum_size = checksum_path.stat().st_size
checksum_parts = checksum_path.read_text(encoding="utf-8").strip().split()

expected_archive = metadata["archive"]
expected_checksum = metadata["checksum_file"]
expected = {
    "archive.sha256": expected_archive["sha256"],
    "archive.size_bytes": expected_archive["size_bytes"],
    "checksum_file.sha256": expected_checksum["sha256"],
    "checksum_file.size_bytes": expected_checksum["size_bytes"],
}
actual = {
    "archive.sha256": archive_hash,
    "archive.size_bytes": archive_size,
    "checksum_file.sha256": checksum_hash,
    "checksum_file.size_bytes": checksum_size,
}

errors = []
if checksum_parts != [archive_hash, expected_archive["name"]]:
    errors.append(
        "checksum file should contain the archive hash and archive filename: "
        f"{checksum_parts!r}"
    )
for key, expected_value in expected.items():
    actual_value = actual[key]
    if actual_value != expected_value:
        errors.append(f"{key}: expected {expected_value}, got {actual_value}")

if errors:
    print(
        "Local package differs from docs/release.json public release metadata:",
        file=sys.stderr,
    )
    for error in errors:
        print(f"- {error}", file=sys.stderr)
    print(
        "This is valid only for an unpublished candidate. Do not update website "
        "checksums unless the matching GitHub Release assets are uploaded too.",
        file=sys.stderr,
    )
    print(
        "To verify the current dist directory without rebuilding, run "
        "VIBELSLAND_VERIFY_DIST=1 zsh scripts/verify-docs-site.sh.",
        file=sys.stderr,
    )
    if fatal_on_mismatch:
        sys.exit(1)
else:
    print("Local package matches docs/release.json release metadata.")
PY

echo "$ARCHIVE"
echo "$CHECKSUM"
